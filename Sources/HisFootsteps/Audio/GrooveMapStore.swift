import Foundation

/// 解析結果の要約。選曲画面はこれだけ読めばよく、数MBの本体を触らずに済む。
struct GrooveSummary: Codable {
    let bpm: Double
    let beatCount: Int
    let hitCount: Int
}

/// 解析結果をキャッシュに保存し、2回目以降の起動を一瞬にするための保管庫。
enum GrooveMapStore {
    private static var summaryCache: [String: GrooveSummary] = [:]

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("GrooveMaps", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func baseName(for song: Song) -> String {
        let safeID = song.id.replacingOccurrences(of: "/", with: "_")
        return "\(safeID)-\(song.byteSize)-v\(GrooveMap.currentVersion)"
    }

    private static func mapURL(for song: Song) -> URL? {
        directory?.appendingPathComponent(baseName(for: song) + ".json")
    }

    private static func summaryURL(for song: Song) -> URL? {
        directory?.appendingPathComponent(baseName(for: song) + ".meta.json")
    }

    // MARK: - 本体

    static func load(for song: Song) -> GrooveMap? {
        guard let url = mapURL(for: song),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode(GrooveMap.self, from: data),
              map.version == GrooveMap.currentVersion
        else { return nil }
        return map
    }

    static func save(_ map: GrooveMap, for song: Song) {
        if let url = mapURL(for: song), let data = try? JSONEncoder().encode(map) {
            try? data.write(to: url, options: .atomic)
        }
        let summary = GrooveSummary(bpm: map.bpm, beatCount: map.beats.count, hitCount: map.hits.count)
        summaryCache[song.id] = summary
        if let url = summaryURL(for: song), let data = try? JSONEncoder().encode(summary) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 要約（選曲画面用）

    static func summary(for song: Song) -> GrooveSummary? {
        if let cached = summaryCache[song.id] { return cached }
        guard let url = summaryURL(for: song),
              let data = try? Data(contentsOf: url),
              let summary = try? JSONDecoder().decode(GrooveSummary.self, from: data)
        else { return nil }
        summaryCache[song.id] = summary
        return summary
    }

    /// 解析アルゴリズムを更新したときに古い世代のキャッシュを掃除する
    static func purgeOldVersions() {
        summaryCache.removeAll()
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        let marker = "-v\(GrooveMap.currentVersion)."
        for file in files where !file.lastPathComponent.contains(marker) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
