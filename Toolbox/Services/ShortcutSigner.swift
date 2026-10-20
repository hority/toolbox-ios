import Foundation

struct ShortcutSigningResponse: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

struct SignedShortcutFile: Identifiable, Sendable {
    let id = UUID()
    let url: URL

    func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

// No cookies, credentials, persistent cache, or redirects are used for uploads.
final class ShortcutNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum ShortcutSigner {
    static let endpoint = URL(string: "https://sign.shortcuty.app/api/v1/sign")!
    static let maximumResponseSize = 16_000_000
    typealias Transport = @Sendable (URLRequest) async throws -> ShortcutSigningResponse

    static func request(for draft: ShortcutDraft) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        // A constant ASCII filename avoids leaking the local draft title in headers.
        request.setValue("Toolbox.shortcut", forHTTPHeaderField: "X-Filename")
        request.httpBody = try ShortcutFormat.plist(draft.source, format: .binary)
        return request
    }

    static func sign(_ draft: ShortcutDraft, transport: Transport = fetch) async throws -> SignedShortcutFile {
        try Task.checkCancellation()
        let result = try await transport(request(for: draft))
        try Task.checkCancellation()
        try validateHTTP(result.response)
        try validateSignedData(result.data, source: draft.source)
        try Task.checkCancellation()
        return try export(result.data, name: draft.name)
    }

    static func validateHTTP(_ response: HTTPURLResponse) throws {
        guard response.url == endpoint else {
            throw ShortcutError.message("署名先が変更されたため中断しました。")
        }
        guard response.statusCode == 200 else {
            let message: String
            switch response.statusCode {
            case 300..<400: message = "署名サービスが別のURLへ転送しようとしたため中断しました。"
            case 400, 413, 422: message = "署名サービスがファイルの形式・サイズを受け付けませんでした。JSONの内容を確認してください。"
            case 401, 402, 403: message = "署名サービスを利用できません。サービス側の利用条件を確認してください。"
            case 429: message = "署名サービスの利用上限に達しました。時間をおいて再度お試しください。"
            case 500...599: message = "署名サービスでエラーが発生しました（HTTP \(response.statusCode)）。時間をおいて再度お試しください。"
            default: message = "署名サービスがエラーを返しました（HTTP \(response.statusCode)）。"
            }
            throw ShortcutError.message(message)
        }
        guard response.expectedContentLength <= maximumResponseSize else {
            throw ShortcutError.message("署名サービスからの応答が大きすぎます。")
        }
    }

    static func validateSignedData(_ data: Data, source: String) throws {
        guard data.count <= maximumResponseSize, data.starts(with: Data("AEA1".utf8)) else {
            throw ShortcutError.message("署名済みショートカットを受信できませんでした。")
        }
        do {
            let returned = try ShortcutImport.unpackSignedArchive(data)
            try validateWorkflow(returned, source: source)
        } catch is CancellationError { throw CancellationError() }
        catch let error as ShortcutError {
            throw ShortcutError.message("署名サービスからファイルを受信しましたが、端末内の検証で停止しました。\n\(error.localizedDescription)")
        }
    }

    static func validateWorkflow(_ returned: [String: Any], source: String) throws {
        let original = try ShortcutFormat.workflow(source)
        // Check the entire property list, not only the action count or archive prefix.
        guard NSDictionary(dictionary: original).isEqual(to: returned) else {
            throw ShortcutError.message("署名サービスの返した内容が送信したショートカットと異なります。安全のため書き出しませんでした。")
        }
    }

    static func fetch(_ request: URLRequest) async throws -> ShortcutSigningResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: ShortcutNoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ShortcutError.message("署名サービスの応答を読み取れませんでした。") }
        try validateHTTP(http)
        var data = Data()
        if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
        for try await byte in bytes {
            guard data.count < maximumResponseSize else { throw ShortcutError.message("署名サービスからの応答が大きすぎます。") }
            data.append(byte)
            if data.count.isMultiple(of: 65_536) { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        return ShortcutSigningResponse(data: data, response: http)
    }

    private static var exportRoot: URL {
        URL.temporaryDirectory.appending(path: "ToolboxShortcutExports", directoryHint: .isDirectory)
    }

    private static func export(_ data: Data, name: String) throws -> SignedShortcutFile {
        let directory = exportRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: ShortcutFormat.safeName(name) + ".shortcut")
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            return SignedShortcutFile(url: url)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    // Recover temporary exports left behind by an app crash without deleting active shares.
    static func removeExpiredExports(now: Date = Date()) {
        let keys: Set<URLResourceKey> = [.creationDateKey]
        guard let directories = try? FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: Array(keys)) else { return }
        for directory in directories {
            guard let values = try? directory.resourceValues(forKeys: keys),
                  let created = values.creationDate, now.timeIntervalSince(created) > 86_400 else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
