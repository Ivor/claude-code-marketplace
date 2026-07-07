---
name: setup-skill-checker
description: Create or review the skill-checker configuration for the current project
user-invocable: true
---

Set up or review the skill-checker config. Config lives in the plugin data directory, not in the project.

## Step 1: Resolve the config

```bash
CONFIG_FILE=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-config.sh)
echo "Config path: $CONFIG_FILE"
test -f "$CONFIG_FILE" && echo "Exists: yes" || echo "Exists: no"
```

## Step 2a: Config exists

Read it and explain each mapping in plain language (format reference: `${CLAUDE_PLUGIN_ROOT}/references/config-format.md`). Done when every mapping has been explained and the user has said whether changes are needed.

## Step 2b: No config

Ask the user which skills they use and which file types they work with. Then create the config and add a mapping per answer:

```bash
CONFIG_FILE=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-config.sh --init)
```

Mapping fields and pattern examples: `${CLAUDE_PLUGIN_ROOT}/references/config-format.md`. Done when the created config covers every skill the user named and they've confirmed it.
