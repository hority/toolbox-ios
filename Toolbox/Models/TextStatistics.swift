/// Counts extended grapheme clusters, so a combined emoji counts as one character.
/// Empty text has zero lines; a trailing newline starts an additional empty line.
struct TextStatistics: Equatable, Sendable {
    let characterCount: Int
    let nonWhitespaceCharacterCount: Int
    let lineCount: Int
    let utf8ByteCount: Int

    init(text: String) {
        var characters = 0
        var nonWhitespaceCharacters = 0
        var newlines = 0

        for character in text {
            characters += 1
            if !character.isWhitespace {
                nonWhitespaceCharacters += 1
            }
            // A CRLF pair is one Character and therefore one newline.
            if character.isNewline {
                newlines += 1
            }
        }

        characterCount = characters
        nonWhitespaceCharacterCount = nonWhitespaceCharacters
        lineCount = text.isEmpty ? 0 : newlines + 1
        utf8ByteCount = text.utf8.count
    }
}
