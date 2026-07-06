import Foundation

struct PersistedState: Codable, Equatable {
    var me: UserProfile
    var people: [UserProfile]
    var groups: [MealGroup]
    var swipedIDs: [UUID]
    var matchedIDs: [UUID]
    var reviewQueue: [ReviewCase]
}

enum Persistence {
    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("villagefeed-state.json")
    }

    static func load(from url: URL = defaultURL) -> PersistedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    static func save(_ state: PersistedState, to url: URL = defaultURL) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
