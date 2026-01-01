# Test Coverage Analysis for Honeycrisp

## Executive Summary

Honeycrisp is a Swift CLI tool for managing Apple Notes. The codebase has **minimal test coverage (~5%)** with 11 tests covering only utility functions. Critical business logic, database operations, and all CLI commands are completely untested.

## Current Test Coverage

### What's Currently Tested

| Component | File | Tests | Coverage |
|-----------|------|-------|----------|
| Argument Parsing | `Args.swift` | 1 | ~80% |
| Note Summary Parsing | `Parsing.swift` | 1 | ~50% |
| Tag Extraction | `Tags.swift` | 1 | ~100% |
| Bullet Normalization | `Parsing.swift` | 2 | ~100% |
| HTML Checklist Detection | `Html.swift` | 2 | ~30% |
| AppleScript String Escaping | `AppleScriptWriter.swift` | 1 | ~5% |
| CoreData ID Parsing | `Parsing.swift` | 1 | ~100% |
| Protobuf Decoding | `Proto.swift` | 2 | ~40% |

### Test Characteristics

- **All tests are unit tests** - no integration or end-to-end tests
- **All tests are happy-path** - no error scenario coverage
- **No mocking** - external dependencies (SQLite, AppleScript, filesystem) untested
- **Single test file** - all 11 tests in `HoneycrispTests.swift`

---

## Coverage Gaps (Priority Order)

### 🔴 Critical: CLI Commands (Main.swift - 500 LOC)

**Current coverage: 0%**

All 8 CLI commands have zero test coverage:

| Command | Function | Lines | Risk |
|---------|----------|-------|------|
| `list` | `cmdList()` | 62 | High - primary read operation |
| `search` | `cmdSearch()` | 43 | High - search logic untested |
| `show` | `cmdShow()` | 61 | High - note display logic |
| `add` | `cmdAdd()` | 30 | Critical - creates data |
| `update` | `cmdUpdate()` | 44 | Critical - modifies data |
| `delete` | `cmdDelete()` | 21 | Critical - destroys data |
| `append` | `cmdAppend()` | 38 | Critical - modifies data |
| `export` | `cmdExport()` | 28 | Medium - read operation |

**Recommended Tests:**

```swift
// Command argument validation
func testListRequiresNoArguments()
func testSearchRequiresQuery()
func testShowRequiresNoteSelector()
func testAddRequiresTitle()
func testUpdateRequiresTitleOrBody()
func testDeleteRequiresNoteSelector()
func testAppendRequiresText()

// Option parsing for each command
func testListWithLimitOption()
func testListWithAccountFilter()
func testListWithFolderFilter()
func testListWithAccountsFlag()
func testListWithFoldersFlag()

// Mutual exclusivity
func testListAccountsAndFoldersMutuallyExclusive()

// JSON output
func testListOutputsJSON()
func testSearchOutputsJSON()
func testShowOutputsJSON()
```

### 🔴 Critical: Database Layer (NotesStore.swift - 452 LOC)

**Current coverage: 0%**

The core business logic for reading notes from the SQLite database is completely untested.

**Key Functions Needing Tests:**

| Function | Purpose | Complexity |
|----------|---------|------------|
| `listNotes()` | List notes with filters | High |
| `searchNotes()` | Full-text search in notes | High |
| `noteDetail()` | Fetch single note details | Medium |
| `resolveNoteIDByTitle()` | Title-to-ID resolution | High |
| `listAccounts()` | List iCloud accounts | Low |
| `listFolders()` | List folders with filters | Medium |

**Recommended Tests:**

```swift
// With a test fixture database
func testListNotesReturnsAllNotes()
func testListNotesWithLimit()
func testListNotesFiltersByAccount()
func testListNotesFiltersByFolder()
func testListNotesExcludesTrash()

func testSearchNotesMatchesTitle()
func testSearchNotesMatchesBody()
func testSearchNotesIsCaseInsensitive()
func testSearchNotesRespectsLimit()

func testNoteDetailReturnsBody()
func testNoteDetailRejectsPasswordProtected()
func testNoteDetailIncludesAttachments()

func testResolveNoteIDThrowsWhenNotFound()
func testResolveNoteIDThrowsWhenAmbiguous()
```

**Testing Strategy:** Create a small SQLite test fixture with known data that mimics the Apple Notes schema.

### 🔴 Critical: SQLite Wrapper (SQLite.swift - 183 LOC)

**Current coverage: 0%**

The database abstraction layer has zero tests.

**Recommended Tests:**

```swift
func testOpenDatabaseSucceeds()
func testOpenMissingDatabaseFails()
func testQueryReturnsRows()
func testQueryWithBindingsWorks()
func testQueryOneReturnsFirstRow()
func testTableColumnsReturnsColumnNames()

// SQLiteRow type conversions
func testRowStringExtraction()
func testRowInt64Extraction()
func testRowDoubleExtraction()
func testRowBoolExtraction()
func testRowDataExtraction()
func testRowHandlesNullValues()
```

### 🟠 High Priority: AppleScript Generation (AppleScriptWriter.swift - 205 LOC)

**Current coverage: ~5%** (only string escaping tested)

The AppleScript generation functions are untested - only `asAppleScriptStringExpr()` has a test.

**Recommended Tests:**

```swift
// Script generation (verify output syntax)
func testAddNoteScriptGeneration()
func testAddNoteWithFolderAndAccount()
func testUpdateNoteScriptGeneration()
func testUpdateNoteWithTitleOnly()
func testUpdateNoteWithBodyOnly()
func testDeleteNoteScriptGeneration()
func testFindNotesByTitleScriptGeneration()

// Edge cases in escaping
func testEscapeAppleScriptHandlesBackslash()
func testEscapeAppleScriptHandlesQuotes()
func testEscapeAppleScriptHandlesMultipleNewlines()
func testEscapeAppleScriptHandlesEmptyString()
func testEscapeAppleScriptHandlesSpecialCharacters()
```

### 🟠 High Priority: JSON Output (Output.swift - 89 LOC)

**Current coverage: 0%**

Output format is never validated.

**Recommended Tests:**

```swift
func testOutputJSONEncodesNoteSummary()
func testOutputJSONEncodesNoteDetail()
func testOutputJSONEncodesSearchResult()
func testOutputJSONEncodesOperationResult()
func testOutputJSONSortsKeys()
func testWantsJSONDetectsFlag()
```

### 🟡 Medium Priority: HTML Utilities (Html.swift - 147 LOC)

**Current coverage: ~30%**

Some HTML functions are tested, but coverage is incomplete.

**Missing Tests:**

```swift
// htmlLooksLikeChecklist edge cases
func testHtmlLooksLikeChecklistWithNestedLists()
func testHtmlLooksLikeChecklistWithMixedContent()

// appendChecklistItemHTML edge cases
func testAppendChecklistItemToEmptyList()
func testAppendChecklistItemToOrderedList()
func testAppendChecklistItemWithHTMLEntities()

// Untested functions
func testHtmlFragmentFromPlainText()
func testHtmlFragmentPreservesNewlines()
func testHtmlFragmentEscapesHTMLCharacters()
```

### 🟡 Medium Priority: Protobuf Decoding (Proto.swift - 197 LOC)

**Current coverage: ~40%**

Decoder is tested but encoder/malformed data handling is not.

**Recommended Tests:**

```swift
func testDecodeNoteTextWithEmptyData()
func testDecodeNoteTextWithCorruptedGzip()
func testDecodeNoteTextWithInvalidProtobuf()
func testDecodeNoteTextWithUnknownEnvelopeVersion()
func testDecodeNoteTextPreservesUnicode()
func testDecodeNoteTextPreservesEmoji()
```

### 🟢 Lower Priority: Supporting Files

| File | LOC | Priority | Notes |
|------|-----|----------|-------|
| `Formatting.swift` | 59 | Low | Text formatting functions |
| `NotesContainer.swift` | 79 | Medium | Path resolution logic |
| `NotesAccessPrompt.swift` | 63 | Low | UI interaction (hard to test) |
| `Models.swift` | 60 | Low | Data structures only |
| `Help.swift` | 43 | Low | Static help text |
| `Version.swift` | 16 | Low | Static version info |
| `IO.swift` | 19 | Low | Simple I/O utilities |

---

## Error Path Testing Gaps

**None of the current tests verify error handling:**

| Error Scenario | Location | Current Tests |
|----------------|----------|---------------|
| Database open failure | `SQLite.swift:11` | ❌ None |
| Query execution failure | `SQLite.swift:47` | ❌ None |
| Note not found | `NotesStore.swift:151` | ❌ None |
| Password protected note | `NotesStore.swift:153` | ❌ None |
| Multiple notes with same title | `NotesStore.swift:138` | ❌ None |
| AppleScript compilation failure | `AppleScriptWriter.swift:7` | ❌ None |
| AppleScript execution failure | `AppleScriptWriter.swift:11` | ❌ None |
| JSON encoding failure | `Output.swift:84` | ❌ None |
| Missing command argument | `Main.swift` (various) | ❌ None |

---

## Recommended Testing Infrastructure

### 1. Test Fixture Database

Create a small SQLite database mimicking Apple Notes schema:

```
Tests/Fixtures/
├── notes_test.db          # Small test database
└── notes_corrupt.db       # Intentionally malformed
```

### 2. Mock AppleScript Runner

Create a protocol to allow testing script generation without execution:

```swift
protocol ScriptRunner {
    func run(_ source: String) throws -> String
}

// In tests
class MockScriptRunner: ScriptRunner {
    var lastScript: String?
    var returnValue: String = ""

    func run(_ source: String) throws -> String {
        lastScript = source
        return returnValue
    }
}
```

### 3. Test Data Helpers

Expand existing protobuf helpers for broader use:

```swift
// Already exists for protobuf
private func makeLegacyNotePayload(text: String) -> Data

// Add similar helpers for:
func makeTestNoteRecord(...) -> NoteRecord
func makeTestAccountRecord(...) -> AccountRecord
func makeTestFolderRecord(...) -> FolderRecord
```

### 4. Separate Test Files

Organize tests by module:

```
Tests/honeycrispTests/
├── CLITests/
│   ├── ArgsTests.swift
│   ├── CommandTests.swift
│   └── OutputTests.swift
├── NotesDBTests/
│   ├── NotesStoreTests.swift
│   ├── SQLiteTests.swift
│   └── ProtoTests.swift
└── WriteTests/
    ├── AppleScriptWriterTests.swift
    └── HtmlTests.swift
```

---

## Implementation Priorities

### Phase 1: Foundation (Estimated: Low Effort)
1. Add error path tests to existing test functions
2. Add edge case tests for already-tested utilities
3. Create test fixture database

### Phase 2: Core Logic (Estimated: Medium Effort)
1. Add SQLite wrapper tests with in-memory database
2. Add NotesStore tests using fixture database
3. Add JSON output validation tests

### Phase 3: Commands (Estimated: Medium Effort)
1. Add command argument validation tests
2. Add command option parsing tests
3. Add mock-based command execution tests

### Phase 4: Integration (Estimated: Higher Effort)
1. Add AppleScript generation validation tests
2. Add end-to-end CLI invocation tests
3. Add code coverage tracking to CI

---

## Metrics Goals

| Metric | Current | Target |
|--------|---------|--------|
| Test Count | 11 | 80+ |
| File Coverage | 14.7% (2.5/17 files) | 90%+ |
| Line Coverage | ~5% | 70%+ |
| Error Path Coverage | 0% | 50%+ |
| Command Coverage | 0% (0/8) | 100% |

---

## Quick Wins

These tests could be added immediately with minimal effort:

1. **More argument parsing tests** - `parseArgs()` has good coverage but lacks edge cases
2. **More AppleScript escaping tests** - add tests for special characters, empty strings
3. **JSON output struct tests** - verify Codable conformance
4. **Error message tests** - verify CLIError messages are descriptive
5. **Date formatting tests** - `formatDate()` is used but untested

---

## Conclusion

The Honeycrisp test suite provides a basic foundation but needs significant expansion. The most critical gaps are:

1. **Zero command-level testing** - all 8 commands untested
2. **Zero database testing** - 452 lines of core logic untested
3. **Zero error path testing** - no validation of failure scenarios
4. **No integration tests** - actual CLI behavior never verified

Addressing these gaps will significantly improve reliability and enable confident refactoring.
