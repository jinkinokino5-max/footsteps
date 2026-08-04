import Foundation

/// アプリにビルド時から内蔵されている楽曲（Resources/Music）
struct BundledSong: Identifiable, Hashable {
    let id: String
    let url: URL
    let displayName: String
}

/// Resources/Music（フォルダ参照でバンドルされる）配下の楽曲ファイルを列挙する
enum BundledSongLibrary {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac"]

    static func loadAll() -> [BundledSong] {
        guard let musicDir = Bundle.main.url(forResource: "Music", withExtension: nil) else {
            return []
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: musicDir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                BundledSong(
                    id: url.lastPathComponent,
                    url: url,
                    displayName: url.deletingPathExtension().lastPathComponent
                )
            }
    }
}
