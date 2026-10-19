import AppIntents
import Foundation

struct AttendanceQRWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "勤怠QRの設定" }
    static var description: IntentDescription {
        IntentDescription("固定QRを一時表示します。内容はUTF-8で64バイト以内。表示を消してもQR自体は無効になりません。")
    }

    @Parameter(title: "表示名（16文字以内）", default: "勤怠QR")
    var label: String

    @Parameter(title: "QRの内容（UTF-8で64バイト以内）", default: "")
    var payload: String

    @Parameter(title: "登庁・退庁", default: .arrival)
    var operation: AttendanceQROperation

    @Parameter(title: "表示時間", default: .thirtySeconds)
    var duration: AttendanceQRDuration

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$label
            \.$payload
            \.$operation
            \.$duration
        }
    }

    func validatedConfiguration() throws -> AttendanceQRConfiguration {
        try AttendanceQRConfiguration(label: label, payload: payload,
                                      operation: operation, durationSeconds: duration.seconds)
    }
}

/// Compile this type into both targets. LiveActivityIntent routes perform() to
/// the containing app process without opening its UI (openAppWhenRun = false).
/// See https://developer.apple.com/documentation/appintents/liveactivityintent
struct ShowAttendanceQRIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "勤怠QRを表示" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "表示名") var label: String
    @Parameter(title: "QRの内容") var payload: String
    @Parameter(title: "登庁・退庁") var operation: AttendanceQROperation
    @Parameter(title: "表示時間") var duration: AttendanceQRDuration

    init() {}

    init(configuration: AttendanceQRConfiguration) {
        label = configuration.label
        payload = configuration.payload
        operation = configuration.operation
        duration = configuration.durationSeconds == 30 ? .thirtySeconds : .sixtySeconds
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireAttendanceQRHostProcess()
        #if !TOOLBOX_WIDGET_EXTENSION
        let configuration = try AttendanceQRConfiguration(
            label: label, payload: payload, operation: operation, durationSeconds: duration.seconds
        )
        try await AttendanceQRActivityController.show(configuration)
        #endif
        return .result()
    }
}

struct HideAttendanceQRIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "勤怠QRを閉じる" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "表示ID") var activityID: String

    init() {}
    init(activityID: String) { self.activityID = activityID }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireAttendanceQRHostProcess()
        #if !TOOLBOX_WIDGET_EXTENSION
        guard await AttendanceQRActivityController.hide(activityID: activityID) else {
            throw AttendanceQRError.noActiveCard
        }
        #endif
        return .result()
    }
}

private func requireAttendanceQRHostProcess() throws {
    #if TOOLBOX_WIDGET_EXTENSION
    // Defensive only: do not fall back to opening the foreground app.
    throw AttendanceQRError.appExecutionRequired
    #endif
}
