---
name: transcript-reader
description: MUST activate before reading any .jsonl transcript file. Claude Code transcripts are JSONL where each line is 100K+ characters — the Read tool will fail. This skill provides a single-command analysis script that extracts everything (messages, tools, tokens, sub-agents) in one pass. Always invoke this skill FIRST when the user asks about past sessions, transcripts, or Claude's performance in prior conversations.
---

# Transcript Reader

## Step 1: Run the analysis script

For ANY transcript analysis, your first action MUST be this Bash command:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze_transcript.py /path/to/transcript.jsonl
```

This single script extracts all session data in one pass: message types, tool usage, user messages, assistant responses, thinking blocks, token usage, sub-agent analysis, and session outcome — including discovering and parsing sub-agent transcripts automatically.

**Do NOT use the Read tool on .jsonl files.** Each JSONL line is a single JSON object that can be 100K+ characters — Read will fail or exhaust token limits. The analysis script uses streaming python3 parsing instead.

**Do NOT spawn sub-agents (Agent tool) for this work.** The script output gives you everything. Analyze the output directly.

After running the script, write your analysis based on its output. For most requests, this single Bash call is all you need.

## Step 2: Deep-dive (only if the user asks for specifics)

### Detect meandering, retries, and circular patterns

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/detect_meandering.py /path/to/transcript.jsonl
```

Shows a timeline of all tool calls, then flags: repeated similar calls (retries), Read failures, circular patterns (same call made 3+ times), silent stretches (many tools with no text output), and errors. Also analyzes sub-agents and flags high tool counts (>30 = high, >15 = elevated). Use when the user asks about inefficiency, meandering, or "what went wrong."

### Analyze a sub-agent in isolation

The main script already summarizes sub-agents. For full detail on a specific one, run the same analysis script on the sub-agent's JSONL:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze_transcript.py ~/.claude/projects/<project>/<session-id>/subagents/agent-<id>.jsonl
```

### Anything narrower

For thinking-block dumps, per-tool call details, searching for user corrections/frustration, or writing a custom query (directory layout, JSONL message types): read `references/deep-dive.md` in this skill's directory.

## Finding sessions

If the user provides a file path, skip straight to Step 1. To find a session by keyword:

```bash
# Find project directories
ls ~/.claude/projects/ | grep "<keyword>"

# Search sessions index for matching sessions
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    idx = json.load(f)
for e in idx.get('entries', []):
    print(f\"{e.get('created','')[:10]}  {e['sessionId'][:8]}...  branch={e.get('gitBranch','')}  msgs={e.get('messageCount','')}  {e.get('firstPrompt','')[:120]}\")
" ~/.claude/projects/<project-dir>/sessions-index.json

# Or grep across all transcripts
grep -l "keyword" ~/.claude/projects/<project-dir>/*.jsonl
```

## Performance checklist

When evaluating Claude's performance in a session, cover every item:

- **Completeness**: Did it produce the deliverable? Check session outcome.
- **User corrections**: Run the frustration search (see `references/deep-dive.md`).
- **Failed tools**: Error count from the analysis output.
- **Efficiency**: Total tool calls, cache hit ratio.
- **Skill activation**: Did Claude use relevant skills?
- **Sub-agents**: Appropriate or wasteful?
