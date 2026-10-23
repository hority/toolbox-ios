import AVFoundation
import Vision

/// One analyzed front-camera frame. Points are normalized to the upright,
/// mirrored image shown in the preview, with the origin at the top left.
struct BrushingFrame: Sendable {
    struct Face: Sendable {
        var bounds: CGRect
        var leftEye: CGPoint
        var rightEye: CGPoint
        var nose: CGPoint
        var mouth: CGPoint

        func blended(toward next: Face, by amount: CGFloat) -> Face {
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * amount }
            func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: mix(a.x, b.x), y: mix(a.y, b.y)) }
            return Face(
                bounds: CGRect(x: mix(bounds.minX, next.bounds.minX), y: mix(bounds.minY, next.bounds.minY),
                               width: mix(bounds.width, next.bounds.width), height: mix(bounds.height, next.bounds.height)),
                leftEye: mix(leftEye, next.leftEye),
                rightEye: mix(rightEye, next.rightEye),
                nose: mix(nose, next.nose),
                mouth: mix(mouth, next.mouth)
            )
        }
    }

    var imageSize: CGSize
    var face: Face?
    /// Mean luma change (0–255) around the mouth since the previous frame.
    var motion: Double
}

/// Frames are analyzed on-device and dropped immediately; nothing is recorded.
/// All mutable state is confined to `queue`.
final class BrushingCamera: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let device: AVCaptureDevice
    private let queue = DispatchQueue(label: "com.hority.toolbox.brushing-camera")
    private let output = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var onFrame: (@Sendable (BrushingFrame) -> Void)?
    private var previousSamples: [UInt8] = []
    private var lastFace: (face: BrushingFrame.Face, time: Double)?

    /// A hand and brush often hide the mouth; keep the last face briefly instead of flickering.
    private static let faceHoldSeconds = 1.0
    private static let sampleColumns = 20
    private static let sampleRows = 16

    init(device: AVCaptureDevice) {
        self.device = device
        super.init()
    }

    func start(onFrame: @escaping @Sendable (BrushingFrame) -> Void,
               completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            if !isConfigured {
                guard configure() else { return completion(false) }
                isConfigured = true
            }
            self.onFrame = onFrame
            session.startRunning()
            completion(session.isRunning)
        }
    }

    func stop() {
        queue.async { [self] in
            session.stopRunning()
            onFrame = nil
            previousSamples = []
            lastFace = nil
        }
    }

    func setRotationAngle(_ angle: CGFloat) {
        queue.async { [self] in
            guard let connection = output.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
            previousSamples = []
            lastFace = nil
        }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return false }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        // Match the preview layer, which mirrors the front camera.
        if let connection = output.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        return true
    }
}

extension BrushingCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let onFrame, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))

        let request = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
        let largest = request.results?.max { $0.boundingBox.width < $1.boundingBox.width }
        if let detected = largest.flatMap(Self.face(from:)) {
            lastFace = (detected, time)
        } else if let held = lastFace, time - held.time > Self.faceHoldSeconds {
            lastFace = nil
        }

        var motion = 0.0
        if let face = lastFace?.face {
            let samples = Self.lumaSamples(pixelBuffer, in: Self.mouthRegion(for: face))
            if samples.count == previousSamples.count, !samples.isEmpty {
                let total = zip(samples, previousSamples).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
                motion = Double(total) / Double(samples.count)
            }
            previousSamples = samples
        } else {
            previousSamples = []
        }
        onFrame(BrushingFrame(imageSize: size, face: lastFace?.face, motion: motion))
    }

    private static func face(from observation: VNFaceObservation) -> BrushingFrame.Face? {
        let box = observation.boundingBox
        // Vision uses a bottom-left origin; convert to top-left.
        func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let points = region?.normalizedPoints, !points.isEmpty else { return nil }
            let count = CGFloat(points.count)
            let x = points.reduce(0) { $0 + $1.x } / count
            let y = points.reduce(0) { $0 + $1.y } / count
            return CGPoint(x: box.minX + x * box.width, y: 1 - (box.minY + y * box.height))
        }
        guard let landmarks = observation.landmarks,
              let eyeA = center(landmarks.leftPupil) ?? center(landmarks.leftEye),
              let eyeB = center(landmarks.rightPupil) ?? center(landmarks.rightEye),
              let nose = center(landmarks.nose),
              let mouth = center(landmarks.outerLips) else { return nil }
        return BrushingFrame.Face(
            bounds: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
            leftEye: eyeA.x <= eyeB.x ? eyeA : eyeB,
            rightEye: eyeA.x <= eyeB.x ? eyeB : eyeA,
            nose: nose,
            mouth: mouth
        )
    }

    /// The mouth and the area just below it, where the brush and hand move.
    private static func mouthRegion(for face: BrushingFrame.Face) -> CGRect {
        let width = face.bounds.width
        let height = face.bounds.height * 0.6
        let region = CGRect(x: face.mouth.x - width / 2, y: face.mouth.y - height * 0.4, width: width, height: height)
        return region.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func lumaSamples(_ buffer: CVPixelBuffer, in region: CGRect) -> [UInt8] {
        guard !region.isNull, !region.isEmpty else { return [] }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return [] }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)
        var samples: [UInt8] = []
        samples.reserveCapacity(sampleColumns * sampleRows)
        for row in 0..<sampleRows {
            let y = region.minY + region.height * (CGFloat(row) + 0.5) / CGFloat(sampleRows)
            let pixelY = min(max(Int(y * CGFloat(height)), 0), height - 1)
            for column in 0..<sampleColumns {
                let x = region.minX + region.width * (CGFloat(column) + 0.5) / CGFloat(sampleColumns)
                let pixelX = min(max(Int(x * CGFloat(width)), 0), width - 1)
                samples.append(luma[pixelY * rowBytes + pixelX])
            }
        }
        return samples
    }
}
