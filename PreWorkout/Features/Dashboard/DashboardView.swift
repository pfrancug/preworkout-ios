import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var days = 28
    @State private var state: LoadState<AnalyticsSummary> = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink {
                        LiveWorkoutView()
                    } label: {
                        Label("Prowadź trening", systemImage: "timer")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.tint, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }

                    Picker("Zakres", selection: $days) {
                        Text("7 dni").tag(7)
                        Text("28 dni").tag(28)
                        Text("90 dni").tag(90)
                    }
                    .pickerStyle(.segmented)

                    LoadStateView(state: state, retry: load) { summary in
                        SummaryGrid(summary: summary)
                    }
                    .frame(minHeight: 200)
                }
                .padding()
            }
            .navigationTitle(appState.activePerson?.displayName ?? String(localized: "Pulpit"))
            .refreshable { await load() }
            .task(id: days) { await load() }
        }
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            state = .loaded(try await APIClient.shared.analyticsSummary(person: appState.activePersonId, days: days))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct SummaryGrid: View {
    let summary: AnalyticsSummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Waga", value: summary.weight.latest.map { Optional($0.weight).display(1, unit: "kg") } ?? "–",
                     detail: rateText)
            StatCard(title: "Średnia 7 dni", value: summary.weight.avg7.display(1, unit: "kg"),
                     detail: summary.weight.change.map { String(format: "%+.1f kg", $0) } ?? "")
            StatCard(title: "Kalorie (śr.)", value: summary.nutrition.avg.kcal.display(0, unit: "kcal"),
                     detail: String(localized: "\(summary.nutrition.loggedDays) dni wpisanych"))
            StatCard(title: "Białko (śr.)", value: summary.nutrition.avg.protein.display(0, unit: "g"),
                     detail: summary.nutrition.proteinPerKg.display(1, unit: "g/kg"))
            StatCard(title: "Treningi", value: "\(summary.training.workouts)",
                     detail: String(localized: "\(summary.training.trainingDays) dni treningowych"))
            StatCard(title: "Ostatni trening",
                     value: summary.training.lastTrainingDate.map(DayString.label) ?? "–",
                     detail: String(localized: "Najdłuższa przerwa: \(summary.training.longestGapDays) dni"))
        }
    }

    private var rateText: String {
        guard let rate = summary.weight.ratePerWeek else { return "" }
        return String(format: "%+.2f kg/tydz.", rate)
    }
}

struct StatCard: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
