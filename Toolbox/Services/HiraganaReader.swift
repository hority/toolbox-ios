import UIKit
import Vision

/// On-device Japanese text recognition. Each found hiragana gets a small square crop of
/// where it appeared, so the zukan shows the real sign or page it came from.
enum HiraganaReader {
    /// Precision over recall: a letter is offered only when its line is confidently read,
    /// looks like real Japanese, is not better explained as mirrored text and, for camera
    /// shots, was also seen by the live scanner moments before (`seenLive`).
    static func finds(in image: UIImage, seenLive: Set<String>? = nil) async -> [HiraganaFind] {
        await Task.detached(priority: .userInitiated) { read(image, seenLive: seenLive) }.value
    }

    private struct Line {
        let observation: VNRecognizedTextObservation
        let candidate: VNRecognizedText
        var text: String { candidate.string }
        var box: CGRect { observation.boundingBox }
    }

    private static let minimumConfidence: Float = 0.5
    private static let minimumLetterPixels: CGFloat = 18

    private static func read(_ image: UIImage, seenLive: Set<String>?) -> [HiraganaFind] {
        guard let cgImage = upright(image, maxSide: 2400) else { return [] }
        let lines = recognize(cgImage).filter(plausible)
        guard !lines.isEmpty else { return [] }
        // Mirrored signs (seen through glass, reflections) can still yield kana-like guesses.
        let mirrored = mirror(cgImage).map { recognize($0).filter(plausible) } ?? []

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        var seen = Set<String>()
        var finds: [HiraganaFind] = []
        for line in lines where !isMirrored(line, mirroredLines: mirrored) {
            let text = line.text
            let count = text.count
            for (offset, index) in text.indices.enumerated() {
                let value = String(text[index]).precomposedStringWithCanonicalMapping
                guard value.count == 1, let character = value.first, Hiragana.isCollectible(character),
                      seenLive?.contains(value) ?? true, !seen.contains(value) else { continue }
                let range = index..<text.index(after: index)
                var box = (try? line.candidate.boundingBox(for: range))?.boundingBox ?? line.box
                if count > 1, abs(box.width - line.box.width) < line.box.width * 0.1,
                   abs(box.height - line.box.height) < line.box.height * 0.1 {
                    box = slice(line.box, offset: offset, count: count)
                }
                guard min(box.width * size.width, box.height * size.height) >= minimumLetterPixels,
                      let jpeg = crop(cgImage, normalized: box, imageSize: size) else { continue }
                seen.insert(value)
                finds.append(HiraganaFind(character: value, image: jpeg))
            }
        }
        return finds
    }

    private static func recognize(_ image: CGImage) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP"]
        request.usesLanguageCorrection = true
        do { try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request]) } catch { return [] }
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { Line(observation: observation, candidate: $0) }
        }
    }

    /// Lone glyphs and lines mixed with Latin letters or symbols are the usual misreads
    /// (patterns, mirrored or rotated text), so only confident, mostly-Japanese lines of
    /// two or more characters count.
    private static func plausible(_ line: Line) -> Bool {
        guard line.candidate.confidence >= minimumConfidence else { return false }
        let letters = line.text.filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isNumber }
        guard letters.count >= 2 else { return false }
        return Double(letters.filter(isJapanese).count) / Double(letters.count) >= 0.8
    }

    static func isJapanese(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x3005, 0x30FC, 0x3041...0x309F, 0x30A0...0x30FF, 0x4E00...0x9FFF: true
            default: false
            }
        }
    }

    /// True when the horizontally flipped photo reads the same place at least as well:
    /// then the original text is most likely a mirror image.
    private static func isMirrored(_ line: Line, mirroredLines: [Line]) -> Bool {
        mirroredLines.contains { other in
            let box = CGRect(x: 1 - other.box.maxX, y: other.box.minY, width: other.box.width, height: other.box.height)
            let overlap = box.intersection(line.box)
            guard !overlap.isNull else { return false }
            let union = box.width * box.height + line.box.width * line.box.height - overlap.width * overlap.height
            return overlap.width * overlap.height / union > 0.3 && other.candidate.confidence >= line.candidate.confidence
        }
    }

    private static func mirror(_ image: CGImage) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image, scale: 1, orientation: .upMirrored).draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    /// Some languages report only a line box; estimate the character's share of it.
    private static func slice(_ line: CGRect, offset: Int, count: Int) -> CGRect {
        let share = CGFloat(1) / CGFloat(count)
        if line.width >= line.height {
            return CGRect(x: line.minX + line.width * share * CGFloat(offset), y: line.minY,
                          width: line.width * share, height: line.height)
        }
        // Vertical writing runs top to bottom; Vision boxes use a lower-left origin.
        return CGRect(x: line.minX, y: line.maxY - line.height * share * CGFloat(offset + 1),
                      width: line.width, height: line.height * share)
    }

    private static func crop(_ image: CGImage, normalized box: CGRect, imageSize: CGSize) -> Data? {
        let rect = VNImageRectForNormalizedRect(box, Int(imageSize.width), Int(imageSize.height))
        let flipped = CGRect(x: rect.minX, y: imageSize.height - rect.maxY, width: rect.width, height: rect.height)
        let side = max(flipped.width, flipped.height) * 1.4
        let square = CGRect(x: flipped.midX - side / 2, y: flipped.midY - side / 2, width: side, height: side)
            .intersection(CGRect(origin: .zero, size: imageSize)).integral
        guard square.width >= 4, square.height >= 4, let piece = image.cropping(to: square) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let output = CGSize(width: 240, height: 240)
        return UIGraphicsImageRenderer(size: output, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: output))
            let aspect = square.width / square.height
            let drawSize = aspect >= 1 ? CGSize(width: output.width, height: output.height / aspect)
                                       : CGSize(width: output.width * aspect, height: output.height)
            UIImage(cgImage: piece).draw(in: CGRect(x: (output.width - drawSize.width) / 2, y: (output.height - drawSize.height) / 2,
                                                    width: drawSize.width, height: drawSize.height))
        }.jpegData(compressionQuality: 0.85)
    }

    /// Applies EXIF orientation and bounds the size so recognition stays fast.
    private static func upright(_ image: UIImage, maxSide: CGFloat) -> CGImage? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
