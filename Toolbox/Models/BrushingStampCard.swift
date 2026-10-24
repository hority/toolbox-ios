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

    func add(stars: Int, mask: BrushingMask, date: Date = .now) {
        stamps.append(BrushingStamp(date: date, stars: stars, mask: mask))
        if let data = try? JSONEncoder().encode(stamps) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
