import SwiftUI
import UIKit

/// A face in view coordinates, either tracked from the camera or drawn for an avatar.
struct ScreenFace {
    let width: CGFloat
    let eyeCenter: CGPoint
    let eyeDistance: CGFloat
    let leftEye: CGPoint
    let rightEye: CGPoint
    let nose: CGPoint
    let mouth: CGPoint
    let roll: Angle

    /// Maps normalized image coordinates into the aspect-filled preview.
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
        mouth = map(face.mouth)
        eyeCenter = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
        eyeDistance = hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)
        roll = .radians(atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x))
    }

    /// An upright face whose eye center is `center`.
    init(avatarCenter center: CGPoint, width: CGFloat) {
        self.width = width
        eyeCenter = center
        eyeDistance = width * 0.38
        leftEye = CGPoint(x: center.x - width * 0.19, y: center.y)
        rightEye = CGPoint(x: center.x + width * 0.19, y: center.y)
        nose = CGPoint(x: center.x, y: center.y + width * 0.2)
        mouth = CGPoint(x: center.x, y: center.y + width * 0.36)
        roll = .zero
    }

    /// A point offset from the eye center in the face's own (tilted) axes.
    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        offset(eyeCenter, x: x, y: y)
    }

    func offset(_ origin: CGPoint, x: CGFloat, y: CGFloat) -> CGPoint {
        let c = cos(roll.radians), s = sin(roll.radians)
        return CGPoint(x: origin.x + x * c - y * s, y: origin.y + x * s + y * c)
    }
}

// MARK: - Masks

/// Where each generated mask image sits, in units of face width.
private struct MaskArt {
    var topWidth: CGFloat
    /// Distance above the eye line where the headband's bottom edge sits.
    var topLift: CGFloat
    var noseWidth: CGFloat?
    var noseDrop: CGFloat = 0

    static func of(_ mask: BrushingMask) -> MaskArt {
        switch mask {
        case .bunny: MaskArt(topWidth: 0.95, topLift: 0.3, noseWidth: 0.62, noseDrop: 0.04)
        case .panda: MaskArt(topWidth: 1.3, topLift: 0.28, noseWidth: 0.2)
        case .cat: MaskArt(topWidth: 1.25, topLift: 0.28, noseWidth: 0.62, noseDrop: 0.03)
        case .penguin: MaskArt(topWidth: 1.3, topLift: 0.3, noseWidth: 0.2, noseDrop: 0.03)
        case .bear: MaskArt(topWidth: 1.3, topLift: 0.28, noseWidth: 0.34, noseDrop: 0.06)
        case .unicorn: MaskArt(topWidth: 1.15, topLift: 0.3, noseWidth: nil)
        }
    }
}

/// Generated mask images placed on a face. `excitement` (0–1) makes the headband
/// bounce and adds blush while brushing; `hop` (0–1) jumps when a zone is cleaned.
struct MaskView: View {
    let mask: BrushingMask
    let face: ScreenFace
    let time: Double
    var excitement: Double = 0
    var hop: Double = 0

    var body: some View {
        let w = face.width
        let art = MaskArt.of(mask)
        let wiggle = sin(time * 14) * 6 * excitement + sin(time * 2) * 2
        let squash = 1 + sin(time * 28) * 0.05 * excitement
        ZStack {
            if mask == .panda {
                ForEach([face.leftEye, face.rightEye], id: \.x) { eye in
                    let side: Double = eye.x < face.eyeCenter.x ? -1 : 1
                    Ellipse()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: face.eyeDistance * 0.6, height: face.eyeDistance * 0.78)
                        .blur(radius: w * 0.01)
                        .rotationEffect(face.roll + .degrees(side * -30))
                        .position(eye)
                }
            }
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse()
                    .fill(Color.pink.opacity(0.25 + 0.35 * excitement))
                    .frame(width: w * 0.2, height: w * 0.12)
                    .blur(radius: w * 0.02)
                    .position(face.point(x: side * w * 0.3, y: w * 0.28))
            }
            if let noseWidth = art.noseWidth {
                MaskImage(name: "mask-\(mask.rawValue)-nose", width: w * noseWidth)
                    .rotationEffect(face.roll)
                    .position(face.offset(face.nose, x: 0, y: w * art.noseDrop))
            }
            let top = MaskImage(name: "mask-\(mask.rawValue)-top", width: w * art.topWidth)
            let anchor = face.point(x: 0, y: -w * art.topLift)
            top
                .scaleEffect(x: 1, y: squash, anchor: .bottom)
                .rotationEffect(face.roll + .degrees(wiggle), anchor: .bottom)
                // Place the unrotated bottom edge on the anchor so rotation pivots there.
                .position(x: anchor.x, y: anchor.y - top.height / 2)
        }
        .offset(y: -hop * w * 0.12)
        .scaleEffect(1 + hop * 0.06)
    }
}

private struct MaskImage: View {
    let name: String
    let width: CGFloat

    var height: CGFloat {
        guard let size = UIImage(named: name)?.size, size.width > 0 else { return width }
        return width * size.height / size.width
    }

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// A mask on a simple drawn face, for pickers and the stamp card.
struct MaskAvatar: View {
    let mask: BrushingMask
    var size: CGFloat = 64

    var body: some View {
        let face = ScreenFace(avatarCenter: CGPoint(x: size / 2, y: size * 0.66), width: size * 0.5)
        ZStack {
            Circle()
                .fill(Color(red: 1, green: 0.89, blue: 0.78))
                .frame(width: size * 0.56, height: size * 0.56)
                .position(x: size / 2, y: size * 0.7)
            ForEach([face.leftEye, face.rightEye], id: \.x) { eye in
                Circle().fill(Color.black).frame(width: size * 0.06, height: size * 0.06).position(eye)
            }
            MaskView(mask: mask, face: face, time: 0)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(mask.title)
    }
}

// MARK: - Germs

enum GermLayout {
    static let colors: [Color] = [.green, .purple, .orange]

    /// Germs sit on the side being brushed, as seen in the mirrored preview.
    static func positions(for zone: BrushingZone, face: ScreenFace) -> [CGPoint] {
        let w = face.width
        let side: CGFloat = switch zone {
        case .upperRight, .lowerRight: 1
        case .upperLeft, .lowerLeft: -1
        case .upperFront, .lowerFront: 0
        }
        let upper = [BrushingZone.upperRight, .upperFront, .upperLeft].contains(zone)
        let center = face.offset(face.mouth, x: side * w * 0.42, y: upper ? -w * 0.08 : w * 0.24)
        let spread: [(x: CGFloat, y: CGFloat)] = [(-0.14, 0.04), (0, -0.07), (0.14, 0.04)]
        return spread.map { face.offset(center, x: w * $0.x, y: w * $0.y) }
    }

    static func size(for face: ScreenFace) -> CGFloat { face.width * 0.18 }
}

struct GermView: View {
    let color: Color
    let time: Double
    let seed: Double
    let shaking: Bool

    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width
            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    let angle = Double(index) / 8 * 2 * .pi + time * 0.6
                    Circle()
                        .fill(color.opacity(0.85))
                        .frame(width: s * 0.26, height: s * 0.26)
                        .offset(x: cos(angle) * s * 0.42, y: sin(angle) * s * 0.42)
                }
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(0.65), color], center: .topLeading,
                                         startRadius: 0, endRadius: s * 0.7))
                    .frame(width: s * 0.8, height: s * 0.8)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Circle().fill(.white).frame(width: s * 0.22, height: s * 0.22)
                        .overlay(Circle().fill(.black).frame(width: s * 0.11, height: s * 0.11)
                            .offset(x: shaking ? sin(time * 30) * s * 0.03 : 0))
                        .offset(x: side * s * 0.15, y: -s * 0.06)
                    Capsule().fill(.black).frame(width: s * 0.2, height: s * 0.05)
                        .rotationEffect(.degrees(side * (shaking ? -30 : -18)))
                        .offset(x: side * s * 0.15, y: -s * 0.22)
                }
                Capsule().fill(.black.opacity(0.75))
                    .frame(width: s * (shaking ? 0.26 : 0.2), height: s * (shaking ? 0.12 : 0.05))
                    .offset(y: s * 0.17)
            }
            .frame(width: s, height: s)
        }
        .offset(x: shaking ? sin(time * 45 + seed) * 4 : 0, y: sin(time * 3 + seed) * 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Sparkles

/// Short-lived sparkle particles, drawn by a Canvas inside a TimelineView.
@MainActor
final class SparkleField {
    private struct Particle {
        var origin: CGPoint
        var velocity: CGVector
        var birth: Date
        var life: TimeInterval
        var size: CGFloat
        var color: Color
        var spin: Double
    }

    private static let colors: [Color] = [.yellow, .white, .pink, .cyan, .mint]
    private static let limit = 400
    private var particles: [Particle] = []

    func emit(at point: CGPoint, count: Int, speed: ClosedRange<CGFloat>, size: ClosedRange<CGFloat>, now: Date = .now) {
        particles.removeAll { now.timeIntervalSince($0.birth) > $0.life }
        for _ in 0..<count where particles.count < Self.limit {
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let velocity = CGFloat.random(in: speed)
            particles.append(Particle(
                origin: point,
                velocity: CGVector(dx: cos(angle) * velocity, dy: sin(angle) * velocity),
                birth: now,
                life: .random(in: 0.6...1.2),
                size: .random(in: size),
                color: Self.colors.randomElement() ?? .yellow,
                spin: .random(in: -4...4)
            ))
        }
    }

    func draw(_ context: inout GraphicsContext, now: Date) {
        for particle in particles {
            let age = now.timeIntervalSince(particle.birth)
            guard age >= 0, age < particle.life else { continue }
            let progress = age / particle.life
            let size = particle.size * (1 - progress * 0.5)
            var star = context
            star.opacity = 1 - progress
            star.translateBy(x: particle.origin.x + particle.velocity.dx * age,
                             y: particle.origin.y + particle.velocity.dy * age + 80 * age * age)
            star.rotate(by: .radians(particle.spin * age))
            star.fill(SparkleShape().path(in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size)),
                      with: .color(particle.color))
        }
    }
}

struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        return Path { path in
            for index in 0..<8 {
                let angle = Double(index) * .pi / 4 - .pi / 2
                let radius = index.isMultiple(of: 2) ? r : r * 0.28
                let point = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}

/// Big "ピカピカ！" pop when a zone's germs are all gone. `progress` runs 0→1.
struct PikapikaBanner: View {
    let progress: Double

    var body: some View {
        Text("ピカピカ！")
            .font(.system(size: 56, weight: .black, design: .rounded))
            .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            .shadow(color: .white, radius: 0, x: 2, y: 2)
            .shadow(color: .orange.opacity(0.6), radius: 10)
            .scaleEffect(0.5 + 0.6 * min(1, progress * 5) - 0.1 * max(0, progress - 0.2))
            .opacity(progress > 0.75 ? (1 - progress) * 4 : 1)
            .accessibilityHidden(true)
    }
}
