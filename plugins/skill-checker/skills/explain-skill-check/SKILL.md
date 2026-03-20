---
name: explain-skill-check
description: Show the current skill-checker config, explain mappings, and offer to modify or remove them
user-invocable: true
argument-hint: [skill-name]
---

Show and explain the skill-checker configuration for this project.

## Resolve config path

```bash
PROJECT_KEY=$(git remote get-url origin 2>/dev/null | sed 's|[^a-zA-Z0-9]|_|g')
if [ -z "$PROJECT_KEY" ]; then PROJECT_KEY=$(echo "$PWD" | sed 's|/|_|g' | sed 's|^_||'); fi
CONFIG_FILE="${CLAUDE_PLUGIN_DATA}/projects/${PROJECT_KEY}/config.json"
if [ -f "$CONFIG_FILE" ]; then cat "$CONFIG_FILE"; elif [ -f ".claude/hooks/skill-checker.json" ]; then cat ".claude/hooks/skill-checker.json"; else echo "No config found"; fi
```

## What to explain

For each mapping, give concrete match/no-match examples:
- "Triggers on: Read, Edit. Does NOT trigger on: Bash, Grep"
- "Matches: `lib/accounts/user.ex`. Does NOT match: `config/runtime.exs`"

## To remove a mapping

```bash
jq --arg skill "skill-name" '.mappings |= map(select(.skill != $skill))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
```
