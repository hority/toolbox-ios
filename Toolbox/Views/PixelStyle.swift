import CoreText
import UIKit
import SwiftUI

/// Retro dot-art look for the brushing coach, matching its chiptune sounds.
enum PixelStyle {
    static let fontName = "DotGothic16-Regular"

    static let ink = Color(red: 0.17, green: 0.14, blue: 0.25)
    static let paper = Color(red: 1, green: 0.96, blue: 0.84)
    static let pink = Color(red: 1, green: 0.36, blue: 0.54)
    static let mint = Color(red: 0.24, green: 0.84, blue: 0.63)
    static let yellow = Color(red: 1, green: 0.82, blue: 0.25)
    static let sky = Color(red: 0.35, green: 0.75, blue: 1)

    /// Registers the bundled font once for this process; no Info.plist entry is needed.
    @MainActor static func registerFont() {
        guard !fontRegistered,
              let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        fontRegistered = true
    }

    @MainActor private static var fontRegistered = false
}

extension Font {
    static func pixel(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(PixelStyle.fontName, size: size, relativeTo: style)
    }
}

/// A rectangle with stepped corners, like a classic game window.
struct PixelFrame: Shape {
    var step: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let s = min(step, rect.width / 2, rect.height / 2)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + s, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + s))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - s))
            path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY - s))
            path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - s))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - s))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s))
            path.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s))
            path.closeSubpath()
        }
    }
}

extension View {
    /// A flat window with a thick ink border and a hard drop shadow.
    func pixelPanel(_ fill: Color = PixelStyle.paper, shadow: Bool = true) -> some View {
        background(PixelFrame().fill(fill))
            .overlay(PixelFrame().stroke(PixelStyle.ink, lineWidth: 3))
            .background(PixelFrame().fill(PixelStyle.ink.opacity(shadow ? 0.45 : 0)).offset(x: 4, y: 4))
    }
}

struct PixelButtonStyle: ButtonStyle {
    var fill: Color = PixelStyle.pink
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .pixelPanel(fill, shadow: !configuration.isPressed)
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
    }
}

/// A bundled dot-art image drawn with hard pixel edges.
struct PixelSprite: View {
    let name: String
    let width: CGFloat

    var height: CGFloat {
        guard let size = UIImage(named: name)?.size, size.width > 0 else { return width }
        return width * size.height / size.width
    }

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.none)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}
