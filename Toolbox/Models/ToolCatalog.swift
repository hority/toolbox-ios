import Foundation

enum ToolID: String, Hashable, Sendable {
    case textCounter
    case shortcutSigning
    case attendanceQR
    case brushingCoach
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
            subtitle: "読み込み・JSON編集・署名・書き出し",
            symbol: "signature",
            availability: .available,
            keywords: ["ショートカット", "署名", "shortcut", "signing"]
        ),
        ToolDefinition(
            id: .attendanceQR,
            title: "登庁・退庁QR",
            subtitle: "ロック画面から固定QRを一時表示",
            symbol: "qrcode",
            availability: .available,
            keywords: ["登庁", "退庁", "出勤", "退勤", "QR", "ウィジェット"]
        ),
        ToolDefinition(
            id: .brushingCoach,
            title: "はみがきコーチ",
            subtitle: "インカメラで2分ナビ・うさぎやパンダに変身",
            symbol: "mouth",
            availability: .available,
            keywords: ["歯みがき", "歯磨き", "はみがき", "子供", "こども", "カメラ", "うさぎ", "パンダ", "タイマー"]
        )
    ]

    static func tools(matching query: String, filter: ToolFilter) -> [ToolDefinition] {
        all.filter { filter.includes($0.availability) && $0.matches(query) }
    }
}
