import Foundation
import XCTest
@testable import Toolbox

final class ShortcutImportTests: XCTestCase {
    func testImportsWorkflowJSONXMLAndBinaryPlist() throws {
        let sample = ShortcutDraft.example
        let inputs = [Data(sample.source.utf8), try ShortcutFormat.plist(sample.source),
                      try ShortcutFormat.plist(sample.source, format: .binary)]
        for data in inputs {
            let imported = try ShortcutImport.decode(data, name: "Imported")
            XCTAssertEqual(imported.name, "Imported")
            XCTAssertEqual(imported.source, sample.source)
            XCTAssertEqual(imported.actionCount, 1)
        }
    }

    func testImportsOldStudioDraftWithNewIdentityAndHistory() throws {
        var draft = ShortcutDraft.example
        draft.replace(name: "Updated", source: draft.source, summary: "Edited")
        let imported = try ShortcutImport.decode(JSONEncoder().encode(draft), name: "File")
        XCTAssertNotEqual(imported.id, draft.id)
        XCTAssertEqual(imported.name, "Updated")
        XCTAssertEqual(imported.revisions.count, 1)
        XCTAssertEqual(imported.revisions.first?.source, draft.revisions.first?.source)
    }

    func testRejectsInvalidSourceInsideSavedDraft() throws {
        var draft = ShortcutDraft.example
        draft.source = "{}"
        XCTAssertThrowsError(try ShortcutImport.decode(JSONEncoder().encode(draft), name: "Bad"))
    }

    func testRejectsInvalidHistoryInsideSavedDraft() throws {
        var draft = ShortcutDraft.example
        draft.revisions = [ShortcutRevision(name: "Broken", source: "{}", summary: "")]
        XCTAssertThrowsError(try ShortcutImport.decode(JSONEncoder().encode(draft), name: "Bad"))
    }

    func testHeaderAloneDoesNotMakeSignedArchiveValid() {
        XCTAssertThrowsError(try ShortcutImport.decode(Data("AEA1not-an-archive".utf8), name: "Fake"))
    }

    func testRejectsNonFileImportURLs() throws {
        XCTAssertThrowsError(try ShortcutImport.read(XCTUnwrap(URL(string: "https://example.com/test.shortcut"))))
    }

    func testBoundedReadRejectsLargeFile() throws {
        let file = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 1, count: 101).write(to: file)
        XCTAssertThrowsError(try ShortcutImport.boundedRead(file, limit: 100))
        XCTAssertEqual(try ShortcutImport.boundedRead(file, limit: 101).count, 101)
    }

    func testRejectsOversizedImport() {
        XCTAssertThrowsError(try ShortcutImport.decode(Data(count: ShortcutImport.maximumFileSize + 1), name: "Large"))
    }
}
