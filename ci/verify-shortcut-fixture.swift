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
        try ShortcutSigner.validateSignedData(signed, source: ShortcutFormat.json(original))
        // The narrow default/version equivalence must not accept semantic changes.
        let changedValues: [(String, Any)] = [
            ("WFWorkflowActions", []), ("WFWorkflowMinimumClientVersion", 999),
            ("WFWorkflowInputContentItemClasses", ["WFImageContentItem"]),
            ("WFWorkflowHasShortcutInputVariables", true), ("WFWorkflowHasOutputFallback", true),
            ("WFQuickActionSurfaces", ["Finder"]), ("WFWorkflowOutputContentItemClasses", ["WFImageContentItem"]),
            ("WFWorkflowClientVersion", "invalid"), ("UnknownField", "added")
        ]
        for (field, value) in changedValues {
            var changed = expected; changed[field] = value
            do { try ShortcutSigner.validateWorkflow(changed, source: ShortcutFormat.json(original)); fatalError("Changed field accepted: \(field)") }
            catch is ShortcutError { }
        }
        for key in ["WFWorkflowHasShortcutInputVariables", "WFWorkflowHasOutputFallback"] {
            var changed = expected; changed[key] = 0 // Numeric zero is not Boolean false.
            do { try ShortcutSigner.validateWorkflow(changed, source: ShortcutFormat.json(original)); fatalError("Numeric false accepted") }
            catch is ShortcutError { }
        }
        var actionTypeMutation = expected
        var alertActions = expected["WFWorkflowActions"] as! [[String: Any]]
        var alertParameters = alertActions[0]["WFWorkflowActionParameters"] as! [String: Any]
        alertParameters["WFAlertActionCancelButtonShown"] = 0
        alertActions[0]["WFWorkflowActionParameters"] = alertParameters
        actionTypeMutation["WFWorkflowActions"] = alertActions
        do { try ShortcutSigner.validateWorkflow(actionTypeMutation, source: ShortcutFormat.json(original)); fatalError("Action Boolean-to-number mutation accepted") }
        catch is ShortcutError { }
        let photoSigned = try Data(contentsOf: root.appending(path: "synthetic-photo-signed.shortcut"))
        let photoOriginal = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appending(path: "synthetic-photo-input.plist")), options: [], format: nil) as! [String: Any]
        let photoReturned = try ShortcutImport.unpackSignedArchive(photoSigned)
        try ShortcutSigner.validateSignedData(photoSigned, source: ShortcutFormat.json(photoOriginal))
        guard NSArray(array: photoOriginal["WFWorkflowActions"] as! [Any]).isEqual(to: photoReturned["WFWorkflowActions"] as! [Any]) else { fatalError("Photo actions changed") }
        var changedPhoto = photoReturned
        var photoActions = photoReturned["WFWorkflowActions"] as! [[String: Any]]
        photoActions[0]["WFWorkflowActionParameters"] = ["WFContentItemLimitNumber": 999]
        changedPhoto["WFWorkflowActions"] = photoActions
        do { try ShortcutSigner.validateWorkflow(changedPhoto, source: ShortcutFormat.json(photoOriginal)); fatalError("Photo parameter mutation accepted") }
        catch is ShortcutError { }
        let explicitDefaults: [(String, Any)] = [("WFWorkflowHasOutputFallback", true), ("WFWorkflowHasShortcutInputVariables", true), ("WFQuickActionSurfaces", ["Finder"]), ("WFWorkflowOutputContentItemClasses", ["WFImageContentItem"])]
        for (key, explicitValue) in explicitDefaults {
            var populated = original; populated[key] = explicitValue
            do { try ShortcutSigner.validateWorkflow(expected, source: ShortcutFormat.json(populated)); fatalError("Populated default changed") }
            catch is ShortcutError { }
        }
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
        print("Synthetic alert/photo archives, corruption rejection, bounded metadata equivalence, semantic mutation rejection and all eight button palette states passed")
    }
    static func corrupted(_ value: Data) -> Data {
        var result = value; result[result.count / 2] ^= 1; return result
    }
}
