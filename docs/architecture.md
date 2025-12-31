---
title: Architecture
summary: 'Honeycrisp architecture overview: CLI entrypoints, read/write pipelines, and core components.'
read_when:
  - "Working on Notes data access, CLI flows, or write paths"
  - "Changing command behavior, output formats, or permissions"
  - "Modifying NotesDB, AppleScript writer, or decoding pipeline"
---

# Architecture

## Summary
- CLI for Apple Notes. Read path: direct SQLite snapshot. Write path: AppleScript to Notes app.
- Core goals: fast reads, minimal permissions, stable CLI output.
- Non-goals: full Notes schema coverage, rich formatting edits, background sync.

## High-level shape
- CLI entry: `Sources/honeycrisp/CLI/Main.swift`
- Read pipeline: Notes container -> snapshot -> SQLite -> decode note body -> output
- Write pipeline: resolve note id -> AppleScript -> Notes app

```
CLI commands
  ├─ read: list/search/show/export
  │    └─ NotesStore (SQLite snapshot, protobuf decode)
  └─ write: add/update/append/delete
       └─ AppleScriptWriter (Notes automation)
```

## Components
- CLI
  - Args parsing, validation, command dispatch.
  - Output formatting: text, markdown, JSON.
  - Tag extraction: simple regex on body text.

- NotesDB
  - `NotesContainer`: resolve Notes DB path, create temp snapshot with WAL/SHM.
  - `NotesStore`: read-only queries, folder/account caches, note detail assembly.
  - `SQLiteDB`: thin wrapper over sqlite3.
  - `NoteDataDecoder`: gunzip + protobuf-ish decode of `zicnotedata.zdata`.

- Write
  - `AppleScriptWriter`: build scripts for add/update/delete/get/set body.
  - `Html`: HTML escaping, append logic, checklist heuristics.

## Read flows
- list/search/show/export
  - `NotesStore.open()`
    - resolve container path
    - copy DB + WAL/SHM to temp dir
    - open read-only SQLite
  - load accounts/folders, build folder paths
  - fetch rows from `ziccloudsyncingobject`
  - body: `zicnotedata.zdata` -> gunzip -> protobuf decode -> plain text
  - output: text, markdown wrapper, or JSON

## Write flows
- add/update/delete/append
  - resolve note id (CoreData `x-coredata://` or numeric id, or title -> id)
  - run AppleScript against Notes app
  - append
    - read current HTML body
    - if checklist-like: insert new `<li>`
    - else: append escaped HTML fragment

## Data model (effective)
- Notes and folders stored in `NoteStore.sqlite`.
- Primary key `z_pk` used internally; CLI accepts numeric id or CoreData id and maps to `z_pk`.
- Notes filtered by account/folder; "Recently Deleted" excluded unless explicitly requested.

## Permissions + UX
- Read: requires filesystem access to `group.com.apple.notes` container or `NoteStore.sqlite`.
  - interactive: NSOpenPanel prompt when access denied.
- Write: requires macOS Automation permission to control Notes.

## Failure modes
- No container access -> prompt or error.
- Protobuf decode failures -> empty body (best-effort).
- AppleScript failures -> surfaced as CLI errors.

## Extension points
- New commands: add in `CLI/Main.swift` + parsing/output helpers.
- New read fields: extend `NotesStore` + models.
- Formatting: adjust `CLI/Formatting.swift` or `Write/Html.swift`.
