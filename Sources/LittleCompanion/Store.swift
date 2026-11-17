import Foundation
import PetCore

/// Each dog's whole life in one versioned JSON file in Application Support. Writes are atomic.
/// A save this build can't read is never overwritten: it's moved aside first, or (if that fails, or the save comes
/// from a newer build) the dog is left read-only for this run and nothing is written over it.
enum Store {
    struct Saved: Codable { var savedAt: Date; var state: DogState }
    private struct Peek: Codable { struct S: Codable { var version: Int? }; var state: S }

    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LittleCompanion")
    /// Each dog keeps its own life; Ollie keeps the original file so older saves carry on.
    static func url(_ dog: String) -> URL { dir.appendingPathComponent(dog == "ollie" ? "state.json" : "state-\(dog).json") }

    /// Dogs whose save must not be written this run (saved by a newer build, or unreadable and couldn't be moved aside).
    nonisolated(unsafe) static var readOnly: Set<String> = []

    static func load(_ dog: String) -> Saved? {
        let url = url(dog)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let v = (try? JSONDecoder().decode(Peek.self, from: data))?.state.version, v > DogState.currentVersion {
            NSLog("LittleCompanion: \(dog)'s save is from a newer version (\(v)); leaving it untouched")
            readOnly.insert(dog)
            return nil
        }
        do {
            return try JSONDecoder().decode(Saved.self, from: data)
        } catch {
            // Never overwrite an unreadable dog: keep the file aside before a new one is adopted.
            let aside = url.deletingLastPathComponent().appendingPathComponent("state-\(dog).unreadable-\(Int(Date().timeIntervalSince1970)).json")
            do { try FileManager.default.moveItem(at: url, to: aside) }
            catch { readOnly.insert(dog); NSLog("LittleCompanion: could not move \(dog)'s unreadable save aside (\(error)); not saving over it") ; return nil }
            NSLog("LittleCompanion: could not read \(dog)'s save (\(error)); kept it at \(aside.path)")
            return nil
        }
    }

    static func save(_ state: DogState, dog: String) {
        guard !readOnly.contains(dog) else { return }
        let url = url(dog)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(savedAt: Date(), state: state)).write(to: url, options: .atomic)
        } catch {
            NSLog("LittleCompanion: save failed: \(error)")
        }
    }
}
