import AVFoundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class BrushingCameraModel {
    enum Status { case idle, starting, running, unauthorized, unavailable }

    /// Mean luma change that counts as brushing. Needs real-device tuning.
    static let motionThreshold = 8.0
    private static let brushingHoldSeconds = 0.5

    private(set) var status = Status.idle
    private(set) var imageSize = CGSize.zero
    private(set) var face: BrushingFrame.Face?
    private(set) var lastMotion: Date?
    let previewLayer = AVCaptureVideoPreviewLayer()

    @ObservationIgnored private var camera: BrushingCamera?
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?

    func isBrushing(at date: Date = .now) -> Bool {
        guard face != nil, let lastMotion else { return false }
        return date.timeIntervalSince(lastMotion) < Self.brushingHoldSeconds
    }

    func start() async {
        guard status == .idle || status == .unauthorized else { return }
        status = .starting
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            // The screen may have closed while the system prompt was shown.
            guard status == .starting else { return }
            guard granted else { status = .unauthorized; return }
        default:
            status = .unauthorized
            return
        }
        if camera == nil {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                status = .unavailable
                return
            }
            let camera = BrushingCamera(device: device)
            previewLayer.session = camera.session
            previewLayer.videoGravity = .resizeAspectFill
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview) { @Sendable [weak self] _, _ in
                Task { @MainActor in self?.applyRotation() }
            }
            self.camera = camera
            rotationCoordinator = coordinator
        }
        camera?.start(
            onFrame: { [weak self] frame in Task { @MainActor in self?.receive(frame) } },
            completion: { [weak self] started in Task { @MainActor in self?.didStart(started) } }
        )
    }

    func stop() {
        camera?.stop()
        face = nil
        lastMotion = nil
        if status == .starting || status == .running { status = .idle }
    }

    private func didStart(_ started: Bool) {
        guard status == .starting else { return }
        status = started ? .running : .unavailable
        applyRotation()
    }

    private func applyRotation() {
        guard let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview else { return }
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        camera?.setRotationAngle(angle)
    }

    private func receive(_ frame: BrushingFrame) {
        guard status == .running else { return }
        if frame.imageSize != imageSize {
            imageSize = frame.imageSize
            face = nil
        }
        if let next = frame.face {
            face = face.map { $0.blended(toward: next, by: 0.5) } ?? next
        } else {
            face = nil
        }
        if frame.motion > Self.motionThreshold {
            lastMotion = .now
        }
    }
}

struct BrushingCoachView: View {
    private enum Phase { case ready, brushing, finished }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("brushingMask") private var mask = BrushingMask.bunny
    @AppStorage("brushingSoundEnabled") private var soundEnabled = true
    @State private var camera = BrushingCameraModel()
    @State private var stampCard = BrushingStampCard()
    @State private var sound = BrushingSound()
    @State private var sparkles = SparkleField()
    @State private var phase = Phase.ready
    @State private var session = BrushingSession()
    @State private var overlaySize = CGSize.zero
    @State private var celebrateDate: Date?
    @State private var zoneAnnounceDate: Date?
    @State private var germPops = 0
    @State private var earnedStamp = false
    @State private var showingStampCard = false
    @State private var idleOwner = UUID()

    init() {
        PixelStyle.registerFont()
    }

    private var screenFace: ScreenFace? {
        camera.face.map { ScreenFace($0, imageSize: camera.imageSize, viewSize: overlaySize) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch camera.status {
            case .unauthorized:
                unauthorizedView
            case .unavailable:
                ContentUnavailableView("カメラを使えません", systemImage: "video.slash",
                                       description: Text("インカメラのある実機で開いてください。"))
                    .foregroundStyle(.white)
            case .idle, .starting, .running:
                cameraView
            }
        }
        .font(.pixel(17))
        .navigationTitle("はみがきコーチ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    soundEnabled.toggle()
                } label: {
                    Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .accessibilityLabel(soundEnabled ? "おとを けす" : "おとを だす")
            }
        }
        .sheet(isPresented: $showingStampCard) {
            BrushingStampCardView(card: stampCard)
        }
        .task {
            sound.isEnabled = soundEnabled
            sound.playMusic(.menu)
            await camera.start()
        }
        .onDisappear {
            camera.stop()
            sound.deactivate()
            AttendanceQRIdleTimer.shared.setActive(false, owner: idleOwner)
        }
        .onChange(of: soundEnabled) { _, enabled in
            sound.isEnabled = enabled
            if enabled { sound.playMusic(phase == .brushing ? .brushing : .menu) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                sound.playMusic(phase == .brushing ? .brushing : .menu)
                Task { await camera.start() }
            } else {
                camera.stop()
                sound.deactivate()
                if phase == .brushing { phase = .ready }
            }
        }
        .onChange(of: phase) { _, newPhase in
            AttendanceQRIdleTimer.shared.setActive(newPhase == .brushing, owner: idleOwner)
            switch newPhase {
            case .ready: sound.playMusic(.menu)
            case .brushing: sound.playMusic(.brushing)
            // The fanfare plays alone; menu music returns after it in the phase task.
            case .finished: sound.stopMusic()
            }
        }
        .task(id: phase) {
            guard phase == .brushing else {
                if phase == .finished {
                    try? await Task.sleep(for: .seconds(2.5))
                    if !Task.isCancelled { sound.playMusic(.menu) }
                }
                return
            }
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled, phase == .brushing {
                try? await Task.sleep(for: .milliseconds(100))
                let now = clock.now
                tick(delta: (now - last) / .seconds(1))
                last = now
            }
        }
        .onChange(of: session.currentZone) { _, zone in
            zoneAnnounceDate = zone == nil ? nil : .now
        }
        .sensoryFeedback(.impact, trigger: session.currentZone)
        .sensoryFeedback(.impact(weight: .light), trigger: germPops)
        .sensoryFeedback(.success, trigger: phase) { _, newPhase in newPhase == .finished }
    }

    // MARK: - Game loop

    private func tick(delta: TimeInterval) {
        let brushing = camera.isBrushing()
        let zone = session.currentZone
        let before = zone.map(session.germsRemaining(in:)) ?? 0
        session.advance(by: delta, brushing: brushing)
        let face = screenFace
        if let zone, let face {
            let after = session.germsRemaining(in: zone)
            if after < before {
                let index = BrushingSession.germsPerZone - before
                let point = GermLayout.positions(for: zone, face: face)[index]
                sparkles.emit(at: point, count: 24, speed: 60...200, size: 12...24)
                sound.play(after == 0 ? .chime : .pop)
                germPops += 1
                if after == 0 { celebrateDate = .now }
            }
        }
        if brushing, let face {
            sparkles.emit(at: face.mouth, count: 2, speed: 40...120, size: 8...16)
        }
        if session.isFinished { finish() }
    }

    private func start() {
        sound.play(.tap)
        session = BrushingSession()
        celebrateDate = nil
        earnedStamp = false
        phase = .brushing
    }

    private func finish() {
        let stars = BrushingSession.stars(for: session.overallRatio)
        if stars > 0 {
            stampCard.add(stars: stars, mask: mask)
            earnedStamp = true
        }
        phase = .finished
        sound.play(.fanfare)
        let center = CGPoint(x: overlaySize.width / 2, y: overlaySize.height * 0.3)
        sparkles.emit(at: center, count: 80, speed: 120...360, size: 12...26)
    }

    // MARK: - Screens

    private var cameraView: some View {
        ZStack {
            CameraPreview(layer: camera.previewLayer)
                .ignoresSafeArea()
            effectLayer
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 12) {
                switch phase {
                case .ready: readyPanel
                case .brushing: brushingHUD
                case .finished: resultPanel
                }
                Spacer()
                switch phase {
                case .ready, .finished: controls
                case .brushing: statusBubble
                }
            }
            .padding(16)
        }
    }

    private var effectLayer: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date
            let time = now.timeIntervalSinceReferenceDate
            let brushing = camera.isBrushing(at: now)
            let sinceClear = celebrateDate.map { now.timeIntervalSince($0) } ?? .infinity
            let sinceZone = zoneAnnounceDate.map { now.timeIntervalSince($0) } ?? .infinity
            ZStack {
                if let face = screenFace {
                    if phase == .brushing, let zone = session.currentZone {
                        let positions = GermLayout.positions(for: zone, face: face)
                        let size = GermLayout.size(for: face)
                        let defeated = BrushingSession.germsPerZone - session.germsRemaining(in: zone)
                        ForEach(defeated..<BrushingSession.germsPerZone, id: \.self) { index in
                            GermView(index: index, time: time, shaking: brushing)
                                .frame(width: size, height: size)
                                .position(positions[index])
                        }
                    }
                    MaskView(mask: mask, face: face, time: time, excitement: brushing ? 1 : 0,
                             hop: sinceClear < 0.6 ? sin(sinceClear / 0.6 * .pi) : 0)
                }
                Canvas { context, _ in sparkles.draw(&context, now: now) }
                if phase == .brushing, sinceZone < 2, let zone = session.currentZone {
                    ZoneToast(title: zone.title, progress: sinceZone / 2)
                        .position(x: overlaySize.width / 2, y: overlaySize.height * 0.24)
                }
                if sinceClear < 1.4 {
                    PikapikaBanner(progress: sinceClear / 1.4)
                        .position(x: overlaySize.width / 2, y: overlaySize.height * 0.45)
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { overlaySize = $0 }
    }

    private var readyPanel: some View {
        Text("ばいきんを やっつけよう！")
            .font(.pixel(20, relativeTo: .headline))
            .foregroundStyle(PixelStyle.pink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .pixelPanel()
    }

    /// Kept small so the face, mask and germs stay visible.
    private var brushingHUD: some View {
        HStack(alignment: .top) {
            ProgressHUD(session: session)
            Spacer()
            Button {
                sound.play(.tap)
                phase = .ready
            } label: {
                Text("×")
                    .font(.pixel(24, relativeTo: .headline))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(PixelButtonStyle(fill: PixelStyle.paper, foreground: PixelStyle.ink))
            .accessibilityLabel("やめる")
        }
    }

    private var statusBubble: some View {
        let brushing = camera.isBrushing()
        let text = camera.face == nil ? "おかおを うつしてね" : brushing ? "ゴシゴシ！ いいね！" : "ブラシを うごかそう"
        return Text(text)
            .font(.pixel(22, relativeTo: .title3))
            .foregroundStyle(brushing ? .white : PixelStyle.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .pixelPanel(brushing ? PixelStyle.pink : PixelStyle.paper)
    }

    private var resultPanel: some View {
        let stars = BrushingSession.stars(for: session.overallRatio)
        return VStack(spacing: 10) {
            StarRow(stars: stars)
            Text(resultMessage(stars: stars))
                .font(.pixel(24, relativeTo: .title2))
                .foregroundStyle(PixelStyle.pink)
                .multilineTextAlignment(.center)
            if earnedStamp {
                Text("がんばりカードに スタンプ ゲット！")
                    .font(.pixel(15, relativeTo: .subheadline))
                    .foregroundStyle(PixelStyle.ink)
            }
            ZoneMap(current: nil) { zone in
                BrushingSession.stars(for: session.ratio(for: zone)) >= 2
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .pixelPanel()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BrushingMask.allCases) { option in
                        MaskButton(mask: option, selected: option == mask) {
                            sound.play(.select)
                            mask = option
                        }
                    }
                }
                .padding(.bottom, 6)
                .padding(.trailing, 6)
            }
            HStack(spacing: 12) {
                Button {
                    sound.play(.tap)
                    showingStampCard = true
                } label: {
                    VStack(spacing: 0) {
                        Text("カード").font(.pixel(12, relativeTo: .caption))
                        Text("\(stampCard.stamps.count)").font(.pixel(20, relativeTo: .headline))
                    }
                    .frame(width: 44, height: 40)
                }
                .buttonStyle(PixelButtonStyle(fill: PixelStyle.yellow, foreground: PixelStyle.ink))
                .accessibilityLabel("がんばりカード スタンプ \(stampCard.stamps.count)こ")

                Button(action: start) {
                    Text(phase == .finished ? "もういちど！" : "はじめる！")
                        .font(.pixel(26, relativeTo: .title2))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(PixelButtonStyle())
                .disabled(camera.status != .running)
                .opacity(camera.status == .running ? 1 : 0.5)
            }
            Text("映像は端末内で処理し、保存・送信しません。採点は口もとの動きの量による目安で、磨き残しは判定できません。")
                .font(.caption2)
                .foregroundStyle(PixelStyle.ink.opacity(0.7))
        }
        .padding(14)
        .pixelPanel()
    }

    private var unauthorizedView: some View {
        ContentUnavailableView {
            Label("カメラが許可されていません", systemImage: "video.slash")
        } description: {
            Text("設定アプリで「工具箱」のカメラを許可すると使えます。映像は保存・送信しません。")
        } actions: {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
    }

    private func resultMessage(stars: Int) -> String {
        switch stars {
        case 3: "すごい！ ピカピカだね！"
        case 2: "よくできました！"
        case 1: "もうすこし ゴシゴシしよう"
        default: "つぎは いっしょに がんばろう"
        }
    }
}

private struct MaskButton: View {
    let mask: BrushingMask
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                MaskAvatar(mask: mask, size: 48)
                Text(mask.title)
                    .font(.pixel(12, relativeTo: .caption))
                    .foregroundStyle(PixelStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 60)
            .padding(.vertical, 4)
            .pixelPanel(selected ? PixelStyle.yellow : .white, shadow: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mask.title)の おめん")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Mouth map (upper row then lower row, as seen in the mirror) above a 12-block time bar.
private struct ProgressHUD: View {
    let session: BrushingSession

    private static let rows: [[BrushingZone]] = [
        [.upperLeft, .upperFront, .upperRight],
        [.lowerLeft, .lowerFront, .lowerRight]
    ]

    var body: some View {
        let blocks = 12
        let filled = Int((1 - session.remaining / BrushingSession.totalDuration) * Double(blocks))
        VStack(spacing: 6) {
            VStack(spacing: 3) {
                ForEach(Self.rows, id: \.first) { row in
                    HStack(spacing: 3) {
                        ForEach(row) { zone in
                            Rectangle().fill(color(for: zone)).frame(width: 16, height: 12)
                        }
                    }
                }
            }
            HStack(spacing: 1) {
                ForEach(0..<blocks, id: \.self) { index in
                    Rectangle()
                        .fill(index < filled ? PixelStyle.pink : PixelStyle.ink.opacity(0.15))
                        .frame(width: 4, height: 6)
                }
            }
        }
        .padding(8)
        .pixelPanel()
        .accessibilityElement()
        .accessibilityLabel("\(session.currentZone?.title ?? "") のこり \(Int(session.remaining.rounded(.up)))びょう")
    }

    private func color(for zone: BrushingZone) -> Color {
        guard let current = session.currentZone else { return PixelStyle.mint }
        if zone == current {
            return PixelStyle.pink
        }
        return zone.rawValue < current.rawValue ? PixelStyle.mint : PixelStyle.ink.opacity(0.15)
    }
}

/// The new zone's name, shown briefly when it changes. `progress` runs 0→1.
private struct ZoneToast: View {
    let title: String
    let progress: Double

    var body: some View {
        Text("つぎは \(title)！")
            .font(.pixel(28, relativeTo: .title))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .pixelPanel(PixelStyle.pink)
            .scaleEffect(progress < 0.06 ? 0.8 : 1)
            .opacity(progress > 0.85 && Int(progress * 40) % 2 == 0 ? 0 : 1)
            .accessibilityHidden(true)
    }
}

private struct StarRow: View {
    let stars: Int
    @State private var revealed = 0

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                PixelSprite(name: index < stars && index < revealed ? "pixel-star" : "pixel-star-empty", width: 44)
            }
        }
        .task {
            for step in 1...3 {
                try? await Task.sleep(for: .milliseconds(350))
                revealed = step
            }
        }
        .accessibilityElement()
        .accessibilityLabel("ほし \(stars)こ")
    }
}

/// Upper row then lower row, as the child sees themselves in the mirrored preview.
private struct ZoneMap: View {
    let current: BrushingZone?
    let done: (BrushingZone) -> Bool

    private static let rows: [[BrushingZone]] = [
        [.upperLeft, .upperFront, .upperRight],
        [.lowerLeft, .lowerFront, .lowerRight]
    ]

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Self.rows, id: \.first) { row in
                GridRow {
                    ForEach(row) { zone in
                        HStack(spacing: 4) {
                            if done(zone) { PixelSprite(name: "pixel-star", width: 14) }
                            Text(zone.shortTitle)
                        }
                        .font(.pixel(15, relativeTo: .subheadline))
                        .foregroundStyle(PixelStyle.ink)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .pixelPanel(done(zone) ? PixelStyle.mint : .white, shadow: false)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BrushingStampCardView: View {
    let card: BrushingStampCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("スタンプ \(card.stamps.count)こ")
                        .font(.pixel(32, relativeTo: .largeTitle))
                        .foregroundStyle(PixelStyle.pink)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 12) {
                        ForEach(card.stamps.reversed()) { stamp in
                            VStack(spacing: 2) {
                                MaskAvatar(mask: stamp.mask, size: 52)
                                HStack(spacing: 1) {
                                    ForEach(0..<stamp.stars, id: \.self) { _ in
                                        PixelSprite(name: "pixel-star", width: 12)
                                    }
                                }
                                Text(stamp.date, format: .dateTime.month().day())
                                    .font(.pixel(11, relativeTo: .caption2))
                            }
                            .padding(6)
                            .pixelPanel(.white, shadow: false)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if card.stamps.isEmpty {
                        Text("はみがきを すると スタンプが たまるよ")
                            .font(.pixel(16))
                    }
                }
                .foregroundStyle(PixelStyle.ink)
                .padding(20)
            }
            .background(PixelStyle.paper)
            .navigationTitle("がんばりカード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("とじる") { dismiss() }
                }
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer = layer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let previewLayer { layer.addSublayer(previewLayer) }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer?.frame = bounds
            CATransaction.commit()
        }
    }
}
