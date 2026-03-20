---
name: setup-skill-checker
description: Create or review the skill-checker configuration for the current project
user-invocable: true
---

Set up or review the skill-checker config. Config is stored in the plugin data directory, not in the project.

## Resolve config location

```bash
PROJECT_KEY=$(git remote get-url origin 2>/dev/null | sed 's|[^a-zA-Z0-9]|_|g')
if [ -z "$PROJECT_KEY" ]; then PROJECT_KEY=$(echo "$PWD" | sed 's|/|_|g' | sed 's|^_||'); fi
CONFIG_DIR="${CLAUDE_PLUGIN_DATA}/projects/${PROJECT_KEY}"
CONFIG_FILE="${CONFIG_DIR}/config.json"
echo "Config path: $CONFIG_FILE"
echo "Exists: $(test -f "$CONFIG_FILE" && echo yes || echo no)"
```

## If config exists

Read it, explain each mapping in plain language, and ask if changes are needed.

## If config doesn't exist

Ask the user what skills they use and what file types they work with. Create the config:

```bash
mkdir -p "$CONFIG_DIR"
```

## Config format

```json
{
  "mappings": [
    {
      "skill": "skill-name",
      "tool_matcher": "Read|Write|Edit|Grep|Glob",
      "file_patterns": ["^lib/.*\\.ex$"],
      "tool_input_matcher": "optional-pattern"
    }
  ]
}
```

- **skill**: Skill name to require (short name, e.g. `elixir-quick-context` — the hook matches qualified plugin names automatically)
- **tool_matcher**: Regex matching tool names. Use `|` for multiple.
- **file_patterns**: Regex matched against **relative path from project root**. Anchor with `^`.
- **tool_input_matcher**: Regex matched against tool input JSON (e.g. `"mix test"` for Bash)
