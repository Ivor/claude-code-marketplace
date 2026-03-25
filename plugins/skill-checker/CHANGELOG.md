# Changelog

## [3.4.1] - 2026-03-25

### Fixed
- Skill tool is now always allowed (never blocked by the hook) — prevents deadlock where an agent can't load a required skill because loading it is itself blocked by `tool_matcher: ".*"`

## [3.4.0] - 2026-03-24

### Added
- `agent_type_matcher` field for mappings — require skills for specific agent types (e.g., Explore, Plan, general-purpose)
- Example in config template showing `agent_type_matcher` usage

## [3.0.0] - 2026-03-19

### Breaking Changes
- Migrated from `commands/` to `skills/` with `SKILL.md` format — slash commands are now `/skill-checker:setup-skill-checker` etc.
- Removed `MultiEdit` from tool_matcher patterns (tool does not exist in Claude Code)

### Added
- `hooks` field in `plugin.json` for reliable hook registration
- `license` and `repository` fields in `plugin.json`
- `strict` and `metadata` fields in `marketplace.json`
- This CHANGELOG

### Changed
- Debug logging is now opt-in via `SKILL_CHECKER_DEBUG=1` environment variable (was always-on)

### Fixed
- Installation paths in README now account for plugin caching

## [2.1.0] - 2025-12-04

### Changed
- Version bump

## [2.0.2] - 2025-12-04

### Changed
- Version bump

## [2.0.1] - 2025-12-04

### Changed
- Removed hooks field from plugin.json

## [2.0.0] - 2025-12-03

### Breaking Changes
- Switched from glob patterns to regex for file matching

### Fixed
- Unbound variable errors with empty arrays
- Updated documentation to reflect regex patterns

## [1.0.0] - 2025-11-18

### Added
- Initial release
- PreToolUse hook for skill enforcement
- Slash commands for setup and configuration
- Fail-open safety design
- Conversation continuation support
- Example configuration templates
