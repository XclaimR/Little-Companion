import Foundation
import PetCore

/// The dog's whole life in one versioned JSON file in Application Support. Writes are atomic.
enum Store {
    struct Saved: Codable { var savedAt: Date; var state: DogState }

    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LittleCompanion/state.json")

    static func load() -> Saved? {
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

    static func save(_ state: DogState) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(savedAt: Date(), state: state)).write(to: url, options: .atomic)
        } catch {
            NSLog("LittleCompanion: save failed: \(error)")
        }
    }
}
