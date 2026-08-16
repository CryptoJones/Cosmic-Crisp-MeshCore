import Foundation

/// Known nodes this iPad has connected to — one profile per radio public key.
/// Message history is already stored per key; this is the user-facing index.
struct NodeProfile: Codable, Identifiable, Equatable {
    var publicKeyHex: String
    var name: String
    var model: String?
    var firstSeen: Date
    var lastConnected: Date
    var id: String { publicKeyHex }
}

enum ProfileStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CosmicCrisp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    static func load() -> [NodeProfile] {
        (try? JSONDecoder().decode([NodeProfile].self, from: Data(contentsOf: url))) ?? []
    }

    static func save(_ profiles: [NodeProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    static func touch(publicKeyHex: String, name: String, model: String?) -> [NodeProfile] {
        var all = load()
        if let i = all.firstIndex(where: { $0.publicKeyHex == publicKeyHex }) {
            all[i].name = name; all[i].model = model ?? all[i].model; all[i].lastConnected = .now
        } else {
            all.append(NodeProfile(publicKeyHex: publicKeyHex, name: name, model: model, firstSeen: .now, lastConnected: .now))
        }
        all.sort { $0.lastConnected > $1.lastConnected }
        save(all)
        return all
    }

    static func remove(publicKeyHex: String) -> [NodeProfile] {
        var all = load(); all.removeAll { $0.publicKeyHex == publicKeyHex }; save(all)
        // Drop that node's history too.
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("messages-\(publicKeyHex.prefix(16)).json"))
        return all
    }
}
