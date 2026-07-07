#!/usr/bin/env bash
#
# Resolve the effective skill-checker config path for the current project.
# Mirrors the resolution order in hooks/skill-checker.sh — keep the two in sync:
#   1. Plugin data config (keyed by git remote URL so worktrees share config)
#   2. Project-level .claude/hooks/skill-checker.json
#   3. Default plugin data path (not yet existing)
#
# Usage:
#   resolve-config.sh          # print the effective config path
#   resolve-config.sh --init   # additionally create an empty config if none exists

set -euo pipefail

remote_url="$(git remote get-url origin 2>/dev/null || true)"
if [[ -n "$remote_url" ]]; then
    project_key="$(echo "$remote_url" | sed 's|[^a-zA-Z0-9]|_|g')"
else
    project_key="$(pwd | sed 's|/|_|g' | sed 's|^_||')"
fi

plugin_data_config="${CLAUDE_PLUGIN_DATA}/projects/${project_key}/config.json"
project_config=".claude/hooks/skill-checker.json"

if [[ -f "$plugin_data_config" ]]; then
    echo "$plugin_data_config"
elif [[ -f "$project_config" ]]; then
    echo "$project_config"
else
    if [[ "${1:-}" == "--init" ]]; then
        mkdir -p "$(dirname "$plugin_data_config")"
        echo '{"mappings":[]}' > "$plugin_data_config"
    fi
    echo "$plugin_data_config"
fi
