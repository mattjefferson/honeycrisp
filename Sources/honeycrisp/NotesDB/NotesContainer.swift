import Foundation

enum NotesAccessError: Error {
    case notFoundOrDenied
    case readDenied

    var message: String {
        switch self {
        case .notFoundOrDenied:
            return "Notes database not found or access denied. Grant access to the Notes container (group.com.apple.notes) and try again."
        case .readDenied:
            return "Failed to read Notes database. Grant access to the Notes container (group.com.apple.notes) and try again."
        }
    }
}

struct NotesContainer {
    let rootURL: URL
    let dbURL: URL

    static let defaultRootPath = "~/Library/Group Containers/group.com.apple.notes"
    static let dbName = "NoteStore.sqlite"
    static var defaultRootURL: URL {
        let path = (defaultRootPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: path)
    }

    static func resolve(notesPath: String?) throws -> NotesContainer {
        let expanded: String? = notesPath.map { ($0 as NSString).expandingTildeInPath }
        let rootURL: URL
        let dbURL: URL

        if let expanded {
            let url = URL(fileURLWithPath: expanded)
            if url.pathExtension == "sqlite" {
                dbURL = url
                rootURL = url.deletingLastPathComponent()
            } else {
                rootURL = url
                dbURL = url.appendingPathComponent(dbName)
            }
        } else {
            rootURL = defaultRootURL
            dbURL = rootURL.appendingPathComponent(dbName)
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: dbURL.path) else {
            if notesPath == nil || rootURL.path.contains("group.com.apple.notes") {
                throw NotesAccessError.notFoundOrDenied
            }
            throw CLIError(message: "Notes database not found at \(dbURL.path)")
        }

        return NotesContainer(rootURL: rootURL, dbURL: dbURL)
    }

    func snapshot() throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("honeycrisp-notes-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let target = tempDir.appendingPathComponent(NotesContainer.dbName)
        do {
            try fm.copyItem(at: dbURL, to: target)
        } catch {
            throw NotesAccessError.readDenied
        }

        let wal = URL(fileURLWithPath: dbURL.path + "-wal")
        if fm.fileExists(atPath: wal.path) {
            try? fm.copyItem(at: wal, to: URL(fileURLWithPath: target.path + "-wal"))
        }
        let shm = URL(fileURLWithPath: dbURL.path + "-shm")
        if fm.fileExists(atPath: shm.path) {
            try? fm.copyItem(at: shm, to: URL(fileURLWithPath: target.path + "-shm"))
        }
        return target
    }
}
