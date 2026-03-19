---
name: add-skill-check
description: Add a new skill enforcement mapping to the current project's skill-checker config
user-invocable: true
argument-hint: [skill-name]
---

Add a new skill check mapping for the current project.

## Steps:

1. **Resolve the config path:**
   ```bash
   PROJECT_KEY=$(echo "$PWD" | sed 's|/|_|g' | sed 's|^_||')
   CONFIG_DIR="${CLAUDE_PLUGIN_DATA}/projects/${PROJECT_KEY}"
   CONFIG_FILE="${CONFIG_DIR}/config.json"
   ```

2. **If config doesn't exist**, create it:
   ```bash
   mkdir -p "$CONFIG_DIR"
   echo '{"mappings":[]}' > "$CONFIG_FILE"
   ```

3. **Read the current config** and show existing mappings briefly

4. **Build the new mapping** by asking the user (or using the argument):
   - Which skill should be required?
   - Which tools should trigger the check? Common patterns:
     - `"Write|Edit"` — file editing
     - `"Bash"` — shell commands
     - `"mcp__.*"` — any MCP tool
     - A specific tool name
   - Should it only apply to certain files? Build regex patterns:
     - `".*\\.ex$"` — all .ex files
     - `"^lib/.*\\.ex$"` — .ex files under lib/
     - `".*\\.heex$"` — HEEx templates
     - `"^src/.*\\.(tsx|jsx)$"` — React components under src/
   - Should it match specific tool input? (e.g., `"mix test"`, `"npm run"`)

5. **Add the mapping** to the config using jq:
   ```bash
   jq --argjson mapping '{"skill":"name","tool_matcher":"Write|Edit","file_patterns":["pattern"]}' \
     '.mappings += [$mapping]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
   ```

6. **Show the updated config** and confirm with the user
