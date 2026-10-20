import Foundation

/// Content-Type is a hint, never proof of completion. No body content enters diagnostics.
struct ShortcutResponseDecoder {
    private enum Format { case undecided, sse, json }
    private var format = Format.undecided
    private var stream = ShortcutResponseStream()
    private var buffer = Data()
    private var received = 0
    private let status: Int
    private let mediaType: String?

    init(status: Int, contentType: String?) {
        self.status = status
        mediaType = Self.normalizedMIME(contentType)
    }

    static func normalizedMIME(_ value: String?) -> String? {
        guard let first = value?.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first else { return nil }
        let type = first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return type.isEmpty ? nil : type
    }

    var diagnostic: String {
        // Unknown header values may contain arbitrary upstream data; never echo them.
        let known = ["text/event-stream", "application/json", "text/plain", "text/html", "application/xhtml+xml", "application/octet-stream"]
        let label = mediaType.map { known.contains($0) ? $0 : "other" } ?? "missing"
        return "HTTP \(status) · Content-Type: \(label)"
    }

    var textCount: Int { stream.text.count }

    /// Returns true at SSE frame boundaries, where the UI may update progress.
    mutating func append(_ byte: UInt8) throws -> Bool {
        do { return try consume(byte) }
        catch { throw invalid() }
    }

    private mutating func consume(_ byte: UInt8) throws -> Bool {
        guard status == 200, mediaType != "text/html", mediaType != "application/xhtml+xml" else { throw invalid() }
        received += 1
        guard received <= 8_000_000 else { throw invalid() }
        if format == .undecided {
            if [UInt8(9), 10, 13, 32].contains(byte) { return false }
            switch byte {
            case 123: format = .json // A Responses object, not an arbitrary JSON draft.
            case 58, 100, 101, 105, 114: format = .sse // :, data, event, id, retry
            default: throw invalid()
            }
        }
        if format == .json {
            guard buffer.count < 4_000_000 else { throw invalid() }
            buffer.append(byte)
            return false
        }
        if byte == 10 {
            if buffer.last == 13 { buffer.removeLast() }
            guard let line = String(data: buffer, encoding: .utf8),
                  line.isEmpty || line.hasPrefix(":") || ["data:", "event:", "id:", "retry:"].contains(where: { line.hasPrefix($0) }) else { throw invalid() }
            try stream.line(line)
            buffer.removeAll(keepingCapacity: true)
            return line.isEmpty
        }
        guard buffer.count < 4_000_000 else { throw invalid() }
        buffer.append(byte)
        return false
    }

    func finish() throws -> String {
        do {
            switch format {
            case .sse:
                guard buffer.isEmpty else { throw invalid() }
                return try stream.finish()
            case .json: return try Self.completedResponseText(buffer)
            case .undecided: throw invalid()
            }
        } catch { throw invalid() }
    }

    /// Public Responses object shape. A created/in-progress response, error envelope,
    /// refusal, tool call, or bare generated workflow cannot satisfy these checks.
    private static func completedResponseText(_ data: Data) throws -> String {
        func bad() -> ShortcutError { .message("Responsesの完了結果を確認できませんでした。") }
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              response["object"] as? String == "response",
              let id = response["id"] as? String, !id.isEmpty,
              response["status"] as? String == "completed",
              response["error"] == nil || response["error"] is NSNull,
              response["incomplete_details"] == nil || response["incomplete_details"] is NSNull,
              let output = response["output"] as? [[String: Any]] else { throw bad() }
        var text = ""
        for item in output {
            // Reasoning may accompany the assistant message; never use it as draft text.
            if item["type"] as? String == "reasoning" { continue }
            guard item["type"] as? String == "message", item["role"] as? String == "assistant",
                  item["status"] as? String == "completed",
                  let content = item["content"] as? [[String: Any]] else { throw bad() }
            for part in content {
                guard part["type"] as? String == "output_text", let value = part["text"] as? String else { throw bad() }
                text += value
                guard text.utf8.count <= 2_000_000 else { throw bad() }
            }
        }
        guard !text.isEmpty else { throw bad() }
        return text
    }

    private func invalid() -> ShortcutError {
        .message("AIの応答の形式・完了状態を確認できませんでした（\(diagnostic)）。利用枠・モデル・接続を確認してください。途中の内容は適用していません。")
    }
}
