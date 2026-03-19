---
name: setup-skill-checker
description: Create or review the skill-checker configuration for the current project
user-invocable: true
---

Help the user set up or review their skill-checker configuration. The config is stored in the plugin data directory, not in the project itself.

## Steps:

1. **Resolve the config location** by running:
   ```bash
   PROJECT_KEY=$(echo "$PWD" | sed 's|/|_|g' | sed 's|^_||')
   CONFIG_DIR="${CLAUDE_PLUGIN_DATA}/projects/${PROJECT_KEY}"
   CONFIG_FILE="${CONFIG_DIR}/config.json"
   echo "Config path: $CONFIG_FILE"
   echo "Exists: $(test -f "$CONFIG_FILE" && echo yes || echo no)"
   ```

2. **If config exists:**
   - Read and display the current configuration
   - Explain what each mapping does in plain language:
     - Which skill is required
     - Which tools trigger the check
     - Which files (if any) are matched
   - Ask if they want to add, modify, or remove mappings

3. **If config doesn't exist:**
   - Ask the user what skills they have and what kinds of files they work with
   - Based on their answers, build appropriate mappings
   - Create the config directory and file:
     ```bash
     mkdir -p "$CONFIG_DIR"
     ```
   - Write the config as JSON with their mappings
   - Show them the result and explain each mapping

## Configuration Format

```json
{
  "mappings": [
    {
      "skill": "skill-name",
      "tool_matcher": "Write|Edit",
      "file_patterns": [".*\\.ext$"],
      "tool_input_matcher": "optional-pattern"
    }
  ]
}
```

- **skill**: Name of the skill to require (must match an installed skill exactly)
- **tool_matcher**: Regex matching tool names — `Write`, `Edit`, `Bash`, `Grep`, or any MCP tool
- **file_patterns**: (optional) Regex patterns matched against relative file paths
- **tool_input_matcher**: (optional) Regex matched against tool input JSON (e.g., `"mix test"` for Bash commands)

## Notes

- The config is stored per-project in the plugin data directory — it won't clutter the project
- If a `.claude/hooks/skill-checker.json` exists in the project, it still works (backwards compatible) but the plugin data config takes priority
- The hook fails open: if config is missing or broken, tool use is always allowed
