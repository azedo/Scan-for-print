import Foundation

/// One scan on disk. Lives in Documents/Scans so it shows up in the Files app.
struct ScanFolder: Sendable {
    let url: URL
    let checkpoints: URL

    var name: String { url.lastPathComponent }
    var images: URL { url.appending(path: "Images", directoryHint: .isDirectory) }
    var texturedModel: URL { url.appending(path: "model.usdz") }
    var stl: URL { url.appending(path: "\(name).stl") }
}

enum ScanStorage {
    static func newFolder(kind: String, withImages: Bool) throws -> ScanFolder {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let name = "\(kind) \(formatter.string(from: .now))"

        let url = URL.documentsDirectory
            .appending(path: "Scans", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
        // Checkpoints are large intermediate files; keep them out of Files.
        let checkpoints = URL.cachesDirectory
            .appending(path: "Checkpoints", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)

        let folder = ScanFolder(url: url, checkpoints: checkpoints)
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(at: checkpoints, withIntermediateDirectories: true)
        if withImages {
            try fm.createDirectory(at: folder.images, withIntermediateDirectories: true)
        }
        return folder
    }
}

struct ScanResult {
    enum Kind { case object, large }
    let kind: Kind
    let folder: ScanFolder
    let mesh: TriangleMesh
    /// Textured USDZ, only for object scans.
    var texturedModel: URL?
}
