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
honeycrisp show NOTE [--title TITLE] [--account NAME] [--folder NAME] [--markdown] [--assets-dir PATH] [--json]
honeycrisp add TITLE [--account NAME] [--folder NAME] [--body TEXT] [--json]
honeycrisp add TITLE [--account NAME] [--folder NAME] [--json] < body.txt
honeycrisp update NOTE [--title TEXT] [--body TEXT] [--account NAME] [--folder NAME] [--json]
honeycrisp update NOTE [--title TEXT] [--account NAME] [--folder NAME] [--json] < body.txt
honeycrisp delete NOTE [--title TITLE] [--account NAME] [--folder NAME] [--json]
honeycrisp export NOTE [--title TITLE] [--account NAME] [--folder NAME] [--markdown] [--assets-dir PATH] [--json]
```

Output format:
- `list`/`search`: one title per line
- `add`: prints the new note title
- `update`: prints the new title if provided, otherwise `updated`
- `delete`: prints `deleted`

Use `--json` for structured output.

Use `--markdown` with `show` or `export` to emit markdown (title as `#` heading).
If the note contains embedded drawings/images, honeycrisp exports them to `./<title>-assets` by default.
Use `--assets-dir PATH` to control where images are written.

When NOTE is a title, it matches exact titles. If multiple notes share the title, use `--id` or narrow with `--account`/`--folder`.

Examples:
```
honeycrisp export "Grocery List" --markdown
honeycrisp show "Weekly-20251116" --markdown --assets-dir ./assets
honeycrisp export "Weekly-20251116" --markdown --assets-dir ./assets
honeycrisp delete "Grocery List" --account iCloud
```

## Notes access
The first time you run the CLI, macOS will ask for permission to control Notes. Approve it so the commands can access your notes.
