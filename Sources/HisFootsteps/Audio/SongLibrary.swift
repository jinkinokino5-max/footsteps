import Foundation

/// アプリに内蔵された楽曲。
struct Song: Identifiable, Hashable {
    let id: String
    let url: URL
    let title: String
    let subtitle: String
    /// ファイルサイズ（解析キャッシュの鍵に使う）
    let byteSize: Int
}

enum SongLibrary {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "aif", "aiff", "caf"]

    static func loadAll() -> [Song] {
        guard let musicDir = Bundle.main.url(forResource: "Music", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(
                at: musicDir,
                includingPropertiesForKeys: [.fileSizeKey]
              )
        else {
            return []
        }

        return files
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let raw = url.deletingPathExtension().lastPathComponent
                return Song(
                    id: url.lastPathComponent,
                    url: url,
                    title: cleanedTitle(raw),
                    subtitle: url.pathExtension.uppercased(),
                    byteSize: size
                )
            }
    }

    /// 「If You're Falling (1)」のような重複サフィックスを外して見栄えを整える
    private static func cleanedTitle(_ raw: String) -> String {
        var title = raw
        if let range = title.range(of: #"\s*\(\d+\)$"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        return title.trimmingCharacters(in: .whitespaces)
    }
}
