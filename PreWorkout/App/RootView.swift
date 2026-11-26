import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(ExerciseStore.self) private var exercises
    @Environment(LiveStore.self) private var live

    var body: some View {
        content
            .onChange(of: appState.phase) { _, newPhase in
                if case .needsLogin = newPhase {
                    exercises.reset()
                    live.unload()
                }
            }
            .onChange(of: appState.accountDeletedCount) { _, _ in
                exercises.reset(clearPreferences: true)
                live.unload()
            }
            .onChange(of: appState.account?.id) { oldId, newId in
                if oldId != newId {
                    exercises.reset()
                    live.unload()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
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
    @Environment(AppState.self) private var appState
    @Environment(ExerciseStore.self) private var exercises
    @Environment(LiveStore.self) private var live

    enum Tab: String {
        case workouts, exercises, live, calories, profile
    }

    /// Survives the re-creation on person switch.
    @AppStorage("preworkout.tab") private var tab: Tab = .workouts
    @State private var whatsNew = WhatsNewStore.shared

    var body: some View {
        TabView(selection: $tab) {
            WorkoutsView()
                .tabItem { Label("Treningi", systemImage: "dumbbell") }
                .tag(Tab.workouts)
            ExercisesView()
                .tabItem { Label("Ćwiczenia", systemImage: "figure.strengthtraining.traditional") }
                .tag(Tab.exercises)
            LiveTab()
                .tabItem { Label("Na żywo", systemImage: live.session != nil ? "record.circle.fill" : "play.circle.fill") }
                .badge(live.session != nil ? Text(verbatim: "●") : nil)
                .tag(Tab.live)
            CaloriesView()
                .tabItem { Label("Kalorie", systemImage: "flame") }
                .tag(Tab.calories)
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .sheet(isPresented: $whatsNew.showSheet) {
            WhatsNewSheet(items: whatsNew.highlights)
        }
        .onChange(of: tab) { live.presented = tab == .live }
        .onChange(of: live.savedCount) { tab = .workouts }
        .task {
            whatsNew.checkOnLaunch()
            live.exerciseName = { [exercises] id in exercises.name(id) }
            await live.load(person: appState.activePersonId)
            live.presented = tab == .live
        }
    }
}
