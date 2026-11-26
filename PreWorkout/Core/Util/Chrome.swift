import SwiftUI
import Sentry

extension View {
    /// Opaque navigation bar so a pushed screen does not draw a second
    /// hairline over the bar that is still animating out.
    func appNavigationChrome() -> some View {
        toolbarBackground(.visible, for: .navigationBar)
    }

    /// Pin the tab bar visible on tab roots and on screens that hide the
    /// navigation bar. A cancelled interactive pop, a fast path reset or a
    /// sheet dismissal can otherwise leave the tab bar stuck hidden, even
    /// though this app never hides it itself.
    func keepsTabBarVisible(_ screen: String) -> some View {
        modifier(KeepsTabBarVisible(screen: screen))
    }
}

private struct KeepsTabBarVisible: ViewModifier {
    let screen: String

    func body(content: Content) -> some View {
        content
            .toolbar(.visible, for: .tabBar)
            .onAppear { crumb("appear") }
            .onDisappear { crumb("disappear") }
    }

    private func crumb(_ event: String) {
        let crumb = Breadcrumb(level: .info, category: "ui")
        crumb.message = "tabBar.visible"
        crumb.data = ["screen": screen, "event": event]
        SentrySDK.addBreadcrumb(crumb)
    }
}
