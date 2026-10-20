import Foundation
import UIKit
import WidgetKit
import XCTest
@testable import Toolbox

final class AttendanceQRPresentationTests: XCTestCase {
    @MainActor
    func testRepeatedActivationAndBackgroundRestoreOriginalIdleState() {
        for original in [false, true] {
            var value = original
            var writes: [Bool] = []
            let timer = AttendanceQRIdleTimer(read: { value }, write: { value = $0; writes.append($0) })
            let owner = UUID()
            timer.setActive(true, owner: owner)
            timer.setActive(true, owner: owner)
            XCTAssertTrue(value)
            timer.setActive(false, owner: owner)
            timer.setActive(false, owner: owner)
            XCTAssertEqual(value, original)
            XCTAssertEqual(writes, [true, original])
            // Foregrounding takes a fresh snapshot rather than restoring an old value.
            value = !original
            timer.setActive(true, owner: owner)
            timer.setActive(false, owner: owner)
            XCTAssertEqual(value, !original)
        }
    }

    @MainActor
    func testMultipleScenesDoNotReleaseEachOthersIdleLease() {
        var value = false
        let timer = AttendanceQRIdleTimer(read: { value }, write: { value = $0 })
        let first = UUID(), second = UUID()
        timer.setActive(true, owner: first)
        timer.setActive(true, owner: second)
        timer.setActive(false, owner: first)
        XCTAssertTrue(value)
        timer.setActive(false, owner: second)
        XCTAssertFalse(value)
    }

    @MainActor
    func testWidgetRouteReplacesConfigurationAndCloseClearsPayload() throws {
        let scene = AttendanceQRSceneDelegate()
        let activity = NSUserActivity(activityType: "synthetic-test")
        activity.userInfo = [WidgetCenter.UserInfoKey.kind: "AttendanceQRWidget"]
        let intent = AttendanceQRWidgetConfigurationIntent()
        intent.label = "勤怠QR"
        intent.payload = " exact demo payload \n"
        intent.operation = .departure
        intent.duration = .sixtySeconds
        // Inject only WidgetKit extraction; the OS archive delivery needs a device.
        scene.receive(activity, resolve: { _ in intent })
        XCTAssertTrue(scene.isShowingQR)
        XCTAssertEqual(scene.configuration?.payload, intent.payload)
        XCTAssertEqual(scene.configuration?.operation, .arrival)
        XCTAssertEqual(scene.configuration?.durationSeconds, 30)
        intent.payload = "second-demo"
        scene.receive(activity, resolve: { _ in intent })
        XCTAssertEqual(scene.configuration?.payload, "second-demo")
        scene.close()
        XCTAssertFalse(scene.isShowingQR)
        XCTAssertNil(scene.configuration)
        scene.receive(activity, resolve: { _ in intent })
        XCTAssertTrue(scene.isShowingQR)
        XCTAssertEqual(scene.configuration?.payload, "second-demo")
    }

    @MainActor
    func testMissingOrInvalidConfigurationShowsSetupAndUnrelatedActivityIsIgnored() {
        let scene = AttendanceQRSceneDelegate()
        let other = NSUserActivity(activityType: "synthetic-test")
        other.userInfo = [WidgetCenter.UserInfoKey.kind: "OtherWidget"]
        scene.receive(other, resolve: { _ in XCTFail("Must not resolve unrelated widgets"); return nil })
        XCTAssertFalse(scene.isShowingQR)
        let activity = NSUserActivity(activityType: "synthetic-test")
        activity.userInfo = [WidgetCenter.UserInfoKey.kind: "AttendanceQRWidget"]
        scene.receive(activity, resolve: { _ in nil })
        XCTAssertTrue(scene.isShowingQR)
        XCTAssertNil(scene.configuration)
        let intent = AttendanceQRWidgetConfigurationIntent()
        intent.label = "勤怠QR"
        for payload in ["", " \n", String(repeating: "a", count: 65)] {
            intent.payload = payload
            scene.receive(activity, resolve: { _ in intent })
            XCTAssertTrue(scene.isShowingQR)
            XCTAssertNil(scene.configuration)
        }
    }
}
