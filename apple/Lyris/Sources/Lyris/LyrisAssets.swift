import AppKit

enum LyrisAssets {
    static let appIcon = image(named: "LyrisAppIcon")
    static let demoArtworkURL = resourceURL(
        named: "LyrisDemoArtwork",
        extension: "png",
        subdirectory: "Demo"
    )

    private static func image(named name: String) -> NSImage? {
        guard let url = resourceURL(
            named: name,
            extension: "png",
            subdirectory: "Brand"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func resourceURL(
        named name: String,
        extension fileExtension: String,
        subdirectory: String
    ) -> URL? {
        if let bundled = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) ?? Bundle.main.url(forResource: name, withExtension: fileExtension) {
            return bundled
        }

        // `swift run` does not assemble an App bundle. Resolve development
        // resources from the working directory without compiling a
        // machine-specific absolute SwiftPM build path into the executable.
        let workingDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let candidates = [
            workingDirectory.appendingPathComponent(
                "Sources/Lyris/Resources",
                isDirectory: true
            ),
            workingDirectory.appendingPathComponent(
                "apple/Lyris/Sources/Lyris/Resources",
                isDirectory: true
            ),
        ]
        for resourceRoot in candidates {
            let url = resourceRoot
                .appendingPathComponent(subdirectory, isDirectory: true)
                .appendingPathComponent(name)
                .appendingPathExtension(fileExtension)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
