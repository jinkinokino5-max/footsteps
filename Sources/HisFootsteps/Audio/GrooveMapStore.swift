import Foundation

/// 解析結果の要約。選曲画面はこれだけ読めばよく、数MBの本体を触らずに済む。
struct GrooveSummary: Codable {
    let bpm: Double
    let beatCount: Int
    let hitCount: Int
}

/// 解析結果をキャッシュに保存し、2回目以降の起動を一瞬にするための保管庫。
enum GrooveMapStore {
    /// 解析はバックグラウンドで走り、選曲画面はメインから読むため、辞書は必ずロック越しに触る
    private static var summaryCache: [String: GrooveSummary] = [:]
    private static let cacheLock = NSLock()

    private static func cachedSummary(_ songID: String) -> GrooveSummary? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return summaryCache[songID]
    }

    private static func storeSummary(_ summary: GrooveSummary, for songID: String) {
        cacheLock.lock()
        summaryCache[songID] = summary
        cacheLock.unlock()
    }

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
        storeSummary(summary, for: song.id)
        if let url = summaryURL(for: song), let data = try? JSONEncoder().encode(summary) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 要約（選曲画面用）

    static func summary(for song: Song) -> GrooveSummary? {
        if let cached = cachedSummary(song.id) { return cached }
        guard let url = summaryURL(for: song),
              let data = try? Data(contentsOf: url),
              let summary = try? JSONDecoder().decode(GrooveSummary.self, from: data)
        else { return nil }
        storeSummary(summary, for: song.id)
        return summary
    }

    /// 解析アルゴリズムを更新したときに古い世代のキャッシュを掃除する
    static func purgeOldVersions() {
        cacheLock.lock()
        summaryCache.removeAll()
        cacheLock.unlock()
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        let marker = "-v\(GrooveMap.currentVersion)."
        for file in files where !file.lastPathComponent.contains(marker) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
