import UIKit
import Vision

/// On-device Japanese text recognition. Each found hiragana gets a small square crop of
/// where it appeared, so the zukan shows the real sign or page it came from.
enum HiraganaReader {
    static func finds(in image: UIImage) async -> [HiraganaFind] {
        await Task.detached(priority: .userInitiated) { read(image) }.value
    }

    private static func read(_ image: UIImage) -> [HiraganaFind] {
        guard let cgImage = upright(image, maxSide: 2400) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP"]
        request.usesLanguageCorrection = true
        do { try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request]) } catch { return [] }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        var seen = Set<String>()
        var finds: [HiraganaFind] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let count = text.count
            for (offset, index) in text.indices.enumerated() {
                let value = String(text[index]).precomposedStringWithCanonicalMapping
                guard value.count == 1, let character = value.first, Hiragana.isCollectible(character),
                      seen.insert(value).inserted else { continue }
                let range = index..<text.index(after: index)
                let line = observation.boundingBox
                var box = (try? candidate.boundingBox(for: range))?.boundingBox ?? line
                if count > 1, abs(box.width - line.width) < line.width * 0.1, abs(box.height - line.height) < line.height * 0.1 {
                    box = slice(line, offset: offset, count: count)
                }
                if let jpeg = crop(cgImage, normalized: box, imageSize: size) {
                    finds.append(HiraganaFind(character: value, image: jpeg))
                }
            }
        }
        return finds
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
