import Foundation
import XCTest
@testable import Toolbox

final class ShortcutSignedArchiveTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")
        return try Data(contentsOf: root.appending(path: name))
    }

    func testAuthenticatedSyntheticArchiveDecodesToExactReturnedWorkflow() throws {
        let expected = try XCTUnwrap(PropertyListSerialization.propertyList(from: fixture("synthetic-returned.plist"), options: [], format: nil) as? [String: Any])
        let signed = try fixture("synthetic-signed.shortcut")
        let actual = try ShortcutImport.unpackSignedArchive(signed)
        XCTAssertTrue(NSDictionary(dictionary: expected).isEqual(to: actual))
        XCTAssertNoThrow(try ShortcutSigner.validateSignedData(signed, source: ShortcutFormat.json(expected)))
    }

    func testObservedAbsentDefaultsAndProducerVersionAreAccepted() throws {
        let original = try XCTUnwrap(PropertyListSerialization.propertyList(from: fixture("synthetic-input.plist"), options: [], format: nil) as? [String: Any])
        XCTAssertNoThrow(try ShortcutSigner.validateSignedData(fixture("synthetic-signed.shortcut"), source: ShortcutFormat.json(original)))
    }

    func testSyntheticPhotoWorkflowPreservesActionsAndParameters() throws {
        let original = try XCTUnwrap(PropertyListSerialization.propertyList(from: fixture("synthetic-photo-input.plist"), options: [], format: nil) as? [String: Any])
        let signed = try fixture("synthetic-photo-signed.shortcut")
        let returned = try ShortcutImport.unpackSignedArchive(signed)
        XCTAssertNoThrow(try ShortcutSigner.validateSignedData(signed, source: ShortcutFormat.json(original)))
        let actions = try XCTUnwrap(returned["WFWorkflowActions"] as? [[String: Any]])
        XCTAssertEqual(actions.map { $0["WFWorkflowActionIdentifier"] as? String }, ["is.workflow.actions.filter.photos", "is.workflow.actions.previewdocument"])
        XCTAssertTrue(NSArray(array: actions).isEqual(to: original["WFWorkflowActions"] as! [Any]))
    }

    func testCorruptedAndTruncatedArchivesFailWithSafeDiagnostics() throws {
        let signed = try fixture("synthetic-signed.shortcut")
        var changed = signed; changed[changed.count / 2] ^= 1
        for data in [changed, Data(signed.prefix(signed.count / 2))] {
            XCTAssertThrowsError(try ShortcutImport.unpackSignedArchive(data)) { error in
                XCTAssertTrue(error is ShortcutError)
                XCTAssertFalse(error.localizedDescription.contains("AppleArchive.ArchiveError"))
            }
        }
    }
}
