import Foundation

/// Grayscale sRGB components, kept independent of SwiftUI for contrast tests.
struct ChatGPTButtonPalette {
    let foreground: Double
    let background: Double

    init(dark: Bool, enabled: Bool, pressed: Bool) {
        if !enabled {
            foreground = dark ? 0.75 : 0.30
            background = dark ? 0.20 : 0.85
        } else {
            foreground = dark ? 0 : 1
            background = dark ? (pressed ? 0.85 : 1) : (pressed ? 0.15 : 0)
        }
    }
}
