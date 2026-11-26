import SwiftUI

/// Profile › What's new: every released version with its changes.
struct WhatsNewView: View {
    @State private var store = WhatsNewStore.shared

    var body: some View {
        List {
            ForEach(store.released) { entry in
                Section {
                    ForEach(entry.items) { item in
                        ChangeRow(item: item)
                    }
                } header: {
                    HStack {
                        Text("Wersja \(entry.version)")
                        Spacer()
                        if let date = entry.date {
                            Text(verbatim: DayString.label(date))
                        }
                    }
                }
            }
        }
        .navigationTitle("Co nowego")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.markSeen()
            Analytics.send("WhatsNew.viewed")
        }
    }
}

struct ChangeRow: View {
    let item: ChangelogItem

    var body: some View {
        Label {
            Text(verbatim: item.text)
                .font(item.highlight ? .body.weight(.semibold) : .body)
        } icon: {
            Image(systemName: item.icon)
                .foregroundStyle(item.highlight ? Color.accentColor : Color.secondary)
        }
    }
}

/// Small bottom sheet after an update: up to 4 highlights from every version
/// the user hasn't seen yet, newest first.
struct WhatsNewSheet: View {
    let items: [ChangelogItem]
    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Co nowego w PreWorkout")
                    .font(.title3.weight(.bold))
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            Text(verbatim: item.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    NavigationLink {
                        WhatsNewView()
                            .onAppear { detent = .large }
                    } label: {
                        Text("Zobacz wszystkie zmiany").font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    Button("Super") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onAppear { Analytics.send("WhatsNew.viewed") }
    }
}
