import Foundation
import XCTest
@testable import Toolbox

final class ShortcutFormatTests: XCTestCase {
    func testSampleIsValidAndHasOneAction() throws {
        let sample = ShortcutDraft.example
        try ShortcutFormat.validate(sample)
        XCTAssertEqual(sample.actionCount, 1)
    }

    func testJSONAndBinaryPlistRoundTrip() throws {
        let source = ShortcutDraft.example.source
        let data = try ShortcutFormat.plist(source, format: .binary)
        XCTAssertTrue(data.starts(with: Data("bplist".utf8)))
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        XCTAssertEqual(try ShortcutFormat.json(object), source)
    }

    func testPlistDataAndDatesSurviveJSONEditingFormat() throws {
        var workflow = try ShortcutFormat.workflow(ShortcutDraft.example.source)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        workflow["TestData"] = Data([0, 1, 127, 255])
        workflow["TestDate"] = date
        let decoded = try ShortcutFormat.workflow(ShortcutFormat.json(workflow))
        XCTAssertEqual(decoded["TestData"] as? Data, Data([0, 1, 127, 255]))
        XCTAssertEqual(decoded["TestDate"] as? Date, date)
    }

    func testLegacyDateMarkerIsAccepted() throws {
        let source = #"{"WFWorkflowActions":[],"date":{"$studioDate":"2023-11-14T22:13:20Z"}}"#
        let object = try ShortcutFormat.workflow(source)
        XCTAssertEqual(object["date"] as? Date, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testRejectsMissingActionsInvalidActionsAndNull() {
        for source in ["{}", #"{"WFWorkflowActions":null}"#,
                       #"{"WFWorkflowActions":[{"WFWorkflowActionIdentifier":"test"}]}"#,
                       #"{"WFWorkflowActions":[],"value":null}"#] {
            XCTAssertThrowsError(try ShortcutFormat.workflow(source))
        }
    }

    func testRejectsInvalidDataAndDateMarkers() {
        for marker in [#"{"$studioData":"%%%"}"#, #"{"$studioDate":"not-a-date"}"#] {
            XCTAssertThrowsError(try ShortcutFormat.workflow("{\"WFWorkflowActions\":[],\"value\":\(marker)}"))
        }
    }

    func testRejectsOversizedSourceAndTooManyActions() throws {
        XCTAssertThrowsError(try ShortcutFormat.workflow(String(repeating: " ", count: 2_000_001)))
        let action: [String: Any] = ["WFWorkflowActionIdentifier": "test", "WFWorkflowActionParameters": [:]]
        let source = try ShortcutFormat.json(["WFWorkflowActions": Array(repeating: action, count: 501)])
        XCTAssertThrowsError(try ShortcutFormat.workflow(source))
    }

    func testFilenameCannotEscapeExportDirectory() {
        XCTAssertEqual(ShortcutFormat.safeName("../../folder\\file:\nname"), "_.._folder_file__name")
        XCTAssertEqual(ShortcutFormat.safeName("..."), "Shortcut")
        XCTAssertEqual(ShortcutFormat.safeName("   "), "Shortcut")
        XCTAssertLessThanOrEqual(ShortcutFormat.safeName(String(repeating: "あ", count: 100)).count, 80)
        XCTAssertLessThanOrEqual(ShortcutFormat.safeName(String(repeating: "👨‍👩‍👧‍👦", count: 100)).utf8.count, 180)
    }

    func testHistoryPreservesPreviousContentAndIsCapped() throws {
        var draft = ShortcutDraft.example
        let firstSource = draft.source
        draft.replace(name: "Version 1", source: firstSource, summary: "Updated")
        XCTAssertEqual(draft.revisions.first?.name, "はじめてのショートカット")
        XCTAssertEqual(draft.revisions.first?.source, firstSource)
        for index in 2...15 { draft.replace(name: "Version \(index)", source: firstSource, summary: "Updated") }
        XCTAssertEqual(draft.revisions.count, 10)
        XCTAssertEqual(draft.revisions.first?.name, "Version 14")
        try ShortcutFormat.validate(draft)
    }
}
