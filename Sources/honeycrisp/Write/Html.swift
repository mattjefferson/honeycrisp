import Foundation

extension Honeycrisp {
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

    static func renderChecklistPlainText(_ text: String, title: String?) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var output: [String] = []
        output.reserveCapacity(lines.count)

        let titleTrimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        var skippedTitle = false

        for raw in lines {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                output.append(line)
                continue
            }
            if !skippedTitle, let titleTrimmed, trimmed == titleTrimmed {
                output.append(line)
                skippedTitle = true
                continue
            }
            if lineHasChecklistPrefix(trimmed) {
                output.append(line)
                continue
            }
            if let normalizedBullet = normalizeBulletLine(line) {
                output.append(normalizedBullet)
                continue
            }

            let indent = line.prefix { $0 == " " || $0 == "\t" }
            output.append("\(indent)[ ] \(trimmed)")
        }

        return output.joined(separator: "\n")
    }

    private static func lineHasChecklistPrefix(_ trimmed: String) -> Bool {
        let lower = trimmed.lowercased()
        let prefixes = [
            "[ ]",
            "[x]",
            "- [ ]",
            "- [x]",
            "* [ ]",
            "* [x]",
            "+ [ ]",
            "+ [x]"
        ]
        return prefixes.contains { lower.hasPrefix($0) }
    }
}
