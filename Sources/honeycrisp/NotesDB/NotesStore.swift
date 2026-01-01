import Foundation

final class NotesStore {
    private let container: NotesContainer
    private let snapshotURL: URL
    private let db: SQLiteDB
    private let keys: [String: Int]
    private let columns: Set<String>
    private let storeUUID: String?
    private let accountsByID: [Int64: AccountRecord]
    private let foldersByID: [Int64: FolderRecord]
    private let folderPaths: [Int64: String]
    private let trashedFolderIDs: Set<Int64>

    private let folderNamesByID: [Int64: String]
    private let accountNamesByID: [Int64: String]

    private static let coreTimeOffset: TimeInterval = 978307200

    private init(container: NotesContainer, snapshotURL: URL, db: SQLiteDB, keys: [String: Int], columns: Set<String>, storeUUID: String?, accounts: [AccountRecord], folders: [FolderRecord]) {
        self.container = container
        self.snapshotURL = snapshotURL
        self.db = db
        self.keys = keys
        self.columns = columns
        self.storeUUID = storeUUID

        var accountsByID: [Int64: AccountRecord] = [:]
        var accountNamesByID: [Int64: String] = [:]
        for account in accounts {
            accountsByID[account.id] = account
            accountNamesByID[account.id] = account.name
        }
        self.accountsByID = accountsByID
        self.accountNamesByID = accountNamesByID

        var foldersByID: [Int64: FolderRecord] = [:]
        var folderNamesByID: [Int64: String] = [:]
        var trashed: Set<Int64> = []
        for folder in folders {
            foldersByID[folder.id] = folder
            folderNamesByID[folder.id] = folder.name
            if folder.type == 1 { // trash
                trashed.insert(folder.id)
            }
        }
        self.foldersByID = foldersByID
        self.folderNamesByID = folderNamesByID
        self.trashedFolderIDs = trashed
        self.folderPaths = NotesStore.buildFolderPaths(foldersByID)
    }

    static func open(notesPath: String?) throws -> NotesStore {
        do {
            return try openInternal(notesPath: notesPath)
        } catch let access as NotesAccessError {
            if notesPath == nil,
               let selectedPath = NotesAccessPrompt.promptForNotesContainer(defaultRoot: NotesContainer.defaultRootURL) {
                do {
                    return try openInternal(notesPath: selectedPath)
                } catch let access as NotesAccessError {
                    throw CLIError(message: access.message)
                }
            }
            throw CLIError(message: access.message)
        }
    }

    private static func openInternal(notesPath: String?) throws -> NotesStore {
        let container = try NotesContainer.resolve(notesPath: notesPath)
        let snapshotURL = try container.snapshot()
        let db = try SQLiteDB(path: snapshotURL.path, readonly: true)
        let columns = try db.tableColumns("ziccloudsyncingobject")
        let keys = try NotesStore.loadKeys(db)
        let storeUUID = try NotesStore.loadStoreUUID(db)
        let accounts = try NotesStore.loadAccounts(db, keys: keys)
        let folders = try NotesStore.loadFolders(db, keys: keys)
        return NotesStore(container: container, snapshotURL: snapshotURL, db: db, keys: keys, columns: columns, storeUUID: storeUUID, accounts: accounts, folders: folders)
    }

    func close() {
        db.close()
        let tempDir = snapshotURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: tempDir)
    }

    func listAccounts() -> [AccountRecord] {
        return accountsByID.values.sorted { $0.name < $1.name }
    }

    func listFolders(accountName: String?) -> [FolderSummaryRecord] {
        var folders = foldersByID.values.filter { $0.type != 3 }
        if let accountName, !accountName.isEmpty {
            let matchingAccountIDs = accountIDs(for: accountName)
            folders = folders.filter { folder in
                guard let owner = folder.ownerID else { return false }
                return matchingAccountIDs.contains(owner)
            }
        }
        return folders.map { folder in
            FolderSummaryRecord(
                id: folder.id,
                name: folder.name,
                accountName: folder.ownerID.flatMap { accountNamesByID[$0] },
                path: folderPaths[folder.id]
            )
        }.sorted { $0.name < $1.name }
    }

    func listNotes(limit: Int?, accountName: String?, folderName: String?, includeTrashed: Bool) throws -> [NoteRecord] {
        return try fetchNoteRows(limit: limit, accountName: accountName, folderName: folderName, includeTrashed: includeTrashed)
    }

    func searchNotes(query: String, limit: Int?, accountName: String?, folderName: String?, includeTrashed: Bool) throws -> [NoteRecord] {
        let rows = try fetchNoteRows(limit: nil, accountName: accountName, folderName: folderName, includeTrashed: includeTrashed)
        var results: [NoteRecord] = []
        results.reserveCapacity(rows.count)
        let needle = query.lowercased()
        for row in rows {
            if row.title.lowercased().contains(needle) {
                results.append(row)
            } else {
                let body = try noteBody(id: row.id)
                if body.lowercased().contains(needle) {
                    results.append(row)
                }
            }
            if let limit, results.count >= limit {
                break
            }
        }
        return results
    }

    func resolveNoteIDByTitle(_ title: String, accountName: String?, folderName: String?) throws -> Int64 {
        let rows = try fetchNoteRows(limit: nil, accountName: accountName, folderName: folderName, includeTrashed: folderName == "Recently Deleted")
        let matches = rows.filter { $0.title == title }
        if matches.isEmpty {
            throw CLIError(message: "No note found with title: \(title)")
        }
        if matches.count > 1 {
            var message = "Multiple notes found with title: \(title). Use --id to disambiguate"
            if accountName == nil && folderName == nil {
                message += " or add --account/--folder"
            }
            throw CLIError(message: message)
        }
        return matches[0].id
    }

    func noteDetail(id: Int64) throws -> NoteDetailRecord {
        guard let row = try fetchNoteRow(id: id) else {
            throw CLIError(message: "Note not found")
        }
        if row.isPasswordProtected {
            throw CLIError(message: "Note is password protected")
        }

        let body = try noteBody(id: id)
        let bodyText = row.hasChecklist ? Honeycrisp.renderChecklistPlainText(body, title: row.title) : body
        let attachments = try fetchAttachments(noteID: id)
        let folderName = row.folderID.flatMap { folderNamesByID[$0] }
        let folderPath = row.folderID.flatMap { folderPaths[$0] }
        let accountName = row.accountID.flatMap { accountNamesByID[$0] }
        let isFolderShared = row.folderID.flatMap { folderShared(folderID: $0) }

        return NoteDetailRecord(
            id: id,
            title: row.title,
            created: row.created,
            modified: row.modified,
            account: accountName,
            folder: folderName,
            folderPath: folderPath,
            shared: row.shared,
            folderShared: isFolderShared,
            attachments: attachments,
            body: bodyText
        )
    }

    func coreDataID(forNote id: Int64) -> String? {
        guard let storeUUID, !storeUUID.isEmpty else { return nil }
        return "x-coredata://\(storeUUID)/ICNote/p\(id)"
    }

    func noteHasTableAttachment(id: Int64) -> Bool {
        let noteEnt = keys["ICNote"] ?? 0
        var conditions: [String] = []
        if columns.contains("ZTYPEUTI") {
            conditions.append("ztypeuti = ?")
        }
        if columns.contains("ZTYPEUTI1") {
            conditions.append("ztypeuti1 = ?")
        }
        guard !conditions.isEmpty else { return false }
        let sql = "SELECT 1 FROM ziccloudsyncingobject WHERE znote = ? AND z_ent != ? AND (\(conditions.joined(separator: " OR "))) LIMIT 1"
        var bindings: [SQLiteValue] = [.integer(id), .integer(Int64(noteEnt))]
        for _ in conditions {
            bindings.append(.text("com.apple.notes.table"))
        }
        do {
            return try db.queryOne(sql, bindings) != nil
        } catch {
            return false
        }
    }

    private func folderShared(folderID: Int64) -> Bool? {
        guard columns.contains("ZSHARED") else { return nil }
        guard let row = try? db.queryOne("SELECT zshared FROM ziccloudsyncingobject WHERE z_pk = ?", [.integer(folderID)]) else {
            return nil
        }
        return row.bool("ZSHARED")
    }

    private func noteBody(id: Int64) throws -> String {
        guard let row = try db.queryOne("SELECT zdata FROM zicnotedata WHERE znote = ?", [.integer(id)]) else {
            return ""
        }
        guard let data = row.data("ZDATA") else { return "" }
        do {
            if let text = try NoteDataDecoder.decodeNoteText(from: data) {
                return text
            }
            return ""
        } catch {
            return ""
        }
    }

    private func fetchNoteRow(id: Int64) throws -> NoteRecord? {
        let sql = noteSelectQuery(limit: 1, accountName: nil, folderName: nil, includeTrashed: true, specificID: id)
        let rows = try db.query(sql.query, sql.bindings)
        return rows.compactMap { makeNoteRecord(from: $0) }.first
    }

    private func fetchNoteRows(limit: Int?, accountName: String?, folderName: String?, includeTrashed: Bool) throws -> [NoteRecord] {
        let sql = noteSelectQuery(limit: limit, accountName: accountName, folderName: folderName, includeTrashed: includeTrashed, specificID: nil)
        let rows = try db.query(sql.query, sql.bindings)
        return rows.compactMap { makeNoteRecord(from: $0) }
    }

    private func noteSelectQuery(
        limit: Int?,
        accountName: String?,
        folderName: String?,
        includeTrashed: Bool,
        specificID: Int64?
    ) -> (query: String, bindings: [SQLiteValue]) {
        let noteEnt = keys["ICNote"] ?? 0
        let hasAccount = columns.contains("ZACCOUNT")
        let hasShared = columns.contains("ZSHARED")
        let hasPassword = columns.contains("ZISPASSWORDPROTECTED")
        let hasChecklist = columns.contains("ZHASCHECKLIST")
        let hasChecklistInProgress = columns.contains("ZHASCHECKLISTINPROGRESS")
        let created2 = columns.contains("ZCREATIONDATE2") ? "zcreationdate2" : "NULL AS zcreationdate2"
        let created3 = columns.contains("ZCREATIONDATE3") ? "zcreationdate3" : "NULL AS zcreationdate3"
        let accountCol = hasAccount ? "zaccount" : "NULL AS zaccount"
        let sharedCol = hasShared ? "zshared" : "NULL AS zshared"
        let passwordCol = hasPassword ? "zispasswordprotected" : "NULL AS zispasswordprotected"
        let checklistCol = hasChecklist ? "zhaschecklist" : "NULL AS zhaschecklist"
        let checklistProgressCol = hasChecklistInProgress ? "zhaschecklistinprogress" : "NULL AS zhaschecklistinprogress"

        var query = "SELECT z_pk, ztitle1, zfolder, zcreationdate1, \(created2), \(created3), zmodificationdate1, \(accountCol), \(sharedCol), \(passwordCol), \(checklistCol), \(checklistProgressCol) FROM ziccloudsyncingobject WHERE z_ent = ? AND ztitle1 IS NOT NULL"
        var bindings: [SQLiteValue] = [.integer(Int64(noteEnt))]

        if let specificID {
            query += " AND z_pk = ?"
            bindings.append(.integer(specificID))
        }

        if let accountName, !accountName.isEmpty {
            let accountIDs = accountIDs(for: accountName)
            if hasAccount {
                if !accountIDs.isEmpty {
                    query += " AND zaccount IN (\(placeholders(accountIDs.count)))"
                    bindings.append(contentsOf: accountIDs.map { .integer($0) })
                } else {
                    query += " AND 1 = 0"
                }
            } else {
                let folderIDs = folderIDs(forAccountIDs: accountIDs)
                if !folderIDs.isEmpty {
                    query += " AND zfolder IN (\(placeholders(folderIDs.count)))"
                    bindings.append(contentsOf: folderIDs.map { .integer($0) })
                } else {
                    query += " AND 1 = 0"
                }
            }
        }

        if let folderName, !folderName.isEmpty {
            let folderIDs = folderIDs(forName: folderName, accountName: accountName)
            if !folderIDs.isEmpty {
                query += " AND zfolder IN (\(placeholders(folderIDs.count)))"
                bindings.append(contentsOf: folderIDs.map { .integer($0) })
            } else {
                query += " AND 1 = 0"
            }
        } else if !includeTrashed, !trashedFolderIDs.isEmpty {
            query += " AND (zfolder IS NULL OR zfolder NOT IN (\(placeholders(trashedFolderIDs.count))))"
            bindings.append(contentsOf: trashedFolderIDs.map { .integer($0) })
        }

        if let limit {
            query += " LIMIT \(limit)"
        }

        return (query, bindings)
    }

    private func fetchAttachments(noteID: Int64) throws -> [AttachmentDetail] {
        let noteEnt = keys["ICNote"] ?? 0
        let columnsList = attachmentSelectColumns()
        let sql = "SELECT \(columnsList.selectList) FROM ziccloudsyncingobject WHERE znote = ? AND z_ent != ?"
        let rows = try db.query(sql, [.integer(noteID), .integer(Int64(noteEnt))])

        var details: [AttachmentDetail] = []
        for row in rows {
            let name = row.string("ZFILENAME") ?? row.string("ZIDENTIFIER") ?? row.string("ZTYPEUTI") ?? "Attachment"
            let created = row.double("ZCREATIONDATE").flatMap { decodeTime($0) }
            let modified = row.double("ZMODIFICATIONDATE").flatMap { decodeTime($0) }
            let url = row.string("ZURL")
            let shared = row.bool("ZSHARED")
            details.append(AttachmentDetail(
                name: name,
                created: created.map { Honeycrisp.formatDate($0) },
                modified: modified.map { Honeycrisp.formatDate($0) },
                url: url,
                shared: shared
            ))
        }
        return details
    }

    private func attachmentSelectColumns() -> (selectList: String, columns: [String]) {
        let possible = [
            "z_pk",
            "zidentifier",
            "zfilename",
            "zcreationdate",
            "zmodificationdate",
            "zurl",
            "zshared",
            "ztypeuti",
            "zmedia",
            "zgeneration1"
        ]
        var selectParts: [String] = []
        var names: [String] = []
        for col in possible {
            let upper = col.uppercased()
            if columns.contains(upper) {
                selectParts.append(col)
            } else {
                selectParts.append("NULL AS \(col)")
            }
            names.append(upper)
        }
        return (selectParts.joined(separator: ", "), names)
    }

    private func accountIDs(for name: String) -> [Int64] {
        accountsByID.values.filter { $0.name == name }.map { $0.id }
    }

    private func folderIDs(forName name: String, accountName: String?) -> [Int64] {
        let candidates = foldersByID.values.filter { $0.name == name }
        if let accountName, !accountName.isEmpty {
            let accountIDs = Set(accountIDs(for: accountName))
            return candidates.filter { folder in
                guard let owner = folder.ownerID else { return false }
                return accountIDs.contains(owner)
            }.map { $0.id }
        }
        return candidates.map { $0.id }
    }

    private func folderIDs(forAccountIDs ids: [Int64]) -> [Int64] {
        let idSet = Set(ids)
        return foldersByID.values.compactMap { folder in
            guard let owner = folder.ownerID, idSet.contains(owner) else { return nil }
            return folder.id
        }
    }

    private func decodeTime(_ value: Double) -> Date {
        let raw = value
        let timestamp: TimeInterval
        if raw < 1 {
            timestamp = Date().timeIntervalSince1970
        } else {
            timestamp = raw + NotesStore.coreTimeOffset
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func makeNoteRecord(from row: SQLiteRow) -> NoteRecord? {
        guard let id = row.int64("Z_PK"), let title = row.string("ZTITLE1") else { return nil }
        let folderID = row.int64("ZFOLDER")
        let created1 = row.double("ZCREATIONDATE1") ?? 0
        let created2 = row.double("ZCREATIONDATE2") ?? 0
        let created3 = row.double("ZCREATIONDATE3") ?? 0
        let modified = row.double("ZMODIFICATIONDATE1") ?? 0
        let shared = row.bool("ZSHARED")
        let accountID = row.int64("ZACCOUNT")
        let isPasswordProtected = row.bool("ZISPASSWORDPROTECTED") ?? false
        let hasChecklist = (row.bool("ZHASCHECKLIST") ?? false) || (row.bool("ZHASCHECKLISTINPROGRESS") ?? false)

        let createdValue = created3 > 0 ? created3 : (created2 > 0 ? created2 : created1)
        let createdDate = decodeTime(createdValue)
        let modifiedDate = decodeTime(modified)

        return NoteRecord(
            id: id,
            title: title,
            folderID: folderID,
            created: createdDate,
            modified: modifiedDate,
            accountID: accountID,
            shared: shared,
            isPasswordProtected: isPasswordProtected,
            hasChecklist: hasChecklist
        )
    }

    private static func loadKeys(_ db: SQLiteDB) throws -> [String: Int] {
        let rows = try db.query("SELECT z_ent, z_name FROM z_primarykey")
        var result: [String: Int] = [:]
        for row in rows {
            if let name = row.string("Z_NAME"), let ent = row.int64("Z_ENT") {
                result[name] = Int(ent)
            }
        }
        return result
    }

    private static func loadStoreUUID(_ db: SQLiteDB) throws -> String? {
        guard let row = try db.queryOne("SELECT z_uuid FROM z_metadata LIMIT 1") else { return nil }
        return row.string("Z_UUID")
    }

    private static func loadAccounts(_ db: SQLiteDB, keys: [String: Int]) throws -> [AccountRecord] {
        guard let accountEnt = keys["ICAccount"] else { return [] }
        let rows = try db.query("SELECT z_pk, zname, zidentifier FROM ziccloudsyncingobject WHERE z_ent = ?", [.integer(Int64(accountEnt))])
        return rows.compactMap { row in
            guard let id = row.int64("Z_PK"), let name = row.string("ZNAME") else { return nil }
            let identifier = row.string("ZIDENTIFIER")
            return AccountRecord(id: id, name: name, identifier: identifier)
        }
    }

    private static func loadFolders(_ db: SQLiteDB, keys: [String: Int]) throws -> [FolderRecord] {
        guard let folderEnt = keys["ICFolder"] else { return [] }
        let rows = try db.query("SELECT z_pk, ztitle2, zparent, zowner, zfoldertype FROM ziccloudsyncingobject WHERE z_ent = ?", [.integer(Int64(folderEnt))])
        return rows.compactMap { row in
            guard let id = row.int64("Z_PK"), let name = row.string("ZTITLE2") else { return nil }
            let parent = row.int64("ZPARENT")
            let owner = row.int64("ZOWNER")
            let type = Int(row.int64("ZFOLDERTYPE") ?? 0)
            return FolderRecord(id: id, name: name, parentID: parent, ownerID: owner, type: type)
        }
    }

    private static func buildFolderPaths(_ folders: [Int64: FolderRecord]) -> [Int64: String] {
        var paths: [Int64: String] = [:]

        func computePath(_ id: Int64) -> String? {
            if let cached = paths[id] { return cached }
            guard let folder = folders[id] else { return nil }
            var parts: [String] = [folder.name]
            var current = folder.parentID
            while let parentID = current {
                guard let parent = folders[parentID] else { break }
                parts.insert(parent.name, at: 0)
                current = parent.parentID
            }
            let path = parts.joined(separator: "/")
            paths[id] = path
            return path
        }

        for id in folders.keys {
            _ = computePath(id)
        }

        return paths
    }

    private func placeholders(_ count: Int) -> String {
        return Array(repeating: "?", count: count).joined(separator: ",")
    }
}
