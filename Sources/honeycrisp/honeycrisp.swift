import Foundation
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

struct OperationResult: Codable {
    let id: String
    let ok: Bool
    let action: String
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
        let noteID = try optionValue(parsed, "--id") ?? parsed.positionals.first
        guard let noteID, !noteID.isEmpty else {
            throw CLIError(message: "show requires a note id")
        }

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
        let noteID = try optionValue(parsed, "--id") ?? parsed.positionals.first
        guard let noteID, !noteID.isEmpty else {
            throw CLIError(message: "update requires a note id")
        }

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
        let noteID = try optionValue(parsed, "--id") ?? parsed.positionals.first
        guard let noteID, !noteID.isEmpty else {
            throw CLIError(message: "delete requires a note id")
        }

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
  honeycrisp show NOTE_ID [--json]
  honeycrisp add TITLE [--account NAME] [--folder NAME] [--body TEXT] [--json]
  honeycrisp add TITLE [--account NAME] [--folder NAME] [--json] < body.txt
  honeycrisp update NOTE_ID [--title TEXT] [--body TEXT] [--json]
  honeycrisp update NOTE_ID [--title TEXT] [--json] < body.txt
  honeycrisp delete NOTE_ID [--json]

Output:
  list/search: one note per line: NOTE_ID<TAB>TITLE
  add/update/delete: prints the NOTE_ID
  --json: structured output
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
