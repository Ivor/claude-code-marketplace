---
name: explain-skill-check
description: Show the current skill-checker config, explain mappings, and offer to modify or remove them
user-invocable: true
argument-hint: [skill-name]
---

Show and explain the skill-checker configuration for this project.

## Step 1: Read the config

```bash
CONFIG_FILE=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-config.sh)
cat "$CONFIG_FILE" 2>/dev/null || echo "No config found"
```

If no config exists, point the user at `/skill-checker:setup-skill-checker` and stop.

## Step 2: Explain every mapping

Field semantics: `${CLAUDE_PLUGIN_ROOT}/references/config-format.md`. For each mapping, give concrete match/no-match examples:

- "Triggers on: Read, Edit. Does NOT trigger on: Bash, Grep"
- "Matches: `lib/accounts/user.ex`. Does NOT match: `config/runtime.exs`"

Done when every mapping in the config has been explained — then offer to modify or remove.

## To remove a mapping

```bash
jq --arg skill "skill-name" '.mappings |= map(select(.skill != $skill))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
```
