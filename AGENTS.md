# Repository Guidelines

## Project Structure & Module Organization
- `Package.swift` defines the Swift Package Manager (SPM) project.
- `Sources/honeycrisp/honeycrisp.swift` contains the CLI implementation and AppleScript helpers.
- No test targets or assets are currently included.

## Build, Test, and Development Commands
- `swift build -c release` — builds the optimized binary at `./.build/release/honeycrisp`.
- `swift build` — debug build for faster iteration.
- `swift run honeycrisp --help` — runs the CLI directly from SPM.

## Coding Style & Naming Conventions
- Language: Swift (Foundation + AppleScript via `NSAppleScript`).
- Indentation: 4 spaces (match existing file).
- Types use `PascalCase` (e.g., `NoteDetail`), functions/vars use `camelCase` (e.g., `cmdSearch`).
- CLI commands are lowercase (`list`, `search`, `show`, `add`, `update`, `delete`).
- No formatter or linter configured; keep changes consistent with existing style.

## Testing Guidelines
- No automated tests yet. If you add tests, place them under `Tests/` and use `swift test`.
- Prefer small, focused tests for parsing helpers (e.g., JSON output parsing).

## Commit & Pull Request Guidelines
- Commit history uses short, imperative messages (e.g., “Add update/delete commands and JSON output”).
- Keep commits scoped to a single logical change.
- PRs should describe behavior changes and include example commands/output when CLI behavior changes (e.g., `--json` output).

## Notes Permissions & Behavior
- The CLI uses AppleScript to control Apple Notes; first run requires macOS Automation permission.
- Consider documenting any new permissions or prompts introduced by changes.
