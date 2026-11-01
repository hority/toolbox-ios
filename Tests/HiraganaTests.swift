import XCTest
@testable import Toolbox

final class HiraganaTests: XCTestCase {
    func testTableHasFortySixUniqueLetters() {
        XCTAssertEqual(Hiragana.all.count, 46)
        XCTAssertEqual(Set(Hiragana.all).count, 46)
        XCTAssertEqual(Hiragana.all.first, "あ")
        XCTAssertEqual(Hiragana.all.last, "ん")
    }

    func testUniqueSkipsVoicedSmallKatakanaAndRepeats() {
        // Decomposed が (か + U+3099) must not count as か.
        XCTAssertEqual(Hiragana.unique(in: "がっこう カタカナ あさひ あ\u{304B}\u{3099}ゃ"), ["こ", "う", "あ", "さ", "ひ"])
    }

    @MainActor func testCollectionKeepsMultipleCatchesAcrossReload() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let collection = HiraganaCollection(directory: directory)
        try collection.add([HiraganaFind(character: "あ", image: Data([1])), HiraganaFind(character: "あ", image: Data([2]))])
        let reloaded = HiraganaCollection(directory: directory)
        XCTAssertEqual(reloaded.count(of: "あ"), 2)
        XCTAssertEqual(reloaded.caughtKinds, 1)
        try reloaded.remove(reloaded.catches[0])
        XCTAssertEqual(HiraganaCollection(directory: directory).count(of: "あ"), 1)
    }
}
