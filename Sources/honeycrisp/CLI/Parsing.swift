import Foundation

extension Honeycrisp {
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

    static func parseCoreDataID(_ value: String) -> Int64? {
        guard let range = value.range(of: "/p", options: .backwards) else {
            return nil
        }
        let tail = value[range.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int64(digits)
    }
}
