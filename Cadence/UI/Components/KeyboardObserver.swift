import SwiftUI
import Combine

/// Publishes the current keyboard height. Use `@StateObject` (or the
/// `.keyboardAware()` modifier) when you need to lift content above the
/// keyboard for layouts SwiftUI's default safe-area avoidance can't handle —
/// e.g. fixed-position content inside a `ZStack(.bottom)`.
final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0

    private var cancellables = Set<AnyCancellable>()

    init() {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

        // receive(on: RunLoop.main) defers the publish to the next runloop iteration,
        // so the @Published mutation never lands during a SwiftUI body computation.
        Publishers.Merge(willShow, willChange)
            .compactMap { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height }
            .receive(on: RunLoop.main)
            .sink { [weak self] h in self?.height = h }
            .store(in: &cancellables)

        willHide
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.height = 0 }
            .store(in: &cancellables)
    }
}

extension View {
    /// Adds bottom padding equal to the keyboard height so anchored-bottom content
    /// (e.g. a panel inside `ZStack(.bottom)`) stays visible above the keyboard.
    /// The padding excludes `safeAreaBottom` so we don't double-count the home indicator.
    func keyboardAware() -> some View {
        modifier(KeyboardAwareModifier())
    }
}

private struct KeyboardAwareModifier: ViewModifier {
    @StateObject private var keyboard = KeyboardObserver()

    func body(content: Content) -> some View {
        content
            // Subtract a rough safe-area-bottom (34pt for home indicator) so we
            // don't double-count it. Off by a few points is fine in practice.
            .padding(.bottom, max(0, keyboard.height - 34))
            .animation(.easeOut(duration: 0.25), value: keyboard.height)
    }
}
