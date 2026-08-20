import Foundation

struct LyrisStorageUsage: Equatable, Sendable {
    let cachedLyricCount: Int
    let lyricsBytes: Int64
    let networkCacheBytes: Int64

    static let empty = Self(
        cachedLyricCount: 0,
        lyricsBytes: 0,
        networkCacheBytes: 0
    )

    var formattedLyricsBytes: String {
        Self.formattedByteCount(lyricsBytes)
    }

    var formattedNetworkCacheBytes: String {
        Self.formattedByteCount(networkCacheBytes)
    }

    static func inspect(
        lyricsURL: URL = LyrisDataLocation.lyricsURL(),
        cacheURL: URL = LyrisDataLocation.cacheURL(),
        fileManager: FileManager = .default
    ) -> Self {
        Self(
            cachedLyricCount: canonicalLyricCount(
                at: lyricsURL,
                fileManager: fileManager
            ),
            lyricsBytes: recursiveByteCount(
                at: lyricsURL,
                fileManager: fileManager
            ),
            networkCacheBytes: recursiveByteCount(
                at: cacheURL,
                fileManager: fileManager
            )
        )
    }

    private static func canonicalLyricCount(
        at lyricsURL: URL,
        fileManager: FileManager
    ) -> Int {
        ["generated", "manual"].reduce(into: 0) { count, directoryName in
            let directory = lyricsURL.appendingPathComponent(
                directoryName,
                isDirectory: true
            )
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            count += children.reduce(into: 0) { subtotal, url in
                guard url.pathExtension.lowercased() == "json",
                      (try? url.resourceValues(
                        forKeys: [.isRegularFileKey]
                      ).isRegularFile) == true else { return }
                subtotal += 1
            }
        }
    }

    private static func recursiveByteCount(
        at rootURL: URL,
        fileManager: FileManager
    ) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return bytes == 0 ? "0 KB" : formatter.string(fromByteCount: bytes)
    }
}
