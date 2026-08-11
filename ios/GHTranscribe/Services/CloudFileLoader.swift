import Foundation

enum CloudFileLoader {
    enum LoaderError: LocalizedError {
        case downloadTimedOut
        case couldNotAccess

        var errorDescription: String? {
            switch self {
            case .downloadTimedOut:
                return "Timed out waiting for the file to download from iCloud."
            case .couldNotAccess:
                return "Could not access the selected file."
            }
        }
    }

    /// Loads a file picked via the document picker, waiting for it to
    /// materialize if it's still an iCloud placeholder.
    static func loadData(from url: URL) async throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try await ensureDownloaded(url)

        var coordinatorError: NSError?
        var result: Data?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            result = try? Data(contentsOf: readURL)
        }
        if let coordinatorError {
            throw coordinatorError
        }
        guard let result else {
            throw LoaderError.couldNotAccess
        }
        return result
    }

    private static func ensureDownloaded(_ url: URL) async throws {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values.ubiquitousItemDownloadingStatus == .current {
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw LoaderError.downloadTimedOut
    }
}
