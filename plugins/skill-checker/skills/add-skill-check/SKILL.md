---
name: add-skill-check
description: Add a new skill enforcement mapping to the current project's skill-checker config
user-invocable: true
argument-hint: [skill-name]
---

Add a new skill check mapping for the current project.

## Step 1: Resolve the config

```bash
CONFIG_FILE=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-config.sh --init)
```

## Step 2: Build the mapping

Read `${CLAUDE_PLUGIN_ROOT}/references/config-format.md` for the mapping fields and pattern examples. Ask the user for whatever the argument didn't supply — at minimum the skill name and tool matcher.

## Step 3: Append it

```bash
jq --argjson mapping '{"skill":"name","tool_matcher":"Read|Write|Edit","file_patterns":["^lib/.*\\.ex$"]}' \
  '.mappings += [$mapping]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
```

Done when the updated config is shown to the user and they confirm the mapping matches what they intended.
