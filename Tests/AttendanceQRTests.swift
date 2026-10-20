import CoreGraphics
import Foundation
import Vision
import XCTest
@testable import Toolbox

/// Source-only until the owner explicitly runs the manual simulator test workflow.
/// All fixtures are synthetic; these tests never request a Live Activity or use a camera.
final class AttendanceQRTests: XCTestCase {
    func testPayloadBytesArePreservedWithoutTrimmingOrNormalization() throws {
        let payload = " e\u{301}・登庁 \n"
        let configuration = try makeConfiguration(payload: payload)
        XCTAssertEqual(Data(configuration.payload.utf8), Data(payload.utf8))
        XCTAssertNotEqual(Data(configuration.payload.utf8), Data(" é・登庁 \n".utf8))
    }

    func testPayloadLimitCountsUTF8BytesRatherThanCharacters() throws {
        XCTAssertNoThrow(try makeConfiguration(payload: String(repeating: "a", count: 64)))
        XCTAssertThrowsError(try makeConfiguration(payload: String(repeating: "a", count: 65))) {
            XCTAssertEqual($0 as? AttendanceQRError, .payloadTooLong)
        }
        XCTAssertNoThrow(try makeConfiguration(payload: String(repeating: "庁", count: 21)))
        XCTAssertThrowsError(try makeConfiguration(payload: String(repeating: "庁", count: 22))) {
            XCTAssertEqual($0 as? AttendanceQRError, .payloadTooLong)
        }
        for payload in ["", "  ", "\n\t", "\u{3000}"] {
            XCTAssertThrowsError(try makeConfiguration(payload: payload)) {
                XCTAssertEqual($0 as? AttendanceQRError, .emptyPayload)
            }
        }
    }

    func testDurationValidationAllowsExactlyThirtyOrSixtySeconds() throws {
        for duration in [30, 60] {
            XCTAssertEqual(try makeConfiguration(duration: duration).durationSeconds, duration)
        }
        for duration in [Int.min, -1, 0, 1, 29, 31, 59, 61, Int.max] {
            XCTAssertThrowsError(try makeConfiguration(duration: duration)) {
                XCTAssertEqual($0 as? AttendanceQRError, .unsupportedDuration)
            }
        }
        XCTAssertEqual(Set(AttendanceQRDuration.allCases.map(\.seconds)), Set([30, 60]))
    }

    func testLabelValidationAndTrimming() throws {
        XCTAssertEqual(try AttendanceQRConfiguration(label: " 登庁 ", payload: "demo",
                                                     operation: .arrival, durationSeconds: 30).label, "登庁")
        for label in ["", " \n"] {
            XCTAssertThrowsError(try AttendanceQRConfiguration(label: label, payload: "demo",
                                                               operation: .arrival, durationSeconds: 30)) {
                XCTAssertEqual($0 as? AttendanceQRError, .emptyLabel)
            }
        }
        for label in [String(repeating: "a", count: 17), String(repeating: "👨‍👩‍👧‍👦", count: 3)] {
            XCTAssertThrowsError(try AttendanceQRConfiguration(label: label, payload: "demo",
                                                               operation: .departure, durationSeconds: 60)) {
                XCTAssertEqual($0 as? AttendanceQRError, .labelTooLong)
            }
        }
    }

    func testRenderedQRDecodesToExactUTF8BytesWithVision() throws {
        let fixtures = [
            "toolbox-demo-arrival",
            "https://example.invalid/attendance?id=DEMO&kind=in",
            "登庁・工具箱・架空データ",
            " e\u{301} 👋 \n",
            String(repeating: "a", count: AttendanceQRConfiguration.maximumPayloadBytes),
            String(repeating: "庁", count: 21)
        ]
        for scale in [CGFloat(2), CGFloat(3)] {
            for payload in fixtures {
                let code = try AttendanceQRRenderer.render(payload: payload, displayScale: scale)
                let request = VNDetectBarcodesRequest()
                request.revision = VNDetectBarcodesRequestRevision4
                request.symbologies = [.qr]
                try VNImageRequestHandler(cgImage: code.image, options: [:]).perform([request])
                let observation = try XCTUnwrap(request.results?.first)
                XCTAssertEqual(request.results?.count, 1)
                XCTAssertEqual(try XCTUnwrap(observation.payloadData), Data(payload.utf8))
            }
        }
    }

    func testQRHasFourWhiteModulesAndNoAntialiasing() throws {
        for scale in [CGFloat(2), CGFloat(3)] {
            let code = try AttendanceQRRenderer.render(
                payload: String(repeating: "a", count: 64), displayScale: scale
            )
            let image = code.image
            let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
            let side = image.width
            let quiet = code.quietZonePixels
            XCTAssertEqual(image.height, side)
            XCTAssertEqual(image.bitsPerPixel, 8)
            XCTAssertEqual(image.bytesPerRow, side)
            XCTAssertFalse(image.shouldInterpolate)
            XCTAssertEqual(side, (code.symbolModules + 8) * code.pixelsPerModule)
            XCTAssertLessThanOrEqual(code.symbolModules, 37)
            XCTAssertGreaterThanOrEqual(code.pointSide, 120)
            XCTAssertLessThanOrEqual(code.pointSide, 140)
            XCTAssertEqual(code.leadingInset * scale, floor(code.leadingInset * scale))
            XCTAssertEqual(Set(bytes), Set([UInt8(0), UInt8(255)]))

            var minBlackX = side
            var minBlackY = side
            var maxBlackX = -1
            var maxBlackY = -1
            for y in 0..<side {
                for x in 0..<side {
                    let pixel = bytes[y * side + x]
                    if x < quiet || y < quiet || x >= side - quiet || y >= side - quiet {
                        XCTAssertEqual(pixel, 255, "The four-module quiet zone must stay white")
                    }
                    let moduleX = (x / code.pixelsPerModule) * code.pixelsPerModule
                    let moduleY = (y / code.pixelsPerModule) * code.pixelsPerModule
                    XCTAssertEqual(pixel, bytes[moduleY * side + moduleX], "Every module is pixel aligned")
                    if pixel == 0 {
                        minBlackX = min(minBlackX, x)
                        minBlackY = min(minBlackY, y)
                        maxBlackX = max(maxBlackX, x)
                        maxBlackY = max(maxBlackY, y)
                    }
                }
            }
            XCTAssertEqual(minBlackX, quiet)
            XCTAssertEqual(minBlackY, quiet)
            XCTAssertEqual(maxBlackX, side - quiet - 1)
            XCTAssertEqual(maxBlackY, side - quiet - 1)
        }
    }

    func testFullscreenRenderingPreservesBytesQuietZoneAndPixelAlignment() throws {
        for scale in [CGFloat(2), CGFloat(3)] {
            for canvas in [CGFloat(288), CGFloat(361), CGFloat(398)] {
                let payload = " e\u{301}・共通デモ \n"
                let code = try AttendanceQRRenderer.render(payload: payload, displayScale: scale,
                                                          canvasSide: canvas)
                XCTAssertLessThanOrEqual(code.pointSide, canvas)
                XCTAssertGreaterThan(code.pointSide, 260)
                XCTAssertEqual(code.leadingInset * scale, floor(code.leadingInset * scale))
                let bytes = try XCTUnwrap(code.image.dataProvider?.data) as Data
                let side = code.image.width
                let quiet = code.quietZonePixels
                XCTAssertEqual(side, (code.symbolModules + 8) * code.pixelsPerModule)
                XCTAssertEqual(Set(bytes), Set([UInt8(0), UInt8(255)]))
                for y in 0..<side {
                    for x in 0..<side where x < quiet || y < quiet || x >= side - quiet || y >= side - quiet {
                        XCTAssertEqual(bytes[y * side + x], 255)
                    }
                }
                let request = VNDetectBarcodesRequest()
                request.revision = VNDetectBarcodesRequestRevision4
                request.symbologies = [.qr]
                try VNImageRequestHandler(cgImage: code.image, options: [:]).perform([request])
                XCTAssertEqual(try XCTUnwrap(request.results?.first?.payloadData), Data(payload.utf8))
            }
        }
        for canvas in [CGFloat.zero, 135, .infinity, .nan, 1025] {
            XCTAssertThrowsError(try AttendanceQRRenderer.render(payload: "demo", displayScale: 3,
                                                                canvasSide: canvas))
        }
    }

    func testInvalidScaleAndOversizedPayloadFailBeforeRendering() {
        for scale in [CGFloat.zero, -1, .infinity, .nan, 5] {
            XCTAssertThrowsError(try AttendanceQRRenderer.render(payload: "demo", displayScale: scale)) {
                XCTAssertEqual($0 as? AttendanceQRError, .invalidDisplayScale)
            }
        }
        XCTAssertThrowsError(try AttendanceQRRenderer.render(payload: String(repeating: "a", count: 65),
                                                            displayScale: 3)) {
            XCTAssertEqual($0 as? AttendanceQRError, .payloadTooLong)
        }
    }

    func testExpiredStaleStoppedAndInvalidStatesNeverExposeQR() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let state = AttendanceQRActivityAttributes.ContentState(
            payload: "toolbox-demo", startedAt: start, expiresAt: start.addingTimeInterval(30)
        )
        XCTAssertTrue(state.shouldDisplayQR(at: start, isStale: false))
        XCTAssertTrue(state.shouldDisplayQR(at: start.addingTimeInterval(29.99), isStale: false))
        XCTAssertFalse(state.shouldDisplayQR(at: start.addingTimeInterval(30), isStale: false))
        XCTAssertFalse(state.shouldDisplayQR(at: start.addingTimeInterval(31), isStale: false))
        XCTAssertFalse(state.shouldDisplayQR(at: start.addingTimeInterval(-1), isStale: false))
        XCTAssertFalse(state.shouldDisplayQR(at: start, isStale: true))
        XCTAssertFalse(state.hidden.shouldDisplayQR(at: start, isStale: false))
        XCTAssertNil(state.hidden.payload)

        for duration in [0.0, 29.0, 30.5, 61.0] {
            let invalid = AttendanceQRActivityAttributes.ContentState(
                payload: "demo", startedAt: start, expiresAt: start.addingTimeInterval(duration)
            )
            XCTAssertFalse(invalid.shouldDisplayQR(at: start, isStale: false))
        }
        let oversized = AttendanceQRActivityAttributes.ContentState(
            payload: String(repeating: "a", count: 65), startedAt: start,
            expiresAt: start.addingTimeInterval(60)
        )
        XCTAssertFalse(oversized.shouldDisplayQR(at: start, isStale: false))
    }

    func testIntentPassesConfigurationDirectlyWithoutOpeningApp() throws {
        let configuration = try makeConfiguration(payload: " exact payload ", duration: 60)
        let intent = ShowAttendanceQRIntent(configuration: configuration)
        XCTAssertEqual(intent.label, configuration.label)
        XCTAssertEqual(Data(intent.payload.utf8), Data(configuration.payload.utf8))
        XCTAssertEqual(intent.operation, configuration.operation)
        XCTAssertEqual(intent.duration.seconds, 60)
        XCTAssertFalse(ShowAttendanceQRIntent.openAppWhenRun)
        XCTAssertFalse(HideAttendanceQRIntent.openAppWhenRun)
    }

    func testEncodedLiveActivityContentRemainsBelowFourKilobytes() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let attributes = AttendanceQRActivityAttributes(label: String(repeating: "庁", count: 16),
                                                       operation: .departure)
        let state = AttendanceQRActivityAttributes.ContentState(
            payload: String(repeating: "\\", count: 64), startedAt: start,
            expiresAt: start.addingTimeInterval(60)
        )
        let size = try JSONEncoder().encode(attributes).count + JSONEncoder().encode(state).count
        XCTAssertLessThan(size, 4096)
    }

    private func makeConfiguration(payload: String = "toolbox-demo", duration: Int = 30) throws
        -> AttendanceQRConfiguration {
        try AttendanceQRConfiguration(label: "勤怠QR", payload: payload,
                                      operation: .arrival, durationSeconds: duration)
    }
}
