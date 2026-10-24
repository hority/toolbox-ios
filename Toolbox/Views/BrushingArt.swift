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

/// Where each dot-art mask sits, in units of face width.
private struct MaskArt {
    var topWidth: CGFloat
    /// Distance above the eye line where the headband's bottom edge sits.
    var topLift: CGFloat
    var noseWidth: CGFloat?
    var noseDrop: CGFloat = 0

    static func of(_ mask: BrushingMask) -> MaskArt {
        switch mask {
        case .bunny: MaskArt(topWidth: 0.95, topLift: 0.3, noseWidth: 0.58, noseDrop: 0.04)
        case .panda: MaskArt(topWidth: 1.3, topLift: 0.28, noseWidth: 0.27)
        case .cat: MaskArt(topWidth: 1.25, topLift: 0.28, noseWidth: 0.58, noseDrop: 0.03)
        case .penguin: MaskArt(topWidth: 1.4, topLift: 0.3, noseWidth: 0.27, noseDrop: 0.03)
        case .bear: MaskArt(topWidth: 1.3, topLift: 0.28, noseWidth: 0.42, noseDrop: 0.06)
        case .unicorn: MaskArt(topWidth: 1.3, topLift: 0.3, noseWidth: nil)
        }
    }
}

/// Dot-art masks placed on a face. `excitement` (0–1) makes the headband bounce
/// and adds blush while brushing; `hop` (0–1) jumps when a zone is cleaned.
struct MaskView: View {
    let mask: BrushingMask
    let face: ScreenFace
    let time: Double
    var excitement: Double = 0
    var hop: Double = 0

    var body: some View {
        let w = face.width
        let art = MaskArt.of(mask)
        // Whole-step wobble reads as sprite animation rather than smooth motion.
        let wiggle = (sin(time * 14) * 6 * excitement).rounded() + (sin(time * 2) * 2).rounded()
        let squash = 1 + (sin(time * 28) > 0 ? 0.06 : 0) * excitement
        ZStack {
            if mask == .panda {
                ForEach([face.leftEye, face.rightEye], id: \.x) { eye in
                    PixelFrame(step: face.eyeDistance * 0.12)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: face.eyeDistance * 0.6, height: face.eyeDistance * 0.72)
                        .rotationEffect(face.roll)
                        .position(eye)
                }
            }
            ForEach([-1.0, 1.0], id: \.self) { side in
                HStack(spacing: w * 0.03) {
                    ForEach(0..<2, id: \.self) { _ in
                        Rectangle().frame(width: w * 0.06, height: w * 0.04)
                    }
                }
                .foregroundStyle(PixelStyle.pink.opacity(0.35 + 0.45 * excitement))
                .rotationEffect(face.roll)
                .position(face.point(x: side * w * 0.3, y: w * 0.28))
            }
            if let noseWidth = art.noseWidth {
                PixelSprite(name: "pixel-mask-\(mask.rawValue)-nose", width: w * noseWidth)
                    .rotationEffect(face.roll)
                    .position(face.offset(face.nose, x: 0, y: w * art.noseDrop))
            }
            let top = PixelSprite(name: "pixel-mask-\(mask.rawValue)-top", width: w * art.topWidth)
            let anchor = face.point(x: 0, y: -w * art.topLift)
            top
                .scaleEffect(x: 1, y: squash, anchor: .bottom)
                .rotationEffect(face.roll + .degrees(wiggle), anchor: .bottom)
                // Place the unrotated bottom edge on the anchor so rotation pivots there.
                .position(x: anchor.x, y: anchor.y - top.height / 2)
        }
        .offset(y: -(hop * 3).rounded() * w * 0.04)
    }
}

/// The mask's animal face as a dot-art icon, for pickers and the stamp card.
struct MaskAvatar: View {
    let mask: BrushingMask
    var size: CGFloat = 64

    var body: some View {
        Image("pixel-icon-\(mask.rawValue)")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(mask.title)
    }
}

// MARK: - Germs

enum GermLayout {
    static let sprites = ["pixel-germ-green", "pixel-germ-purple", "pixel-germ-orange"]

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
        let spread: [(x: CGFloat, y: CGFloat)] = [(-0.15, 0.04), (0, -0.08), (0.15, 0.04)]
        return spread.map { face.offset(center, x: w * $0.x, y: w * $0.y) }
    }

    static func size(for face: ScreenFace) -> CGFloat { face.width * 0.2 }
}

/// A dot-art germ that bobs in two-frame steps and shivers while being brushed.
struct GermView: View {
    let index: Int
    let time: Double
    let shaking: Bool

    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width
            let unit = s / 16
            let frame = Int(time * 4 + Double(index)) % 2
            PixelSprite(name: GermLayout.sprites[index], width: s)
                .scaleEffect(x: frame == 0 ? 1 : 1.0625, y: frame == 0 ? 1 : 0.9375, anchor: .bottom)
                .offset(x: shaking ? (Int(time * 20) % 2 == 0 ? -unit : unit) : 0,
                        y: frame == 0 ? 0 : -unit)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sparkles

/// Short-lived dot-art sparkles, drawn by a Canvas inside a TimelineView.
@MainActor
final class SparkleField {
    private struct Particle {
        var origin: CGPoint
        var velocity: CGVector
        var birth: Date
        var life: TimeInterval
        var size: CGFloat
        var color: Color
    }

    private static let colors: [Color] = [PixelStyle.yellow, .white, PixelStyle.pink, PixelStyle.sky, PixelStyle.mint]
    private static let limit = 400
    private static let grid: CGFloat = 4
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
                color: Self.colors.randomElement() ?? .yellow
            ))
        }
    }

    /// Plus-shaped sparkles snapped to a 4pt grid that shrink in steps and blink out.
    func draw(_ context: inout GraphicsContext, now: Date) {
        let g = Self.grid
        for particle in particles {
            let age = now.timeIntervalSince(particle.birth)
            guard age >= 0, age < particle.life else { continue }
            let progress = age / particle.life
            if progress > 0.7, Int(age * 16) % 2 == 0 { continue }
            let arm = max(1, ((particle.size / 2) * (1 - progress * 0.6) / g).rounded()) * g
            let x = ((particle.origin.x + particle.velocity.dx * age) / g).rounded() * g
            let y = ((particle.origin.y + particle.velocity.dy * age + 80 * age * age) / g).rounded() * g
            var plus = Path()
            plus.addRect(CGRect(x: x - g / 2, y: y - arm, width: g, height: arm * 2))
            plus.addRect(CGRect(x: x - arm, y: y - g / 2, width: arm * 2, height: g))
            context.fill(plus, with: .color(particle.color))
        }
    }
}

/// Big "ピカピカ！" pop when a zone's germs are all gone. `progress` runs 0→1.
struct PikapikaBanner: View {
    let progress: Double

    var body: some View {
        Text("ピカピカ！")
            .font(.pixel(56, relativeTo: .largeTitle))
            .foregroundStyle(PixelStyle.yellow)
            .shadow(color: PixelStyle.ink, radius: 0, x: 4, y: 4)
            .shadow(color: PixelStyle.ink, radius: 0, x: -2, y: -2)
            .scaleEffect(progress < 0.1 ? 0.6 : progress < 0.2 ? 1.15 : 1)
            .opacity(progress > 0.75 && Int(progress * 40) % 2 == 0 ? 0 : 1)
            .accessibilityHidden(true)
    }
}
