import Foundation

struct AccountRecord {
    let id: Int64
    let name: String
    let identifier: String?
}

struct FolderRecord {
    let id: Int64
    let name: String
    let parentID: Int64?
    let ownerID: Int64?
    let type: Int
}

struct NoteRecord {
    let id: Int64
    let title: String
    let folderID: Int64?
    let created: Date
    let modified: Date
    let accountID: Int64?
    let shared: Bool?
    let isPasswordProtected: Bool
}

struct NoteDetailRecord {
    let id: Int64
    let title: String
    let created: Date
    let modified: Date
    let account: String?
    let folder: String?
    let folderPath: String?
    let shared: Bool?
    let folderShared: Bool?
    let attachments: [AttachmentDetail]
    let body: String
}

struct AttachmentRecord {
    let id: Int64
    let name: String
    let created: Date?
    let modified: Date?
    let url: String?
    let shared: Bool?
    let typeUti: String?
    let identifier: String?
    let mediaID: Int64?
    let generation: String?
}

struct FolderSummaryRecord {
    let id: Int64
    let name: String
    let accountName: String?
    let path: String?
}
