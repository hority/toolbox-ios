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

    func testChangedMetadataStillFailsExactWorkflowValidation() throws {
        let original = try XCTUnwrap(PropertyListSerialization.propertyList(from: fixture("synthetic-input.plist"), options: [], format: nil) as? [String: Any])
        XCTAssertThrowsError(try ShortcutSigner.validateSignedData(fixture("synthetic-signed.shortcut"), source: ShortcutFormat.json(original))) { error in
            XCTAssertTrue(error.localizedDescription.contains("端末内の検証"))
            XCTAssertTrue(error.localizedDescription.contains("異なります"))
        }
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
