import Foundation

/// Persists a security-scoped bookmark for a folder the user has explicitly
/// granted access to (e.g. Just Press Record's iCloud folder), so the app
/// can create new sidecar files inside it. Picking a single file only
/// grants access to that file, not its containing directory, so this is a
/// separate, opt-in grant.
enum FolderAccessStore {
    private static let defaultsKey = "GrantedFolderBookmark"

    static func save(folderURL: URL) throws {
        let bookmark = try folderURL.bookmarkData()
        UserDefaults.standard.set(bookmark, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    static var grantedFolderName: String? {
        resolvedURL()?.lastPathComponent
    }

    static func resolvedURL() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    /// Returns the granted folder if it contains `fileURL`, else nil.
    static func resolvedURL(covering fileURL: URL) -> URL? {
        guard let folder = resolvedURL() else { return nil }
        let folderPath = folder.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        return filePath.hasPrefix(folderPath) ? folder : nil
    }
}
