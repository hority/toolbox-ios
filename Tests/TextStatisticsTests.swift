import XCTest
@testable import Toolbox

final class TextStatisticsTests: XCTestCase {
    func testEmptyText() {
        let result = TextStatistics(text: "")
        XCTAssertEqual(result.characterCount, 0)
        XCTAssertEqual(result.nonWhitespaceCharacterCount, 0)
        XCTAssertEqual(result.lineCount, 0)
        XCTAssertEqual(result.utf8ByteCount, 0)
    }

    func testASCIIText() {
        let result = TextStatistics(text: "Hello world")
        XCTAssertEqual(result.characterCount, 11)
        XCTAssertEqual(result.nonWhitespaceCharacterCount, 10)
        XCTAssertEqual(result.lineCount, 1)
        XCTAssertEqual(result.utf8ByteCount, 11)
    }

    func testJapaneseText() {
        let result = TextStatistics(text: "工具箱")
        XCTAssertEqual(result.characterCount, 3)
        XCTAssertEqual(result.nonWhitespaceCharacterCount, 3)
        XCTAssertEqual(result.lineCount, 1)
        XCTAssertEqual(result.utf8ByteCount, 9)
    }

    func testCombinedEmojiCountsAsOneCharacter() {
        let result = TextStatistics(text: "👨‍👩‍👧‍👦")
        XCTAssertEqual(result.characterCount, 1)
        XCTAssertEqual(result.nonWhitespaceCharacterCount, 1)
        XCTAssertEqual(result.utf8ByteCount, 25)
    }

    func testCombiningAccentCountsAsOneCharacter() {
        let result = TextStatistics(text: "e\u{301}")
        XCTAssertEqual(result.characterCount, 1)
        XCTAssertEqual(result.utf8ByteCount, 3)
    }

    func testWhitespaceAndTrailingNewline() {
        let result = TextStatistics(text: "a \t\nb\n")
        XCTAssertEqual(result.characterCount, 6)
        XCTAssertEqual(result.nonWhitespaceCharacterCount, 2)
        XCTAssertEqual(result.lineCount, 3)
        XCTAssertEqual(result.utf8ByteCount, 6)
    }

    func testWindowsNewlineCountsOnce() {
        let result = TextStatistics(text: "a\r\nb")
        XCTAssertEqual(result.characterCount, 3)
        XCTAssertEqual(result.nonWhitespaceCharacterCount, 2)
        XCTAssertEqual(result.lineCount, 2)
        XCTAssertEqual(result.utf8ByteCount, 4)
    }

    func testCarriageReturnAndUnicodeLineSeparator() {
        let result = TextStatistics(text: "a\rb\u{2028}c")
        XCTAssertEqual(result.lineCount, 3)
        XCTAssertEqual(result.nonWhitespaceCharacterCount, 3)
    }

    func testFullWidthAndNonBreakingSpacesAreExcluded() {
        let result = TextStatistics(text: "あ\u{3000}い\u{00A0}")
        XCTAssertEqual(result.characterCount, 4)
        XCTAssertEqual(result.nonWhitespaceCharacterCount, 2)
    }

    func testOnlyNewlinesIncludeEmptyLines() {
        let result = TextStatistics(text: "\n\n")
        XCTAssertEqual(result.lineCount, 3)
        XCTAssertEqual(result.nonWhitespaceCharacterCount, 0)
    }
}
