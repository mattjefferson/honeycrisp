import Foundation
import AppKit
import Darwin

struct ParsedArgs {
    var flags: Set<String> = []
    var options: [String: String] = [:]
    var positionals: [String] = []
}

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

struct AccountEntry {
    let id: String
    let name: String
}

struct FolderEntry {
    let id: String
    let account: String
    let name: String
}

struct NoteDetail: Codable {
    let title: String
    let created: String
    let modified: String
    let body: String
    let format: String?
    let assets: [String]?
}

struct NoteExportDetail: Codable {
    let title: String
    let body: String
}

struct OperationResult: Codable {
    let ok: Bool
    let action: String
    let title: String?
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

struct MarkdownConversionResult {
    let markdown: String
    let assets: [String]
    let hadAttachments: Bool
}

struct MarkdownExportContext {
    let assetsDirPath: String?
    let assetsDirURL: URL?
    let titleSlug: String
    var assets: [String] = []
    var hadAttachments: Bool = false
    var imageIndex: Int = 1
}

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

        if wantsAccounts {
            let output = try AppleScript.run(AppleScript.listAccounts())
            var accounts = uniqueAccountsByID(parseAccountEntries(output))
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
            let output = try AppleScript.run(AppleScript.listFolders(account: account))
            var folders = uniqueFoldersByID(parseFolderEntries(output))
            if let limit, folders.count > limit {
                folders = Array(folders.prefix(limit))
            }
            if wantsJSON(parsed) {
                let summaries = folders.map { FolderSummary(account: $0.account, name: $0.name) }
                try outputJSON(summaries)
                return
            }
            for folderInfo in folders {
                if let account, !account.isEmpty {
                    print(folderInfo.name)
                } else {
                    print("\(folderInfo.account)\t\(folderInfo.name)")
                }
            }
            return
        }

        let script = AppleScript.listNotes(limit: limit, folder: folder, account: account)
        let output = try AppleScript.run(script)
        let notes = uniqueNotesByID(parseNoteSummaries(output))
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

        let script = AppleScript.searchNotes(query: query, limit: limit, folder: folder, account: account)
        let output = try AppleScript.run(script)
        let notes = uniqueNotesByID(parseNoteSummaries(output))
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

    static func cmdShow(_ parsed: ParsedArgs) throws {
        let account = try optionValue(parsed, "--account")
        let folder = try optionValue(parsed, "--folder")
        if let _ = try optionValue(parsed, "--title") {
            throw CLIError(message: "show does not accept --title; pass the title as NOTE")
        }
        let noteID = try resolveNoteID(parsed, commandName: "show", selectorTitleOption: nil, account: account, folder: folder)

        let script = AppleScript.showNote(id: noteID)
        let output = try AppleScript.run(script)
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError(message: "Note not found")
        }
        let detail = try parseNoteDetail(output)
        let wantsMarkdown = parsed.flags.contains("--markdown")
        var assets: [String] = []
        var hadAttachments = false
        let bodyText: String
        let attachmentCount = countEmbeddedImages(detail.body)

        if wantsMarkdown {
            let assetsDirOption = try optionValue(parsed, "--assets-dir")
            let assetsDirPath = resolveAssetsDirPath(option: assetsDirOption, title: detail.title, html: detail.body)
            let conversion = htmlToMarkdown(detail.body, assetsDirPath: assetsDirPath, title: detail.title)
            hadAttachments = conversion.hadAttachments
            assets = conversion.assets
            let cleanedBody = stripLeadingTitleHeading(conversion.markdown, title: detail.title)
            bodyText = markdownFrom(title: detail.title, body: cleanedBody)
            if !wantsJSON(parsed), hadAttachments, let assetsDirPath {
                printErr("Exported \(assets.count) attachment(s) to \(assetsDirPath)")
            }
        } else {
            let treatAsChecklist = htmlLooksLikeChecklist(detail.body)
            bodyText = htmlToPlainText(
                detail.body,
                title: detail.title,
                includeImagePlaceholders: true,
                normalizeLists: treatAsChecklist
            )
        }

        if wantsJSON(parsed) {
            let result = NoteDetail(
                title: detail.title,
                created: detail.created,
                modified: detail.modified,
                body: bodyText,
                format: wantsMarkdown ? "markdown" : "text",
                assets: assets.isEmpty ? nil : assets
            )
            try outputJSON(result)
            return
        }

        if wantsMarkdown {
            print(bodyText)
        } else {
            let plain = formatShowText(
                title: detail.title,
                created: detail.created,
                modified: detail.modified,
                body: bodyText,
                attachmentCount: attachmentCount
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

        let script = AppleScript.addNote(title: title, body: body, folder: folder, account: account)
        let output = try AppleScript.run(script)
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
        let noteID = try resolveNoteID(parsed, commandName: "update", selectorTitleOption: nil, account: account, folder: folder)

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

        let script = AppleScript.updateNote(
            id: noteID,
            title: title ?? "",
            body: body ?? "",
            updateTitle: title != nil,
            updateBody: bodyProvided
        )
        let output = try AppleScript.run(script)
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
        let noteID = try resolveNoteID(parsed, commandName: "delete", selectorTitleOption: nil, account: account, folder: folder)

        let script = AppleScript.deleteNote(id: noteID)
        let output = try AppleScript.run(script)
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
        let noteID = try resolveNoteID(parsed, commandName: "append", selectorTitleOption: nil, account: account, folder: folder)

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

        let currentBody = try AppleScript.run(AppleScript.getNoteBody(id: noteID))
        let newBody: String
        if htmlLooksLikeChecklist(currentBody), let updated = appendChecklistItemHTML(currentBody, item: text) {
            newBody = updated
        } else {
            newBody = currentBody + htmlFragmentFromPlainText(text)
        }
        let output = try AppleScript.run(AppleScript.setNoteBody(id: noteID, html: newBody))
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
        let noteID = try resolveNoteID(parsed, commandName: "export", selectorTitleOption: nil, account: account, folder: folder)

        let script = AppleScript.exportNote(id: noteID)
        let output = try AppleScript.run(script)
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError(message: "Note not found")
        }

        let detail = try parseExportDetail(output)
        let wantsMarkdown = parsed.flags.contains("--markdown")
        let content: String
        var assets: [String] = []
        var hadAttachments = false
        if wantsMarkdown {
            let assetsDirOption = try optionValue(parsed, "--assets-dir")
            let assetsDirPath = resolveAssetsDirPath(option: assetsDirOption, title: detail.title, html: detail.body)
            let conversion = htmlToMarkdown(detail.body, assetsDirPath: assetsDirPath, title: detail.title)
            hadAttachments = conversion.hadAttachments
            assets = conversion.assets
            let cleanedBody = stripLeadingTitleHeading(conversion.markdown, title: detail.title)
            content = markdownFrom(title: detail.title, body: cleanedBody)
            if !wantsJSON(parsed), hadAttachments, let assetsDirPath {
                printErr("Exported \(assets.count) attachment(s) to \(assetsDirPath)")
            }
        } else {
            let treatAsChecklist = htmlLooksLikeChecklist(detail.body)
            content = htmlToPlainText(
                detail.body,
                title: detail.title,
                includeImagePlaceholders: false,
                normalizeLists: treatAsChecklist
            )
        }

        if wantsJSON(parsed) {
            let result = ExportResult(title: detail.title, format: wantsMarkdown ? "markdown" : "text", content: content, assets: assets.isEmpty ? nil : assets)
            try outputJSON(result)
            return
        }
        print(content)
    }

    static func optionValue(_ parsed: ParsedArgs, _ name: String) throws -> String? {
        if parsed.flags.contains(name) {
            throw CLIError(message: "Missing value for \(name)")
        }
        return parsed.options[name]
    }

    static func parseIntOption(_ parsed: ParsedArgs, _ name: String) throws -> Int? {
        guard let value = try optionValue(parsed, name) else { return nil }
        guard let number = Int(value), number >= 0 else {
            throw CLIError(message: "Invalid value for \(name): \(value)")
        }
        return number
    }

    static func resolveNoteID(_ parsed: ParsedArgs, commandName: String, selectorTitleOption: String?, account: String?, folder: String?) throws -> String {
        if let id = try optionValue(parsed, "--id"), !id.isEmpty {
            return id
        }

        if let selector = selectorTitleOption,
           let title = try optionValue(parsed, selector),
           !title.isEmpty {
            return try resolveNoteIDByTitle(title, account: account, folder: folder)
        }

        if let positional = parsed.positionals.first, !positional.isEmpty {
            if positional.hasPrefix("x-coredata://") {
                return positional
            }
            return try resolveNoteIDByTitle(positional, account: account, folder: folder)
        }

        if let selector = selectorTitleOption {
            throw CLIError(message: "\(commandName) requires a note id or title (or \(selector) TITLE)")
        }
        throw CLIError(message: "\(commandName) requires a note id or title")
    }

    static func resolveNoteIDByTitle(_ title: String, account: String?, folder: String?) throws -> String {
        let script = AppleScript.findNotesByTitle(title: title, folder: folder, account: account)
        let output = try AppleScript.run(script)
        let matches = parseNoteSummaries(output)
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

    static func htmlToPlainText(
        _ html: String,
        title: String? = nil,
        includeImagePlaceholders: Bool = false,
        normalizeLists: Bool = false
    ) -> String {
        var normalized = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if includeImagePlaceholders {
            let replaced = replaceImageTagsWithPlaceholders(normalized, title: title ?? "")
            normalized = replaced.html
        }
        guard let data = normalized.data(using: .utf8) else { return normalized }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            let plain = attributed.string
            return normalizeLists ? normalizePlainTextLists(plain) : plain
        }
        return normalized
    }

    static func htmlToMarkdown(_ html: String) -> String {
        return htmlToPlainText(html)
    }

    static func htmlToMarkdown(_ html: String, assetsDirPath: String?, title: String) -> MarkdownConversionResult {
        let normalized = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let data = normalized.data(using: .utf8) else {
            return MarkdownConversionResult(markdown: htmlToPlainText(normalized), assets: [], hadAttachments: false)
        }

        var context = MarkdownExportContext(
            assetsDirPath: assetsDirPath,
            assetsDirURL: assetsDirPath.map { URL(fileURLWithPath: $0, isDirectory: true) },
            titleSlug: slugify(title)
        )

        do {
            let doc = try XMLDocument(data: data, options: [.documentTidyHTML])
            if let root = doc.rootElement() {
                let body = root.elements(forName: "body").first
                let nodes = body?.children ?? root.children ?? []
                let rendered = renderMarkdown(nodes: nodes, context: &context, inline: false, listDepth: 0)
                let markdown = normalizeMarkdown(rendered)
                return MarkdownConversionResult(markdown: markdown, assets: context.assets, hadAttachments: context.hadAttachments)
            }
        } catch {
            return MarkdownConversionResult(markdown: htmlToPlainText(normalized), assets: [], hadAttachments: false)
        }

        return MarkdownConversionResult(markdown: htmlToPlainText(normalized), assets: [], hadAttachments: false)
    }

    static func renderMarkdown(nodes: [XMLNode], context: inout MarkdownExportContext, inline: Bool, listDepth: Int) -> String {
        var result = ""
        for node in nodes {
            result += renderMarkdown(node: node, context: &context, inline: inline, listDepth: listDepth)
        }
        return result
    }

    static func renderMarkdown(node: XMLNode, context: inout MarkdownExportContext, inline: Bool, listDepth: Int) -> String {
        if node.kind == .text {
            return normalizeText(node.stringValue ?? "", inline: inline)
        }
        guard let element = node as? XMLElement else {
            return ""
        }

        let tag = element.name?.lowercased() ?? ""
        switch tag {
        case "br":
            return "\n"
        case "p":
            let content = renderMarkdown(nodes: element.children ?? [], context: &context, inline: true, listDepth: listDepth)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { return "" }
            return "\n\n" + content + "\n\n"
        case "div", "section", "article", "header", "footer", "nav", "address":
            let content = renderMarkdown(nodes: element.children ?? [], context: &context, inline: false, listDepth: listDepth)
            return "\n\n" + content + "\n\n"
        case "span":
            return renderMarkdown(nodes: element.children ?? [], context: &context, inline: inline, listDepth: listDepth)
        case "strong", "b":
            let content = renderMarkdown(nodes: element.children ?? [], context: &context, inline: true, listDepth: listDepth)
            return "**" + content + "**"
        case "em", "i":
            let content = renderMarkdown(nodes: element.children ?? [], context: &context, inline: true, listDepth: listDepth)
            return "*" + content + "*"
        case "code":
            let content = element.stringValue ?? ""
            if let parent = element.parent as? XMLElement, parent.name?.lowercased() == "pre" {
                return content
            }
            return wrapInlineCode(content)
        case "pre":
            let content = element.stringValue ?? ""
            return "\n\n" + wrapCodeBlock(content) + "\n\n"
        case "a":
            let content = renderMarkdown(nodes: element.children ?? [], context: &context, inline: true, listDepth: listDepth)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let href = element.attribute(forName: "href")?.stringValue ?? ""
            if href.isEmpty {
                return content
            }
            let label = content.isEmpty ? href : content
            return "[\(label)](\(href))"
        case "img":
            return renderImage(element, context: &context)
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tag.dropFirst()) ?? 1
            let content = renderMarkdown(nodes: element.children ?? [], context: &context, inline: true, listDepth: listDepth)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { return "" }
            return "\n\n" + String(repeating: "#", count: max(1, min(6, level))) + " " + content + "\n\n"
        case "ul":
            return renderList(element, context: &context, ordered: false, listDepth: listDepth)
        case "ol":
            return renderList(element, context: &context, ordered: true, listDepth: listDepth)
        case "li":
            return renderMarkdown(nodes: element.children ?? [], context: &context, inline: false, listDepth: listDepth)
        case "blockquote":
            let content = renderMarkdown(nodes: element.children ?? [], context: &context, inline: false, listDepth: listDepth)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            return "\n\n" + prefixLines(trimmed, with: "> ") + "\n\n"
        case "hr":
            return "\n\n---\n\n"
        default:
            return renderMarkdown(nodes: element.children ?? [], context: &context, inline: inline, listDepth: listDepth)
        }
    }

    static func renderList(_ element: XMLElement, context: inout MarkdownExportContext, ordered: Bool, listDepth: Int) -> String {
        let items = (element.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.name?.lowercased() == "li" }
        if items.isEmpty { return "" }
        let indent = String(repeating: "  ", count: listDepth)
        var lines: [String] = []
        lines.reserveCapacity(items.count)
        var index = 1
        for li in items {
            let bullet = ordered ? "\(index)." : "-"
            let content = renderMarkdown(nodes: li.children ?? [], context: &context, inline: false, listDepth: listDepth + 1)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                lines.append("\(indent)\(bullet)")
            } else {
                let contentLines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                lines.append("\(indent)\(bullet) \(contentLines[0])")
                if contentLines.count > 1 {
                    let continuationIndent = indent + "  "
                    for line in contentLines.dropFirst() {
                        lines.append("\(continuationIndent)\(line)")
                    }
                }
            }
            index += 1
        }
        return "\n\n" + lines.joined(separator: "\n") + "\n\n"
    }

    static func normalizeText(_ text: String, inline: Bool) -> String {
        let replaced = text.replacingOccurrences(of: "\u{00a0}", with: " ")
        if inline {
            return replaced
        }
        return replaced
    }

    static func wrapInlineCode(_ text: String) -> String {
        let fence = String(repeating: "`", count: maxBacktickRun(text) + 1)
        return "\(fence)\(text)\(fence)"
    }

    static func wrapCodeBlock(_ text: String) -> String {
        let fence = String(repeating: "`", count: maxBacktickRun(text) + 3)
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return "\(fence)\n\(normalized)\n\(fence)"
    }

    static func maxBacktickRun(_ text: String) -> Int {
        var maxRun = 0
        var current = 0
        for ch in text {
            if ch == "`" {
                current += 1
                if current > maxRun { maxRun = current }
            } else {
                current = 0
            }
        }
        return maxRun
    }

    static func prefixLines(_ text: String, with prefix: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.map { prefix + $0 }.joined(separator: "\n")
    }

    static func normalizeMarkdown(_ text: String) -> String {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { rtrim($0) }

        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }

        var normalized: [String] = []
        var emptyCount = 0
        for line in lines {
            if line.isEmpty {
                emptyCount += 1
                if emptyCount <= 1 {
                    normalized.append("")
                }
            } else {
                emptyCount = 0
                normalized.append(line)
            }
        }
        return normalized.joined(separator: "\n")
    }

    static func rtrim(_ line: String) -> String {
        var trimmed = line
        while let last = trimmed.last, last == " " || last == "\t" {
            trimmed.removeLast()
        }
        return trimmed
    }

    static func markdownFrom(title: String, body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleText = title.isEmpty ? "Untitled" : title
        if trimmedBody.isEmpty {
            return "# \(titleText)\n"
        }
        return "# \(titleText)\n\n\(trimmedBody)"
    }

    static func htmlFragmentFromPlainText(_ text: String) -> String {
        let escaped = escapeHTML(text)
        let withBreaks = escaped.replacingOccurrences(of: "\n", with: "<br>")
        return "<div>\(withBreaks)</div>"
    }

    static func escapeHTML(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }

    static func appendChecklistItemHTML(_ html: String, item: String) -> String? {
        let normalized = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let data = normalized.data(using: .utf8) else { return nil }
        do {
            let doc = try XMLDocument(data: data, options: [.documentTidyHTML])
            guard let root = doc.rootElement() else { return nil }
            let body = root.elements(forName: "body").first ?? root
            guard let ul = findLastElement(named: "ul", in: body) else { return nil }
            let li = XMLElement(name: "li", stringValue: item)
            ul.addChild(li)
            return innerHTML(of: body)
        } catch {
            return nil
        }
    }

    static func findLastElement(named name: String, in element: XMLElement) -> XMLElement? {
        var last: XMLElement?
        if element.name?.lowercased() == name {
            last = element
        }
        for child in element.children ?? [] {
            if let childElement = child as? XMLElement {
                if let found = findLastElement(named: name, in: childElement) {
                    last = found
                }
            }
        }
        return last
    }

    static func innerHTML(of element: XMLElement) -> String {
        guard let children = element.children else { return "" }
        return children.map { $0.xmlString }.joined()
    }

    static func formatShowText(title: String, created: String, modified: String, body: String, attachmentCount: Int) -> String {
        var lines: [String] = []
        lines.append("name:\t\(title)")
        lines.append("created:\t\(created)")
        lines.append("modified:\t\(modified)")
        if attachmentCount > 0 {
            lines.append("attachments:\t\(attachmentCount)")
        }
        lines.append("")
        lines.append(body)
        return lines.joined(separator: "\n")
    }

    static func renderImage(_ element: XMLElement, context: inout MarkdownExportContext) -> String {
        let alt = element.attribute(forName: "alt")?.stringValue ?? ""
        let src = element.attribute(forName: "src")?.stringValue ?? ""
        if src.isEmpty {
            return alt
        }

        let normalizedSrc = src.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSrc.hasPrefix("data:image/") {
            context.hadAttachments = true
            if let assetsDirURL = context.assetsDirURL,
               let saved = writeEmbeddedImage(src: normalizedSrc, context: &context, assetsDirURL: assetsDirURL) {
                return "![\(alt)](\(saved))"
            }
            return "[attachment omitted]"
        }

        return "![\(alt)](\(normalizedSrc))"
    }

    static func writeEmbeddedImage(src: String, context: inout MarkdownExportContext, assetsDirURL: URL) -> String? {
        guard let commaIndex = src.firstIndex(of: ",") else { return nil }
        let metadata = String(src[..<commaIndex])
        let dataPart = String(src[src.index(after: commaIndex)...])
        let parts = metadata.split(separator: ";")
        guard let mimePart = parts.first, mimePart.hasPrefix("data:image/") else { return nil }
        let mime = String(mimePart.replacingOccurrences(of: "data:", with: ""))

        let ext: String
        if mime.contains("png") {
            ext = "png"
        } else if mime.contains("jpeg") || mime.contains("jpg") {
            ext = "jpg"
        } else if mime.contains("gif") {
            ext = "gif"
        } else {
            ext = "bin"
        }

        let sanitizedBase = context.titleSlug.isEmpty ? "note" : context.titleSlug
        let filename = "\(sanitizedBase)-\(context.imageIndex).\(ext)"
        context.imageIndex += 1

        let outputURL = assetsDirURL.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: assetsDirURL, withIntermediateDirectories: true)
            let cleaned = dataPart.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            guard let data = Data(base64Encoded: cleaned) else { return nil }
            try data.write(to: outputURL, options: .atomic)
            let relPath = context.assetsDirPath.map { "\($0)/\(filename)" } ?? filename
            context.assets.append(relPath)
            return relPath
        } catch {
            return nil
        }
    }

    static func resolveAssetsDirPath(option: String?, title: String, html: String) -> String? {
        if let option, !option.isEmpty {
            return option
        }
        guard htmlHasEmbeddedImages(html) else {
            return nil
        }
        let slug = slugify(title)
        let dirName = slug.isEmpty ? "note-assets" : "\(slug)-assets"
        return dirName
    }

    static func htmlHasEmbeddedImages(_ html: String) -> Bool {
        return html.contains("data:image/")
    }

    static func slugify(_ value: String) -> String {
        let lower = value.lowercased()
        var result = ""
        var previousDash = false
        for scalar in lower.unicodeScalars {
            if ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar)) {
                result.append(Character(scalar))
                previousDash = false
            } else if scalar == "-" || scalar == "_" || scalar == " " {
                if !previousDash {
                    result.append("-")
                    previousDash = true
                }
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func replaceImageTagsWithPlaceholders(_ html: String, title: String) -> (html: String, names: [String]) {
        let slug = slugify(title)
        var index = 1
        var names: [String] = []
        var output = ""
        var searchRange = html.startIndex..<html.endIndex

        while let range = html.range(of: "<img", options: [.caseInsensitive], range: searchRange) {
            output += String(html[searchRange.lowerBound..<range.lowerBound])
            guard let tagEnd = html[range.lowerBound..<html.endIndex].firstIndex(of: ">") else {
                output += String(html[range.lowerBound..<html.endIndex])
                searchRange = html.endIndex..<html.endIndex
                break
            }

            let tag = String(html[range.lowerBound...tagEnd])
            let ext = imageExtension(fromImgTag: tag)
            let base = slug.isEmpty ? "note" : slug
            let name = "\(base)-\(index).\(ext)"
            index += 1
            names.append(name)
            output += "<p>[image: \(name)]</p>"
            searchRange = html.index(after: tagEnd)..<html.endIndex
        }

        if searchRange.lowerBound < html.endIndex {
            output += String(html[searchRange.lowerBound..<html.endIndex])
        }

        return (output, names)
    }

    static func imageExtension(fromImgTag tag: String) -> String {
        let lower = tag.lowercased()
        if lower.contains("data:image/png") { return "png" }
        if lower.contains("data:image/jpeg") { return "jpg" }
        if lower.contains("data:image/jpg") { return "jpg" }
        if lower.contains("data:image/gif") { return "gif" }
        return "png"
    }

    static func countEmbeddedImages(_ html: String) -> Int {
        var count = 0
        var searchRange = html.startIndex..<html.endIndex
        while let range = html.range(of: "<img", options: [.caseInsensitive], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<html.endIndex
        }
        return count
    }

    static func normalizePlainTextLists(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var output: [String] = []
        output.reserveCapacity(lines.count)

        for raw in lines {
            let line = String(raw)
            if let normalized = normalizeBulletLine(line) {
                output.append(normalized)
            } else {
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
    }

    static func htmlLooksLikeChecklist(_ html: String) -> Bool {
        let normalized = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let data = normalized.data(using: .utf8) else { return false }
        do {
            let doc = try XMLDocument(data: data, options: [.documentTidyHTML])
            let root = doc.rootElement()
            let nodes = root?.elements(forName: "body").first?.children ?? root?.children ?? []
            var listCount = 0
            var otherCount = 0
            countChecklistText(nodes, inList: false, ignoreText: false, listCount: &listCount, otherCount: &otherCount)
            if listCount == 0 { return false }
            if otherCount == 0 { return true }
            return listCount >= otherCount * 2
        } catch {
            return false
        }
    }

    static func countChecklistText(
        _ nodes: [XMLNode],
        inList: Bool,
        ignoreText: Bool,
        listCount: inout Int,
        otherCount: inout Int
    ) {
        for node in nodes {
            if node.kind == .text {
                let trimmed = node.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if trimmed.isEmpty { continue }
                if ignoreText { continue }
                if inList {
                    listCount += 1
                } else {
                    otherCount += 1
                }
                continue
            }
            guard let element = node as? XMLElement else { continue }
            let tag = element.name?.lowercased() ?? ""
            let isListTag = tag == "ul" || tag == "ol" || tag == "li"
            let nextInList = inList || isListTag
            let nextIgnoreText = ignoreText || tag.hasPrefix("h")
            countChecklistText(
                element.children ?? [],
                inList: nextInList,
                ignoreText: nextIgnoreText,
                listCount: &listCount,
                otherCount: &otherCount
            )
        }
    }

    static func normalizeBulletLine(_ line: String) -> String? {
        let whitespace = CharacterSet.whitespacesAndNewlines
        let trimmed = line.trimmingCharacters(in: whitespace)
        guard !trimmed.isEmpty else { return nil }

        let bulletSymbols: [Character] = ["•", "◦", "‣", "∙", "·"]
        guard let first = trimmed.first, bulletSymbols.contains(first) else { return nil }

        let indentLevel = line.prefix { $0 == "\t" || $0 == " " }.filter { $0 == "\t" }.count
        let indent = String(repeating: "  ", count: indentLevel)

        let afterBullet = trimmed.dropFirst().trimmingCharacters(in: whitespace)
        let prefix = "[ ]"
        if afterBullet.isEmpty {
            return "\(indent)\(prefix)"
        }
        return "\(indent)\(prefix) \(afterBullet)"
    }

    static func stripLeadingTitleHeading(_ markdown: String, title: String) -> String {
        let normalizedTitle = normalizeTitleText(title)
        if normalizedTitle.isEmpty {
            return markdown
        }

        var lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var i = 0
        while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
            i += 1
        }

        guard i < lines.count else { return markdown }
        let firstLineTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
        guard let firstHeading = extractHeadingText(firstLineTrimmed) else {
            return markdown
        }

        let firstLevel = headingLevel(firstLineTrimmed)
        var headingIndices: [Int] = [i]
        var textParts: [String] = []
        if !firstHeading.isEmpty {
            textParts.append(firstHeading)
        }

        var j = i + 1
        while j < lines.count {
            let trimmed = lines[j].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                headingIndices.append(j)
                j += 1
                continue
            }
            guard let headingText = extractHeadingText(trimmed) else {
                break
            }
            if headingLevel(trimmed) != firstLevel {
                break
            }
            headingIndices.append(j)
            if !headingText.isEmpty {
                textParts.append(headingText)
            }
            j += 1
        }

        if textParts.isEmpty {
            return markdown
        }

        let joinedSpace = normalizeTitleText(textParts.joined(separator: " "))
        let joinedNoSpace = normalizeTitleText(textParts.joined())
        if joinedSpace != normalizedTitle && joinedNoSpace != normalizedTitle {
            return markdown
        }

        for index in headingIndices.reversed() {
            lines.remove(at: index)
        }
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    static func extractHeadingText(_ line: String) -> String? {
        guard line.first == "#" else { return nil }
        let hashCount = headingLevel(line)
        let index = line.index(line.startIndex, offsetBy: hashCount)
        let remainder = line[index...].trimmingCharacters(in: .whitespaces)
        if remainder.isEmpty {
            return ""
        }
        return remainder
    }

    static func headingLevel(_ line: String) -> Int {
        var hashCount = 0
        for ch in line {
            if ch == "#" {
                hashCount += 1
            } else {
                break
            }
        }
        return hashCount
    }

    static func normalizeTitleText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let parts = trimmed
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map { $0.lowercased() }
        return parts.joined(separator: " ")
    }

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

    static func parseNoteSummaries(_ output: String) -> [NoteMatch] {
        let lines = output.split(whereSeparator: \.isNewline)
        var results: [NoteMatch] = []
        results.reserveCapacity(lines.count)
        for lineSub in lines {
            let line = String(lineSub)
            guard let tabIndex = line.firstIndex(of: "\t") else {
                continue
            }
            let id = String(line[..<tabIndex])
            let title = String(line[line.index(after: tabIndex)...])
            results.append(NoteMatch(id: id, title: title))
        }
        return results
    }

    static func parseAccountEntries(_ output: String) -> [AccountEntry] {
        let lines = output.split(whereSeparator: \.isNewline)
        var results: [AccountEntry] = []
        results.reserveCapacity(lines.count)
        for lineSub in lines {
            let line = String(lineSub)
            guard let tabIndex = line.firstIndex(of: "\t") else { continue }
            let id = String(line[..<tabIndex])
            let name = String(line[line.index(after: tabIndex)...])
            results.append(AccountEntry(id: id, name: name))
        }
        return results
    }

    static func parseFolderEntries(_ output: String) -> [FolderEntry] {
        let lines = output.split(whereSeparator: \.isNewline)
        var results: [FolderEntry] = []
        results.reserveCapacity(lines.count)
        for lineSub in lines {
            let line = String(lineSub)
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let id = String(parts[0])
            let account = String(parts[1])
            let name = String(parts[2])
            results.append(FolderEntry(id: id, account: account, name: name))
        }
        return results
    }

    static func uniqueAccountsByID(_ accounts: [AccountEntry]) -> [AccountEntry] {
        var seen: Set<String> = []
        var unique: [AccountEntry] = []
        unique.reserveCapacity(accounts.count)
        for account in accounts {
            if seen.insert(account.id).inserted {
                unique.append(account)
            }
        }
        return unique
    }

    static func uniqueFoldersByID(_ folders: [FolderEntry]) -> [FolderEntry] {
        var seen: Set<String> = []
        var unique: [FolderEntry] = []
        unique.reserveCapacity(folders.count)
        for folder in folders {
            if seen.insert(folder.id).inserted {
                unique.append(folder)
            }
        }
        return unique
    }

    static func uniqueNotesByID(_ notes: [NoteMatch]) -> [NoteMatch] {
        var seen: Set<String> = []
        var unique: [NoteMatch] = []
        unique.reserveCapacity(notes.count)
        for note in notes {
            if seen.insert(note.id).inserted {
                unique.append(note)
            }
        }
        return unique
    }

    static func parseNoteDetail(_ output: String) throws -> NoteDetail {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3 else {
            throw CLIError(message: "Invalid note detail output")
        }

        func stripPrefix(_ line: String, _ prefix: String) -> String {
            guard line.hasPrefix(prefix) else { return line }
            return String(line.dropFirst(prefix.count))
        }

        var index = 0
        if lines[0].hasPrefix("id:\t") {
            index += 1
        }
        guard index + 2 < lines.count else {
            throw CLIError(message: "Invalid note detail output")
        }

        let title = stripPrefix(lines[index], "name:\t")
        let created = stripPrefix(lines[index + 1], "created:\t")
        let modified = stripPrefix(lines[index + 2], "modified:\t")

        var bodyStart = index + 3
        if lines.count > bodyStart, lines[bodyStart].isEmpty {
            bodyStart += 1
        }
        let body = bodyStart < lines.count ? lines[bodyStart...].joined(separator: "\n") : ""

        if title.isEmpty {
            throw CLIError(message: "Invalid note detail output")
        }
        return NoteDetail(title: title, created: created, modified: modified, body: body, format: nil, assets: nil)
    }

    static func parseExportDetail(_ output: String) throws -> NoteExportDetail {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 1 else {
            throw CLIError(message: "Invalid export output")
        }

        func stripPrefix(_ line: String, _ prefix: String) -> String {
            guard line.hasPrefix(prefix) else { return line }
            return String(line.dropFirst(prefix.count))
        }

        var index = 0
        if lines[0].hasPrefix("id:\t") {
            index += 1
        }
        guard index < lines.count else {
            throw CLIError(message: "Invalid export output")
        }
        let title = stripPrefix(lines[index], "name:\t")

        var bodyStart = index + 1
        if lines.count > bodyStart, lines[bodyStart].isEmpty {
            bodyStart += 1
        }
        let body = bodyStart < lines.count ? lines[bodyStart...].joined(separator: "\n") : ""

        if title.isEmpty {
            throw CLIError(message: "Invalid export output")
        }
        return NoteExportDetail(title: title, body: body)
    }

    static func parseArgs(_ args: [String]) -> ParsedArgs {
        var parsed = ParsedArgs()
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--" {
                if i + 1 < args.count {
                    parsed.positionals.append(contentsOf: args[(i + 1)...])
                }
                break
            }

            if arg == "-h" {
                parsed.flags.insert("--help")
                i += 1
                continue
            }
            if arg == "-j" {
                parsed.flags.insert("--json")
                i += 1
                continue
            }
            if arg == "-m" {
                parsed.flags.insert("--markdown")
                i += 1
                continue
            }

            if arg.hasPrefix("--") {
                let trimmed = String(arg.dropFirst(2))
                if let eqIndex = trimmed.firstIndex(of: "=") {
                    let name = "--" + String(trimmed[..<eqIndex])
                    let value = String(trimmed[trimmed.index(after: eqIndex)...])
                    parsed.options[name] = value
                } else if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                    parsed.options["--" + trimmed] = args[i + 1]
                    i += 1
                } else {
                    parsed.flags.insert("--" + trimmed)
                }
                i += 1
                continue
            }

            if arg.hasPrefix("-") {
                parsed.flags.insert(arg)
                i += 1
                continue
            }

            parsed.positionals.append(arg)
            i += 1
        }

        return parsed
    }

    static func isStdinTTY() -> Bool {
        return isatty(STDIN_FILENO) != 0
    }

    static func readStdin() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func printErr(_ message: String) {
        if let data = (message + "\n").data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    static func printHelp() {
        let help = """
Honeycrisp - Apple Notes CLI

Usage:
  honeycrisp list [--account NAME] [--folder NAME] [--limit N] [--json]
  honeycrisp list --accounts [--limit N] [--json]
  honeycrisp list --folders [--account NAME] [--limit N] [--json]
  honeycrisp search QUERY [--account NAME] [--folder NAME] [--limit N] [--json]
  honeycrisp show NOTE [--account NAME] [--folder NAME] [--markdown] [--assets-dir PATH] [--json]
  honeycrisp add TITLE [--account NAME] [--folder NAME] [--body TEXT] [--json]
  honeycrisp add TITLE [--account NAME] [--folder NAME] [--json] < body.txt
  honeycrisp update NOTE [--title TEXT] [--body TEXT] [--account NAME] [--folder NAME] [--json]
  honeycrisp update NOTE [--title TEXT] [--account NAME] [--folder NAME] [--json] < body.txt
  honeycrisp append NOTE TEXT [--account NAME] [--folder NAME] [--body TEXT] [--json]
  honeycrisp append NOTE [--account NAME] [--folder NAME] [--json] < body.txt
  honeycrisp delete NOTE [--account NAME] [--folder NAME] [--json]
  honeycrisp export NOTE [--account NAME] [--folder NAME] [--markdown] [--assets-dir PATH] [--json]

Output:
  list/search: one title per line
  add: prints the new note title
  update: prints the new title if provided, otherwise "updated"
  delete: prints "deleted"
  append: prints the note title
  --json: structured output
  --markdown: export as markdown
  --assets-dir: export embedded images to a folder

Notes:
  NOTE can be a note id (x-coredata://...) or an exact title.
  If multiple notes share a title, use --id or add --account/--folder to narrow.
  For update, NOTE selects the note and --title sets the new title.
  Notes in "Recently Deleted" are excluded unless you pass --folder "Recently Deleted".
"""
        print(help)
    }
}

enum AppleScript {
    static func run(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw CLIError(message: "Failed to compile AppleScript")
        }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            throw CLIError(message: message)
        }
        if let value = output.stringValue {
            return value
        }
        return ""
    }

    static func listNotes(limit: Int?, folder: String?, account: String?) -> String {
        let limitValue = limit ?? 0
        let folderExpr = asAppleScriptStringExpr(folder ?? "")
        let accountExpr = asAppleScriptStringExpr(account ?? "")

        return """
        set limitCount to \(limitValue)
        set folderName to \(folderExpr)
        set accountName to \(accountExpr)
        set includeDeleted to false
        if folderName is "Recently Deleted" then
            set includeDeleted to true
        end if
        tell application "Notes"
            set deletedIDs to {}
            if not includeDeleted then
                if accountName is not "" then
                    try
                        set deletedFolder to first folder of account accountName whose name is "Recently Deleted"
                        repeat with dn in notes of deletedFolder
                            set end of deletedIDs to (id of dn)
                        end repeat
                    end try
                else
                    repeat with acc in accounts
                        try
                            set deletedFolder to first folder of acc whose name is "Recently Deleted"
                            repeat with dn in notes of deletedFolder
                                set end of deletedIDs to (id of dn)
                            end repeat
                        end try
                    end repeat
                end if
            end if
            set targetNotes to notes
            if accountName is not "" then
                set targetNotes to notes of account accountName
            end if
            if folderName is not "" then
                if accountName is not "" then
                    set targetNotes to notes of folder folderName of account accountName
                else
                    set matched to {}
                    repeat with acc in accounts
                        repeat with f in folders of acc
                            if name of f is folderName then
                                set matched to matched & (notes of f)
                            end if
                        end repeat
                    end repeat
                    set targetNotes to matched
                end if
            end if
            set outputLines to {}
            repeat with n in targetNotes
                set noteID to id of n
                if includeDeleted or (noteID is not in deletedIDs) then
                    set end of outputLines to ((noteID) & tab & (name of n))
                end if
                if (limitCount > 0) and ((count of outputLines) is greater than or equal to limitCount) then exit repeat
            end repeat
            set AppleScript's text item delimiters to linefeed
            return outputLines as text
        end tell
        """
    }

    static func searchNotes(query: String, limit: Int?, folder: String?, account: String?) -> String {
        let limitValue = limit ?? 0
        let queryExpr = asAppleScriptStringExpr(query)
        let folderExpr = asAppleScriptStringExpr(folder ?? "")
        let accountExpr = asAppleScriptStringExpr(account ?? "")

        return """
        set limitCount to \(limitValue)
        set queryText to \(queryExpr)
        set folderName to \(folderExpr)
        set accountName to \(accountExpr)
        set includeDeleted to false
        if folderName is "Recently Deleted" then
            set includeDeleted to true
        end if
        tell application "Notes"
            set deletedIDs to {}
            if not includeDeleted then
                if accountName is not "" then
                    try
                        set deletedFolder to first folder of account accountName whose name is "Recently Deleted"
                        repeat with dn in notes of deletedFolder
                            set end of deletedIDs to (id of dn)
                        end repeat
                    end try
                else
                    repeat with acc in accounts
                        try
                            set deletedFolder to first folder of acc whose name is "Recently Deleted"
                            repeat with dn in notes of deletedFolder
                                set end of deletedIDs to (id of dn)
                            end repeat
                        end try
                    end repeat
                end if
            end if
            set targetNotes to notes
            if accountName is not "" then
                set targetNotes to notes of account accountName
            end if
            if folderName is not "" then
                if accountName is not "" then
                    set targetNotes to notes of folder folderName of account accountName
                else
                    set matched to {}
                    repeat with acc in accounts
                        repeat with f in folders of acc
                            if name of f is folderName then
                                set matched to matched & (notes of f)
                            end if
                        end repeat
                    end repeat
                    set targetNotes to matched
                end if
            end if
            set outputLines to {}
            repeat with n in targetNotes
                if ((name of n) contains queryText) or ((body of n) contains queryText) then
                    set noteID to id of n
                    if includeDeleted or (noteID is not in deletedIDs) then
                        set end of outputLines to ((noteID) & tab & (name of n))
                    end if
                    if (limitCount > 0) and ((count of outputLines) is greater than or equal to limitCount) then exit repeat
                end if
            end repeat
            set AppleScript's text item delimiters to linefeed
            return outputLines as text
        end tell
        """
    }

    static func showNote(id: String) -> String {
        let idExpr = asAppleScriptStringExpr(id)
        return """
        set noteID to \(idExpr)
        tell application "Notes"
            set theNote to first note whose id is noteID
            set outputLines to {}
            set end of outputLines to ("name:\t" & (name of theNote))
            set end of outputLines to ("created:\t" & ((creation date of theNote) as text))
            set end of outputLines to ("modified:\t" & ((modification date of theNote) as text))
            set end of outputLines to ""
            set end of outputLines to ((body of theNote) as text)
            set AppleScript's text item delimiters to linefeed
            return outputLines as text
        end tell
        """
    }

    static func addNote(title: String, body: String, folder: String?, account: String?) -> String {
        let titleExpr = asAppleScriptStringExpr(title)
        let bodyExpr = asAppleScriptStringExpr(body)
        let folderExpr = asAppleScriptStringExpr(folder ?? "")
        let accountExpr = asAppleScriptStringExpr(account ?? "")

        return """
        set titleText to \(titleExpr)
        set bodyText to \(bodyExpr)
        set folderName to \(folderExpr)
        set accountName to \(accountExpr)
        tell application "Notes"
            if accountName is not "" then
                set acc to account accountName
            else
                set acc to first account
            end if
            if folderName is not "" then
                set newNote to make new note at folder folderName of acc with properties {name:titleText, body:bodyText}
            else
                set newNote to make new note at acc with properties {name:titleText, body:bodyText}
            end if
            return id of newNote
        end tell
        """
    }

    static func updateNote(id: String, title: String, body: String, updateTitle: Bool, updateBody: Bool) -> String {
        let idExpr = asAppleScriptStringExpr(id)
        let titleExpr = asAppleScriptStringExpr(title)
        let bodyExpr = asAppleScriptStringExpr(body)
        let updateTitleExpr = updateTitle ? "true" : "false"
        let updateBodyExpr = updateBody ? "true" : "false"

        return """
        set noteID to \(idExpr)
        set titleText to \(titleExpr)
        set bodyText to \(bodyExpr)
        set shouldUpdateTitle to \(updateTitleExpr)
        set shouldUpdateBody to \(updateBodyExpr)
        tell application "Notes"
            set theNote to first note whose id is noteID
            if shouldUpdateTitle then
                set name of theNote to titleText
            end if
            if shouldUpdateBody then
                set body of theNote to bodyText
            end if
            return id of theNote
        end tell
        """
    }

    static func deleteNote(id: String) -> String {
        let idExpr = asAppleScriptStringExpr(id)
        return """
        set noteID to \(idExpr)
        tell application "Notes"
            set theNote to first note whose id is noteID
            delete theNote
            return noteID
        end tell
        """
    }

    static func findNotesByTitle(title: String, folder: String?, account: String?) -> String {
        let titleExpr = asAppleScriptStringExpr(title)
        let folderExpr = asAppleScriptStringExpr(folder ?? "")
        let accountExpr = asAppleScriptStringExpr(account ?? "")

        return """
        set titleText to \(titleExpr)
        set folderName to \(folderExpr)
        set accountName to \(accountExpr)
        set includeDeleted to false
        if folderName is "Recently Deleted" then
            set includeDeleted to true
        end if
        tell application "Notes"
            set deletedIDs to {}
            if not includeDeleted then
                if accountName is not "" then
                    try
                        set deletedFolder to first folder of account accountName whose name is "Recently Deleted"
                        repeat with dn in notes of deletedFolder
                            set end of deletedIDs to (id of dn)
                        end repeat
                    end try
                else
                    repeat with acc in accounts
                        try
                            set deletedFolder to first folder of acc whose name is "Recently Deleted"
                            repeat with dn in notes of deletedFolder
                                set end of deletedIDs to (id of dn)
                            end repeat
                        end try
                    end repeat
                end if
            end if
            set targetNotes to notes
            if accountName is not "" then
                set targetNotes to notes of account accountName
            end if
            if folderName is not "" then
                if accountName is not "" then
                    set targetNotes to notes of folder folderName of account accountName
                else
                    set matched to {}
                    repeat with acc in accounts
                        repeat with f in folders of acc
                            if name of f is folderName then
                                set matched to matched & (notes of f)
                            end if
                        end repeat
                    end repeat
                    set targetNotes to matched
                end if
            end if
            set outputLines to {}
            repeat with n in targetNotes
                if (name of n) is titleText then
                    set noteID to id of n
                    if includeDeleted or (noteID is not in deletedIDs) then
                        set end of outputLines to ((noteID) & tab & (name of n))
                    end if
                end if
            end repeat
            set AppleScript's text item delimiters to linefeed
            return outputLines as text
        end tell
        """
    }

    static func exportNote(id: String) -> String {
        let idExpr = asAppleScriptStringExpr(id)
        return """
        set noteID to \(idExpr)
        tell application "Notes"
            set theNote to first note whose id is noteID
            set outputLines to {}
            set end of outputLines to ("name:\t" & (name of theNote))
            set end of outputLines to ""
            set end of outputLines to ((body of theNote) as text)
            set AppleScript's text item delimiters to linefeed
            return outputLines as text
        end tell
        """
    }

    static func getNoteBody(id: String) -> String {
        let idExpr = asAppleScriptStringExpr(id)
        return """
        set noteID to \(idExpr)
        tell application "Notes"
            set theNote to first note whose id is noteID
            return (body of theNote) as text
        end tell
        """
    }

    static func setNoteBody(id: String, html: String) -> String {
        let idExpr = asAppleScriptStringExpr(id)
        let htmlExpr = asAppleScriptStringExpr(html)
        return """
        set noteID to \(idExpr)
        set htmlFragment to \(htmlExpr)
        tell application "Notes"
            set theNote to first note whose id is noteID
            set body of theNote to htmlFragment
            return name of theNote
        end tell
        """
    }

    static func listAccounts() -> String {
        return """
        tell application "Notes"
            set outputLines to {}
            repeat with acc in accounts
                set end of outputLines to ((id of acc) & tab & (name of acc))
            end repeat
            set AppleScript's text item delimiters to linefeed
            return outputLines as text
        end tell
        """
    }

    static func listFolders(account: String?) -> String {
        let accountExpr = asAppleScriptStringExpr(account ?? "")
        return """
        set accountName to \(accountExpr)
        tell application "Notes"
            set outputLines to {}
            if accountName is not "" then
                repeat with f in folders of account accountName
                    set end of outputLines to ((id of f) & tab & accountName & tab & (name of f))
                end repeat
            else
                repeat with acc in accounts
                    repeat with f in folders of acc
                        set end of outputLines to ((id of f) & tab & (name of acc) & tab & (name of f))
                    end repeat
                end repeat
            end if
            set AppleScript's text item delimiters to linefeed
            return outputLines as text
        end tell
        """
    }

    static func asAppleScriptStringExpr(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let parts = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        if parts.count == 1 {
            return "\"\(escapeAppleScript(parts[0]))\""
        }
        return parts.map { "\"\(escapeAppleScript($0))\"" }.joined(separator: " & linefeed & ")
    }

    static func escapeAppleScript<S: StringProtocol>(_ value: S) -> String {
        var text = String(value)
        text = text.replacingOccurrences(of: "\\", with: "\\\\")
        text = text.replacingOccurrences(of: "\"", with: "\\\"")
        return text
    }
}
