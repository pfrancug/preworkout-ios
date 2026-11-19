import SwiftUI

@main
struct PreWorkoutApp: App {
    @State private var appState = AppState()
    @State private var exercises = ExerciseStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(exercises)
                .task { await appState.bootstrap() }
        }
    }
}
