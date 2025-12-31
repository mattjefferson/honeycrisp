import Foundation

struct ParsedArgs {
    var flags: Set<String> = []
    var options: [String: String] = [:]
    var positionals: [String] = []
}

extension Honeycrisp {
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
}
