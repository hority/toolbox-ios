import SwiftUI

/// Explicit paired colors avoid `.tint(.primary)` inheriting a white title on
/// the white prominent-button fill in dark mode. Disabled labels stay legible.
struct ChatGPTConnectionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let colors = ChatGPTButtonPalette(dark: scheme == .dark, enabled: enabled, pressed: configuration.isPressed)
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(Color(white: colors.foreground))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(white: colors.background), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
