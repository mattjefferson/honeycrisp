import Foundation

struct CLIError: Error {
    let message: String
}

struct NoteSummary: Codable {
    let title: String
}

struct AccountSummary: Codable {
    let name: String
}

struct FolderSummary: Codable {
    let account: String
    let name: String
}

struct NoteDetail: Codable {
    let title: String
    let created: String
    let modified: String
    let account: String?
    let folder: String?
    let folderPath: String?
    let shared: Bool?
    let folderShared: Bool?
    let tags: [String]?
    let attachments: [AttachmentDetail]?
    let body: String
    let format: String?
    let assets: [String]?
}

struct OperationResult: Codable {
    let ok: Bool
    let action: String
    let title: String?
    let id: String?
}

struct ExportResult: Codable {
    let title: String
    let format: String
    let content: String
    let assets: [String]?
}

struct NoteMatch {
    let id: String
    let title: String
}

struct AttachmentDetail: Codable {
    let name: String
    let created: String?
    let modified: String?
    let url: String?
    let shared: Bool?
}

struct NoteSearchResult: Codable {
    let title: String
    let created: String
    let modified: String
    let account: String?
    let folder: String?
    let folderPath: String?
    let shared: Bool?
    let folderShared: Bool?
    let tags: [String]?
    let attachments: [AttachmentDetail]?
}

extension Honeycrisp {
    static func wantsJSON(_ parsed: ParsedArgs) -> Bool {
        return parsed.flags.contains("--json")
    }

    static func outputJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CLIError(message: "Failed to encode JSON output")
        }
        print(json)
    }
}
