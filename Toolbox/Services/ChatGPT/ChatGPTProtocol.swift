import Foundation

/// Pure protocol validation, shared with fixture tests. Never includes remote payloads in errors.
enum ChatGPTProtocol {
    static func identityClaims(_ claims: [String: Any], clientID: String, nonce: String?, now: Date = Date()) throws -> (String, String) {
        let audience = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard claims["iss"] as? String == "https://auth.openai.com", audience.contains(clientID),
              (audience.count == 1 || claims["azp"] as? String == clientID),
              (claims["nbf"] as? Double ?? 0) <= now.timeIntervalSince1970 + 30,
              let expiration = claims["exp"] as? Double, expiration > now.timeIntervalSince1970,
              let subject = claims["sub"] as? String, !subject.isEmpty,
              nonce == nil || claims["nonce"] as? String == nonce else {
            throw ShortcutError.message("OpenAIの本人確認結果を検証できませんでした。")
        }
        return (subject, claims["email"] as? String ?? "ChatGPTアカウント")
    }

    static func tokenPolicy(type: String, expiresIn: Double, scopes: [String]) throws {
        guard type.lowercased() == "bearer", expiresIn.isFinite, expiresIn > 0, expiresIn <= 86400,
              Set(["openid", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct"]).isSubset(of: Set(scopes)) else {
            throw ShortcutError.message("認証の種類・有効期限・ChatGPTプラン利用権限を確認できませんでした。")
        }
    }

    static func callback(_ request: String, state: String) throws -> [String: String] {
        let first = request.components(separatedBy: "\r\n")[0].components(separatedBy: " ")
        guard first.count == 3, first[0] == "GET", first[1].hasPrefix("/auth/callback?"),
              let url = URLComponents(string: "http://127.0.0.1" + first[1]), url.path == "/auth/callback" else {
            throw ShortcutError.message("認証の戻り先が不正です。")
        }
        var values: [String: String] = [:]
        for item in url.queryItems ?? [] {
            guard values[item.name] == nil, let value = item.value else {
                throw ShortcutError.message("認証の応答が重複・欠落しています。")
            }
            values[item.name] = value
        }
        guard values["state"] == state else { throw ShortcutError.message("認証の状態が一致しません。") }
        return values
    }

    static func clientID(_ values: [String: String], previous: String?) throws -> String {
        guard values["error"] == nil else { throw ShortcutError.message("ChatGPTへの接続が許可されませんでした。") }
        guard let code = values["code"], !code.isEmpty else { throw ShortcutError.message("認証コードがありません。") }
        let id = values["client_id"] ?? previous ?? ""
        guard !id.isEmpty, id != "dynamic_agent_client", previous == nil || previous == id else {
            throw ShortcutError.message("アカウントの登録情報が一致しません。")
        }
        return id
    }
}

/// Accept only complete SSE frames and a successful terminal response. Partial text is never a draft.
struct ShortcutResponseStream {
    private var dataLines: [String] = []
    private var frameBytes = 0
    private(set) var text = ""
    private(set) var completed = false
    private var totalBytes = 0

    mutating func line(_ line: String) throws {
        totalBytes += line.utf8.count
        guard totalBytes <= 8_000_000 else { throw failure() }
        if line.isEmpty {
            if !dataLines.isEmpty { try event(dataLines.joined(separator: "\n")) }
            dataLines = []; frameBytes = 0
        } else if line.hasPrefix("data:") {
            let value = line.dropFirst(5)
            let data = value.hasPrefix(" ") ? String(value.dropFirst()) : String(value)
            frameBytes += data.utf8.count
            guard frameBytes <= 4_000_000 else { throw failure() }
            dataLines.append(data)
        }
    }

    private mutating func event(_ data: String) throws {
        if data == "[DONE]" { guard completed else { throw failure() }; return }
        guard !completed, let event = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
              let type = event["type"] as? String else { throw failure() }
        switch type {
        case "response.output_text.delta":
            guard let delta = event["delta"] as? String else { throw failure() }
            text += delta
            guard text.utf8.count <= 2_000_000 else { throw failure() }
        case "response.completed":
            guard let response = event["response"] as? [String: Any], response["status"] as? String == "completed",
                  response["error"] == nil || response["error"] is NSNull else { throw failure() }
            completed = true
        case "response.failed", "response.incomplete", "error", "response.refusal.delta", "response.refusal.done":
            throw failure()
        default: break
        }
    }

    func finish() throws -> String {
        guard completed, dataLines.isEmpty, !text.isEmpty else { throw failure() }
        return text
    }

    private func failure() -> ShortcutError {
        .message("AIの応答が完了しませんでした。利用枠・モデル・接続を確認してください。途中の内容は適用していません。")
    }
}
