import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct AttendanceQRLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AttendanceQRActivityAttributes.self) { context in
            AttendanceQRActivityCard(context: context)
                .activityBackgroundTint(.white)
                .activitySystemActionForegroundColor(.black)
        } dynamicIsland: { context in
            // The OS-managed dismissal strategy ends the activity immediately,
            // so these are brief fallback presentations, not a persistent QR.
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.operation.title, systemImage: "qrcode")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.label).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.shouldDisplayQR(at: Date(), isStale: context.isStale) {
                        HStack {
                            Text("QRはロック画面に表示").font(.caption)
                            Spacer()
                            Button(intent: HideAttendanceQRIntent(activityID: context.activityID)) {
                                Image(systemName: "xmark.circle")
                            }
                            .accessibilityLabel("実行中のQR表示を停止")
                        }
                    } else {
                        Text("QRの表示終了").font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: "qrcode")
            } compactTrailing: {
                Text(context.attributes.operation == .arrival ? "登" : "退")
            } minimal: {
                Image(systemName: "qrcode")
            }
            .keylineTint(.white)
        }
    }
}

private struct AttendanceQRActivityCard: View {
    let context: ActivityViewContext<AttendanceQRActivityAttributes>
    @Environment(\.displayScale) private var displayScale

    private var canShowQR: Bool {
        context.state.shouldDisplayQR(at: Date(), isStale: context.isStale)
    }

    var body: some View {
        HStack(spacing: 12) {
            qrContent
                .frame(width: AttendanceQRRenderer.presentationSide,
                       height: AttendanceQRRenderer.presentationSide)
                .background(.white)

            VStack(alignment: .leading, spacing: 5) {
                Text(context.attributes.label)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(context.attributes.operation.title)
                    .font(.system(size: 14, weight: .medium))
                if canShowQR {
                    HStack(spacing: 3) {
                        Text("非表示まで")
                        Text(timerInterval: context.state.startedAt...context.state.expiresAt,
                             countsDown: true, showsHours: false)
                            .monospacedDigit()
                            .frame(maxWidth: 44, alignment: .leading)
                    }
                    .font(.system(size: 11))
                } else {
                    Text("表示を終了しました").font(.system(size: 11))
                }
                Text("表示のみ・打刻結果は未確認")
                    .font(.system(size: 10))
                    .lineLimit(2)
                // This card is already ended; interactivity and a second end()
                // are not guaranteed. Use the system's dismissal affordance.
                Text("カードをスワイプで閉じる")
                    .font(.system(size: 10))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.black)
        .padding(10)
        .frame(height: 156)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var qrContent: some View {
        if canShowQR, let payload = context.state.payload {
            if let code = try? AttendanceQRRenderer.render(payload: payload, displayScale: displayScale) {
                ZStack(alignment: .topLeading) {
                    Color.white
                    Image(code.image, scale: displayScale,
                          label: Text("\(context.attributes.operation.title)用の固定QRコード"))
                        .interpolation(.none)
                        .widgetAccentedRenderingMode(.fullColor)
                        .frame(width: code.pointSide, height: code.pointSide)
                        .offset(x: code.leadingInset, y: code.leadingInset)
                        .privacySensitive()
                }
                .frame(width: AttendanceQRRenderer.presentationSide,
                       height: AttendanceQRRenderer.presentationSide)
            } else {
                statusLabel("QRを表示できません", symbol: "exclamationmark.triangle")
            }
        } else {
            statusLabel("表示終了", symbol: "qrcode")
        }
    }

    private func statusLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30))
            Text(title).font(.system(size: 12, weight: .medium))
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
