import Foundation
import SwiftData

@Model
final class IntakeSession {
    var id: UUID
    var createdAt: Date
    var startTime: Date
    var totalItems: Int
    var initialAcceptedItems: Int
    var isCompleted: Bool
    var completedAt: Date?
    var cargoPlaces: Int?
    var shipmentLabel: String?
    @Relationship(deleteRule: .cascade) var measurements: [Measurement]
    @Relationship(deleteRule: .cascade) var teamChanges: [TeamChange]

    init(startTime: Date, totalItems: Int, initialAcceptedItems: Int,
         cargoPlaces: Int? = nil, shipmentLabel: String? = nil) {
        id = UUID()
        createdAt = .now
        self.startTime = startTime
        self.totalItems = totalItems
        self.initialAcceptedItems = initialAcceptedItems
        isCompleted = false
        completedAt = nil
        self.cargoPlaces = cargoPlaces
        self.shipmentLabel = shipmentLabel
        measurements = []
        teamChanges = []
    }

    var sortedMeasurements: [Measurement] {
        measurements.sorted { $0.timestamp < $1.timestamp }
    }

    var acceptedNow: Int { sortedMeasurements.last?.acceptedItems ?? initialAcceptedItems }
    var lastTime: Date { sortedMeasurements.last?.timestamp ?? startTime }
}

@Model
final class Measurement {
    var id: UUID
    var timestamp: Date
    var acceptedItems: Int

    init(timestamp: Date, acceptedItems: Int) {
        id = UUID()
        self.timestamp = timestamp
        self.acceptedItems = acceptedItems
    }
}

@Model
final class TeamChange {
    var id: UUID
    var timestamp: Date
    var previousWorkers: Int
    var workerCount: Int
    var acceptedItemsAtChange: Int

    init(timestamp: Date, previousWorkers: Int, workerCount: Int, acceptedItemsAtChange: Int) {
        id = UUID()
        self.timestamp = timestamp
        self.previousWorkers = previousWorkers
        self.workerCount = workerCount
        self.acceptedItemsAtChange = acceptedItemsAtChange
    }
}

enum IntakeValidation: LocalizedError {
    case invalidTotal, invalidAccepted, invalidTime, decreasing, chronology

    var errorDescription: String? {
        switch self {
        case .invalidTotal: return "Всего должно быть больше нуля."
        case .invalidAccepted: return "Количество должно быть от 0 до общего числа."
        case .invalidTime: return "Укажи корректное время, не позже текущего."
        case .decreasing: return "Новое значение не может быть меньше предыдущего замера."
        case .chronology: return "Замеры должны идти по времени и не уменьшаться."
        }
    }
}

enum IntakeValidator {
    static func new(start: Date, accepted: Int, total: Int, now: Date = .now) throws {
        guard total > 0 else { throw IntakeValidation.invalidTotal }
        guard (0...total).contains(accepted) else { throw IntakeValidation.invalidAccepted }
        guard start <= now else { throw IntakeValidation.invalidTime }
    }

    static func measurement(_ count: Int, at time: Date, session: IntakeSession,
                            now: Date = .now) throws {
        guard (0...session.totalItems).contains(count) else { throw IntakeValidation.invalidAccepted }
        guard count >= session.acceptedNow else { throw IntakeValidation.decreasing }
        guard time > session.lastTime && time <= now else { throw IntakeValidation.invalidTime }
    }

    static func timeline(start: Date, initial: Int, total: Int,
                         points: [(Date, Int)], now: Date = .now) throws {
        try self.new(start: start, accepted: initial, total: total, now: now)
        var priorTime = start
        var priorCount = initial
        for (time, count) in points.sorted(by: { $0.0 < $1.0 }) {
            guard time > priorTime && time <= now else { throw IntakeValidation.chronology }
            guard count >= priorCount, count <= total else { throw IntakeValidation.chronology }
            priorTime = time
            priorCount = count
        }
    }
}
