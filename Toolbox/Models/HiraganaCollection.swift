import Foundation
import Observation

struct HiraganaCatch: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let character: String
    var date = Date()
    var imageFile: String { "\(id.uuidString).jpg" }
}

/// A newly found character with its cropped picture, before the child keeps it.
struct HiraganaFind: Identifiable, Sendable {
    let id = UUID()
    let character: String
    let image: Data
}

/// The zukan. Pictures stay on this device in Application Support and are never sent.
@MainActor @Observable final class HiraganaCollection {
    private(set) var catches: [HiraganaCatch] = []
    var error: String?
    @ObservationIgnored let directory: URL
    private var index: URL { directory.appending(path: "catches.json") }

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "HiraganaHunter", directoryHint: .isDirectory)) {
        self.directory = directory
        do {
            if let data = try? Data(contentsOf: index) {
                catches = try JSONDecoder().decode([HiraganaCatch].self, from: data)
            }
        } catch { self.error = "ずかんを読み込めませんでした。" }
    }

    var caughtKinds: Int { Set(catches.map(\.character)).count }
    func catches(of character: String) -> [HiraganaCatch] { catches.filter { $0.character == character }.sorted { $0.date > $1.date } }
    func count(of character: String) -> Int { catches.reduce(0) { $0 + ($1.character == character ? 1 : 0) } }
    func has(_ character: String) -> Bool { catches.contains { $0.character == character } }
    func imageURL(_ item: HiraganaCatch) -> URL { directory.appending(path: item.imageFile) }

    func add(_ finds: [HiraganaFind]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var next = catches
        var written: [URL] = []
        do {
            for find in finds {
                let item = HiraganaCatch(character: find.character)
                let url = imageURL(item)
                try find.image.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                written.append(url)
                next.append(item)
            }
            try save(next)
        } catch {
            written.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
    }

    func remove(_ item: HiraganaCatch) throws {
        try save(catches.filter { $0.id != item.id })
        try? FileManager.default.removeItem(at: imageURL(item))
    }

    private func save(_ next: [HiraganaCatch]) throws {
        try JSONEncoder().encode(next).write(to: index, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        catches = next
    }
}
