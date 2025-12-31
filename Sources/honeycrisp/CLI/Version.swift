import Foundation

enum HoneycrispVersion {
    static let version = "0.1.0"
    static let name = "honeycrisp"

    static func string() -> String {
        "\(name) \(version)"
    }
}

extension Honeycrisp {
    static func printVersion() {
        print(HoneycrispVersion.string())
    }
}
