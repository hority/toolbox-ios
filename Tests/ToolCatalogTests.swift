import XCTest
@testable import Toolbox

final class ToolCatalogTests: XCTestCase {
    func testEmptySearchShowsAllTools() {
        XCTAssertEqual(ToolCatalog.tools(matching: "", filter: .all).map(\.id), [.textCounter, .shortcutSigning, .attendanceQR])
    }

    func testSearchIgnoresOuterWhitespaceAndCase() {
        XCTAssertEqual(ToolCatalog.tools(matching: "  TeXT\n", filter: .all).map(\.id), [.textCounter])
    }

    func testJapaneseSearchMatchesTitle() {
        XCTAssertEqual(ToolCatalog.tools(matching: "署名", filter: .all).map(\.id), [.shortcutSigning])
    }

    func testWhitespaceSearchShowsAllTools() {
        XCTAssertEqual(ToolCatalog.tools(matching: " \n\t", filter: .all).count, ToolCatalog.all.count)
    }

    func testAvailableFilterIncludesImplementedTools() {
        XCTAssertEqual(ToolCatalog.tools(matching: "", filter: .available).map(\.id), [.textCounter, .shortcutSigning, .attendanceQR])
    }

    func testPlannedFilterIsEmpty() {
        XCTAssertEqual(ToolCatalog.tools(matching: "", filter: .planned).map(\.id), [])
    }

    func testSearchAndAvailabilityFilterBothApply() {
        XCTAssertEqual(ToolCatalog.tools(matching: "署名", filter: .available).map(\.id), [.shortcutSigning])
    }

    func testUnknownSearchReturnsNoResults() {
        XCTAssertTrue(ToolCatalog.tools(matching: "definitely not a tool", filter: .all).isEmpty)
    }

    func testCatalogIdentifiersAreUnique() {
        let identifiers = ToolCatalog.all.map(\.id)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testSigningIsAvailable() {
        let signing = ToolCatalog.all.first { $0.id == .shortcutSigning }
        XCTAssertNotNil(signing)
        XCTAssertEqual(signing?.availability, .available)
    }
}
