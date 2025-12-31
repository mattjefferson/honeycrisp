---
summary: 'Honeycrisp release workflow (versioning + artifacts)'
read_when:
  - Preparing a release or editing release notes.
---

# Honeycrisp Release Workflow

Versioning: SemVer. Source of truth: `Sources/honeycrisp/CLI/Version.swift`.

## Checklist
1) Update `CHANGELOG.md` (see `docs/update-changelog.md`).
2) Bump `HoneycrispVersion.version`.
3) Verify version output:
   - `swift run honeycrisp --version`
4) Run tests:
   - `swift test`
5) Build release binary:
   - `swift build -c release`
6) Package artifacts (macOS):
   - `tar -czf honeycrisp-<version>-macos.tar.gz -C .build/release honeycrisp`
   - `zip -j honeycrisp-<version>-macos.zip .build/release/honeycrisp`
   - `shasum -a 256 honeycrisp-<version>-macos.tar.gz honeycrisp-<version>-macos.zip > honeycrisp-<version>-macos.sha256`
7) Tag and push:
   - `git tag v<version>`
   - `git push origin v<version>`
8) Create GitHub release:
   - Title: `honeycrisp <version>`
   - Body: `CHANGELOG.md` entries for the version (no extra text).
   - Publish to trigger the `release` GitHub Actions workflow (uploads artifacts + checksum).
9) Verify release on GitHub (tag, notes, assets, checksums).
