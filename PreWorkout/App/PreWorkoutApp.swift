import SwiftUI

@main
struct PreWorkoutApp: App {
    @State private var appState = AppState()
    @State private var exercises = ExerciseStore()
    @State private var live = LiveStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(exercises)
                .environment(live)
                .task {
                    Outbox.shared.start()
                    await appState.bootstrap()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Outbox.shared.flush() }
        }
    }
}
