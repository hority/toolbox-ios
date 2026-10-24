import Foundation

enum BrushingMask: String, CaseIterable, Identifiable, Codable, Sendable {
    case bunny, panda, cat, penguin, bear, unicorn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bunny: "うさぎ"
        case .panda: "パンダ"
        case .cat: "ねこ"
        case .penguin: "ペンギン"
        case .bear: "くま"
        case .unicorn: "ユニコーン"
        }
    }

    /// Stamps needed before the mask can be chosen.
    var requiredStamps: Int {
        switch self {
        case .bunny, .panda: 0
        case .cat: 3
        case .penguin: 5
        case .bear: 7
        case .unicorn: 10
        }
    }
}

struct BrushingStamp: Codable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var stars: Int
    var mask: BrushingMask
}

/// The child's stamp card, kept only in this device's UserDefaults.
@MainActor
@Observable
final class BrushingStampCard {
    private static let key = "brushingStamps"
    private let defaults: UserDefaults
    private(set) var stamps: [BrushingStamp]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stamps = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([BrushingStamp].self, from: $0) } ?? []
    }

    func isUnlocked(_ mask: BrushingMask) -> Bool {
        stamps.count >= mask.requiredStamps
    }

    /// Returns the masks this stamp unlocked.
    @discardableResult
    func add(stars: Int, mask: BrushingMask, date: Date = .now) -> [BrushingMask] {
        let before = Set(BrushingMask.allCases.filter(isUnlocked))
        stamps.append(BrushingStamp(date: date, stars: stars, mask: mask))
        if let data = try? JSONEncoder().encode(stamps) {
            defaults.set(data, forKey: Self.key)
        }
        return BrushingMask.allCases.filter { isUnlocked($0) && !before.contains($0) }
    }
}
