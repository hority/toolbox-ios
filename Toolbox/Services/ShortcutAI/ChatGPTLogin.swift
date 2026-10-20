import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security
import UIKit

struct ChatGPTSession: Codable, Sendable {
    var clientID: String
    var subject: String
    var email: String
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var expiresAt: Date
    var scopes: [String]
}

private struct OpenAITokens: Decodable, Sendable {
    var token_type: String
    var access_token: String
    var refresh_token: String?
    var id_token: String?
    var expires_in: Double
    var scope: String?
}

@MainActor final class ChatGPTLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private struct Attempt {
        let id: UUID
        let state: String
        let nonce: String
        let verifier: String
        let previous: ChatGPTSession?
        let continuation: CheckedContinuation<ChatGPTSession, Error>
        var callbackURL = ""
        var exchanging = false
    }
    private var pending: Attempt?
    private var listener: NWListener?
    private var browser: ASWebAuthenticationSession?
    private var exchange: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var connections: [NWConnection] = []

    func signIn(previous: ChatGPTSession?) async throws -> ChatGPTSession {
        guard pending == nil else { throw ShortcutError.message("ログイン処理が進行中です。") }
        try Task.checkCancellation()
        let attemptID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let server = try NWListener(using: parameters)
                    let attempt = Attempt(id: attemptID, state: try Self.random(), nonce: try Self.random(),
                                          verifier: try Self.random(), previous: previous, continuation: continuation)
                    pending = attempt
                    listener = server
                    timeout = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(180)) } catch { return }
                        self?.finish(attempt.id, .failure(ShortcutError.message("ログインが時間切れになりました。再度お試しください。")))
                    }
                    server.stateUpdateHandler = { [weak self] state in
                        Task { @MainActor in
                            guard let self, self.pending?.id == attempt.id else { return }
                            switch state {
                            case .ready: self.openBrowser(attempt.id)
                            case .failed: self.finish(attempt.id, .failure(ShortcutError.message("端末内のログイン接続を開始できませんでした。")))
                            default: break
                            }
                        }
                    }
                    server.newConnectionHandler = { [weak self] connection in
                        Task { @MainActor in
                            guard let self, self.pending?.id == attempt.id, self.connections.count < 8 else { connection.cancel(); return }
                            self.connections.append(connection)
                            connection.start(queue: .main)
                            self.receive(connection, collected: Data(), id: attempt.id)
                        }
                    }
                    server.start(queue: .main)
                } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(attemptID, .failure(CancellationError())) }
        }
    }

    func cancel() {
        if let id = pending?.id { finish(id, .failure(CancellationError())) }
    }

    private func openBrowser(_ id: UUID) {
        guard browser == nil, var attempt = pending, attempt.id == id, let port = listener?.port else { return }
        attempt.callbackURL = "http://127.0.0.1:\(port.rawValue)/auth/callback"
        pending = attempt
        do {
            let hostID: String
            if let saved = try ChatGPTKeychain.read("host-id"), let value = String(data: saved, encoding: .utf8), !value.isEmpty {
                hostID = value
            } else {
                hostID = "urn:uuid:\(UUID().uuidString.lowercased())"
                try ChatGPTKeychain.write("host-id", data: Data(hostID.utf8))
            }
            var items: [URLQueryItem] = [
                .init(name: "client_id", value: attempt.previous?.clientID ?? "dynamic_agent_client"),
                .init(name: "ext_agent_host_id", value: hostID),
                .init(name: "response_type", value: "code"),
                .init(name: "redirect_uri", value: attempt.callbackURL),
                .init(name: "scope", value: "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),
                .init(name: "resource", value: "https://api.openai.com/v1"),
                .init(name: "state", value: attempt.state), .init(name: "nonce", value: attempt.nonce),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "code_challenge", value: Data(SHA256.hash(data: Data(attempt.verifier.utf8))).base64URL),
            ]
            if let previous = attempt.previous {
                if !previous.idToken.isEmpty { items.append(.init(name: "id_token_hint", value: previous.idToken)) }
            } else { items.append(.init(name: "agent_name_hint", value: "Toolbox")) }
            var url = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
            url.queryItems = items
            let session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: nil) { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, self.pending?.id == id, self.pending?.exchanging == false else { return }
                    self.finish(id, .failure(ShortcutError.message("ログインがキャンセルされたか、完了できませんでした。")))
                }
            }
            session.presentationContextProvider = self
            browser = session
            if !session.start() { finish(id, .failure(ShortcutError.message("ログイン画面を開けませんでした。"))) }
        } catch { finish(id, .failure(error)) }
    }

    private func receive(_ connection: NWConnection, collected: Data, id: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, let attempt = self.pending, attempt.id == id, !attempt.exchanging else { connection.cancel(); return }
                var received = collected
                if let data { received.append(data) }
                guard received.count <= 16_384 else { self.close(connection); return }
                guard let request = String(data: received, encoding: .utf8), request.contains("\r\n\r\n") else {
                    if !complete && error == nil { self.receive(connection, collected: received, id: id) }
                    else { self.close(connection) }
                    return
                }
                guard let values = try? ChatGPTProtocol.callback(request, state: attempt.state) else { self.close(connection); return }
                self.pending?.exchanging = true
                let html = "<!doctype html><p>Toolboxに戻ってください。</p>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(html)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                self.listener?.cancel(); self.listener = nil
                self.browser?.cancel(); self.browser = nil
                self.exchange = Task {
                    do {
                        let clientID = try ChatGPTProtocol.clientID(values, previous: attempt.previous?.clientID)
                        let tokens = try await Self.tokens([
                            "grant_type": "authorization_code", "client_id": clientID, "code": values["code"]!,
                            "code_verifier": attempt.verifier, "redirect_uri": attempt.callbackURL,
                            "resource": "https://api.openai.com/v1",
                        ])
                        let session = try await Self.validated(tokens, clientID: clientID, nonce: attempt.nonce, previous: attempt.previous)
                        try Task.checkCancellation()
                        self.finish(id, .success(session))
                    } catch { self.finish(id, .failure(error)) }
                }
            }
        }
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }

    private func finish(_ id: UUID, _ result: Result<ChatGPTSession, Error>) {
        guard let attempt = pending, attempt.id == id else { return }
        pending = nil
        timeout?.cancel(); timeout = nil
        exchange?.cancel(); exchange = nil
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        connections.forEach { $0.cancel() }; connections.removeAll()
        attempt.continuation.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    static func refresh(_ previous: ChatGPTSession) async throws -> ChatGPTSession {
        let result = try await tokens(["grant_type": "refresh_token", "client_id": previous.clientID,
            "refresh_token": previous.refreshToken, "resource": "https://api.openai.com/v1"])
        return try await validated(result, clientID: previous.clientID, nonce: nil, previous: previous)
    }

    static func revoke(_ session: ChatGPTSession) async throws {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(["token": session.refreshToken, "token_type_hint": "refresh_token", "client_id": session.clientID])
        for attempt in 0..<2 {
            do {
                let (_, response) = try await ChatGPTHTTP.session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 { return }
                guard status >= 500, attempt == 0 else { break }
            } catch {
                try Task.checkCancellation()
                if attempt != 0 { break }
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw ShortcutError.message("接続解除を確認できませんでした。")
    }

    private static func tokens(_ fields: [String: String]) async throws -> OpenAITokens {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(fields)
        let (data, response) = try await ChatGPTHTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ShortcutError.message("ChatGPT認証に失敗しました。もう一度ログインしてください。")
        }
        return try JSONDecoder().decode(OpenAITokens.self, from: data)
    }

    private static func validated(_ tokens: OpenAITokens, clientID: String, nonce: String?, previous: ChatGPTSession?) async throws -> ChatGPTSession {
        let scopes = tokens.scope?.split(separator: " ").map(String.init) ?? (nonce == nil ? previous?.scopes ?? [] : [])
        try ChatGPTProtocol.tokenPolicy(type: tokens.token_type, expiresIn: tokens.expires_in, scopes: scopes)
        let identity: (String, String)
        let idToken: String
        if let newToken = tokens.id_token {
            idToken = newToken
            identity = try await OpenAIIdentity.verify(newToken, clientID: clientID, nonce: nonce)
            if let previous, previous.subject != identity.0 { throw ShortcutError.message("ログイン中のアカウントが一致しません。") }
        } else if nonce == nil, let previous {
            idToken = previous.idToken
            identity = (previous.subject, previous.email)
        } else { throw ShortcutError.message("本人確認用のIDトークンがありません。") }
        guard let refresh = tokens.refresh_token, !refresh.isEmpty, !tokens.access_token.isEmpty else {
            throw ShortcutError.message("ログインを維持するための認証情報がありません。")
        }
        return ChatGPTSession(clientID: clientID, subject: identity.0, email: identity.1,
            accessToken: tokens.access_token, refreshToken: refresh, idToken: idToken,
            expiresAt: Date().addingTimeInterval(tokens.expires_in), scopes: scopes)
    }

    private static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(fields.map { key, value in "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").utf8)
    }

    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ShortcutError.message("安全な乱数を生成できませんでした。") }
        return Data(bytes).base64URL
    }
}

private enum OpenAIIdentity {
    static func verify(_ token: String, clientID: String, nonce: String?) async throws -> (String, String) {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let headerData = Data(base64URL: parts[0]), let claimsData = Data(base64URL: parts[1]),
              let signature = Data(base64URL: parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              header["alg"] as? String == "RS256", let keyID = header["kid"] as? String else { throw invalid() }
        var request = URLRequest(url: URL(string: "https://auth.openai.com/.well-known/jwks.json")!)
        request.timeoutInterval = 30
        let (data, response) = try await ChatGPTHTTP.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let jwks = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keys = jwks["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == keyID && $0["kty"] as? String == "RSA" }),
              let n = key["n"] as? String, let e = key["e"] as? String,
              let modulus = Data(base64URL: n), let exponent = Data(base64URL: e) else { throw invalid() }
        let der = block(0x30, integer(modulus) + integer(exponent))
        guard let publicKey = SecKeyCreateWithData(der as CFData,
            [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                Data("\(parts[0]).\(parts[1])".utf8) as CFData, signature as CFData, nil) else { throw invalid() }
        return try ChatGPTProtocol.identityClaims(claims, clientID: clientID, nonce: nonce)
    }

    private static func invalid() -> ShortcutError { .message("OpenAIの本人確認結果を検証できませんでした。再度ログインしてください。") }
    private static func integer(_ data: Data) -> Data { block(0x02, (data.first ?? 0) & 0x80 != 0 ? Data([0]) + data : data) }
    private static func block(_ tag: UInt8, _ data: Data) -> Data {
        var length = data.count
        var bytes = [UInt8]()
        repeat { bytes.insert(UInt8(length & 255), at: 0); length >>= 8 } while length > 0
        let encoded = data.count < 128 ? Data([UInt8(data.count)]) : Data([0x80 | UInt8(bytes.count)] + bytes)
        return Data([tag]) + encoded + data
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        let value = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4))
    }
}
