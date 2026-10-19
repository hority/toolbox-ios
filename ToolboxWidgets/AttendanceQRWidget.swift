import AppIntents
import SwiftUI
import WidgetKit

struct AttendanceQRWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: AttendanceQRWidgetConfigurationIntent
}

struct AttendanceQRWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AttendanceQRWidgetEntry {
        AttendanceQRWidgetEntry(date: Date(), configuration: AttendanceQRWidgetConfigurationIntent())
    }

    func snapshot(for configuration: AttendanceQRWidgetConfigurationIntent,
                  in context: Context) async -> AttendanceQRWidgetEntry {
        AttendanceQRWidgetEntry(date: Date(), configuration: configuration)
    }

    func timeline(for configuration: AttendanceQRWidgetConfigurationIntent,
                  in context: Context) async -> Timeline<AttendanceQRWidgetEntry> {
        Timeline(entries: [AttendanceQRWidgetEntry(date: Date(), configuration: configuration)],
                 policy: .never)
    }
}

struct AttendanceQRWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AttendanceQRWidget",
                               intent: AttendanceQRWidgetConfigurationIntent.self,
                               provider: AttendanceQRWidgetProvider()) { entry in
            AttendanceQRWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("勤怠QR")
        .description("ボタンから固定QRを一時表示。追加後に表示名・内容・登庁/退庁・30秒/60秒を設定します。")
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct AttendanceQRWidgetView: View {
    let entry: AttendanceQRWidgetEntry

    var body: some View {
        if let configuration = try? entry.configuration.validatedConfiguration() {
            Button(intent: ShowAttendanceQRIntent(configuration: configuration)) {
                HStack(spacing: 7) {
                    Image(systemName: "qrcode")
                        .font(.title2)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(configuration.label).font(.headline).lineLimit(1)
                        Text("\(configuration.operation.title) · \(configuration.durationSeconds)秒")
                            .font(.caption).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(configuration.label)、\(configuration.operation.title)のQRを表示")
            .accessibilityHint("固定QRの表示を\(configuration.durationSeconds)秒後に消すよう設定します")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("勤怠QRを設定", systemImage: "qrcode")
                    .font(.headline)
                Text("長押しで内容を編集").font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityLabel("勤怠QRが未設定、または入力が長すぎます。ウィジェットを長押しして編集してください")
        }
    }
}
