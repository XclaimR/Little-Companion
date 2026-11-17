import Foundation
import PetCore

/// The dog's whole life in one versioned JSON file in Application Support. Writes are atomic.
enum Store {
    struct Saved: Codable { var savedAt: Date; var state: DogState }

    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LittleCompanion")
    /// Each dog keeps its own life; Ollie keeps the original file so older saves carry on.
    static func url(_ dog: String) -> URL { dir.appendingPathComponent(dog == "ollie" ? "state.json" : "state-\(dog).json") }

    static func load(_ dog: String) -> Saved? {
        let url = url(dog)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Saved.self, from: data)
        } catch {
            // Never overwrite an unreadable dog: keep the file aside before a new one is adopted.
            let aside = url.deletingLastPathComponent().appendingPathComponent("state.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            NSLog("LittleCompanion: could not read saved dog (\(error)); kept it at \(aside.path)")
            return nil
        }
    }

    static func save(_ state: DogState, dog: String) {
        let url = url(dog)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(savedAt: Date(), state: state)).write(to: url, options: .atomic)
        } catch {
            NSLog("LittleCompanion: save failed: \(error)")
        }
    }
}
