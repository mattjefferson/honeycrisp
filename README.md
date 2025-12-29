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
honeycrisp show NOTE_ID [--json]
honeycrisp add TITLE [--account NAME] [--folder NAME] [--body TEXT] [--json]
honeycrisp add TITLE [--account NAME] [--folder NAME] [--json] < body.txt
honeycrisp update NOTE_ID [--title TEXT] [--body TEXT] [--json]
honeycrisp update NOTE_ID [--title TEXT] [--json] < body.txt
honeycrisp delete NOTE_ID [--json]
```

Output format for `list` and `search` is one note per line:
```
NOTE_ID<TAB>TITLE
```

Use `--json` for structured output.

## Notes access
The first time you run the CLI, macOS will ask for permission to control Notes. Approve it so the commands can access your notes.
