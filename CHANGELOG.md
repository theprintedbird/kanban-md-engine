# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog v1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- A blank line inside a card split it, turning the rest into column prose and its list items into new cards
- Cards indented with `task_indent` were read as continuation lines of the card above

## [0.2.0] - 2026-10-23

### Added

- `SPEC.md`, the behaviour specification
- Warning for empty list items with continuation lines
- `validate()` warns on a non-numeric `wip_limit`

### Changed

- Config in the board file now takes precedence over plugin config
- Resolved column config is no longer written to the markdown unless `write_full_config_to_markdown` is set
- Only known timestamp keys are formatted as timestamps; other numbers stay numbers

### Fixed

- Multi-line property comments on cards were dropped
- Unknown `__SPECIAL__` H6 sections were destroyed
- Card ids did not persist when `persist_card_ids` was enabled
- Board config comment was lost when the file had no H1 title
- `archive_done_cards()` used the wrong timestamp key for multi-word columns
- `Column:remove_card()` could remove the wrong card
- Stray comma after the `kanban:config` / `column:config` prefix
- Mojibake in the CLI adapter's `notify()` prefixes
- Kanban syntax inside fenced code blocks was parsed
- Non-numeric `wip_limit` crashed stats
- Reading a directory as a board raised instead of reporting
- Cards containing literal HTML comments did not parse
- Blank line between column prose and the first card was lost
- Plain HTML comments outside columns were lost
- Quoting in properties
- Nested lists in a card split it into new cards
- Commas, brackets and outer whitespace in array elements did not round trip
- Edits to a multi-line card's text did not reach the file
- `auto_id` was not always registered
- Blank lines accumulated under a column heading as cards moved

## [0.1.0] - 2025-12-31

### Added

- Engine split out of the kanban-md Neovim plugin, with a CLI adapter

[Unreleased]: https://github.com/theprintedbird/kanban-md-engine/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/theprintedbird/kanban-md-engine/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/theprintedbird/kanban-md-engine/releases/tag/v0.1.0
