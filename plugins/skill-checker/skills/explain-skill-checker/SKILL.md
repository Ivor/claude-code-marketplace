---
name: explain-skill-checker
description: Explain how the skill-checker plugin works, its architecture, and current configuration
user-invocable: true
---

Explain how the skill-checker plugin works and show the current project's configuration.

## Steps:

1. **Explain the concept:**
   - This plugin enforces that Claude loads specific skills before using certain tools
   - It works via a PreToolUse hook — a script that runs before every tool call
   - If the required skill isn't loaded in the conversation, the tool call is blocked
   - Claude is told which skill to load, loads it, then retries — seamlessly

2. **Show the current config** by resolving the config path:
   ```bash
   PROJECT_KEY=$(echo "$PWD" | sed 's|/|_|g' | sed 's|^_||')
   PLUGIN_CONFIG="${CLAUDE_PLUGIN_DATA}/projects/${PROJECT_KEY}/config.json"
   PROJECT_CONFIG=".claude/hooks/skill-checker.json"

   if [ -f "$PLUGIN_CONFIG" ]; then
     echo "Config location: $PLUGIN_CONFIG (plugin data)"
     cat "$PLUGIN_CONFIG"
   elif [ -f "$PROJECT_CONFIG" ]; then
     echo "Config location: $PROJECT_CONFIG (project-level)"
     cat "$PROJECT_CONFIG"
   else
     echo "No config found for this project"
   fi
   ```

3. **For each mapping**, explain in plain language:
   - "Before editing `.heex` files, Claude must load the `liveview-templates` skill"
   - "Before running `mix test`, Claude must load the `test-debugger` skill"

4. **Explain the safety model:**
   - Fail-open: if anything goes wrong (missing config, broken JSON, no jq), tool use is allowed
   - Conversation continuation: skills from a previous session don't count — they must be reloaded
   - Config priority: plugin data directory config takes precedence over project-level `.claude/hooks/skill-checker.json`

5. **Offer next steps:**
   - `/skill-checker:add-skill-check` to add a new mapping
   - `/skill-checker:setup-skill-checker` to reconfigure from scratch
