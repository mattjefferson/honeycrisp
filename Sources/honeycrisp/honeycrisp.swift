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
    let id: String
    let title: String
}

struct NoteDetail: Codable {
    let id: String
    let title: String
    let created: String
    let modified: String
    let body: String
}

struct NoteExportDetail: Codable {
    let id: String
    let title: String
    let body: String
}

struct OperationResult: Codable {
    let id: String
    let ok: Bool
    let action: String
}

struct ExportResult: Codable {
    let id: String
    let title: String
    let format: String
    let content: String
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
        default:
            throw CLIError(message: "Unknown command: \(command)")
        }
    }

    static func cmdList(_ parsed: ParsedArgs) throws {
        let limit = try parseIntOption(parsed, "--limit")
        let folder = try optionValue(parsed, "--folder")
        let account = try optionValue(parsed, "--account")

        let script = AppleScript.listNotes(limit: limit, folder: folder, account: account)
        let output = try AppleScript.run(script)
        if wantsJSON(parsed) {
            let notes = parseNoteSummaries(output)
            try outputJSON(notes)
            return
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        print(output)
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
        if wantsJSON(parsed) {
            let notes = parseNoteSummaries(output)
            try outputJSON(notes)
            return
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        print(output)
    }

    static func cmdShow(_ parsed: ParsedArgs) throws {
        let account = try optionValue(parsed, "--account")
        let folder = try optionValue(parsed, "--folder")
        let noteID = try resolveNoteID(parsed, commandName: "show", selectorTitleOption: "--title", account: account, folder: folder)

        let script = AppleScript.showNote(id: noteID)
        let output = try AppleScript.run(script)
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError(message: "Note not found")
        }
        if wantsJSON(parsed) {
            let detail = try parseNoteDetail(output)
            try outputJSON(detail)
            return
        }
        print(output)
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
            let result = OperationResult(id: trimmed, ok: true, action: "add")
            try outputJSON(result)
            return
        }
        print(trimmed)
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
            let result = OperationResult(id: trimmed, ok: true, action: "update")
            try outputJSON(result)
            return
        }
        print(trimmed)
    }

    static func cmdDelete(_ parsed: ParsedArgs) throws {
        let account = try optionValue(parsed, "--account")
        let folder = try optionValue(parsed, "--folder")
        let noteID = try resolveNoteID(parsed, commandName: "delete", selectorTitleOption: "--title", account: account, folder: folder)

        let script = AppleScript.deleteNote(id: noteID)
        let output = try AppleScript.run(script)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw CLIError(message: "Failed to delete note")
        }
        if wantsJSON(parsed) {
            let result = OperationResult(id: trimmed, ok: true, action: "delete")
            try outputJSON(result)
            return
        }
        print(trimmed)
    }

    static func cmdExport(_ parsed: ParsedArgs) throws {
        let account = try optionValue(parsed, "--account")
        let folder = try optionValue(parsed, "--folder")
        let noteID = try resolveNoteID(parsed, commandName: "export", selectorTitleOption: "--title", account: account, folder: folder)

        let script = AppleScript.exportNote(id: noteID)
        let output = try AppleScript.run(script)
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError(message: "Note not found")
        }

        let detail = try parseExportDetail(output)
        let wantsMarkdown = parsed.flags.contains("--markdown")
        let content: String
        if wantsMarkdown {
            let bodyMarkdown = htmlToMarkdown(detail.body)
            let cleanedBody = stripLeadingTitleHeading(bodyMarkdown, title: detail.title)
            content = markdownFrom(title: detail.title, body: cleanedBody)
        } else {
            content = htmlToPlainText(detail.body)
        }

        if wantsJSON(parsed) {
            let result = ExportResult(id: detail.id, title: detail.title, format: wantsMarkdown ? "markdown" : "text", content: content)
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
            let ids = matches.prefix(5).map { $0.id }
            var message = "Multiple notes found with title: \(title). Use --id to disambiguate"
            if account == nil && folder == nil {
                message += " or add --account/--folder"
            }
            if !ids.isEmpty {
                message += ". Matches: " + ids.joined(separator: ", ")
            }
            throw CLIError(message: message)
        }
        return matches[0].id
    }

    static func htmlToPlainText(_ html: String) -> String {
        let normalized = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let data = normalized.data(using: .utf8) else { return normalized }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return normalized
    }

    static func htmlToMarkdown(_ html: String) -> String {
        let normalized = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let data = normalized.data(using: .utf8) else {
            return htmlToPlainText(normalized)
        }
        do {
            let doc = try XMLDocument(data: data, options: [.documentTidyHTML])
            if let root = doc.rootElement() {
                let body = root.elements(forName: "body").first
                let nodes = body?.children ?? root.children ?? []
                let rendered = renderMarkdown(nodes: nodes, inline: false, listDepth: 0)
                return normalizeMarkdown(rendered)
            }
        } catch {
            return htmlToPlainText(normalized)
        }
        return htmlToPlainText(normalized)
    }

    static func renderMarkdown(nodes: [XMLNode], inline: Bool, listDepth: Int) -> String {
        var result = ""
        for node in nodes {
            result += renderMarkdown(node: node, inline: inline, listDepth: listDepth)
        }
        return result
    }

    static func renderMarkdown(node: XMLNode, inline: Bool, listDepth: Int) -> String {
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
            let content = renderMarkdown(nodes: element.children ?? [], inline: true, listDepth: listDepth)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { return "" }
            return "\n\n" + content + "\n\n"
        case "div", "section", "article", "header", "footer", "nav", "address":
            let content = renderMarkdown(nodes: element.children ?? [], inline: false, listDepth: listDepth)
            return "\n\n" + content + "\n\n"
        case "span":
            return renderMarkdown(nodes: element.children ?? [], inline: inline, listDepth: listDepth)
        case "strong", "b":
            let content = renderMarkdown(nodes: element.children ?? [], inline: true, listDepth: listDepth)
            return "**" + content + "**"
        case "em", "i":
            let content = renderMarkdown(nodes: element.children ?? [], inline: true, listDepth: listDepth)
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
            let content = renderMarkdown(nodes: element.children ?? [], inline: true, listDepth: listDepth)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let href = element.attribute(forName: "href")?.stringValue ?? ""
            if href.isEmpty {
                return content
            }
            let label = content.isEmpty ? href : content
            return "[\(label)](\(href))"
        case "img":
            let alt = element.attribute(forName: "alt")?.stringValue ?? ""
            let src = element.attribute(forName: "src")?.stringValue ?? ""
            if src.isEmpty {
                return alt
            }
            return "![\(alt)](\(src))"
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tag.dropFirst()) ?? 1
            let content = renderMarkdown(nodes: element.children ?? [], inline: true, listDepth: listDepth)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { return "" }
            return "\n\n" + String(repeating: "#", count: max(1, min(6, level))) + " " + content + "\n\n"
        case "ul":
            return renderList(element, ordered: false, listDepth: listDepth)
        case "ol":
            return renderList(element, ordered: true, listDepth: listDepth)
        case "li":
            return renderMarkdown(nodes: element.children ?? [], inline: false, listDepth: listDepth)
        case "blockquote":
            let content = renderMarkdown(nodes: element.children ?? [], inline: false, listDepth: listDepth)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            return "\n\n" + prefixLines(trimmed, with: "> ") + "\n\n"
        case "hr":
            return "\n\n---\n\n"
        default:
            return renderMarkdown(nodes: element.children ?? [], inline: inline, listDepth: listDepth)
        }
    }

    static func renderList(_ element: XMLElement, ordered: Bool, listDepth: Int) -> String {
        let items = (element.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.name?.lowercased() == "li" }
        if items.isEmpty { return "" }
        let indent = String(repeating: "  ", count: listDepth)
        var lines: [String] = []
        lines.reserveCapacity(items.count)
        var index = 1
        for li in items {
            let bullet = ordered ? "\(index)." : "-"
            let content = renderMarkdown(nodes: li.children ?? [], inline: false, listDepth: listDepth + 1)
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

    static func parseNoteSummaries(_ output: String) -> [NoteSummary] {
        let lines = output.split(whereSeparator: \.isNewline)
        var results: [NoteSummary] = []
        results.reserveCapacity(lines.count)
        for lineSub in lines {
            let line = String(lineSub)
            guard let tabIndex = line.firstIndex(of: "\t") else {
                continue
            }
            let id = String(line[..<tabIndex])
            let title = String(line[line.index(after: tabIndex)...])
            results.append(NoteSummary(id: id, title: title))
        }
        return results
    }

    static func parseNoteDetail(_ output: String) throws -> NoteDetail {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 4 else {
            throw CLIError(message: "Invalid note detail output")
        }

        func stripPrefix(_ line: String, _ prefix: String) -> String {
            guard line.hasPrefix(prefix) else { return line }
            return String(line.dropFirst(prefix.count))
        }

        let id = stripPrefix(lines[0], "id:\t")
        let title = stripPrefix(lines[1], "name:\t")
        let created = stripPrefix(lines[2], "created:\t")
        let modified = stripPrefix(lines[3], "modified:\t")

        var bodyStart = 4
        if lines.count > 4, lines[4].isEmpty {
            bodyStart = 5
        }
        let body = bodyStart < lines.count ? lines[bodyStart...].joined(separator: "\n") : ""

        if id.isEmpty {
            throw CLIError(message: "Invalid note detail output")
        }
        return NoteDetail(id: id, title: title, created: created, modified: modified, body: body)
    }

    static func parseExportDetail(_ output: String) throws -> NoteExportDetail {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else {
            throw CLIError(message: "Invalid export output")
        }

        func stripPrefix(_ line: String, _ prefix: String) -> String {
            guard line.hasPrefix(prefix) else { return line }
            return String(line.dropFirst(prefix.count))
        }

        let id = stripPrefix(lines[0], "id:\t")
        let title = stripPrefix(lines[1], "name:\t")

        var bodyStart = 2
        if lines.count > 2, lines[2].isEmpty {
            bodyStart = 3
        }
        let body = bodyStart < lines.count ? lines[bodyStart...].joined(separator: "\n") : ""

        if id.isEmpty {
            throw CLIError(message: "Invalid export output")
        }
        return NoteExportDetail(id: id, title: title, body: body)
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
  honeycrisp search QUERY [--account NAME] [--folder NAME] [--limit N] [--json]
  honeycrisp show NOTE [--title TITLE] [--account NAME] [--folder NAME] [--json]
  honeycrisp add TITLE [--account NAME] [--folder NAME] [--body TEXT] [--json]
  honeycrisp add TITLE [--account NAME] [--folder NAME] [--json] < body.txt
  honeycrisp update NOTE [--title TEXT] [--body TEXT] [--account NAME] [--folder NAME] [--json]
  honeycrisp update NOTE [--title TEXT] [--account NAME] [--folder NAME] [--json] < body.txt
  honeycrisp delete NOTE [--title TITLE] [--account NAME] [--folder NAME] [--json]
  honeycrisp export NOTE [--title TITLE] [--account NAME] [--folder NAME] [--markdown] [--json]

Output:
  list/search: one note per line: NOTE_ID<TAB>TITLE
  add/update/delete: prints the NOTE_ID
  --json: structured output
  --markdown: export as markdown

Notes:
  NOTE can be a note id (x-coredata://...) or an exact title.
  If multiple notes share a title, use --id or add --account/--folder to narrow.
  For update, NOTE selects the note and --title sets the new title.
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
        tell application "Notes"
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
                set end of outputLines to ((id of n) & tab & (name of n))
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
        tell application "Notes"
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
                    set end of outputLines to ((id of n) & tab & (name of n))
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
            set end of outputLines to ("id:\t" & (id of theNote))
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
        tell application "Notes"
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
                    set end of outputLines to ((id of n) & tab & (name of n))
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
            set end of outputLines to ("id:\t" & (id of theNote))
            set end of outputLines to ("name:\t" & (name of theNote))
            set end of outputLines to ""
            set end of outputLines to ((body of theNote) as text)
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
