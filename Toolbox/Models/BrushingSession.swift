import Foundation

/// The camera cannot tell which teeth are being brushed, so the app guides the
/// order and only measures whether brushing motion continued in each period.
enum BrushingZone: Int, CaseIterable, Identifiable, Sendable {
    case upperRight, upperFront, upperLeft, lowerLeft, lowerFront, lowerRight

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .upperRight: "うえの みぎ"
        case .upperFront: "うえの まえ"
        case .upperLeft: "うえの ひだり"
        case .lowerLeft: "したの ひだり"
        case .lowerFront: "したの まえ"
        case .lowerRight: "したの みぎ"
        }
    }

    var shortTitle: String {
        switch self {
        case .upperRight, .lowerRight: "みぎ"
        case .upperFront, .lowerFront: "まえ"
        case .upperLeft, .lowerLeft: "ひだり"
        }
    }
}

struct BrushingSession: Sendable {
    static let zoneDuration: TimeInterval = 20
    static let totalDuration = zoneDuration * Double(BrushingZone.allCases.count)

    private(set) var elapsed: TimeInterval = 0
    private(set) var activeTime: [BrushingZone: TimeInterval] = [:]

    var isFinished: Bool { elapsed >= Self.totalDuration }

    var currentZone: BrushingZone? {
        isFinished ? nil : BrushingZone(rawValue: Int(elapsed / Self.zoneDuration))
    }

    var remaining: TimeInterval { max(0, Self.totalDuration - elapsed) }

    var zoneProgress: Double {
        guard let zone = currentZone else { return 1 }
        return (elapsed - Self.zoneDuration * Double(zone.rawValue)) / Self.zoneDuration
    }

    /// Credits time to the zone it belongs to, even when a step crosses a zone boundary.
    mutating func advance(by delta: TimeInterval, brushing: Bool) {
        var remainingDelta = min(max(delta, 0), 1)
        while remainingDelta > 0, let zone = currentZone {
            let zoneEnd = Self.zoneDuration * Double(zone.rawValue + 1)
            let step = min(remainingDelta, zoneEnd - elapsed)
            if brushing { activeTime[zone, default: 0] += step }
            elapsed = step == zoneEnd - elapsed ? zoneEnd : elapsed + step
            remainingDelta -= step
        }
    }

    func ratio(for zone: BrushingZone) -> Double {
        min(1, activeTime[zone, default: 0] / Self.zoneDuration)
    }

    var overallRatio: Double {
        BrushingZone.allCases.map(ratio(for:)).reduce(0, +) / Double(BrushingZone.allCases.count)
    }

    static let germsPerZone = 3
    /// Brushing time that defeats one germ; all three fall at the two-star line.
    static let secondsPerGerm = zoneDuration * 0.6 / Double(germsPerZone)

    func germsRemaining(in zone: BrushingZone) -> Int {
        max(0, Self.germsPerZone - Int(activeTime[zone, default: 0] / Self.secondsPerGerm))
    }

    static func stars(for ratio: Double) -> Int {
        switch ratio {
        case 0.7...: 3
        case 0.4...: 2
        case 0.1...: 1
        default: 0
        }
    }
}
