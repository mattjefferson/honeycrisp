import Foundation
import XCTest

final class HoneycrispE2ETests: XCTestCase {
    private struct OperationResult: Decodable {
        let ok: Bool
        let action: String
        let title: String?
        let id: String?
    }

    private struct NoteSummary: Decodable {
        let title: String
    }

    private struct NoteSearchResult: Decodable {
        let title: String
    }

    private struct NoteDetail: Decodable {
        let title: String
        let body: String
        let format: String?
    }

    private struct ExportResult: Decodable {
        let title: String
        let format: String
        let content: String
    }

    private struct WaitError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func testNoteLifecyclePlainAndMarkdown() throws {
        try Self.skipUnlessEnabled()

        let runID = UUID().uuidString
        let plainTitle = "HC E2E Plain \(runID)"
        let markdownTitle = "HC E2E Markdown \(runID)"
        let plainBody = "Plain body \(runID)"
        let markdownBody = "Line one\n- item \(runID)"
        let markdownAnchor = "Line one"
        let updatedBody = "Updated body \(runID)"
        let updatedPayload = "\(plainTitle)\n\(updatedBody)"
        let appendedText = "Appended line \(runID)"
        var plainID: String? = nil
        var markdownID: String? = nil

        defer {
            if let plainID {
                _ = try? Self.runHoneycrisp(["delete", "--id", plainID] + Self.writeArgs())
            }
            if let markdownID {
                _ = try? Self.runHoneycrisp(["delete", "--id", markdownID] + Self.writeArgs())
            }
        }

        let addPlain = try Self.runHoneycrisp(["add", plainTitle, "--body", plainBody] + Self.writeArgs() + ["--json"])
        let addPlainResult: OperationResult = try Self.decodeJSON(addPlain)
        XCTAssertTrue(addPlainResult.ok)
        XCTAssertEqual(addPlainResult.action, "add")
        let resolvedPlainID = try Self.requireID(addPlainResult.id, "plain add")
        plainID = resolvedPlainID

        try Self.waitFor("list includes plain note") {
            let listOutput = try Self.runHoneycrisp(["list", "--limit", "200", "--json"] + Self.readArgs())
            let notes: [NoteSummary] = try Self.decodeJSON(listOutput)
            return notes.contains { $0.title == plainTitle }
        }

        let showOutput = try Self.runHoneycrisp(["show", plainTitle, "--json"] + Self.readArgs())
        let showDetail: NoteDetail = try Self.decodeJSON(showOutput)
        XCTAssertEqual(showDetail.title, plainTitle)
        XCTAssertTrue(showDetail.body.contains(plainBody))

        try Self.waitFor("search finds plain note") {
            let searchOutput = try Self.runHoneycrisp(["search", plainTitle, "--json"] + Self.readArgs())
            let results: [NoteSearchResult] = try Self.decodeJSON(searchOutput)
            return results.contains { $0.title == plainTitle }
        }

        let updateOutput = try Self.runHoneycrisp([
            "update",
            "--id",
            resolvedPlainID,
            "--body",
            updatedPayload
        ] + Self.writeArgs() + ["--json"])
        let updateResult: OperationResult = try Self.decodeJSON(updateOutput)
        XCTAssertTrue(updateResult.ok)
        XCTAssertEqual(updateResult.action, "update")
        XCTAssertNil(updateResult.title)

        let appendOutput = try Self.runHoneycrisp([
            "append",
            "--id",
            resolvedPlainID,
            "--body",
            appendedText
        ] + Self.writeArgs() + ["--json"])
        let appendResult: OperationResult = try Self.decodeJSON(appendOutput)
        XCTAssertTrue(appendResult.ok)
        XCTAssertEqual(appendResult.action, "append")

        try Self.waitFor("export includes updates", timeout: 20) {
            let exportOutput = try Self.runHoneycrisp(["export", "--id", resolvedPlainID, "--json"] + Self.readArgs())
            let exportResult: ExportResult = try Self.decodeJSON(exportOutput)
            return exportResult.format == "text"
                && exportResult.content.contains(updatedBody)
                && exportResult.content.contains(appendedText)
        }

        let deleteOutput = try Self.runHoneycrisp(["delete", "--id", resolvedPlainID] + Self.writeArgs() + ["--json"])
        let deleteResult: OperationResult = try Self.decodeJSON(deleteOutput)
        XCTAssertTrue(deleteResult.ok)
        XCTAssertEqual(deleteResult.action, "delete")

        let addMarkdown = try Self.runHoneycrisp(["add", markdownTitle, "--body", markdownBody] + Self.writeArgs() + ["--json"])
        let addMarkdownResult: OperationResult = try Self.decodeJSON(addMarkdown)
        XCTAssertTrue(addMarkdownResult.ok)
        let resolvedMarkdownID = try Self.requireID(addMarkdownResult.id, "markdown add")
        markdownID = resolvedMarkdownID

        try Self.waitFor("export markdown includes body", timeout: 20) {
            let exportMarkdown = try Self.runHoneycrisp(["export", "--id", resolvedMarkdownID, "--markdown", "--json"] + Self.readArgs())
            let exportMarkdownResult: ExportResult = try Self.decodeJSON(exportMarkdown)
            return exportMarkdownResult.format == "markdown"
                && exportMarkdownResult.content.hasPrefix("# ")
                && exportMarkdownResult.content.contains(markdownAnchor)
        }

        let deleteMarkdown = try Self.runHoneycrisp(["delete", "--id", resolvedMarkdownID] + Self.writeArgs() + ["--json"])
        let deleteMarkdownResult: OperationResult = try Self.decodeJSON(deleteMarkdown)
        XCTAssertTrue(deleteMarkdownResult.ok)
        XCTAssertEqual(deleteMarkdownResult.action, "delete")
    }

    private static func skipUnlessEnabled() throws {
        #if !os(macOS)
        throw XCTSkip("E2E tests require macOS.")
        #endif
        let env = ProcessInfo.processInfo.environment
        let enabled = env["HONEYCRISP_E2E"] == "1"
        try XCTSkipIf(!enabled, "Set HONEYCRISP_E2E=1 to run Notes E2E tests.")
    }

    private static func runHoneycrisp(_ args: [String], input: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = honeycrispURL()
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let input {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            try process.run()
            if let data = input.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()
        } else {
            process.standardInput = nil
            try process.run()
        }

        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let message = """
            honeycrisp failed (status \(process.terminationStatus))
            args: \(args.joined(separator: " "))
            stdout: \(stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            """
            throw WaitError(message: message)
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeJSON<T: Decodable>(_ output: String) throws -> T {
        guard let data = output.data(using: .utf8) else {
            throw WaitError(message: "Failed to decode JSON output.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func requireID(_ value: String?, _ label: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw WaitError(message: "Missing id for \(label).")
        }
        return value
    }

    private static func waitFor(
        _ description: String,
        timeout: TimeInterval = 12,
        interval: TimeInterval = 0.5,
        _ condition: () throws -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            do {
                if try condition() { return }
            } catch {
                lastError = error
            }
            Thread.sleep(forTimeInterval: interval)
        }
        if let lastError { throw lastError }
        throw WaitError(message: "Timed out: \(description)")
    }

    private static func honeycrispURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["HONEYCRISP_BIN"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        for bundle in Bundle.allBundles where bundle.bundleURL.pathExtension == "xctest" {
            return bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("honeycrisp")
        }
        return URL(fileURLWithPath: "honeycrisp")
    }

    private static func readArgs() -> [String] {
        var args: [String] = []
        let env = ProcessInfo.processInfo.environment
        if let account = env["HONEYCRISP_ACCOUNT"], !account.isEmpty {
            args += ["--account", account]
        }
        if let folder = env["HONEYCRISP_FOLDER"], !folder.isEmpty {
            args += ["--folder", folder]
        }
        if let notesPath = env["HONEYCRISP_NOTES_PATH"], !notesPath.isEmpty {
            args += ["--notes-path", notesPath]
        }
        return args
    }

    private static func writeArgs() -> [String] {
        var args: [String] = []
        let env = ProcessInfo.processInfo.environment
        if let account = env["HONEYCRISP_ACCOUNT"], !account.isEmpty {
            args += ["--account", account]
        }
        if let folder = env["HONEYCRISP_FOLDER"], !folder.isEmpty {
            args += ["--folder", folder]
        }
        return args
    }
}
