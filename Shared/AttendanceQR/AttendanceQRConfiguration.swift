import AppIntents
import Foundation

enum AttendanceQROperation: String, AppEnum, Codable, CaseIterable, Sendable {
    case arrival
    case departure

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "登庁・退庁" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.arrival: "登庁", .departure: "退庁"]
    }

    var title: String { self == .arrival ? "登庁" : "退庁" }
    var symbol: String { self == .arrival ? "building.2" : "figure.walk.departure" }
}

enum AttendanceQRDuration: String, AppEnum, Codable, CaseIterable, Sendable {
    case thirtySeconds
    case sixtySeconds

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "表示時間" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.thirtySeconds: "30秒", .sixtySeconds: "60秒"]
    }

    var seconds: Int { self == .thirtySeconds ? 30 : 60 }
}

enum AttendanceQRError: LocalizedError, Equatable {
    case emptyLabel
    case labelTooLong
    case emptyPayload
    case payloadTooLong
    case unsupportedDuration
    case renderingFailed
    case unsupportedCodeSize
    case invalidDisplayScale
    case activitiesDisabled
    case appExecutionRequired
    case noActiveCard

    var errorDescription: String? {
        switch self {
        case .emptyLabel: "表示名を入力してください。"
        case .labelTooLong: "表示名は16文字・UTF-8で64バイト以内にしてください。"
        case .emptyPayload: "ウィジェットの編集でQRコードの内容を入力してください。"
        case .payloadTooLong: "読み取りやすさのため、QRの内容はUTF-8で64バイト以内にしてください。"
        case .unsupportedDuration: "表示時間は30秒または60秒を選んでください。"
        case .renderingFailed: "この内容のQRコードを作れませんでした。"
        case .unsupportedCodeSize: "この内容は小さなQR表示に適していません。内容を短くしてください。"
        case .invalidDisplayScale: "この画面の表示倍率に対応していません。"
        case .activitiesDisabled: "設定で工具箱のライブアクティビティを許可してください。"
        case .appExecutionRequired: "工具箱を一度開き、ウィジェットを追加し直してください。"
        case .noActiveCard: "実行中の表示が見つかりません。残っているカードはスワイプして閉じてください。"
        }
    }
}

/// A deliberately small payload budget keeps a 136-point QR readable.
/// Payload bytes are never trimmed, normalized, escaped or interpreted as a URL.
struct AttendanceQRConfiguration: Equatable, Sendable {
    static let maximumPayloadBytes = 64
    static let maximumLabelCharacters = 16
    static let maximumLabelBytes = 64

    let label: String
    let payload: String
    let operation: AttendanceQROperation
    let durationSeconds: Int

    init(label: String, payload: String, operation: AttendanceQROperation, durationSeconds: Int) throws {
        let displayLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayLabel.isEmpty else { throw AttendanceQRError.emptyLabel }
        guard displayLabel.count <= Self.maximumLabelCharacters,
              displayLabel.utf8.count <= Self.maximumLabelBytes else {
            throw AttendanceQRError.labelTooLong
        }
        try Self.validatePayload(payload)
        guard durationSeconds == 30 || durationSeconds == 60 else {
            throw AttendanceQRError.unsupportedDuration
        }
        self.label = displayLabel
        self.payload = payload
        self.operation = operation
        self.durationSeconds = durationSeconds
    }

    static func validatePayload(_ payload: String) throws {
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AttendanceQRError.emptyPayload
        }
        guard payload.utf8.count <= maximumPayloadBytes else {
            throw AttendanceQRError.payloadTooLong
        }
    }
}
