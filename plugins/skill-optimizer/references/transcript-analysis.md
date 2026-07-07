# Transcript analysis recipes

How to locate and score a `claude -p` session transcript.

## Transcript location

Extract `session_id` from the JSON result. The full transcript is at:

```
~/.claude/projects/<sanitized-cwd>/<session_id>.jsonl
```

Sanitized cwd: replace `/` with `-`, strip nothing else. Example: `/Users/alice/code/myproject` becomes `-Users-alice-code-myproject`.

## Counting tool calls

Count tool_use blocks across the main session and all subagents:

```bash
# Main session
cat ~/.claude/projects/<sanitized-cwd>/<session_id>.jsonl \
  | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' \
  | wc -l

# All subagents (recursive)
find ~/.claude/projects/<sanitized-cwd>/<session_id>/subagents -name "*.jsonl" 2>/dev/null \
  | xargs -I{} sh -c 'cat "{}" | jq -r "select(.type == \"assistant\") | .message.content[]? | select(.type == \"tool_use\") | .name"' \
  | wc -l
```

Sum both counts for the total. Subagent metadata is in sibling `.meta.json` files (`{"agentType": "Explore", "description": "..."}`).

**Do not rely on `agent_progress` entries** in the parent JSONL — those are streamed updates and miss tool calls. Always read each subagent's own `.jsonl`.

## Verifying Skill activation

Check whether the test session invoked the Skill tool to load the target skill:

```bash
cat ~/.claude/projects/<sanitized-cwd>/<session_id>.jsonl \
  | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Skill") | .input' \
  2>/dev/null
```

Empty output means the skill body was never loaded.

## Easier: transcript-reader plugin

If the `transcript-reader` plugin is installed (`claude plugin install transcript-reader@ivors-claude-code-marketplace`), one command replaces all of the above — tool counts, sub-agent breakdowns, token usage, and meandering detection in a single pass.
