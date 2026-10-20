import AppleArchive
import CryptoKit
import Foundation
import Security
import System

enum ShortcutImport {
    static let maximumFileSize = 16_000_000
    static let maximumWorkflowSize = 2_000_000

    static func read(_ url: URL) throws -> ShortcutDraft {
        guard url.isFileURL else { throw ShortcutError.message("ファイルアプリからショートカットを選んでください。") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try decode(boundedRead(url, limit: maximumFileSize), name: url.deletingPathExtension().lastPathComponent)
    }

    // Read incrementally; checking a reported file size alone does not bound memory use.
    static func boundedRead(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, limit + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            guard data.count <= limit else { throw ShortcutError.message("ファイルが大きすぎます（最大\(limit / 1_000_000)MB）。") }
        }
        return data
    }

    static func decode(_ data: Data, name: String) throws -> ShortcutDraft {
        guard data.count <= maximumFileSize else { throw ShortcutError.message("16MB以内のファイルを選んでください。") }
        if var draft = try? JSONDecoder().decode(ShortcutDraft.self, from: data) {
            try ShortcutFormat.validate(draft)
            draft.id = UUID()
            draft.modified = Date()
            return draft
        }
        let workflow: Any
        if data.starts(with: Data("AEA1".utf8)) { workflow = try unpackSignedArchive(data) }
        else if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) { workflow = plist }
        else { workflow = try JSONSerialization.jsonObject(with: data) }
        let source = try ShortcutFormat.json(workflow)
        _ = try ShortcutFormat.workflow(source)
        return ShortcutDraft(name: String((name.isEmpty ? "Shortcut" : name).prefix(100)), source: source,
            summary: "ファイルから読み込みました。編集した内容を追加するには、あらためて署名してください。")
    }

    // Read a signed AEA in memory, without extracting paths or running any actions.
    // The included certificate supplies the integrity-checking key, not a trust decision.
    // Apple Shortcuts is responsible for final certificate trust and import validation.
    static func unpackSignedArchive(_ data: Data) throws -> [String: Any] {
        var stage = "アーカイブを開く処理"
        do { return try unpackSignedArchive(data, stage: &stage) }
        catch is CancellationError { throw CancellationError() }
        catch let error as ShortcutError { throw error }
        catch {
            // Do not expose provider bytes, certificate contents, or filesystem paths.
            throw ShortcutError.message("署名ファイルの\(stage)に失敗しました。ファイルの破損または未対応の形式が考えられます。書き出しは行っていません。")
        }
    }

    private static func unpackSignedArchive(_ data: Data, stage: inout String) throws -> [String: Any] {
        guard data.count <= maximumFileSize, data.starts(with: Data("AEA1".utf8)) else {
            throw ShortcutError.message("署名済みショートカットの形式ではありません。")
        }
        let directory = URL.temporaryDirectory.appending(path: "ToolboxImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "Input.shortcut")
        try data.write(to: file, options: .completeFileProtectionUnlessOpen)
        guard let input = ArchiveByteStream.fileStream(path: FilePath(file.path), mode: .readOnly, options: [], permissions: []) else {
            throw ShortcutError.message("署名ファイルを開けませんでした。")
        }
        var inputOpen = true
        defer { if inputOpen { try? input.close() } }
        guard let context = ArchiveEncryptionContext(from: input),
              context.profile == .hkdf_sha256_hmac__none__ecdsa_p256,
              let auth = context.authData, auth.count <= maximumWorkflowSize,
              let metadata = try PropertyListSerialization.propertyList(from: auth, options: [], format: nil) as? [String: Any],
              let chain = metadata["SigningCertificateChain"] as? [Data], let leaf = chain.first,
              let certificate = SecCertificateCreateWithData(nil, leaf as CFData),
              let key = SecCertificateCopyKey(certificate),
              let representation = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            throw ShortcutError.message("この署名ファイルには対応していません。『誰でも』で共有したショートカットを選んでください。")
        }
        stage = "署名鍵・属性の検証"
        try context.setSigningPublicKey(P256.Signing.PublicKey(x963Representation: representation))
        guard context.decryptAttributes() else {
            throw ShortcutError.message("署名アーカイブの属性を検証できませんでした。")
        }
        // Bound the decompressed archive before a compression block is allocated.
        guard context.rawSize >= 0, context.rawSize <= maximumFileSize,
              context.compressionBlockSize > 0, context.compressionBlockSize <= maximumFileSize else {
            throw ShortcutError.message("展開後のアーカイブが大きすぎます。")
        }
        // ArchiveEncryptionContext(from:) consumes the AEA prologue. Continue from
        // that position, as in Apple's decrypt sample; rewinding feeds the prologue
        // to a decoder expecting the encrypted/compressed payload.
        stage = "署名付きデータの展開"
        guard let decrypted = ArchiveByteStream.decryptionStream(readingFrom: input, encryptionContext: context, threadCount: 1) else {
            throw ShortcutError.message("署名を検証・展開できませんでした。連絡先限定のファイルは『誰でも』で共有し直してください。")
        }
        var decryptedOpen = true
        defer { if decryptedOpen { try? decrypted.close() } }
        guard let archive = ArchiveStream.decodeStream(readingFrom: decrypted, threadCount: 1) else {
            throw ShortcutError.message("アーカイブを読み取れませんでした。")
        }
        var archiveOpen = true
        defer { if archiveOpen { try? archive.close() } }
        var entries = 0
        var totalBytes = 0
        var result: [String: Any]?
        stage = "内部アーカイブの読み取り"
        while let header = try archive.readHeader() {
            try Task.checkCancellation()
            entries += 1
            guard entries <= 16 else { throw ShortcutError.message("アーカイブの項目数が多すぎます。") }
            let key = ArchiveHeader.FieldKey("DAT")
            guard let field = header.field(forKey: key), case .blob(_, let size, _) = field else { continue }
            guard size <= maximumWorkflowSize else { throw ShortcutError.message("ショートカットの内容が大きすぎます。") }
            totalBytes += Int(size)
            guard totalBytes <= maximumFileSize else { throw ShortcutError.message("展開後の内容が大きすぎます。") }
            var content = Data(count: Int(size))
            try content.withUnsafeMutableBytes { try archive.readBlob(key: key, into: $0) }
            if let workflow = try? PropertyListSerialization.propertyList(from: content, options: [], format: nil) as? [String: Any],
               workflow["WFWorkflowActions"] != nil {
                guard result == nil else { throw ShortcutError.message("複数のショートカット定義が含まれているため読み込めません。") }
                _ = try ShortcutFormat.workflow(ShortcutFormat.json(workflow))
                result = workflow
            }
        }
        // Consume the whole archive, and propagate close errors before accepting it.
        stage = "アーカイブ末尾の検証"
        try archive.close(); archiveOpen = false
        try decrypted.close(); decryptedOpen = false
        try input.close(); inputOpen = false
        guard let result else { throw ShortcutError.message("ショートカットの定義が見つかりませんでした。") }
        return result
    }
}
