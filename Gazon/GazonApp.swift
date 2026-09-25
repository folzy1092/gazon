import SwiftUI
import SwiftData

@main
struct GazonApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [IntakeSession.self, Measurement.self, TeamChange.self])
    }
}
