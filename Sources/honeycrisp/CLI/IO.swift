import Foundation
import Darwin

extension Honeycrisp {
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
}
