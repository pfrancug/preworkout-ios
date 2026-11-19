import SwiftUI

@main
struct PreWorkoutApp: App {
    @State private var appState = AppState()
    @State private var exercises = ExerciseStore()
    @State private var live = LiveStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(exercises)
                .environment(live)
                .task { await appState.bootstrap() }
        }
    }
}
