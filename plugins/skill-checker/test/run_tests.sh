#!/usr/bin/env bash

# Test suite for skill-checker hook
# Runs the hook with mock inputs and verifies allow/deny decisions

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$PLUGIN_DIR/hooks/skill-checker.sh"
TEST_DIR="$(mktemp -d)"
PASS=0
FAIL=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# ============================================================================
# HELPERS
# ============================================================================

# Create a config file with given mappings JSON
create_config() {
    local config_dir="$TEST_DIR/project/.claude/hooks"
    mkdir -p "$config_dir"
    echo "$1" > "$config_dir/skill-checker.json"
}

# Create a transcript file with given JSONL lines
create_transcript() {
    local transcript_path="$TEST_DIR/transcript.jsonl"
    echo "$1" > "$transcript_path"
    echo "$transcript_path"
}

# Build hook input JSON
build_hook_input() {
    local tool_name="$1"
    local tool_input="$2"
    local transcript_path="${3:-}"

    jq -n \
        --arg tool_name "$tool_name" \
        --argjson tool_input "$tool_input" \
        --arg cwd "$TEST_DIR/project" \
        --arg transcript_path "$transcript_path" \
        '{
            tool_name: $tool_name,
            tool_input: $tool_input,
            cwd: $cwd,
            transcript_path: $transcript_path
        }'
}

# Run the hook and capture output + exit code
run_hook() {
    local input="$1"
    local output
    local exit_code=0

    output="$(echo "$input" | (cd "$TEST_DIR/project" && bash "$HOOK_SCRIPT") 2>/dev/null)" || exit_code=$?
    echo "$output"
    return $exit_code
}

# Extract the permission decision from hook output
# If no JSON output (fail-open warnings), treat as "allow"
get_decision() {
    local output="$1"
    if [[ -z "$output" ]]; then
        echo "allow"
        return
    fi
    echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo "allow"
}

# Assert the decision matches expected
assert_decision() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo -e "  ${GREEN}PASS${RESET} $test_name (got: $actual)"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RESET} $test_name (expected: $expected, got: $actual)"
        ((FAIL++))
    fi
}

# ============================================================================
# TRANSCRIPT BUILDERS
# ============================================================================

# Build a transcript line with a Skill tool_use
skill_entry() {
    local skill_name="$1"
    local timestamp="${2:-2026-01-01T12:00:00Z}"

    jq -nc \
        --arg skill "$skill_name" \
        --arg ts "$timestamp" \
        '{timestamp:$ts,message:{content:[{type:"tool_use",name:"Skill",input:{skill:$skill}}]}}'
}

# Build a continuation marker line
continuation_entry() {
    local timestamp="${1:-2026-01-01T11:00:00Z}"

    jq -nc \
        --arg ts "$timestamp" \
        '{timestamp:$ts,message:{content:[{type:"text",text:"Continued from a previous conversation"}]}}'
}

# ============================================================================
# TESTS
# ============================================================================

echo -e "${BOLD}Skill Checker Hook — Test Suite${RESET}"
echo ""

# --- Test Group 1: Fail-open behavior ---
echo -e "${BOLD}1. Fail-open behavior${RESET}"

# No config file (neither project nor plugin data)
rm -rf "$TEST_DIR/project"
mkdir -p "$TEST_DIR/project"
input="$(build_hook_input "Edit" '{"file_path": "lib/foo.ex"}')"
output="$(run_hook "$input")"
assert_decision "No config file → allow" "allow" "$(get_decision "$output")"

# --- Test Group 2: No matching mappings ---
echo -e "\n${BOLD}2. No matching mappings${RESET}"

create_config '{
  "mappings": [
    {
      "skill": "elixir-best-practices",
      "tool_matcher": "Write|Edit",
      "file_patterns": ["^lib/.*\\.ex$"]
    }
  ]
}'

# Tool doesn't match
input="$(build_hook_input "Grep" '{"pattern": "foo"}')"
output="$(run_hook "$input")"
assert_decision "Tool doesn't match mapping → allow" "allow" "$(get_decision "$output")"

# Tool matches but file doesn't match pattern
input="$(build_hook_input "Edit" '{"file_path": "'"$TEST_DIR/project"'/config/runtime.exs"}')"
output="$(run_hook "$input")"
assert_decision "File doesn't match pattern → allow" "allow" "$(get_decision "$output")"

# --- Test Group 3: Matching mapping, skill missing ---
echo -e "\n${BOLD}3. Deny when skill not loaded${RESET}"

transcript_path="$(create_transcript '{}')"

input="$(build_hook_input "Edit" '{"file_path": "'"$TEST_DIR/project"'/lib/accounts/user.ex"}' "$transcript_path")"
output="$(run_hook "$input")"
assert_decision "Skill not in transcript → deny" "deny" "$(get_decision "$output")"

# --- Test Group 4: Matching mapping, skill present ---
echo -e "\n${BOLD}4. Allow when skill is loaded${RESET}"

transcript_path="$(create_transcript "$(skill_entry "elixir-best-practices")")"

input="$(build_hook_input "Edit" '{"file_path": "'"$TEST_DIR/project"'/lib/accounts/user.ex"}' "$transcript_path")"
output="$(run_hook "$input")"
assert_decision "Skill in transcript → allow" "allow" "$(get_decision "$output")"

# --- Test Group 5: tool_input_matcher ---
echo -e "\n${BOLD}5. Tool input matching${RESET}"

create_config '{
  "mappings": [
    {
      "skill": "test-debugger",
      "tool_matcher": "Bash",
      "tool_input_matcher": "mix test"
    }
  ]
}'

# Bash with mix test, skill missing
transcript_path="$(create_transcript '{}')"
input="$(build_hook_input "Bash" '{"command": "mix test test/accounts_test.exs"}' "$transcript_path")"
output="$(run_hook "$input")"
assert_decision "Bash 'mix test' without skill → deny" "deny" "$(get_decision "$output")"

# Bash with other command, should not match
input="$(build_hook_input "Bash" '{"command": "mix compile"}' "$transcript_path")"
output="$(run_hook "$input")"
assert_decision "Bash 'mix compile' → allow (no match)" "allow" "$(get_decision "$output")"

# Bash with mix test, skill present
transcript_path="$(create_transcript "$(skill_entry "test-debugger")")"
input="$(build_hook_input "Bash" '{"command": "mix test test/accounts_test.exs"}' "$transcript_path")"
output="$(run_hook "$input")"
assert_decision "Bash 'mix test' with skill → allow" "allow" "$(get_decision "$output")"

# --- Test Group 6: Multiple skills required ---
echo -e "\n${BOLD}6. Multiple skills from different mappings${RESET}"

create_config '{
  "mappings": [
    {
      "skill": "elixir-best-practices",
      "tool_matcher": "Write|Edit",
      "file_patterns": ["^lib/.*\\.ex$"]
    },
    {
      "skill": "liveview-templates",
      "tool_matcher": "Write|Edit",
      "file_patterns": [".*/live/.*\\.ex$"]
    }
  ]
}'

# File matches both patterns (lib/live/page_live.ex), only one skill loaded
transcript_path="$(create_transcript "$(skill_entry "elixir-best-practices")")"
input="$(build_hook_input "Edit" '{"file_path": "'"$TEST_DIR/project"'/lib/live/page_live.ex"}' "$transcript_path")"
output="$(run_hook "$input")"
assert_decision "Two skills required, only one loaded → deny" "deny" "$(get_decision "$output")"

# Both skills loaded
transcript_lines="$(skill_entry "elixir-best-practices" "2026-01-01T12:00:00Z")
$(skill_entry "liveview-templates" "2026-01-01T12:01:00Z")"
transcript_path="$(create_transcript "$transcript_lines")"

input="$(build_hook_input "Edit" '{"file_path": "'"$TEST_DIR/project"'/lib/live/page_live.ex"}' "$transcript_path")"
output="$(run_hook "$input")"
assert_decision "Two skills required, both loaded → allow" "allow" "$(get_decision "$output")"

# --- Test Group 7: Conversation continuation ---
echo -e "\n${BOLD}7. Conversation continuation${RESET}"

create_config '{
  "mappings": [
    {
      "skill": "elixir-best-practices",
      "tool_matcher": "Write|Edit",
      "file_patterns": ["^lib/.*\\.ex$"]
    }
  ]
}'

# Skill loaded BEFORE continuation → should deny
transcript_lines="$(skill_entry "elixir-best-practices" "2026-01-01T10:00:00Z")
$(continuation_entry "2026-01-01T11:00:00Z")"
transcript_path="$(create_transcript "$transcript_lines")"

input="$(build_hook_input "Edit" '{"file_path": "'"$TEST_DIR/project"'/lib/accounts/user.ex"}' "$transcript_path")"
output="$(run_hook "$input")"
assert_decision "Skill loaded before continuation → deny" "deny" "$(get_decision "$output")"

# Skill loaded AFTER continuation → should allow
transcript_lines="$(continuation_entry "2026-01-01T11:00:00Z")
$(skill_entry "elixir-best-practices" "2026-01-01T12:00:00Z")"
transcript_path="$(create_transcript "$transcript_lines")"

input="$(build_hook_input "Edit" '{"file_path": "'"$TEST_DIR/project"'/lib/accounts/user.ex"}' "$transcript_path")"
output="$(run_hook "$input")"
assert_decision "Skill loaded after continuation → allow" "allow" "$(get_decision "$output")"

# --- Test Group 8: Plugin data directory config ---
echo -e "\n${BOLD}8. Plugin data directory config${RESET}"

# Set up plugin data directory with config
PLUGIN_DATA_DIR="$TEST_DIR/plugin-data"
PROJECT_KEY="$(echo "$TEST_DIR/project" | sed 's|/|_|g' | sed 's|^_||')"
mkdir -p "$PLUGIN_DATA_DIR/projects/$PROJECT_KEY"
cat > "$PLUGIN_DATA_DIR/projects/$PROJECT_KEY/config.json" << 'CONF'
{
  "mappings": [
    {
      "skill": "data-dir-skill",
      "tool_matcher": "Write|Edit",
      "file_patterns": [".*\\.txt$"]
    }
  ]
}
CONF

# Remove project-level config so only plugin data config exists
rm -rf "$TEST_DIR/project/.claude"

# Override run_hook to include CLAUDE_PLUGIN_DATA
run_hook_with_plugin_data() {
    local input="$1"
    local output
    local exit_code=0
    output="$(echo "$input" | (cd "$TEST_DIR/project" && CLAUDE_PLUGIN_DATA="$PLUGIN_DATA_DIR" bash "$HOOK_SCRIPT") 2>/dev/null)" || exit_code=$?
    echo "$output"
    return $exit_code
}

# Plugin data config should deny when skill missing
transcript_path="$(create_transcript '{}')"
input="$(build_hook_input "Edit" '{"file_path": "'"$TEST_DIR/project"'/notes.txt"}' "$transcript_path")"
output="$(run_hook_with_plugin_data "$input")"
assert_decision "Plugin data config, skill missing → deny" "deny" "$(get_decision "$output")"

# Plugin data config should allow when skill present
transcript_path="$(create_transcript "$(skill_entry "data-dir-skill")")"
input="$(build_hook_input "Edit" '{"file_path": "'"$TEST_DIR/project"'/notes.txt"}' "$transcript_path")"
output="$(run_hook_with_plugin_data "$input")"
assert_decision "Plugin data config, skill loaded → allow" "allow" "$(get_decision "$output")"

# Plugin data config takes priority over project config
mkdir -p "$TEST_DIR/project/.claude/hooks"
cat > "$TEST_DIR/project/.claude/hooks/skill-checker.json" << 'CONF'
{
  "mappings": [
    {
      "skill": "project-level-skill",
      "tool_matcher": "Write|Edit",
      "file_patterns": [".*\\.txt$"]
    }
  ]
}
CONF

# Should require data-dir-skill (plugin data), not project-level-skill
transcript_path="$(create_transcript '{}')"
input="$(build_hook_input "Edit" '{"file_path": "'"$TEST_DIR/project"'/notes.txt"}' "$transcript_path")"
output="$(run_hook_with_plugin_data "$input")"
# The deny message should mention data-dir-skill, not project-level-skill
deny_reason="$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
if echo "$deny_reason" | grep -q "data-dir-skill"; then
    echo -e "  ${GREEN}PASS${RESET} Plugin data config takes priority over project config (got: data-dir-skill)"
    ((PASS++))
else
    echo -e "  ${RED}FAIL${RESET} Plugin data config takes priority over project config (expected: data-dir-skill in deny reason)"
    ((FAIL++))
fi

# ============================================================================
# RESULTS
# ============================================================================

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
TOTAL=$((PASS + FAIL))
echo -e "${BOLD}Results: ${GREEN}$PASS passed${RESET}, ${RED}$FAIL failed${RESET} (${TOTAL} total)"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

[[ $FAIL -eq 0 ]]
