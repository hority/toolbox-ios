import Foundation
import XCTest
@testable import Toolbox

@MainActor
final class ShortcutLibraryTests: XCTestCase {
    func testSaveReloadAndRemove() throws {
        let directory = URL.temporaryDirectory.appending(path: "ToolboxLibraryTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = ShortcutLibrary(directory: directory)
        XCTAssertNil(library.error)
        var draft = ShortcutDraft.example
        draft.name = "Saved locally"
        try library.upsert(draft)
        let reloaded = ShortcutLibrary(directory: directory)
        XCTAssertEqual(reloaded.drafts.first?.id, draft.id)
        XCTAssertEqual(reloaded.drafts.first?.name, "Saved locally")
        try reloaded.remove(draft.id)
        XCTAssertFalse(ShortcutLibrary(directory: directory).drafts.contains { $0.id == draft.id })
    }

    func testInvalidUpdateKeepsLastSavedDraft() throws {
        let directory = URL.temporaryDirectory.appending(path: "ToolboxLibraryTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = ShortcutLibrary(directory: directory)
        let original = try XCTUnwrap(library.drafts.first)
        var invalid = original
        invalid.source = "{}"
        XCTAssertThrowsError(try library.upsert(invalid))
        XCTAssertEqual(library.drafts.first?.source, original.source)
    }

    func testCorruptLibraryIsNotOverwrittenOnRead() throws {
        let directory = URL.temporaryDirectory.appending(path: "ToolboxLibraryTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "drafts.json")
        let corrupt = Data("broken-json".utf8)
        try corrupt.write(to: file)
        let library = ShortcutLibrary(directory: directory)
        XCTAssertNotNil(library.error)
        XCTAssertThrowsError(try library.upsert(.example))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
}
