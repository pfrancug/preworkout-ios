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
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Pulpit", systemImage: "house") }
            DiaryView()
                .tabItem { Label("Dziennik", systemImage: "book") }
            TrainingView()
                .tabItem { Label("Trening", systemImage: "dumbbell") }
            CalendarView()
                .tabItem { Label("Kalendarz", systemImage: "calendar") }
            MoreView()
                .tabItem { Label("Więcej", systemImage: "ellipsis.circle") }
        }
    }
}
