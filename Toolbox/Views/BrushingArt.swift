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
    enum Head {
        /// A pair of ears from one sprite (drawn as the right ear, mirrored for the left) on the crown, `spread` from the center.
        case ears(width: CGFloat, spread: CGFloat = 0.32)
        /// One piece on the middle of the crown; `sink` lowers it toward the forehead.
        case center(width: CGFloat, sink: CGFloat = 0)
        /// A piece that wraps the head (mane, wool); its bottom edge sits `lift` above the eyes.
        case wrap(width: CGFloat, lift: CGFloat)
    }

    /// From the eye line to where ears meet the head, tuned on a child's face on device.
    static let crown: CGFloat = 0.5
    /// Vision's nose landmarks center below the tip on a child's small nose; raise pieces by this.
    static let noseLift: CGFloat = 0.12

    var head: Head?
    var noseWidth: CGFloat?
    var noseDrop: CGFloat = 0
    /// Width of an eye piece (such as glasses) in units of the distance between the eyes.
    var eyesWidth: CGFloat?

    static func of(_ mask: BrushingMask) -> MaskArt {
        switch mask {
        case .bunny: MaskArt(head: .ears(width: 0.22, spread: 0.2), noseWidth: 0.58, noseDrop: 0.04)
        case .panda: MaskArt(head: .ears(width: 0.3, spread: 0.36), noseWidth: 0.27)
        case .cat: MaskArt(head: .ears(width: 0.3), noseWidth: 0.58, noseDrop: 0.03)
        case .penguin: MaskArt(head: .center(width: 0.4), noseWidth: 0.27, noseDrop: 0.03)
        case .bear: MaskArt(head: .ears(width: 0.3, spread: 0.36), noseWidth: 0.42, noseDrop: 0.06)
        case .unicorn: MaskArt(head: .center(width: 0.3))
        case .wolf: MaskArt(head: .ears(width: 0.28), noseWidth: 0.4, noseDrop: 0.06)
        case .pig: MaskArt(head: .ears(width: 0.3, spread: 0.34), noseWidth: 0.4, noseDrop: 0.06)
        case .cow: MaskArt(head: .ears(width: 0.3, spread: 0.36), noseWidth: 0.55, noseDrop: 0.1)
        case .horse: MaskArt(head: .ears(width: 0.24, spread: 0.26), noseWidth: 0.5, noseDrop: 0.1)
        case .orca: MaskArt(head: .center(width: 0.3))
        case .rhino: MaskArt(head: .ears(width: 0.24), noseWidth: 0.45, noseDrop: 0.02)
        case .giraffe: MaskArt(head: .ears(width: 0.32, spread: 0.28), noseWidth: 0.45, noseDrop: 0.08)
        case .kangaroo: MaskArt(head: .ears(width: 0.24, spread: 0.26), noseWidth: 0.4, noseDrop: 0.05)
        case .zebra: MaskArt(head: .ears(width: 0.26), noseWidth: 0.5, noseDrop: 0.1)
        case .cheetah: MaskArt(head: .ears(width: 0.26, spread: 0.36), noseWidth: 0.55, noseDrop: 0.06)
        // The mane frames the face: its ends reach the jaw and its top just clears the head.
        case .lion: MaskArt(head: .wrap(width: 1.45, lift: -0.5), noseWidth: 0.55, noseDrop: 0.06)
        case .tiger: MaskArt(head: .ears(width: 0.28, spread: 0.36), noseWidth: 0.55, noseDrop: 0.06)
        case .frog: MaskArt(head: .ears(width: 0.3, spread: 0.22))
        case .goat: MaskArt(head: .ears(width: 0.3), noseWidth: 0.4, noseDrop: 0.08)
        case .sheep: MaskArt(head: .wrap(width: 1.25, lift: 0), noseWidth: 0.45, noseDrop: 0.06)
        case .spider: MaskArt(head: .center(width: 0.45))
        case .mouse: MaskArt(head: .ears(width: 0.38, spread: 0.38), noseWidth: 0.58, noseDrop: 0.04)
        case .chick: MaskArt(head: .center(width: 0.4), noseWidth: 0.3, noseDrop: 0.03)
        case .chicken: MaskArt(head: .center(width: 0.35), noseWidth: 0.3, noseDrop: 0.06)
        case .fox: MaskArt(head: .ears(width: 0.28), noseWidth: 0.45, noseDrop: 0.06)
        case .teacher: MaskArt(eyesWidth: 1.9)
        // The head mirror sits on the forehead rather than the crown.
        case .doctor: MaskArt(head: .center(width: 0.35, sink: 0.22))
        }
    }
}

/// Dot-art masks placed on a face. `excitement` (0–1) flaps the ears and adds
/// blush while brushing; `hop` (0–1) jumps when a zone is cleaned.
struct MaskView: View {
    let mask: BrushingMask
    let face: ScreenFace
    let time: Double
    var excitement: Double = 0
    var hop: Double = 0

    var body: some View {
        let w = face.width
        let art = MaskArt.of(mask)
        // Whole-step motion reads as sprite animation rather than smooth tweening.
        let sway = (sin(time * 2) * 2).rounded()
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
                    .position(face.offset(face.nose, x: 0, y: w * (art.noseDrop - MaskArt.noseLift)))
            }
            if let eyesWidth = art.eyesWidth {
                PixelSprite(name: "pixel-mask-\(mask.rawValue)-eyes", width: face.eyeDistance * eyesWidth)
                    .rotationEffect(face.roll)
                    .position(face.eyeCenter)
            }
            // Head pieces pivot on their bottom edge: each frame's unrotated bottom is placed
            // on its anchor so rotation and squash happen around where it meets the head.
            switch art.head {
            case .ears(let width, let spread)?:
                ForEach([-1.0, 1.0], id: \.self) { side in
                    let ear = PixelSprite(name: "pixel-mask-\(mask.rawValue)-ear", width: w * width)
                    let anchor = face.point(x: side * w * spread, y: -w * MaskArt.crown)
                    // Ears flap out of phase, like a sprite's two-frame wiggle.
                    let flap = (sin(time * 14 + side) * 10 * excitement).rounded()
                    ear
                        .scaleEffect(x: side, y: squash, anchor: .bottom)
                        .rotationEffect(face.roll + .degrees(side * flap + sway), anchor: .bottom)
                        .position(x: anchor.x, y: anchor.y - ear.height / 2)
                }
            case .center(let width, let sink)?:
                let piece = PixelSprite(name: "pixel-mask-\(mask.rawValue)-center", width: w * width)
                let anchor = face.point(x: 0, y: -w * (MaskArt.crown + 0.04 - sink))
                let bob = (sin(time * 14) * 6 * excitement).rounded()
                piece
                    .scaleEffect(x: 1, y: squash, anchor: .bottom)
                    .rotationEffect(face.roll + .degrees(bob + sway), anchor: .bottom)
                    .position(x: anchor.x, y: anchor.y - piece.height / 2)
            case .wrap(let width, let lift)?:
                let piece = PixelSprite(name: "pixel-mask-\(mask.rawValue)-top", width: w * width)
                let anchor = face.point(x: 0, y: -w * lift)
                piece
                    .scaleEffect(x: 1, y: squash, anchor: .bottom)
                    .rotationEffect(face.roll + .degrees(sway), anchor: .bottom)
                    .position(x: anchor.x, y: anchor.y - piece.height / 2)
            case nil:
                EmptyView()
            }
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
