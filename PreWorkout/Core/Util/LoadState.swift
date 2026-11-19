import SwiftUI

/// Simple async loading wrapper used by the screens.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

struct LoadStateView<Value, Content: View>: View {
    let state: LoadState<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Nie udało się wczytać", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Spróbuj ponownie") { Task { await retry() } }
            }
        case .loaded(let value):
            content(value)
        }
    }
}
