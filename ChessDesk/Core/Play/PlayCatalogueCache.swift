import Foundation

/// The last catalogue of bots each backend answered, kept on the device: it
/// lets a player open the bots and play without a connection (the engines
/// are on the device too, once Maia's network has been fetched). It is only
/// ever what the server said; nothing is bundled in its place.
nonisolated struct PlayCatalogueCache: Sendable {
    let folder: URL

    static var standard: PlayCatalogueCache {
        PlayCatalogueCache(folder: URL.applicationSupportDirectory.appending(path: "ChessDesk", directoryHint: .isDirectory))
    }

    /// One file per backend, so sample data never stands in for the server.
    private func file(for backend: Backend) -> URL {
        let name = backend.tokenAccount.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return folder.appending(path: "play-catalogue-\(String(name)).json")
    }

    func catalogue(for backend: Backend) -> PlayCatalogue? {
        guard let data = try? Data(contentsOf: file(for: backend)) else { return nil }
        // A file written by an older version that no longer decodes is ignored.
        return try? JSONDecoder().decode(PlayCatalogue.self, from: data)
    }

    func keep(_ catalogue: PlayCatalogue, for backend: Backend) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(catalogue).write(to: file(for: backend), options: .atomic)
        } catch {
            // Not kept this time; the next answer tries again.
        }
    }
}
