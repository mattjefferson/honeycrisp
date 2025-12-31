# honeycrisp
An Apple Notes cli

## Build
```
swift build -c release
```

Binary will be at `./.build/release/honeycrisp`.

## Usage
```
honeycrisp list [--account NAME] [--folder NAME] [--limit N] [--json] [--notes-path PATH]
honeycrisp list --accounts [--limit N] [--json] [--notes-path PATH]
honeycrisp list --folders [--account NAME] [--limit N] [--json] [--notes-path PATH]
honeycrisp search QUERY [--account NAME] [--folder NAME] [--limit N] [--json] [--notes-path PATH]
honeycrisp show NOTE [--id NOTE_ID] [--account NAME] [--folder NAME] [--markdown] [--json] [--notes-path PATH]
honeycrisp add TITLE [--account NAME] [--folder NAME] [--body TEXT] [--json]
honeycrisp add TITLE [--account NAME] [--folder NAME] [--json] < body.txt
honeycrisp update NOTE [--id NOTE_ID] [--title TEXT] [--body TEXT] [--account NAME] [--folder NAME] [--json]
honeycrisp update NOTE [--id NOTE_ID] [--title TEXT] [--account NAME] [--folder NAME] [--json] < body.txt
honeycrisp append NOTE TEXT [--id NOTE_ID] [--account NAME] [--folder NAME] [--body TEXT] [--json]
honeycrisp append NOTE [--id NOTE_ID] [--account NAME] [--folder NAME] [--json] < body.txt
honeycrisp delete NOTE [--id NOTE_ID] [--account NAME] [--folder NAME] [--json]
honeycrisp export NOTE [--id NOTE_ID] [--account NAME] [--folder NAME] [--markdown] [--json] [--notes-path PATH]
```

Output format:
- `list`/`search`: one title per line
- `add`: prints the new note title
- `update`: prints the new title if provided, otherwise `updated`
- `delete`: prints `deleted`
- `append`: prints the note title

Use `--json` for structured output.

Use `--markdown` with `show` or `export` to emit markdown (title as `#` heading).
Use `--notes-path` to point directly at the Notes container or `NoteStore.sqlite`.

NOTE can be a CoreData id (`x-coredata://...`), numeric id, or exact title.
When NOTE is a title, it matches exact titles. If multiple notes share the title, use `--id` or narrow with `--account`/`--folder`.
Notes in "Recently Deleted" are excluded unless you pass `--folder "Recently Deleted"`.

Examples:
```
honeycrisp export "Grocery List" --markdown
honeycrisp show "Weekly-20251116" --markdown
honeycrisp export "Weekly-20251116" --markdown
honeycrisp append "Grocery List" "Buy lemons"
honeycrisp append "Snowbird List" --body "Extra socks"
honeycrisp list --accounts
honeycrisp list --folders --account iCloud
honeycrisp delete "Grocery List" --account iCloud
```

## Notes access
- Reading uses direct database access. On first use, honeycrisp will open a folder picker; select the `group.com.apple.notes` container or `NoteStore.sqlite` to grant access.
- Writing uses AppleScript. The first time you use add/update/append/delete, macOS will ask to allow automation access to Notes.
