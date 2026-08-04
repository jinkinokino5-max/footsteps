import Foundation

/// 踊る対象の楽曲。アプリ内蔵曲と、ユーザーが「ファイル」から取り込んだ曲の両方を扱う。
struct Song: Identifiable, Hashable {
    let id: String
    let url: URL
    let title: String
    let subtitle: String
    /// ファイルサイズ（解析キャッシュの鍵に使う）
    let byteSize: Int
    /// ユーザーが取り込んだ曲か（内蔵曲は削除できない）
    let isImported: Bool
}

enum SongLibraryError: Error, LocalizedError {
    case accessDenied
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "ファイルへのアクセスが許可されませんでした"
        case .unsupportedFormat: return "対応していない形式です（mp3 / m4a / wav / aac）"
        }
    }
}

enum SongLibrary {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "aif", "aiff", "caf"]

    /// 取り込んだ曲の置き場所。「ファイル」アプリからも見えるようにDocuments直下に置く。
    static var importsDirectory: URL? {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Tracks", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func loadAll() -> [Song] {
        var songs = bundledSongs()
        songs.append(contentsOf: importedSongs())
        return songs
    }

    private static func bundledSongs() -> [Song] {
        guard let musicDir = Bundle.main.url(forResource: "Music", withExtension: nil) else { return [] }
        return songs(in: musicDir, imported: false)
    }

    private static func importedSongs() -> [Song] {
        guard let dir = importsDirectory else { return [] }
        return songs(in: dir, imported: true)
    }

    private static func songs(in directory: URL, imported: Bool) -> [Song] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return [] }

        return files
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return Song(
                    id: (imported ? "import/" : "bundle/") + url.lastPathComponent,
                    url: url,
                    title: url.deletingPathExtension().lastPathComponent,
                    subtitle: imported ? "取り込み" : "内蔵",
                    byteSize: size,
                    isImported: imported
                )
            }
    }

    // MARK: - 取り込み

    /// 「ファイル」アプリから選ばれた曲をアプリ内へコピーする。
    @discardableResult
    static func importSong(from source: URL) throws -> Song {
        guard supportedExtensions.contains(source.pathExtension.lowercased()) else {
            throw SongLibraryError.unsupportedFormat
        }
        guard let dir = importsDirectory else { throw SongLibraryError.accessDenied }

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        var destination = dir.appendingPathComponent(source.lastPathComponent)
        var suffix = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = source.deletingPathExtension().lastPathComponent
            destination = dir.appendingPathComponent("\(base)-\(suffix).\(source.pathExtension)")
            suffix += 1
        }

        let data = try Data(contentsOf: source)
        try data.write(to: destination, options: .atomic)

        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? data.count
        return Song(
            id: "import/" + destination.lastPathComponent,
            url: destination,
            title: destination.deletingPathExtension().lastPathComponent,
            subtitle: "取り込み",
            byteSize: size,
            isImported: true
        )
    }

    static func delete(_ song: Song) {
        guard song.isImported else { return }
        try? FileManager.default.removeItem(at: song.url)
    }
}
