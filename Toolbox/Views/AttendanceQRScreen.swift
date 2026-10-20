import SwiftUI
import UIKit

/// One process-wide lease: multiple windows cannot restore each other's idle timer.
@MainActor
final class AttendanceQRIdleTimer {
    static let shared = AttendanceQRIdleTimer()
    private var owners: Set<UUID> = []
    private var previousValue: Bool?
    private let read: @MainActor () -> Bool
    private let write: @MainActor (Bool) -> Void

    init(read: @escaping @MainActor () -> Bool = { UIApplication.shared.isIdleTimerDisabled },
         write: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.read = read
        self.write = write
    }

    func setActive(_ active: Bool, owner: UUID) {
        if active {
            guard owners.insert(owner).inserted else { return }
            if owners.count == 1 {
                previousValue = read()
                write(true)
            }
        } else {
            guard owners.remove(owner) != nil else { return }
            if owners.isEmpty, let previousValue {
                write(previousValue)
                self.previousValue = nil
            }
        }
    }
}

struct AttendanceQRScreen: View {
    let configuration: AttendanceQRConfiguration?
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(configuration?.label ?? "勤怠QRの設定").font(.headline)
                Spacer()
                Button("閉じる", action: close).buttonStyle(.bordered)
            }
            if let configuration {
                GeometryReader { geometry in
                    let side = min(1024, floor(min(geometry.size.width, geometry.size.height) * displayScale) / displayScale)
                    if scenePhase == .active,
                       let code = try? AttendanceQRRenderer.render(payload: configuration.payload,
                                                                  displayScale: displayScale, canvasSide: side) {
                        AttendanceQRBitmap(code: code, displayScale: displayScale)
                            .offset(x: floor((geometry.size.width - side) * displayScale / 2) / displayScale,
                                    y: floor((geometry.size.height - side) * displayScale / 2) / displayScale)
                    } else {
                        Text(scenePhase == .active ? "QRを表示できません。画面を縦向きにしてください。" : "QRを非表示にしています")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Text("登庁・退庁共通 · 読み取り後に閉じてください")
                    .font(.footnote)
                Text("表示中は自動スリープを停止します。打刻結果は勤務先で確認してください。")
                    .font(.caption)
            } else {
                Text("QRが未設定、または入力が正しくありません。")
                    .font(.headline)
                AttendanceQRHelpView()
            }
        }
        .padding(16)
        .background(.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }
}

/// Created only for a successfully rendered QR in an active scene. Removing the
/// bitmap (close, background, invalid input or insufficient space) releases sleep.
private struct AttendanceQRBitmap: View {
    let code: AttendanceQRRenderer.RenderedCode
    let displayScale: CGFloat
    @Environment(\.scenePhase) private var scenePhase
    @State private var owner = UUID()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Image(code.image, scale: displayScale, label: Text("登庁・退庁共通の固定QRコード"))
                .interpolation(.none)
                .frame(width: code.pointSide, height: code.pointSide)
                .offset(x: code.leadingInset, y: code.leadingInset)
        }
        .frame(width: code.canvasSide, height: code.canvasSide)
        .privacySensitive()
        .onAppear { AttendanceQRIdleTimer.shared.setActive(scenePhase == .active, owner: owner) }
        .onChange(of: scenePhase) { _, phase in
            AttendanceQRIdleTimer.shared.setActive(phase == .active, owner: owner)
        }
        .onDisappear { AttendanceQRIdleTimer.shared.setActive(false, owner: owner) }
    }
}
