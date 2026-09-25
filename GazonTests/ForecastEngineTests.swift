import XCTest
@testable import Gazon

final class ForecastEngineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(_ minutes: Double, _ count: Int) -> IntakePoint {
        IntakePoint(time: start.addingTimeInterval(minutes * 60), count: count)
    }

    func testNoMeasurementsHasNoForecast() {
        let s = IntakeSnapshot(startTime: start, initialAcceptedItems: 0, totalItems: 600, measurements: [])
        let r = ForecastEngine.calculate(snapshot: s, now: start)
        XCTAssertNil(r.estimatedFinish)
        XCTAssertEqual(r.remainingItems, 600)
    }

    func testOverallRateAndOneHourRemaining() {
        let s = IntakeSnapshot(startTime: start, initialAcceptedItems: 0, totalItems: 600,
                               measurements: [point(60, 300)])
        let r = ForecastEngine.calculate(snapshot: s, now: start.addingTimeInterval(3600), method: .overall)
        XCTAssertEqual(r.overallRate, 5, accuracy: 0.0001)
        XCTAssertEqual(r.remainingItems, 300)
        XCTAssertEqual(r.remainingTime!, 3600, accuracy: 0.0001)
    }

    func testRecentAccelerationChangesSmoothedRate() {
        let slow = IntakeSnapshot(startTime: start, initialAcceptedItems: 0, totalItems: 600,
                                  measurements: [point(20, 40), point(40, 80), point(60, 120)])
        let fast = IntakeSnapshot(startTime: start, initialAcceptedItems: 0, totalItems: 600,
                                  measurements: [point(20, 40), point(40, 80), point(60, 200)])
        let a = ForecastEngine.calculate(snapshot: slow, now: point(60, 0).time)
        let b = ForecastEngine.calculate(snapshot: fast, now: point(60, 0).time)
        XCTAssertGreaterThan(b.smoothedRate!, a.smoothedRate!)
        XCTAssertLessThan(b.estimatedFinish!, a.estimatedFinish!)
    }

    func testSlowdownMovesForecastLater() {
        let fast = IntakeSnapshot(startTime: start, initialAcceptedItems: 0, totalItems: 600,
                                  measurements: [point(20, 80), point(40, 160), point(60, 240)])
        let slow = IntakeSnapshot(startTime: start, initialAcceptedItems: 0, totalItems: 600,
                                  measurements: [point(20, 80), point(40, 160), point(60, 180)])
        let a = ForecastEngine.calculate(snapshot: fast, now: point(60, 0).time)
        let b = ForecastEngine.calculate(snapshot: slow, now: point(60, 0).time)
        XCTAssertGreaterThan(b.estimatedFinish!, a.estimatedFinish!)
    }

    func testCompletion() {
        let s = IntakeSnapshot(startTime: start, initialAcceptedItems: 0, totalItems: 600,
                               measurements: [point(60, 600)])
        let r = ForecastEngine.calculate(snapshot: s, now: point(60, 0).time)
        XCTAssertEqual(r.progress, 1)
        XCTAssertEqual(r.remainingItems, 0)
        XCTAssertEqual(r.estimatedFinish, point(60, 0).time)
    }

    func testValidationRejectsOverTotalAndDuplicateTimestamp() {
        XCTAssertThrowsError(try IntakeValidator.new(start: start, accepted: 601, total: 600, now: start))
        XCTAssertThrowsError(try IntakeValidator.timeline(start: start, initial: 0, total: 600,
            points: [(point(10, 10).time, 10), (point(10, 20).time, 20)], now: point(20, 0).time))
    }

    func testShortBurstDoesNotBecomeOnlyRate() {
        let s = IntakeSnapshot(startTime: start, initialAcceptedItems: 0, totalItems: 600,
                               measurements: [point(60, 300), point(61, 400)])
        let r = ForecastEngine.calculate(snapshot: s, now: point(61, 0).time)
        XCTAssertLessThan(r.smoothedRate!, 10)
    }

    func testTeamChangeUsesOnlyNewIntervals() {
        let s = IntakeSnapshot(startTime: start, initialAcceptedItems: 0, totalItems: 600,
                               measurements: [point(30, 30), point(40, 40), point(50, 140)],
                               teamChanges: [point(40, 0).time])
        let r = ForecastEngine.calculate(snapshot: s, now: point(50, 0).time)
        XCTAssertEqual(r.smoothedRate!, 10, accuracy: 0.0001)
    }
}
