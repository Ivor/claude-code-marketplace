#!/usr/bin/env bash

# skill-checker.sh
#
# Claude Code PreToolUse hook that enforces skill activation before using specific tools.
#
# This hook intercepts tool use attempts and checks if required skills are loaded in the
# conversation transcript. If a tool use matches configured mappings but any required
# skills are not active, the hook denies execution and prompts Claude to load all missing skills.
#
# See skill-checker.exs for detailed flow diagrams and documentation.

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly PROJECT_CONFIG_FILE=".claude/hooks/skill-checker.json"

# ============================================================================
# UTILITIES
# ============================================================================

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Log error to stderr
log_error() {
    echo "$@" >&2
}

# Allow tool use (exit with success)
allow_tool_use() {
    # Output JSON response
    jq -n '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow"
        }
    }'

    exit 0
}

# Allow tool use with a warning message
allow_with_warning() {
    local reason="$1"

    local message="⚠️  SKILL-CHECKER HOOK WARNING ⚠️

The skill-checker hook encountered an issue and is allowing tool use to proceed:

${reason}

Please inform the user about this issue so they can fix the configuration.
The hook will continue to fail-open (allow tool use) until resolved.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Output warning to stderr so Claude sees it
    echo "$message" >&2

    exit 0
}

# Deny tool use with error message
deny_tool_use() {
    local missing_skills=("$@")
    local tool_name="${TOOL_NAME:-Unknown}"
    local file_path="${FILE_PATH:-}"

    # Build context line
    local context_line
    if [[ -n "$file_path" ]]; then
        context_line="File: $(realpath --relative-to="$CWD" "$file_path" 2>/dev/null || echo "$file_path")"
    else
        context_line="Tool: $tool_name"
    fi

    # Build message based on number of missing skills
    local header skills_text action_text
    if [[ ${#missing_skills[@]} -eq 1 ]]; then
        header="🚫 SKILL REQUIRED BEFORE TOOL USE"
        skills_text="Required Skill: ${missing_skills[0]}"
        action_text="ACTION REQUIRED:
→ Skill(skill: \"${missing_skills[0]}\")"
    else
        header="🚫 MULTIPLE SKILLS REQUIRED BEFORE TOOL USE"
        skills_text="Required Skills:"
        for skill in "${missing_skills[@]}"; do
            skills_text="${skills_text}
  - ${skill}"
        done
        action_text="ACTIONS REQUIRED:"
        for skill in "${missing_skills[@]}"; do
            action_text="${action_text}
→ Skill(skill: \"${skill}\")"
        done
    fi

    local message="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${header}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This is not an error. The skill-checker plugin requires you to load
specific skills before working in this area. This ensures you have the
right context and best practices loaded. Do not try to work around this.

${context_line}
${skills_text}

${action_text}

Once you activate the skill, this tool will be allowed.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Output JSON response
    jq -n \
        --arg msg "$message" \
        '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: $msg
            }
        }'

    exit 0
}

# ============================================================================
# JSON UTILITIES
# ============================================================================

# Extract value from JSON using jq
json_get() {
    local json="$1"
    local path="$2"
    local default="${3:-}"

    echo "$json" | jq -r "$path // \"$default\""
}

# Get array from JSON
json_get_array() {
    local json="$1"
    local path="$2"

    echo "$json" | jq -c "$path // []"
}

# ============================================================================
# PATTERN MATCHING
# ============================================================================

# Check if text matches regex pattern
matches_regex() {
    local text="$1"
    local pattern="$2"

    [[ "$text" =~ $pattern ]]
}

# Check if file path matches regex pattern
matches_file_pattern() {
    local file_path="$1"
    local regex_pattern="$2"

    matches_regex "$file_path" "$regex_pattern"
}

# ============================================================================
# SKILL CHECKING
# ============================================================================

# Find the timestamp of the most recent continuation marker
# Returns empty string if not found (not an error)
find_continuation_timestamp() {
    local transcript_path="$1"

    [[ ! -f "$transcript_path" ]] && return 0

    # Look for the continuation marker message
    grep -i "continued from a previous conversation" "$transcript_path" 2>/dev/null | \
        tail -1 | \
        jq -r '.timestamp // empty' 2>/dev/null || true
}

# Check if a skill is active in the transcript (after continuation if present)
# Returns 1 (false) if skill not found, 0 (true) if found
is_skill_active() {
    local transcript_path="$1"
    local skill_name="$2"

    [[ ! -f "$transcript_path" ]] && return 1

    # Find continuation timestamp if it exists
    local continuation_ts
    continuation_ts="$(find_continuation_timestamp "$transcript_path")"

    local result
    if [[ -n "$continuation_ts" ]]; then
        # Check skills loaded after continuation
        result="$(jq -c \
            --arg skill "$skill_name" \
            --arg ts "$continuation_ts" \
            'select(.timestamp > $ts) | .message.content[]? | select(.type == "tool_use" and .name == "Skill") | select(.input.skill == $skill or .input.command == $skill)' \
            "$transcript_path" 2>/dev/null)"
    else
        # Check all skills
        result="$(jq -c \
            --arg skill "$skill_name" \
            '.message.content[]? | select(.type == "tool_use" and .name == "Skill") | select(.input.skill == $skill or .input.command == $skill)' \
            "$transcript_path" 2>/dev/null)"
    fi

    [[ -n "$result" ]]
}

# Check which skills are missing from the transcript
get_missing_skills() {
    local transcript_path="$1"
    shift
    local required_skills=("$@")

    local missing_skills=()

    for skill in "${required_skills[@]}"; do
        if ! is_skill_active "$transcript_path" "$skill"; then
            missing_skills+=("$skill")
        fi
    done

    printf '%s\n' "${missing_skills[@]}"
}

# ============================================================================
# MAPPING LOGIC
# ============================================================================

# Check if tool name matches the tool_matcher pattern
matches_tool() {
    local tool_name="$1"
    local tool_matcher="$2"

    matches_regex "$tool_name" "$tool_matcher"
}

# Check if tool input matches the tool_input_matcher pattern
matches_tool_input() {
    local tool_input_json="$1"
    local tool_input_matcher="$2"

    matches_regex "$tool_input_json" "$tool_input_matcher"
}

# Check if at least one regex pattern matches the file path
matches_any_file_pattern() {
    local file_path="$1"
    local cwd="$2"
    shift 2
    local patterns=("$@")

    # Convert to relative path for matching
    local relative_path

    # Try GNU realpath first (Linux)
    if relative_path="$(realpath --relative-to="$cwd" "$file_path" 2>/dev/null)"; then
        : # Success, relative_path is set
    # Fallback for macOS: remove cwd prefix if file is under cwd
    elif [[ "$file_path" == "$cwd"/* ]]; then
        relative_path="${file_path#$cwd/}"
    else
        # File is outside cwd, use absolute path
        relative_path="$file_path"
    fi

    for pattern in "${patterns[@]}"; do
        if matches_file_pattern "$relative_path" "$pattern"; then
            return 0
        fi
    done

    return 1
}

# Check if a mapping matches the current tool use
mapping_matches() {
    local mapping="$1"
    local tool_name="$2"
    local tool_input_json="$3"
    local file_path="$4"
    local cwd="$5"

    # Extract mapping fields
    local tool_matcher
    tool_matcher="$(json_get "$mapping" '.tool_matcher')"
    [[ -z "$tool_matcher" ]] && return 1

    # Check if tool matches
    matches_tool "$tool_name" "$tool_matcher" || return 1

    # Check tool_input_matcher if specified
    local tool_input_matcher
    tool_input_matcher="$(json_get "$mapping" '.tool_input_matcher')"
    if [[ -n "$tool_input_matcher" ]]; then
        matches_tool_input "$tool_input_json" "$tool_input_matcher" || return 1
    fi

    # Check file_patterns if specified (regex patterns for file paths)
    local patterns_json
    patterns_json="$(json_get_array "$mapping" '.file_patterns')"
    local patterns_count
    patterns_count="$(echo "$patterns_json" | jq 'length')"

    if [[ "$patterns_count" -gt 0 ]]; then
        [[ -z "$file_path" ]] && return 1

        # Extract regex patterns into array
        local patterns=()
        while IFS= read -r pattern; do
            patterns+=("$pattern")
        done < <(echo "$patterns_json" | jq -r '.[]')

        matches_any_file_pattern "$file_path" "$cwd" "${patterns[@]}" || return 1
    fi

    return 0
}

# Find all matching mappings and extract required skills
find_required_skills() {
    local config="$1"
    local tool_name="$2"
    local tool_input_json="$3"
    local file_path="$4"
    local cwd="$5"

    local mappings_json
    mappings_json="$(json_get_array "$config" '.mappings')"

    local required_skills=()

    # Check each mapping
    while IFS= read -r mapping; do
        if mapping_matches "$mapping" "$tool_name" "$tool_input_json" "$file_path" "$cwd"; then
            local skill
            skill="$(json_get "$mapping" '.skill')"
            [[ -n "$skill" ]] && required_skills+=("$skill")
        fi
    done < <(echo "$mappings_json" | jq -c '.[]')

    # Remove duplicates and output
    # Use ${array[@]+"${array[@]}"} to handle empty arrays with set -u
    if [[ ${#required_skills[@]} -gt 0 ]]; then
        printf '%s\n' "${required_skills[@]}" | sort -u
    fi
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

main() {
    # Debug logging (opt-in via SKILL_CHECKER_DEBUG=1)
    local debug_log="/tmp/skill-checker-debug.log"
    debug() {
        if [[ "${SKILL_CHECKER_DEBUG:-0}" == "1" ]]; then
            echo "$@" >> "$debug_log"
        fi
    }

    debug "=== SKILL CHECKER DEBUG ==="
    debug "Timestamp: $(date)"

    # Check for required dependencies
    if ! command_exists jq; then
        allow_with_warning "jq is required but not installed. Please install jq to enable skill checking."
    fi

    # Read input from stdin
    local hook_data
    if ! hook_data="$(cat)"; then
        allow_with_warning "Failed to read hook input from stdin."
    fi

    # Log raw input
    debug "Raw hook data:"
    if [[ "${SKILL_CHECKER_DEBUG:-0}" == "1" ]]; then
        echo "$hook_data" | jq '.' >> "$debug_log" 2>&1
    fi

    # Parse hook data (fail open on error)
    if ! echo "$hook_data" | jq -e . >/dev/null 2>&1; then
        allow_with_warning "Failed to parse hook input JSON. The input may be malformed."
    fi

    # Extract tool information
    TOOL_NAME="$(json_get "$hook_data" '.tool_name')"
    local tool_input_json
    tool_input_json="$(echo "$hook_data" | jq -c '.tool_input // {}')"
    FILE_PATH="$(json_get "$tool_input_json" '.file_path')"
    CWD="$(json_get "$hook_data" '.cwd')"
    local transcript_path
    transcript_path="$(json_get "$hook_data" '.transcript_path')"

    # If running inside a subagent, resolve the subagent's own transcript
    local agent_id
    agent_id="$(json_get "$hook_data" '.agent_id')"
    local subagent_transcript=""
    if [[ -n "$agent_id" ]]; then
        local session_dir="${transcript_path%.jsonl}"
        local candidate="${session_dir}/subagents/agent-${agent_id}.jsonl"
        if [[ -f "$candidate" ]]; then
            subagent_transcript="$candidate"
            debug "Subagent detected (${agent_id}), will also check: $subagent_transcript"
        fi
    fi

    # Debug: Log extracted values
    debug "TOOL_NAME: $TOOL_NAME"
    debug "FILE_PATH: $FILE_PATH"
    debug "CWD: $CWD"
    debug "transcript_path: $transcript_path"
    debug "subagent_transcript: $subagent_transcript"

    # Debug: Check for continuation
    local continuation_ts
    continuation_ts="$(find_continuation_timestamp "$transcript_path")"
    if [[ -n "$continuation_ts" ]]; then
        debug "Continuation detected at: $continuation_ts"
        debug "Only checking skills loaded after this timestamp"
    else
        debug "No continuation detected, checking all skills"
    fi

    # Resolve config file location
    # Priority: 1) Plugin data directory (per-project), 2) Project-level config
    # Uses git remote URL as project key so worktrees share the same config
    local config_file=""
    if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]] && [[ -n "$CWD" ]]; then
        local project_key
        local remote_url
        remote_url="$(git -C "$CWD" remote get-url origin 2>/dev/null || true)"
        if [[ -n "$remote_url" ]]; then
            project_key="$(echo "$remote_url" | sed 's|[^a-zA-Z0-9]|_|g')"
        else
            project_key="$(echo "$CWD" | sed 's|/|_|g' | sed 's|^_||')"
        fi
        local plugin_data_config="${CLAUDE_PLUGIN_DATA}/projects/${project_key}/config.json"
        if [[ -f "$plugin_data_config" ]]; then
            config_file="$plugin_data_config"
            debug "Using plugin data config: $config_file"
        fi
    fi
    if [[ -z "$config_file" ]] && [[ -f "$PROJECT_CONFIG_FILE" ]]; then
        config_file="$PROJECT_CONFIG_FILE"
        debug "Using project config: $config_file"
    fi
    if [[ -z "$config_file" ]]; then
        allow_with_warning "No skill-checker config found for this project.
Run /skill-checker:setup-skill-checker to create one."
    fi

    # Read config (fail open on error)
    local config
    if ! config="$(cat "$config_file")"; then
        allow_with_warning "Failed to read config file: ${config_file}
Check file permissions and try again."
    fi

    # Parse config (fail open on error)
    if ! echo "$config" | jq -e . >/dev/null 2>&1; then
        allow_with_warning "Failed to parse config JSON in: ${config_file}
The JSON syntax may be invalid. Please validate the config file."
    fi

    # Find required skills
    local required_skills=()
    while IFS= read -r skill; do
        [[ -n "$skill" ]] && required_skills+=("$skill")
    done < <(find_required_skills "$config" "$TOOL_NAME" "$tool_input_json" "$FILE_PATH" "$CWD")

    # Debug: Log required skills
    debug "Required skills count: ${#required_skills[@]}"
    if [[ ${#required_skills[@]} -gt 0 ]]; then
        debug "Required skills: ${required_skills[*]}"
    else
        debug "Required skills: (none)"
    fi

    # If no skills required, allow
    if [[ ${#required_skills[@]} -eq 0 ]]; then
        debug "DECISION: No skills required, allowing tool use"
        allow_tool_use
    fi

    # Check if transcript is available (fail open if not)
    if [[ -z "$transcript_path" ]] || [[ ! -f "$transcript_path" ]]; then
        debug "DECISION: Transcript not available, failing open (allowing tool use)"
        allow_tool_use
    fi

    # Check which skills are missing
    # Subagents check their own transcript; main agent checks the main transcript
    local check_transcript="$transcript_path"
    if [[ -n "$subagent_transcript" ]]; then
        check_transcript="$subagent_transcript"
        debug "Using subagent transcript for skill check"
    fi

    debug "Checking which skills are missing..."
    local missing_skills=()
    while IFS= read -r skill; do
        debug "  - Skill '$skill' is missing"
        [[ -n "$skill" ]] && missing_skills+=("$skill")
    done < <(get_missing_skills "$check_transcript" "${required_skills[@]}" 2>/dev/null)

    # Debug: Log missing skills
    debug "Missing skills count: ${#missing_skills[@]}"
    debug "Missing skills: ${missing_skills[*]}"

    # If all skills are active, allow
    if [[ ${#missing_skills[@]} -eq 0 ]]; then
        debug "DECISION: All required skills are active, allowing tool use"
        allow_tool_use
    fi

    # Deny with error message
    debug "DECISION: Denying tool use due to missing skills"
    deny_tool_use "${missing_skills[@]}"
}

# ============================================================================
# ENTRY POINT
# ============================================================================

main "$@"
