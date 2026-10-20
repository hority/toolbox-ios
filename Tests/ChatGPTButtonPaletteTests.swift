import XCTest
@testable import Toolbox

final class ChatGPTButtonPaletteTests: XCTestCase {
    func testLightDarkPressedAndDisabledTextContrast() {
        func luminance(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        for dark in [false, true] {
            for enabled in [false, true] {
                for pressed in [false, true] {
                    let colors = ChatGPTButtonPalette(dark: dark, enabled: enabled, pressed: pressed)
                    let a = luminance(colors.foreground), b = luminance(colors.background)
                    XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5)
                }
            }
        }
    }
}
