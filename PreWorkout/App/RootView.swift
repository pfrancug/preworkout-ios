import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.phase {
        case .checking:
            ProgressView()
        case .needsLogin:
            LoginView()
        case .offline(let message):
            ContentUnavailableView {
                Label("Brak połączenia", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Spróbuj ponownie") { Task { await appState.bootstrap() } }
                    .buttonStyle(.borderedProminent)
            }
        case .ready:
            MainTabView()
                // Every screen reloads its data when the active person changes.
                .id(appState.activePersonId)
        }
    }
}

struct MainTabView: View {
    enum Tab: String {
        case workouts, exercises, profile
    }

    /// Survives the re-creation on person switch.
    @AppStorage("preworkout.tab") private var tab: Tab = .workouts

    var body: some View {
        TabView(selection: $tab) {
            WorkoutsView()
                .tabItem { Label("Treningi", systemImage: "dumbbell") }
                .tag(Tab.workouts)
            ExercisesView()
                .tabItem { Label("Ćwiczenia", systemImage: "figure.strengthtraining.traditional") }
                .tag(Tab.exercises)
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
    }
}
