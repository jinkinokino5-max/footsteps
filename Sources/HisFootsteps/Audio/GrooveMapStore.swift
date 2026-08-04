import Foundation

/// 解析結果をキャッシュに保存し、2回目以降の起動を一瞬にするための保管庫。
enum GrooveMapStore {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("GrooveMaps", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(for song: Song) -> URL? {
        guard let directory else { return nil }
        let safeID = song.id.replacingOccurrences(of: "/", with: "_")
        let name = "\(safeID)-\(song.byteSize)-v\(GrooveMap.currentVersion).json"
        return directory.appendingPathComponent(name)
    }

    static func load(for song: Song) -> GrooveMap? {
        guard let url = fileURL(for: song),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode(GrooveMap.self, from: data),
              map.version == GrooveMap.currentVersion
        else { return nil }
        return map
    }

    static func save(_ map: GrooveMap, for song: Song) {
        guard let url = fileURL(for: song), let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 解析アルゴリズムを更新したときに古い世代のキャッシュを掃除する
    static func purgeOldVersions() {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        let suffix = "-v\(GrooveMap.currentVersion).json"
        for file in files where !file.lastPathComponent.hasSuffix(suffix) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
