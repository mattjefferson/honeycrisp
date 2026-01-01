import Foundation

extension Honeycrisp {
    static func formatShowText(
        title: String,
        created: String,
        modified: String,
        account: String?,
        folder: String?,
        folderPath: String?,
        shared: Bool?,
        folderShared: Bool?,
        tags: [String],
        body: String,
        attachmentCount: Int
    ) -> String {
        var lines: [String] = []
        lines.append("name:\t\(title)")
        lines.append("created:\t\(created)")
        lines.append("modified:\t\(modified)")
        if let account, !account.isEmpty {
            lines.append("account:\t\(account)")
        }
        let folderDisplay = folderPath ?? folder
        if let folderDisplay, !folderDisplay.isEmpty {
            lines.append("folder:\t\(folderDisplay)")
        }
        if let shared {
            lines.append("shared:\t\(shared)")
        }
        if let folderShared {
            lines.append("folder_shared:\t\(folderShared)")
        }
        if !tags.isEmpty {
            lines.append("tags:\t" + tags.joined(separator: ", "))
        }
        if attachmentCount > 0 {
            lines.append("attachments:\t\(attachmentCount)")
        }
        lines.append("")
        lines.append(body)
        return lines.joined(separator: "\n")
    }

    static func markdownFrom(title: String, body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleText = title.isEmpty ? "Untitled" : title
        if trimmedBody.isEmpty {
            return "# \(titleText)\n"
        }
        return "# \(titleText)\n\n\(trimmedBody)"
    }

    static func resolvedNoteBody(detail: NoteDetailRecord, noteID: Int64, store: NotesStore) -> String {
        guard store.noteHasTableAttachment(id: noteID) else { return detail.body }
        guard let coreDataID = store.coreDataID(forNote: noteID) else { return detail.body }
        guard let html = try? AppleScriptWriter.run(AppleScriptWriter.getNoteBody(id: coreDataID)) else { return detail.body }
        guard let rendered = plainTextFromHTML(html), !rendered.isEmpty else { return detail.body }
        return rendered
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
