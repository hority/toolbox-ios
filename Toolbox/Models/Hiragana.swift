import Foundation

/// The 46 basic hiragana from あ to ん. Voiced, small and archaic kana are not collected.
enum Hiragana {
    /// Gojūon table, five columns per row; `nil` marks the traditional gaps.
    static let rows: [[String?]] = [
        ["あ", "い", "う", "え", "お"],
        ["か", "き", "く", "け", "こ"],
        ["さ", "し", "す", "せ", "そ"],
        ["た", "ち", "つ", "て", "と"],
        ["な", "に", "ぬ", "ね", "の"],
        ["は", "ひ", "ふ", "へ", "ほ"],
        ["ま", "み", "む", "め", "も"],
        ["や", nil, "ゆ", nil, "よ"],
        ["ら", "り", "る", "れ", "ろ"],
        ["わ", nil, "を", nil, "ん"],
    ]

    static let all: [String] = rows.flatMap { $0.compactMap { $0 } }
    private static let set = Set(all)

    static func isCollectible(_ character: Character) -> Bool { set.contains(String(character)) }

    /// Unique collectible hiragana in order of first appearance. Text is NFC-normalized so
    /// a decomposed が (か + ゙) is not mistaken for か.
    static func unique(in text: String) -> [String] {
        var seen = Set<String>()
        return text.precomposedStringWithCanonicalMapping.compactMap { character in
            let value = String(character)
            return set.contains(value) && seen.insert(value).inserted ? value : nil
        }
    }
}
