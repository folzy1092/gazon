import Foundation

enum ForecastMethod: String, CaseIterable, Identifiable {
    case smoothed, latest, overall
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smoothed: "Сглаженный"
        case .latest: "Последний интервал"
        case .overall: "Средний за всю приёмку"
        }
    }
}

struct IntakePoint {
    let time: Date
    let count: Int
}

struct IntakeSnapshot {
    let startTime: Date
    let initialAcceptedItems: Int
    let totalItems: Int
    let measurements: [IntakePoint]
    let teamChanges: [Date]

    init(session: IntakeSession) {
        startTime = session.startTime
        initialAcceptedItems = session.initialAcceptedItems
        totalItems = session.totalItems
        measurements = session.measurements.map { IntakePoint(time: $0.timestamp, count: $0.acceptedItems) }
        teamChanges = session.teamChanges.map(\.timestamp)
    }

    init(startTime: Date, initialAcceptedItems: Int, totalItems: Int,
         measurements: [IntakePoint], teamChanges: [Date] = []) {
        self.startTime = startTime
        self.initialAcceptedItems = initialAcceptedItems
        self.totalItems = totalItems
        self.measurements = measurements
        self.teamChanges = teamChanges
    }
}

struct ForecastResult {
    let overallRate: Double
    let currentRate: Double?
    let smoothedRate: Double?
    let remainingItems: Int
    let remainingTime: TimeInterval?
    let estimatedFinish: Date?
    let earliestFinish: Date?
    let latestFinish: Date?
    let progress: Double
    let lastTime: Date
}

struct ForecastEngine {
    static func calculate(session: IntakeSession, now: Date = .now,
                          method: ForecastMethod = .smoothed) -> ForecastResult {
        calculate(snapshot: IntakeSnapshot(session: session), now: now, method: method)
    }

    static func calculate(snapshot: IntakeSnapshot, now: Date,
                          method: ForecastMethod = .smoothed) -> ForecastResult {
        let points = [IntakePoint(time: snapshot.startTime, count: snapshot.initialAcceptedItems)]
            + snapshot.measurements.sorted { $0.time < $1.time }
        let last = points.last!
        let remaining = max(0, snapshot.totalItems - last.count)
        let progress = snapshot.totalItems > 0
            ? min(1, max(0, Double(last.count) / Double(snapshot.totalItems))) : 0
        let elapsed = last.time.timeIntervalSince(snapshot.startTime) / 60
        let overall = elapsed > 0 ? max(0, Double(last.count - snapshot.initialAcceptedItems) / elapsed) : 0

        let change = snapshot.teamChanges.filter { $0 <= last.time }.max()
        var intervals: [(time: Date, rate: Double)] = []
        var pendingDuration: TimeInterval = 0
        var pendingCount = 0
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let duration = b.time.timeIntervalSince(a.time)
            guard duration > 0, b.count >= a.count else { continue }
            if let change, a.time < change {
                pendingDuration = 0
                pendingCount = 0
                continue
            }
            pendingDuration += duration
            pendingCount += b.count - a.count
            if pendingDuration >= 180 {
                intervals.append((b.time, Double(pendingCount) * 60 / pendingDuration))
                pendingDuration = 0
                pendingCount = 0
            }
        }
        // A short final interval may merge with the previous interval, but never stand alone.
        if pendingDuration > 0, let previous = intervals.last {
            let previousPoint = points.last(where: { $0.time == previous.time })
            if let previousPoint, let before = points.last(where: { $0.time < previousPoint.time }) {
                let combined = last.time.timeIntervalSince(before.time)
                if combined >= 180 {
                    intervals[intervals.count - 1] = (last.time, Double(last.count - before.count) * 60 / combined)
                }
            }
        }
        let current = intervals.last?.rate
        let rates = Array(intervals.suffix(3).reversed()).map(\.rate)
        let weights: [Double] = rates.count == 3 ? [0.5, 0.3, 0.2]
            : rates.count == 2 ? [0.65, 0.35] : [1]
        let smoothed: Double? = rates.isEmpty
            ? (change == nil && elapsed >= 3 && overall > 0 ? overall : nil)
            : zip(rates, weights).map(*).reduce(0, +)
        let selected: Double?
        switch method {
        case .smoothed: selected = smoothed
        case .latest: selected = current
        case .overall: selected = elapsed >= 3 ? overall : nil
        }
        let time: TimeInterval? = remaining == 0 ? 0
            : (selected ?? 0) > 0 ? Double(remaining) * 60 / selected! : nil
        let finish = time.map { last.time.addingTimeInterval($0) }
        let margin = time.map { max(300, $0 * 0.1) } ?? 0
        let early = finish.map { max(last.time, $0.addingTimeInterval(-margin)) }
        let late = finish.map { $0.addingTimeInterval(margin) }
        return ForecastResult(overallRate: overall, currentRate: current,
                              smoothedRate: smoothed, remainingItems: remaining,
                              remainingTime: time, estimatedFinish: finish,
                              earliestFinish: remaining == 0 ? finish : early,
                              latestFinish: remaining == 0 ? finish : late,
                              progress: progress, lastTime: last.time)
    }
}
