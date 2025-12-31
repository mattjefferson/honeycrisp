import Foundation
import AppKit

enum AppleScriptWriter {
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
        var result = ""
        result.reserveCapacity(value.count)
        for ch in value {
            switch ch {
            case "\\":
                result.append("\\\\")
            case "\"":
                result.append("\\\"")
            default:
                result.append(ch)
            }
        }
        return result
    }
}
