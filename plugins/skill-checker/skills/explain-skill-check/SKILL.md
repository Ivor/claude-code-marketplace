---
name: explain-skill-check
description: Explain a specific skill check mapping in detail — what it matches, what it blocks, with examples
user-invocable: true
argument-hint: [skill-name]
---

Explain an existing mapping in the skill-checker configuration in detail.

## Steps:

1. **Read the config:**
   ```bash
   PROJECT_KEY=$(echo "$PWD" | sed 's|/|_|g' | sed 's|^_||')
   PLUGIN_CONFIG="${CLAUDE_PLUGIN_DATA}/projects/${PROJECT_KEY}/config.json"
   PROJECT_CONFIG=".claude/hooks/skill-checker.json"

   if [ -f "$PLUGIN_CONFIG" ]; then
     cat "$PLUGIN_CONFIG"
   elif [ -f "$PROJECT_CONFIG" ]; then
     cat "$PROJECT_CONFIG"
   fi
   ```

2. **List all mappings** with a brief summary

3. **For the selected mapping** (matching the argument, or ask if not specified):

   - **Skill**: Name and what it provides
   - **Tool matcher**: Which tools trigger this — give concrete examples:
     - "Triggers on: Write, Edit"
     - "Does NOT trigger on: Read, Grep, Bash"
   - **File patterns** (if present): Which files match — give concrete examples:
     - "Matches: `lib/accounts/user.ex`, `lib/web/live/page_live.ex`"
     - "Does NOT match: `config/runtime.exs`, `mix.exs`"
   - **Tool input matcher** (if present): What commands trigger:
     - "Matches: `mix test test/accounts_test.exs`"
     - "Does NOT match: `mix compile`, `mix deps.get`"

4. **Offer to modify or remove** the mapping if the user wants changes. To remove:
   ```bash
   jq --arg skill "skill-name" '.mappings |= map(select(.skill != $skill))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
   ```
