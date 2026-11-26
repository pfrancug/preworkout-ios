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
        case workouts, calendar, live, body, profile
    }

    /// Survives the re-creation on person switch.
    @AppStorage("preworkout.tab") private var tab: Tab = .workouts
    @State private var whatsNew = WhatsNewStore.shared
    private let outbox = Outbox.shared

    var body: some View {
        TabView(selection: $tab) {
            WorkoutsView()
                .outboxBadge()
                .tabItem { Label("Treningi", systemImage: "dumbbell") }
                .tag(Tab.workouts)
            CalendarView()
                .outboxBadge()
                .tabItem { Label("Kalendarz", systemImage: "calendar") }
                .tag(Tab.calendar)
            LiveTab()
                .tabItem { Label("Na żywo", systemImage: live.session != nil ? "record.circle.fill" : "play.circle.fill") }
                .badge(live.session != nil ? Text(verbatim: "●") : nil)
                .tag(Tab.live)
            BodyView()
                .outboxBadge()
                .tabItem { Label("Ciało", systemImage: "figure.arms.open") }
                .tag(Tab.body)
            ProfileView()
                .outboxBadge()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .sheet(isPresented: $whatsNew.showSheet) {
            WhatsNewSheet(items: whatsNew.highlights)
        }
        .alert(
            "Nie zapisano zmiany",
            isPresented: Binding(
                get: { outbox.rejectedMessage != nil },
                set: { if !$0 { outbox.rejectedMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(outbox.rejectedMessage ?? "")
        }
        .onChange(of: tab) { _, newTab in
            live.presented = newTab == .live
            Analytics.send("Tab.switched", ["tab": newTab.rawValue])
        }
        .onChange(of: live.savedCount) { tab = .workouts }
        .task {
            whatsNew.checkOnLaunch()
            live.exerciseName = { [exercises] id in exercises.name(id) }
            await live.load(person: appState.activePersonId)
            live.presented = tab == .live
        }
    }
}
