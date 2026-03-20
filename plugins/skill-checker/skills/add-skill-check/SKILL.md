---
name: add-skill-check
description: Add a new skill enforcement mapping to the current project's skill-checker config
user-invocable: true
argument-hint: [skill-name]
---

Add a new skill check mapping for the current project.

## Resolve config path

```bash
PROJECT_KEY=$(git remote get-url origin 2>/dev/null | sed 's|[^a-zA-Z0-9]|_|g')
if [ -z "$PROJECT_KEY" ]; then PROJECT_KEY=$(echo "$PWD" | sed 's|/|_|g' | sed 's|^_||'); fi
CONFIG_DIR="${CLAUDE_PLUGIN_DATA}/projects/${PROJECT_KEY}"
CONFIG_FILE="${CONFIG_DIR}/config.json"
if [ ! -f "$CONFIG_FILE" ]; then mkdir -p "$CONFIG_DIR" && echo '{"mappings":[]}' > "$CONFIG_FILE"; fi
```

## Build the mapping

Ask the user (or use the argument) for:
- **Skill name** (short name, e.g. `elixir-quick-context`)
- **Tool matcher** — `"Read|Write|Edit|Grep|Glob"`, `"Bash"`, `"mcp__.*"`, etc.
- **File patterns** (optional) — regex against relative path from root, anchored with `^`:
  `"^lib/.*\\.ex$"`, `"^test/.*\\.exs$"`, `"^src/.*\\.tsx$"`
- **Tool input matcher** (optional) — regex against tool input: `"mix test"`, `"npm run"`

## Add to config

```bash
jq --argjson mapping '{"skill":"name","tool_matcher":"Read|Write|Edit","file_patterns":["^lib/.*\\.ex$"]}' \
  '.mappings += [$mapping]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
```

Show the updated config and confirm.
