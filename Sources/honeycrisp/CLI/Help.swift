import Foundation

extension Honeycrisp {
    static func printHelp() {
        let help = """
Honeycrisp - Apple Notes CLI

Usage:
  honeycrisp version
  honeycrisp list [--account NAME] [--folder NAME] [--limit N] [--json] [--notes-path PATH]
  honeycrisp list --accounts [--limit N] [--json] [--notes-path PATH]
  honeycrisp list --folders [--account NAME] [--limit N] [--json] [--notes-path PATH]
  honeycrisp search QUERY [--account NAME] [--folder NAME] [--limit N] [--json] [--notes-path PATH]
  honeycrisp show NOTE [--id NOTE_ID] [--account NAME] [--folder NAME] [--markdown] [--json] [--notes-path PATH]
  honeycrisp add TITLE [TEXT...] [--account NAME] [--folder NAME] [--body TEXT] [--json]
  honeycrisp add TITLE [--account NAME] [--folder NAME] [--json] < body.txt
  honeycrisp update NOTE [--id NOTE_ID] [--title TEXT] [--body TEXT] [--account NAME] [--folder NAME] [--json]
  honeycrisp update NOTE [--id NOTE_ID] [--title TEXT] [--account NAME] [--folder NAME] [--json] < body.txt
  honeycrisp append NOTE TEXT [--id NOTE_ID] [--account NAME] [--folder NAME] [--body TEXT] [--json]
  honeycrisp append NOTE [--id NOTE_ID] [--account NAME] [--folder NAME] [--json] < body.txt
  honeycrisp delete NOTE [--id NOTE_ID] [--account NAME] [--folder NAME] [--json]
  honeycrisp export NOTE [--id NOTE_ID] [--account NAME] [--folder NAME] [--markdown] [--json] [--notes-path PATH]

Output:
  list/search: one title per line
  add: prints the new note title
  update: prints the new title if provided, otherwise "updated"
  delete: prints "deleted"
  append: prints the note title
  --json: structured output
  --markdown: export as markdown
  -v, --version: print version

Notes:
  NOTE can be a CoreData id (x-coredata://...) or an exact title.
  If multiple notes share a title, use --id or add --account/--folder to narrow.
  For update, NOTE selects the note and --title sets the new title.
  Notes in "Recently Deleted" are excluded unless you pass --folder "Recently Deleted".
  --notes-path may point to the group.com.apple.notes folder or NoteStore.sqlite.
  add accepts body text via --body, trailing args, or stdin.
"""
        print(help)
    }
}
