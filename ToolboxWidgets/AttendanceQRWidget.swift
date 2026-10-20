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
        .description("タップでアプリの全画面QRを開きます。表示名と登庁・退庁共通のQR内容を設定します。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct AttendanceQRWidgetView: View {
    let entry: AttendanceQRWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        // Default WidgetKit tap delivers the exact configuration in NSUserActivity.
        // Do not add a Button, Link or widgetURL: no private payload belongs in a URL.
        Group {
            if family == .accessoryCircular {
                Image(systemName: "qrcode")
                    .font(.title2)
                    .widgetAccentable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "qrcode").font(.title2).widgetAccentable()
                    VStack(alignment: .leading) {
                        Text(entry.configuration.label).font(.headline).lineLimit(1)
                        Text("全画面QRを開く").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("アプリで勤怠QRを開く。未設定の場合は設定方法を表示")
        .accessibilityHint("ロック解除後に共通のQRを全画面表示します")
    }
}
