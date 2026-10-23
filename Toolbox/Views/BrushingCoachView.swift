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
    @State private var germPops = 0
    @State private var earnedStamp = false
    @State private var unlockedMasks: [BrushingMask] = []
    @State private var showingStampCard = false
    @State private var idleOwner = UUID()

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
        .fontDesign(.rounded)
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
            if !stampCard.isUnlocked(mask) { mask = .bunny }
            await camera.start()
        }
        .onDisappear {
            camera.stop()
            sound.deactivate()
            AttendanceQRIdleTimer.shared.setActive(false, owner: idleOwner)
        }
        .onChange(of: soundEnabled) { _, enabled in
            sound.isEnabled = enabled
            if enabled, phase == .brushing { sound.startMusic() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await camera.start() }
            } else {
                camera.stop()
                sound.deactivate()
                if phase == .brushing { phase = .ready }
            }
        }
        .onChange(of: phase) { _, newPhase in
            AttendanceQRIdleTimer.shared.setActive(newPhase == .brushing, owner: idleOwner)
            if newPhase == .brushing { sound.startMusic() } else { sound.stopMusic() }
        }
        .task(id: phase) {
            guard phase == .brushing else { return }
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled, phase == .brushing {
                try? await Task.sleep(for: .milliseconds(100))
                let now = clock.now
                tick(delta: (now - last) / .seconds(1))
                last = now
            }
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
                sparkles.emit(at: point, count: 28, speed: 60...200, size: 10...22)
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
        session = BrushingSession()
        celebrateDate = nil
        earnedStamp = false
        unlockedMasks = []
        phase = .brushing
    }

    private func finish() {
        let stars = BrushingSession.stars(for: session.overallRatio)
        if stars > 0 {
            unlockedMasks = stampCard.add(stars: stars, mask: mask)
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
                case .brushing: brushingPanel
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
            ZStack {
                if let face = screenFace {
                    if phase == .brushing, let zone = session.currentZone {
                        let positions = GermLayout.positions(for: zone, face: face)
                        let size = GermLayout.size(for: face)
                        let defeated = BrushingSession.germsPerZone - session.germsRemaining(in: zone)
                        ForEach(defeated..<BrushingSession.germsPerZone, id: \.self) { index in
                            GermView(color: GermLayout.colors[index], time: time, seed: Double(index) * 2,
                                     shaking: brushing)
                                .frame(width: size, height: size)
                                .position(positions[index])
                        }
                    }
                    MaskView(mask: mask, face: face, time: time, excitement: brushing ? 1 : 0,
                             hop: sinceClear < 0.6 ? sin(sinceClear / 0.6 * .pi) : 0)
                }
                Canvas { context, _ in sparkles.draw(&context, now: now) }
                if sinceClear < 1.4 {
                    PikapikaBanner(progress: sinceClear / 1.4)
                        .position(x: overlaySize.width / 2, y: overlaySize.height * 0.45)
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { overlaySize = $0 }
    }

    private var readyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ばいきんを やっつけよう！", systemImage: "sparkles")
                .font(.title2.weight(.heavy))
                .foregroundStyle(.pink)
            Text("ゴシゴシ みがくと、ばいきんが にげていくよ。2ふんかん がんばろう！")
                .font(.subheadline.weight(.semibold))
            Text("映像は端末内で処理し、保存・送信しません。採点は口もとの動きの量による目安で、磨き残しは判定できません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brushingCard()
    }

    private var brushingPanel: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("つぎは ここ！")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(session.currentZone?.title ?? "")
                        .font(.largeTitle.weight(.heavy))
                        .foregroundStyle(.pink)
                        .contentTransition(.numericText())
                        .animation(.spring, value: session.currentZone)
                }
                Spacer()
                TimerRing(progress: session.zoneProgress, remaining: session.remaining)
            }
            ZoneMap(current: session.currentZone) { zone in
                zone.rawValue < (session.currentZone?.rawValue ?? BrushingZone.allCases.count) ? "checkmark" : nil
            }
            HStack {
                Text("ばいきん")
                ForEach(0..<BrushingSession.germsPerZone, id: \.self) { index in
                    let remaining = session.currentZone.map(session.germsRemaining(in:)) ?? 0
                    Image(systemName: index < BrushingSession.germsPerZone - remaining ? "sparkle" : "ladybug.fill")
                        .foregroundStyle(index < BrushingSession.germsPerZone - remaining ? Color.yellow : GermLayout.colors[index])
                }
                Spacer()
                Button("やめる") { phase = .ready }
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.bordered)
            }
            .font(.headline)
        }
        .brushingCard()
    }

    private var statusBubble: some View {
        Group {
            if camera.face == nil {
                Label("おかおを うつしてね", systemImage: "face.dashed")
            } else if camera.isBrushing() {
                Label("ゴシゴシ！ いいね！", systemImage: "sparkles")
                    .foregroundStyle(.white)
            } else {
                Label("ブラシを うごかそう", systemImage: "hand.wave.fill")
            }
        }
        .font(.title3.weight(.heavy))
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(camera.isBrushing() ? AnyShapeStyle(Color.pink.gradient) : AnyShapeStyle(.regularMaterial),
                    in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .animation(.spring(duration: 0.25), value: camera.isBrushing())
    }

    private var resultPanel: some View {
        let stars = BrushingSession.stars(for: session.overallRatio)
        return VStack(spacing: 10) {
            StarRow(stars: stars)
            Text(resultMessage(stars: stars))
                .font(.title2.weight(.heavy))
                .foregroundStyle(.pink)
                .multilineTextAlignment(.center)
            if earnedStamp {
                Label("がんばりカードに スタンプ ゲット！", systemImage: "seal.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
            }
            ForEach(unlockedMasks) { newMask in
                HStack {
                    MaskAvatar(mask: newMask, size: 48)
                    Text("NEW！ \(newMask.title)の おめんが つかえるよ")
                        .font(.subheadline.weight(.heavy))
                }
            }
            ZoneMap(current: nil) { zone in
                BrushingSession.stars(for: session.ratio(for: zone)) >= 2 ? "star.fill" : "star"
            }
        }
        .frame(maxWidth: .infinity)
        .brushingCard()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(BrushingMask.allCases) { option in
                    MaskButton(mask: option, selected: option == mask, unlocked: stampCard.isUnlocked(option),
                               remaining: option.requiredStamps - stampCard.stamps.count) {
                        mask = option
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    showingStampCard = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "seal.fill")
                        Text("\(stampCard.stamps.count)").font(.caption.weight(.heavy))
                    }
                    .frame(width: 56, height: 56)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityLabel("がんばりカード スタンプ \(stampCard.stamps.count)こ")

                Button(action: start) {
                    Text(phase == .finished ? "もういちど！" : "はじめる！")
                        .font(.title2.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(.white)
                        .background(LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing),
                                    in: Capsule())
                        .shadow(color: .pink.opacity(0.4), radius: 8, y: 4)
                }
                .disabled(camera.status != .running)
                .opacity(camera.status == .running ? 1 : 0.5)
            }
        }
        .brushingCard()
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

private extension View {
    func brushingCard() -> some View {
        padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.6), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

private struct MaskButton: View {
    let mask: BrushingMask
    let selected: Bool
    let unlocked: Bool
    let remaining: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                MaskAvatar(mask: mask, size: 56)
                    .saturation(unlocked ? 1 : 0)
                    .opacity(unlocked ? 1 : 0.5)
                    .overlay {
                        if !unlocked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    }
                    .background(Circle().fill(selected ? Color.pink.opacity(0.2) : .clear))
                    .overlay(Circle().stroke(selected ? Color.pink : .clear, lineWidth: 3))
                Text(unlocked ? mask.title : "あと\(remaining)かい")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selected ? .pink : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(unlocked ? "\(mask.title)の おめん" : "\(mask.title)の おめん、あと\(remaining)かいで つかえる")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TimerRing: View {
    let progress: Double
    let remaining: TimeInterval

    var body: some View {
        ZStack {
            Circle().stroke(Color.pink.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.pink.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(Duration.seconds(remaining.rounded(.up)), format: .time(pattern: .minuteSecond))
                .font(.subheadline.weight(.heavy).monospacedDigit())
        }
        .frame(width: 64, height: 64)
        .accessibilityLabel("のこり \(Int(remaining.rounded(.up)))びょう")
    }
}

private struct StarRow: View {
    let stars: Int
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < stars ? "star.fill" : "star")
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(index < stars ? Color.yellow.gradient : Color.gray.gradient)
                    .shadow(color: .orange.opacity(index < stars ? 0.5 : 0), radius: 6)
                    .scaleEffect(revealed ? 1 : 0.1)
                    .rotationEffect(.degrees(revealed ? 0 : -90))
                    .animation(.spring(duration: 0.5, bounce: 0.6).delay(Double(index) * 0.3), value: revealed)
            }
        }
        .onAppear { revealed = true }
        .accessibilityElement()
        .accessibilityLabel("ほし \(stars)こ")
    }
}

/// Upper row then lower row, as the child sees themselves in the mirrored preview.
private struct ZoneMap: View {
    let current: BrushingZone?
    let symbol: (BrushingZone) -> String?

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
                            if let name = symbol(zone) { Image(systemName: name) }
                            Text(zone.shortTitle)
                        }
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(zone == current ? AnyShapeStyle(Color.pink.gradient) : AnyShapeStyle(Color.white.opacity(0.5)),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(zone == current ? Color.white : Color.primary)
                        .scaleEffect(zone == current ? 1.06 : 1)
                        .animation(.spring(duration: 0.3, bounce: 0.5), value: current)
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

    private var nextMask: BrushingMask? {
        BrushingMask.allCases.first { !card.isUnlocked($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("スタンプ \(card.stamps.count)こ")
                        .font(.largeTitle.weight(.heavy))
                        .foregroundStyle(.orange)
                    if let nextMask {
                        HStack {
                            MaskAvatar(mask: nextMask, size: 44).saturation(0)
                            Text("あと \(nextMask.requiredStamps - card.stamps.count)こで \(nextMask.title)の おめん！")
                                .font(.headline)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                        ForEach(card.stamps.reversed()) { stamp in
                            VStack(spacing: 2) {
                                MaskAvatar(mask: stamp.mask, size: 56)
                                    .background(Circle().fill(Color.orange.opacity(0.15)))
                                Text(String(repeating: "★", count: stamp.stars))
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(.yellow)
                                Text(stamp.date, format: .dateTime.month().day())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if card.stamps.isEmpty {
                        Text("はみがきを すると スタンプが たまるよ")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .fontDesign(.rounded)
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
