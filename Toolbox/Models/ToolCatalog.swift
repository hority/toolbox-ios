import Foundation

enum ToolID: String, Hashable, Sendable {
    case textCounter
    case shortcutSigning
}

enum ToolAvailability: Equatable, Sendable {
    case available
    case planned

    var title: String {
        switch self {
        case .available: "利用できます"
        case .planned: "準備中"
        }
    }
}

enum ToolFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case available
    case planned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "すべて"
        case .available: "利用可能"
        case .planned: "準備中"
        }
    }

    func includes(_ availability: ToolAvailability) -> Bool {
        switch self {
        case .all: true
        case .available: availability == .available
        case .planned: availability == .planned
        }
    }
}

struct ToolDefinition: Identifiable, Sendable {
    let id: ToolID
    let title: String
    let subtitle: String
    let symbol: String
    let availability: ToolAvailability
    let keywords: [String]

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return ([title, subtitle] + keywords).contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }
}

enum ToolCatalog {
    static let all: [ToolDefinition] = [
        ToolDefinition(
            id: .textCounter,
            title: "文字数カウント",
            subtitle: "文字数・行数・データサイズを確認",
            symbol: "textformat.abc",
            availability: .available,
            keywords: ["テキスト", "文字", "カウント", "text", "count", "UTF-8"]
        ),
        ToolDefinition(
            id: .shortcutSigning,
            title: "ショートカット署名",
            subtitle: "今後追加予定のツールです",
            symbol: "signature",
            availability: .planned,
            keywords: ["ショートカット", "署名", "shortcut", "signing"]
        )
    ]

    static func tools(matching query: String, filter: ToolFilter) -> [ToolDefinition] {
        all.filter { filter.includes($0.availability) && $0.matches(query) }
    }
}
