import SwiftUI

private struct NeutralFocus: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(.white.opacity(focused ? 0.32 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func neutralFocus() -> some View { modifier(NeutralFocus()) }
}
