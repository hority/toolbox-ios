import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Local-only QR generation. The returned bitmap has exactly four white modules
/// on each edge and an integer number of physical pixels per module.
enum AttendanceQRRenderer {
    static let quietZoneModules = 4
    static let presentationSide: CGFloat = 136
    static let maximumSymbolModules = 37 // QR version 5, adequate for 64 UTF-8 bytes at M.

    struct RenderedCode {
        let image: CGImage
        let symbolModules: Int
        let pixelsPerModule: Int
        let displayScale: CGFloat

        var quietZonePixels: Int { AttendanceQRRenderer.quietZoneModules * pixelsPerModule }
        var pointSide: CGFloat { CGFloat(image.width) / displayScale }
        // An odd spare pixel belongs to the trailing/bottom edge. Centering it
        // fractionally would put otherwise sharp module edges on half-pixels.
        var leadingInset: CGFloat {
            floor((AttendanceQRRenderer.presentationSide * displayScale - CGFloat(image.width)) / 2)
                / displayScale
        }
    }

    static func render(payload: String, displayScale: CGFloat) throws -> RenderedCode {
        try AttendanceQRConfiguration.validatePayload(payload)
        guard displayScale.isFinite, (1...4).contains(displayScale) else {
            throw AttendanceQRError.invalidDisplayScale
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { throw AttendanceQRError.renderingFailed }
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        guard let source = context.createCGImage(output, from: output.extent.integral) else {
            throw AttendanceQRError.renderingFailed
        }
        let width = source.width
        let height = source.height
        guard width == height, width <= 256 else { throw AttendanceQRError.unsupportedCodeSize }

        // Core Image may include its own border. Find the actual symbol bounds
        // before adding our exact four-module quiet zone. Finder patterns touch
        // every outside edge of a standard QR symbol.
        var sourcePixels = [UInt8](repeating: 255, count: width * height)
        let drewSource = sourcePixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let bitmap = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            bitmap.interpolationQuality = .none
            bitmap.setShouldAntialias(false)
            bitmap.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard drewSource else { throw AttendanceQRError.renderingFailed }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where sourcePixels[y * width + x] < 128 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        let modules = maxX - minX + 1
        guard modules >= 21, modules <= maximumSymbolModules,
              modules == maxY - minY + 1, (modules - 21).isMultiple(of: 4) else {
            throw AttendanceQRError.unsupportedCodeSize
        }
        let totalModules = modules + 2 * quietZoneModules
        let pixelsPerModule = Int((presentationSide * displayScale) / CGFloat(totalModules))
        guard pixelsPerModule >= 2 else { throw AttendanceQRError.invalidDisplayScale }
        let side = totalModules * pixelsPerModule
        var pixels = [UInt8](repeating: 255, count: side * side)
        for y in 0..<modules {
            for x in 0..<modules where sourcePixels[(minY + y) * width + minX + x] < 128 {
                let originX = (x + quietZoneModules) * pixelsPerModule
                let originY = (y + quietZoneModules) * pixelsPerModule
                for dy in 0..<pixelsPerModule {
                    let start = (originY + dy) * side + originX
                    for dx in 0..<pixelsPerModule { pixels[start + dx] = 0 }
                }
            }
        }

        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { throw AttendanceQRError.renderingFailed }
        return RenderedCode(image: image, symbolModules: modules,
                            pixelsPerModule: pixelsPerModule, displayScale: displayScale)
    }
}
