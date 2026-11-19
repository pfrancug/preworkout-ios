import SwiftUI

/// Simple async loading wrapper used by the screens.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
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
                    .buttonStyle(.bordered)
            }
        case .loaded(let value):
            content(value)
        }
    }
}
