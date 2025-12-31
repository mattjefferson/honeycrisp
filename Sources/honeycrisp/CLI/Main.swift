import Foundation

@main
struct Honeycrisp {
    static func main() {
        do {
            try run()
        } catch {
            let message: String
            if let cliError = error as? CLIError {
                message = cliError.message
            } else {
                message = "Unexpected error: \(error)"
            }
            printErr(message)
            exit(1)
        }
    }

    static func run() throws {
        var args = CommandLine.arguments
        args.removeFirst()

        if args.isEmpty {
            printHelp()
            exit(0)
        }

        let command = args.removeFirst()
        if command == "help" || command == "-h" || command == "--help" {
            printHelp()
            exit(0)
        }

        let parsed = parseArgs(args)
        if parsed.flags.contains("--help") {
            printHelp()
            exit(0)
        }

        switch command {
        case "list":
            try cmdList(parsed)
        case "search":
            try cmdSearch(parsed)
        case "show":
            try cmdShow(parsed)
        case "add":
            try cmdAdd(parsed)
        case "update":
            try cmdUpdate(parsed)
        case "delete":
            try cmdDelete(parsed)
        case "export":
            try cmdExport(parsed)
        case "append":
            try cmdAppend(parsed)
        default:
            throw CLIError(message: "Unknown command: \(command)")
        }
    }

    static func cmdList(_ parsed: ParsedArgs) throws {
        let limit = try parseIntOption(parsed, "--limit")
        let folder = try optionValue(parsed, "--folder")
        let account = try optionValue(parsed, "--account")
        let wantsAccounts = parsed.flags.contains("--accounts")
        let wantsFolders = parsed.flags.contains("--folders")
        if wantsAccounts && wantsFolders {
            throw CLIError(message: "list cannot use --accounts and --folders together")
        }

        let store = try openNotesStore(parsed)
        defer { store.close() }

        if wantsAccounts {
            var accounts = store.listAccounts()
            if let limit, accounts.count > limit {
                accounts = Array(accounts.prefix(limit))
            }
            if wantsJSON(parsed) {
                let summaries = accounts.map { AccountSummary(name: $0.name) }
                try outputJSON(summaries)
                return
            }
            for entry in accounts {
                print(entry.name)
            }
            return
        }

        if wantsFolders {
            var folders = store.listFolders(accountName: account)
            if let limit, folders.count > limit {
                folders = Array(folders.prefix(limit))
            }
            if wantsJSON(parsed) {
                let summaries = folders.map { FolderSummary(account: $0.accountName ?? "", name: $0.name) }
                try outputJSON(summaries)
                return
            }
            for folderInfo in folders {
                if let account, !account.isEmpty {
                    print(folderInfo.name)
                } else {
                    let accountName = folderInfo.accountName ?? ""
                    print("\(accountName)\t\(folderInfo.name)")
                }
            }
            return
        }

        let includeTrashed = folder == "Recently Deleted"
        var notes = try store.listNotes(limit: limit, accountName: account, folderName: folder, includeTrashed: includeTrashed)
        if wantsJSON(parsed) {
            let summaries = notes.map { NoteSummary(title: $0.title) }
            try outputJSON(summaries)
            return
        }
        if notes.isEmpty { return }
        for note in notes {
            print(note.title)
        }
    }

    static func cmdSearch(_ parsed: ParsedArgs) throws {
        guard !parsed.positionals.isEmpty else {
            throw CLIError(message: "search requires a query")
        }
        let query = parsed.positionals.joined(separator: " ")
        let limit = try parseIntOption(parsed, "--limit")
        let folder = try optionValue(parsed, "--folder")
        let account = try optionValue(parsed, "--account")
        let includeTrashed = folder == "Recently Deleted"

        let store = try openNotesStore(parsed)
        defer { store.close() }

        let notes = try store.searchNotes(query: query, limit: limit, accountName: account, folderName: folder, includeTrashed: includeTrashed)
        if wantsJSON(parsed) {
            var results: [NoteSearchResult] = []
            results.reserveCapacity(notes.count)
            for note in notes {
                let detail = try store.noteDetail(id: note.id)
                let tags = extractTags(from: detail.body)
                let attachments = detail.attachments.isEmpty ? nil : detail.attachments
                let result = NoteSearchResult(
                    title: detail.title,
                    created: formatDate(detail.created),
                    modified: formatDate(detail.modified),
                    account: detail.account,
                    folder: detail.folder,
                    folderPath: detail.folderPath,
                    shared: detail.shared,
                    folderShared: detail.folderShared,
                    tags: tags.isEmpty ? nil : tags,
                    attachments: attachments
                )
                results.append(result)
            }
            try outputJSON(results)
            return
        }
        if notes.isEmpty { return }
        for note in notes {
            print(note.title)
        }
    }

    static func cmdShow(_ parsed: ParsedArgs) throws {
        let account = try optionValue(parsed, "--account")
        let folder = try optionValue(parsed, "--folder")
        if let _ = try optionValue(parsed, "--title") {
            throw CLIError(message: "show does not accept --title; pass the title as NOTE")
        }

        let store = try openNotesStore(parsed)
        defer { store.close() }

        let noteID = try resolveNotePK(parsed, commandName: "show", selectorTitleOption: nil, account: account, folder: folder, store: store)
        let detail = try store.noteDetail(id: noteID)
        let wantsMarkdown = parsed.flags.contains("--markdown")
        let tags = extractTags(from: detail.body)

        let bodyText: String
        if wantsMarkdown {
            bodyText = markdownFrom(title: detail.title, body: detail.body)
        } else {
            bodyText = detail.body
        }

        if wantsJSON(parsed) {
            let result = NoteDetail(
                title: detail.title,
                created: formatDate(detail.created),
                modified: formatDate(detail.modified),
                account: detail.account,
                folder: detail.folder,
                folderPath: detail.folderPath,
                shared: detail.shared,
                folderShared: detail.folderShared,
                tags: tags.isEmpty ? nil : tags,
                attachments: detail.attachments.isEmpty ? nil : detail.attachments,
                body: bodyText,
                format: wantsMarkdown ? "markdown" : "text",
                assets: nil
            )
            try outputJSON(result)
            return
        }

        if wantsMarkdown {
            print(bodyText)
        } else {
            let plain = formatShowText(
                title: detail.title,
                created: formatDate(detail.created),
                modified: formatDate(detail.modified),
                account: detail.account,
                folder: detail.folder,
                folderPath: detail.folderPath,
                shared: detail.shared,
                folderShared: detail.folderShared,
                tags: tags,
                body: bodyText,
                attachmentCount: detail.attachments.count
            )
            print(plain)
        }
    }

    static func cmdAdd(_ parsed: ParsedArgs) throws {
        let title = parsed.positionals.first
        guard let title, !title.isEmpty else {
            throw CLIError(message: "add requires a title")
        }

        let account = try optionValue(parsed, "--account")
        let folder = try optionValue(parsed, "--folder")

        let body: String
        if let bodyArg = try optionValue(parsed, "--body") {
            body = bodyArg
        } else if !isStdinTTY() {
            body = readStdin()
        } else {
            body = ""
        }

        let output = try AppleScriptWriter.run(AppleScriptWriter.addNote(title: title, body: body, folder: folder, account: account))
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw CLIError(message: "Failed to create note")
        }
        if wantsJSON(parsed) {
            let result = OperationResult(ok: true, action: "add", title: title)
            try outputJSON(result)
            return
        }
        print(title)
    }

    static func cmdUpdate(_ parsed: ParsedArgs) throws {
        let account = try optionValue(parsed, "--account")
        let folder = try optionValue(parsed, "--folder")
        let noteID = try resolveNoteIDForWrite(parsed, commandName: "update", selectorTitleOption: nil, account: account, folder: folder)

        let title = try optionValue(parsed, "--title")

        var body: String? = nil
        var bodyProvided = false
        if parsed.options.keys.contains("--body") || parsed.flags.contains("--body") {
            body = try optionValue(parsed, "--body") ?? ""
            bodyProvided = true
        } else if !isStdinTTY() {
            body = readStdin()
            bodyProvided = true
        }

        if title == nil && !bodyProvided {
            throw CLIError(message: "update requires --title and/or --body")
        }

        let script = AppleScriptWriter.updateNote(
            id: noteID,
            title: title ?? "",
            body: body ?? "",
            updateTitle: title != nil,
            updateBody: bodyProvided
        )
        let output = try AppleScriptWriter.run(script)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw CLIError(message: "Failed to update note")
        }
        if wantsJSON(parsed) {
            let result = OperationResult(ok: true, action: "update", title: title)
            try outputJSON(result)
            return
        }
        if let title {
            print(title)
        } else {
            print("updated")
        }
    }

    static func cmdDelete(_ parsed: ParsedArgs) throws {
        let account = try optionValue(parsed, "--account")
        let folder = try optionValue(parsed, "--folder")
        if let _ = try optionValue(parsed, "--title") {
            throw CLIError(message: "delete does not accept --title; pass the title as NOTE")
        }
        let noteID = try resolveNoteIDForWrite(parsed, commandName: "delete", selectorTitleOption: nil, account: account, folder: folder)

        let script = AppleScriptWriter.deleteNote(id: noteID)
        let output = try AppleScriptWriter.run(script)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw CLIError(message: "Failed to delete note")
        }
        if wantsJSON(parsed) {
            let result = OperationResult(ok: true, action: "delete", title: nil)
            try outputJSON(result)
            return
        }
        print("deleted")
    }

    static func cmdAppend(_ parsed: ParsedArgs) throws {
        let account = try optionValue(parsed, "--account")
        let folder = try optionValue(parsed, "--folder")
        if let _ = try optionValue(parsed, "--title") {
            throw CLIError(message: "append does not accept --title; pass the title as NOTE")
        }
        let noteID = try resolveNoteIDForWrite(parsed, commandName: "append", selectorTitleOption: nil, account: account, folder: folder)

        let text: String
        if let bodyArg = try optionValue(parsed, "--body") {
            text = bodyArg
        } else if parsed.positionals.count > 1 {
            text = parsed.positionals.dropFirst().joined(separator: " ")
        } else if !isStdinTTY() {
            text = readStdin()
        } else {
            throw CLIError(message: "append requires text (use --body, trailing args, or stdin)")
        }

        let currentBody = try AppleScriptWriter.run(AppleScriptWriter.getNoteBody(id: noteID))
        let newBody: String
        if htmlLooksLikeChecklist(currentBody), let updated = appendChecklistItemHTML(currentBody, item: text) {
            newBody = updated
        } else {
            newBody = currentBody + htmlFragmentFromPlainText(text)
        }
        let output = try AppleScriptWriter.run(AppleScriptWriter.setNoteBody(id: noteID, html: newBody))
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw CLIError(message: "Failed to append to note")
        }
        if wantsJSON(parsed) {
            let result = OperationResult(ok: true, action: "append", title: trimmed)
            try outputJSON(result)
            return
        }
        print(trimmed)
    }

    static func cmdExport(_ parsed: ParsedArgs) throws {
        let account = try optionValue(parsed, "--account")
        let folder = try optionValue(parsed, "--folder")
        if let _ = try optionValue(parsed, "--title") {
            throw CLIError(message: "export does not accept --title; pass the title as NOTE")
        }

        let store = try openNotesStore(parsed)
        defer { store.close() }

        let noteID = try resolveNotePK(parsed, commandName: "export", selectorTitleOption: nil, account: account, folder: folder, store: store)
        let detail = try store.noteDetail(id: noteID)
        let wantsMarkdown = parsed.flags.contains("--markdown")

        let content: String
        if wantsMarkdown {
            content = markdownFrom(title: detail.title, body: detail.body)
        } else {
            content = detail.body
        }

        if wantsJSON(parsed) {
            let result = ExportResult(title: detail.title, format: wantsMarkdown ? "markdown" : "text", content: content, assets: nil)
            try outputJSON(result)
            return
        }
        print(content)
    }
}

extension Honeycrisp {
    static func openNotesStore(_ parsed: ParsedArgs) throws -> NotesStore {
        let notesPath = try optionValue(parsed, "--notes-path")
        return try NotesStore.open(notesPath: notesPath)
    }

    static func resolveNotePK(
        _ parsed: ParsedArgs,
        commandName: String,
        selectorTitleOption: String?,
        account: String?,
        folder: String?,
        store: NotesStore
    ) throws -> Int64 {
        if let id = try optionValue(parsed, "--id"), !id.isEmpty {
            if let pk = parseCoreDataID(id) {
                return pk
            }
            if let pk = Int64(id) {
                return pk
            }
            throw CLIError(message: "\(commandName) requires a CoreData id (x-coredata://...) or numeric id for --id")
        }

        if let selector = selectorTitleOption,
           let title = try optionValue(parsed, selector),
           !title.isEmpty {
            return try store.resolveNoteIDByTitle(title, accountName: account, folderName: folder)
        }

        if let positional = parsed.positionals.first, !positional.isEmpty {
            if let pk = parseCoreDataID(positional) {
                return pk
            }
            if let pk = Int64(positional) {
                return pk
            }
            return try store.resolveNoteIDByTitle(positional, accountName: account, folderName: folder)
        }

        if let selector = selectorTitleOption {
            throw CLIError(message: "\(commandName) requires a note id or title (or \(selector) TITLE)")
        }
        throw CLIError(message: "\(commandName) requires a note id or title")
    }

    static func resolveNoteIDForWrite(
        _ parsed: ParsedArgs,
        commandName: String,
        selectorTitleOption: String?,
        account: String?,
        folder: String?
    ) throws -> String {
        if let id = try optionValue(parsed, "--id"), !id.isEmpty {
            return id
        }

        if let selector = selectorTitleOption,
           let title = try optionValue(parsed, selector),
           !title.isEmpty {
            return try resolveNoteIDByTitleForWrite(title, account: account, folder: folder)
        }

        if let positional = parsed.positionals.first, !positional.isEmpty {
            if positional.hasPrefix("x-coredata://") {
                return positional
            }
            return try resolveNoteIDByTitleForWrite(positional, account: account, folder: folder)
        }

        if let selector = selectorTitleOption {
            throw CLIError(message: "\(commandName) requires a note id or title (or \(selector) TITLE)")
        }
        throw CLIError(message: "\(commandName) requires a note id or title")
    }

    static func resolveNoteIDByTitleForWrite(_ title: String, account: String?, folder: String?) throws -> String {
        let script = AppleScriptWriter.findNotesByTitle(title: title, folder: folder, account: account)
        let output = try AppleScriptWriter.run(script)
        let matches = uniqueNotesByID(parseNoteSummaries(output))
        if matches.isEmpty {
            throw CLIError(message: "No note found with title: \(title)")
        }
        if matches.count > 1 {
            var message = "Multiple notes found with title: \(title). Use --id to disambiguate"
            if account == nil && folder == nil {
                message += " or add --account/--folder"
            }
            throw CLIError(message: message)
        }
        return matches[0].id
    }
}
