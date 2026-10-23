import AVFoundation
import SwiftUI
import UIKit

enum FaceEffect: String, CaseIterable, Identifiable {
    case none, bunny, panda

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "なし"
        case .bunny: "うさぎ"
        case .panda: "パンダ"
        }
    }
}

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
    @State private var camera = BrushingCameraModel()
    @State private var effect = FaceEffect.bunny
    @State private var phase = Phase.ready
    @State private var session = BrushingSession()
    @State private var idleOwner = UUID()

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
        .navigationTitle("はみがきコーチ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await camera.start() }
        .onDisappear {
            camera.stop()
            AttendanceQRIdleTimer.shared.setActive(false, owner: idleOwner)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await camera.start() }
            } else {
                camera.stop()
                if phase == .brushing { phase = .ready }
            }
        }
        .onChange(of: phase) { _, newPhase in
            AttendanceQRIdleTimer.shared.setActive(newPhase == .brushing, owner: idleOwner)
        }
        .task(id: phase) {
            guard phase == .brushing else { return }
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled, phase == .brushing {
                try? await Task.sleep(for: .milliseconds(100))
                let now = clock.now
                let delta = (now - last) / .seconds(1)
                last = now
                session.advance(by: delta, brushing: camera.isBrushing())
                if session.isFinished { phase = .finished }
            }
        }
        .sensoryFeedback(.impact, trigger: session.currentZone)
        .sensoryFeedback(.success, trigger: phase) { _, newPhase in newPhase == .finished }
    }

    private var cameraView: some View {
        ZStack {
            CameraPreview(layer: camera.previewLayer)
                .ignoresSafeArea()
            GeometryReader { geometry in
                if let face = camera.face {
                    FaceEffectOverlay(effect: effect,
                                      face: ScreenFace(face, imageSize: camera.imageSize, viewSize: geometry.size))
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                switch phase {
                case .ready: readyPanel
                case .brushing: brushingPanel
                case .finished: resultPanel
                }
                Spacer()
                if phase != .brushing { controls }
            }
            .padding(16)
        }
    }

    private var readyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("2ふんかん はみがきしよう！")
                .font(.title2.bold())
            Text("がめんの「つぎは ここ！」に あわせて、ばしょを かえながら みがいてね。")
                .font(.subheadline)
            Text("映像は端末内で処理し、保存・送信しません。採点は口もとの動きの量による目安で、磨き残しは判定できません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var brushingPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("つぎは ここ！").font(.headline)
                Spacer()
                Text(Duration.seconds(session.remaining.rounded(.up)),
                     format: .time(pattern: .minuteSecond))
                    .font(.headline.monospacedDigit())
            }
            Text(session.currentZone?.title ?? "")
                .font(.largeTitle.bold())
            ZoneMap(current: session.currentZone) { zone in
                zone.rawValue < (session.currentZone?.rawValue ?? BrushingZone.allCases.count) ? "checkmark" : nil
            }
            ProgressView(value: session.zoneProgress)
            Group {
                if camera.face == nil {
                    Label("おかおを うつしてね", systemImage: "face.dashed")
                } else if camera.isBrushing() {
                    Label("ゴシゴシ！ いいね", systemImage: "sparkles")
                        .foregroundStyle(.green)
                } else {
                    Label("ブラシを うごかそう", systemImage: "hand.wave")
                }
            }
            .font(.headline)
            Button("やめる", role: .cancel) { phase = .ready }
                .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var resultPanel: some View {
        let stars = BrushingSession.stars(for: session.overallRatio)
        return VStack(spacing: 10) {
            Text(String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars))
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
                .accessibilityLabel("ほし \(stars)こ")
            Text(resultMessage(stars: stars))
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            ZoneMap(current: nil) { zone in
                BrushingSession.stars(for: session.ratio(for: zone)) >= 2 ? "star.fill" : "star"
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("エフェクト", selection: $effect) {
                ForEach(FaceEffect.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                session = BrushingSession()
                phase = .brushing
            } label: {
                Text(phase == .finished ? "もういちど" : "はじめる")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(camera.status != .running)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
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
        case 3: "すごい！ ピカピカだね"
        case 2: "よくできました！"
        case 1: "もうすこし ゴシゴシしよう"
        default: "つぎは いっしょに がんばろう"
        }
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
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(zone == current ? Color.accentColor : Color.secondary.opacity(0.2),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(zone == current ? Color.white : Color.primary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A face mapped from normalized image coordinates into the aspect-filled preview.
private struct ScreenFace {
    let width: CGFloat
    let eyeCenter: CGPoint
    let eyeDistance: CGFloat
    let leftEye: CGPoint
    let rightEye: CGPoint
    let nose: CGPoint
    let roll: Angle

    init(_ face: BrushingFrame.Face, imageSize: CGSize, viewSize: CGSize) {
        let scale = max(viewSize.width / max(imageSize.width, 1), viewSize.height / max(imageSize.height, 1))
        let origin = CGPoint(x: (viewSize.width - imageSize.width * scale) / 2,
                             y: (viewSize.height - imageSize.height * scale) / 2)
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + point.x * imageSize.width * scale, y: origin.y + point.y * imageSize.height * scale)
        }
        width = face.bounds.width * imageSize.width * scale
        leftEye = map(face.leftEye)
        rightEye = map(face.rightEye)
        nose = map(face.nose)
        eyeCenter = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
        eyeDistance = hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)
        roll = .radians(atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x))
    }

    /// A point offset from the eye center in the face's own (tilted) axes.
    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        let c = cos(roll.radians), s = sin(roll.radians)
        return CGPoint(x: eyeCenter.x + x * c - y * s, y: eyeCenter.y + x * s + y * c)
    }
}

private struct FaceEffectOverlay: View {
    let effect: FaceEffect
    let face: ScreenFace

    var body: some View {
        let w = face.width
        switch effect {
        case .none:
            EmptyView()
        case .bunny:
            ForEach([-1.0, 1.0], id: \.self) { side in
                BunnyEar()
                    .frame(width: w * 0.26, height: w * 0.8)
                    .rotationEffect(face.roll + .degrees(side * 12))
                    .position(face.point(x: side * w * 0.2, y: -w * 0.95))
            }
            Ellipse()
                .fill(Color.pink)
                .frame(width: w * 0.12, height: w * 0.08)
                .rotationEffect(face.roll)
                .position(face.nose)
        case .panda:
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle()
                    .fill(Color.black)
                    .frame(width: w * 0.34, height: w * 0.34)
                    .position(face.point(x: side * w * 0.4, y: -w * 0.62))
            }
            ForEach([face.leftEye, face.rightEye], id: \.x) { eye in
                let side: Double = eye.x < face.eyeCenter.x ? -1 : 1
                Ellipse()
                    .fill(Color.black.opacity(0.75))
                    .frame(width: face.eyeDistance * 0.6, height: face.eyeDistance * 0.8)
                    .rotationEffect(face.roll + .degrees(side * -30))
                    .position(eye)
            }
            Ellipse()
                .fill(Color.black)
                .frame(width: w * 0.14, height: w * 0.09)
                .rotationEffect(face.roll)
                .position(face.nose)
        }
    }
}

private struct BunnyEar: View {
    var body: some View {
        ZStack {
            Capsule().fill(Color.white)
            Capsule().stroke(Color.gray.opacity(0.4), lineWidth: 2)
            Capsule().fill(Color.pink.opacity(0.7)).scaleEffect(x: 0.5, y: 0.8)
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
