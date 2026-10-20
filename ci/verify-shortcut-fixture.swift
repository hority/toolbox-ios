import AppleArchive
import CryptoKit
import Foundation
import Security
import System

// macOS-only, no simulator, no network, no signing keys. Compiles the real decoder.
@main struct VerifyShortcutFixture {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let signed = try Data(contentsOf: root.appending(path: "synthetic-signed.shortcut"))
        let expected = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appending(path: "synthetic-returned.plist")), options: [], format: nil) as! [String: Any]
        let original = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appending(path: "synthetic-input.plist")), options: [], format: nil) as! [String: Any]
        // Demonstrate the old stream-position bug on the same public synthetic fixture.
        let path = root.appending(path: "synthetic-signed.shortcut")
        let input = ArchiveByteStream.fileStream(path: FilePath(path.path), mode: .readOnly, options: [], permissions: [])!
        defer { try? input.close() }
        let context = ArchiveEncryptionContext(from: input)!
        let offset = try input.seek(toOffset: 0, relativeTo: .current)
        guard offset > 0 else { fatalError("Context did not consume a prologue") }
        let metadata = try PropertyListSerialization.propertyList(from: context.authData!, options: [], format: nil) as! [String: Any]
        let cert = SecCertificateCreateWithData(nil, (metadata["SigningCertificateChain"] as! [Data])[0] as CFData)!
        let key = SecCertificateCopyKey(cert)!
        let representation = SecKeyCopyExternalRepresentation(key, nil)! as Data
        try context.setSigningPublicKey(P256.Signing.PublicKey(x963Representation: representation))
        guard context.decryptAttributes() else { fatalError("Fixture attributes invalid") }
        _ = try input.seek(toOffset: 0, relativeTo: .start)
        var oldFailed = false
        do {
            if let decrypted = ArchiveByteStream.decryptionStream(readingFrom: input, encryptionContext: context, threadCount: 1) {
                defer { try? decrypted.close() }
                if let archive = ArchiveStream.decodeStream(readingFrom: decrypted, threadCount: 1) {
                    defer { try? archive.close() }
                    _ = try archive.readHeader()
                } else { oldFailed = true }
            } else { oldFailed = true }
        } catch { oldFailed = true }
        guard oldFailed else { fatalError("Old rewind failure was not reproduced") }
        print("Reproduced old rewind failure; context consumed \(offset) bytes")
        let actual = try ShortcutImport.unpackSignedArchive(signed)
        guard NSDictionary(dictionary: expected).isEqual(to: actual) else { fatalError("Decoded fixture mismatch") }
        try ShortcutSigner.validateSignedData(signed, source: ShortcutFormat.json(expected))
        do {
            try ShortcutSigner.validateSignedData(signed, source: ShortcutFormat.json(original))
            fatalError("Signer metadata changes must not bypass exact comparison")
        } catch is ShortcutError { }
        for candidate in [Data(signed.prefix(signed.count / 2)), corrupted(signed)] {
            do { _ = try ShortcutImport.unpackSignedArchive(candidate); fatalError("Invalid archive accepted") }
            catch is ShortcutError { }
        }
        for dark in [false, true] { for enabled in [false, true] { for pressed in [false, true] {
            let p = ChatGPTButtonPalette(dark: dark, enabled: enabled, pressed: pressed)
            func lum(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            let a = lum(p.foreground), b = lum(p.background)
            guard (max(a, b) + 0.05) / (min(a, b) + 0.05) >= 4.5 else { fatalError("Button contrast failed") }
        } } }
        print("Synthetic archive decode, corruption rejection, full workflow comparison and all eight button palette states passed")
    }
    static func corrupted(_ value: Data) -> Data {
        var result = value; result[result.count / 2] ^= 1; return result
    }
}
