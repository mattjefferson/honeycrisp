import Foundation

extension Honeycrisp {
    static func extractTags(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)#([A-Za-z0-9_-]+)", options: [.anchorsMatchLines]) else {
            return []
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var seen: Set<String> = []
        var tags: [String] = []
        tags.reserveCapacity(matches.count)
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let raw = nsText.substring(with: match.range(at: 1))
            let key = raw.lowercased()
            if seen.insert(key).inserted {
                tags.append(raw)
            }
        }
        return tags
    }
}
