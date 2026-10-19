import Foundation
import Observation

enum ShortcutError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct ShortcutRevision: Codable, Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    var name: String
    var source: String
    var summary: String
}

struct ShortcutDraft: Codable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var source: String
    var summary: String
    var modified = Date()
    var revisions: [ShortcutRevision] = []

    var actionCount: Int {
        guard let object = try? ShortcutFormat.workflow(source) else { return 0 }
        return (object["WFWorkflowActions"] as? [Any])?.count ?? 0
    }

    mutating func replace(name: String, source: String, summary: String) {
        revisions.insert(ShortcutRevision(name: self.name, source: self.source, summary: self.summary), at: 0)
        revisions = Array(revisions.prefix(10))
        self.name = name
        self.source = source
        self.summary = summary
        modified = Date()
    }

    static var example: ShortcutDraft {
        let workflow: [String: Any] = [
            "WFWorkflowClientVersion": "3036.0.4.2",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": ["WFWorkflowIconStartColor": 4282601983 as UInt64, "WFWorkflowIconGlyphNumber": 59511],
            "WFWorkflowImportQuestions": [], "WFWorkflowTypes": [],
            "WFWorkflowInputContentItemClasses": ["WFStringContentItem"],
            "WFWorkflowHasOutputFallback": false,
            "WFWorkflowActions": [[
                "WFWorkflowActionIdentifier": "is.workflow.actions.alert",
                "WFWorkflowActionParameters": [
                    "WFAlertActionTitle": "こんにちは！",
                    "WFAlertActionMessage": "工具箱から作成したショートカットです。",
                    "WFAlertActionCancelButtonShown": false,
                ],
            ]],
        ]
        return ShortcutDraft(name: "はじめてのショートカット", source: try! ShortcutFormat.json(workflow), summary: "メッセージを表示するサンプルです。JSONを編集して内容を変更できます。")
    }
}

enum ShortcutFormat {
    static func workflow(_ source: String) throws -> [String: Any] {
        guard source.utf8.count <= 2_000_000,
              let raw = try JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any],
              let object = try decodeValues(raw) as? [String: Any],
              let actions = object["WFWorkflowActions"] as? [[String: Any]], actions.count <= 500,
              actions.allSatisfy({ $0["WFWorkflowActionIdentifier"] is String && $0["WFWorkflowActionParameters"] is [String: Any] }),
              PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
            throw ShortcutError.message("WFWorkflowActionsと各アクションの識別子・パラメータを確認してください。nullは使用できません。")
        }
        return object
    }

    static func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: encodeValues(object), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    static func plist(_ source: String, format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: workflow(source), format: format, options: 0)
    }

    static func safeName(_ name: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !cleaned.isEmpty else { return "Shortcut" }
        var result = ""
        for character in cleaned.prefix(80) {
            guard result.utf8.count + String(character).utf8.count <= 180 else { break }
            result.append(character)
        }
        return result.isEmpty ? "Shortcut" : result
    }

    static func validate(_ draft: ShortcutDraft) throws {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.name.count <= 100, draft.summary.utf8.count <= 10_000,
              draft.revisions.count <= 10 else {
            throw ShortcutError.message("名前・説明または履歴が長すぎます。名前は100文字以内で入力してください。")
        }
        _ = try workflow(draft.source)
        for revision in draft.revisions {
            guard revision.name.count <= 100, revision.summary.utf8.count <= 10_000 else {
                throw ShortcutError.message("履歴の名前・説明が長すぎます。")
            }
            _ = try workflow(revision.source)
        }
    }

    private static func dateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func encodeValues(_ value: Any) -> Any {
        if let data = value as? Data { return ["$studioData": data.base64EncodedString()] }
        if let date = value as? Date { return ["$studioDate": dateFormatter().string(from: date)] }
        if let array = value as? [Any] { return array.map(encodeValues) }
        if let object = value as? [String: Any] { return object.mapValues(encodeValues) }
        return value
    }

    private static func decodeValues(_ value: Any) throws -> Any {
        if let array = value as? [Any] { return try array.map(decodeValues) }
        if let object = value as? [String: Any] {
            if object.count == 1, let encoded = object["$studioData"] as? String {
                guard let data = Data(base64Encoded: encoded) else { throw ShortcutError.message("添付データを読み込めませんでした。") }
                return data
            }
            if object.count == 1, let encoded = object["$studioDate"] as? String {
                guard let date = (dateFormatter().date(from: encoded) ?? ISO8601DateFormatter().date(from: encoded)) else { throw ShortcutError.message("日付データを読み込めませんでした。") }
                return date
            }
            return try object.mapValues(decodeValues)
        }
        return value
    }
}

@MainActor @Observable final class ShortcutLibrary {
    var drafts: [ShortcutDraft] = []
    var error: String?
    private let file: URL
    private var loadFailed = false

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "ShortcutLibrary", directoryHint: .isDirectory)) {
        file = directory.appending(path: "drafts.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try ShortcutImport.boundedRead(file, limit: 64_000_000)
                let loaded = try JSONDecoder().decode([ShortcutDraft].self, from: data)
                for draft in loaded { try ShortcutFormat.validate(draft) }
                drafts = loaded
            } else { drafts = [.example]; try save() }
        } catch {
            loadFailed = true
            self.error = "編集データを読み込めませんでした。既存ファイルを保護するため保存を中止しています。アプリを開き直してください。\(error.localizedDescription)"
        }
    }

    func save() throws {
        guard !loadFailed else {
            throw ShortcutError.message("保存済みデータを読み込めなかったため、上書きを中止しました。アプリを開き直して再度お試しください。")
        }
        let data = try JSONEncoder().encode(drafts)
        guard data.count <= 64_000_000 else {
            throw ShortcutError.message("ライブラリが64MBを超えています。不要な下書きを書き出して削除してください。")
        }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func upsert(_ draft: ShortcutDraft) throws {
        try ShortcutFormat.validate(draft)
        let previous = drafts
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[index] = draft }
        else { drafts.insert(draft, at: 0) }
        do { try save() } catch { drafts = previous; throw error }
    }

    func remove(_ id: UUID) throws {
        let previous = drafts
        drafts.removeAll { $0.id == id }
        do { try save() } catch { drafts = previous; throw error }
    }
}

