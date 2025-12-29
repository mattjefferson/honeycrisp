# honeycrisp
An Apple Notes cli

## Build
```
swift build -c release
```

Binary will be at `./.build/release/honeycrisp`.

## Usage
```
honeycrisp list [--account NAME] [--folder NAME] [--limit N] [--json]
honeycrisp search QUERY [--account NAME] [--folder NAME] [--limit N] [--json]
honeycrisp show NOTE [--title TITLE] [--account NAME] [--folder NAME] [--json]
honeycrisp add TITLE [--account NAME] [--folder NAME] [--body TEXT] [--json]
honeycrisp add TITLE [--account NAME] [--folder NAME] [--json] < body.txt
honeycrisp update NOTE [--title TEXT] [--body TEXT] [--account NAME] [--folder NAME] [--json]
honeycrisp update NOTE [--title TEXT] [--account NAME] [--folder NAME] [--json] < body.txt
honeycrisp delete NOTE [--title TITLE] [--account NAME] [--folder NAME] [--json]
honeycrisp export NOTE [--title TITLE] [--account NAME] [--folder NAME] [--markdown] [--json]
```

Output format for `list` and `search` is one note per line:
```
NOTE_ID<TAB>TITLE
```

Use `--json` for structured output.

Use `--markdown` with `export` to emit markdown (title as `#` heading).

When NOTE is a title, it matches exact titles. If multiple notes share the title, use `--id` or narrow with `--account`/`--folder`.

Examples:
```
honeycrisp export "Grocery List" --markdown
honeycrisp delete "Grocery List" --account iCloud
```

## Notes access
The first time you run the CLI, macOS will ask for permission to control Notes. Approve it so the commands can access your notes.
