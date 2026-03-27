# Transcript Reader Plugin

Analyze Claude Code session transcripts — what happened, which tools were used, how sub-agents performed, and where things went wrong.

## What It Does

Claude Code stores every conversation as JSONL files under `~/.claude/projects/`. Each line is a single JSON object that can be 100K+ characters, making them impossible to read with normal file tools. This plugin provides two scripts that parse transcripts efficiently and extract structured information:

- **analyze_transcript.py** — Full session overview: messages, tool usage, token costs, sub-agent summaries, session outcome
- **detect_meandering.py** — Quality analysis: retries, circular patterns, Read failures, silent stretches, high tool count sub-agents

## Installation

```bash
claude plugin marketplace add https://github.com/Ivor/claude-code-marketplace
claude plugin install transcript-reader@ivors-claude-code-marketplace
```

## Usage

The skill activates automatically when you ask about past sessions or transcripts. You can also invoke it directly:

```
/transcript-reader
```

### Example Questions

1. "What did I work on in my last session?"
2. "How many tool calls did Claude make in that PR review?"
3. "Did Claude use the right skills in my session on this branch?"
4. "Were there any errors or failures in yesterday's session?"
5. "Which sub-agents were spawned and what were they doing?"
6. "Did Claude start going in circles or waste time?"
7. "How did the session end — did Claude finish the work or get interrupted?"
8. "Find the session where I was working on the interpolation refactor"
9. "How much did that session cost in tokens?"
10. "What was Claude's reasoning when it decided to spawn 7 sub-agents?"

### Example: Analyzing a Session

Prompt:

```
Analyze the session at <path to transcript> — I want to know what happened,
what tools were used, and how Claude performed. Check for any sub-agents too.
```

Result (2 tool calls — one Skill activation, one Bash script):

> ## Session Summary
>
> **Date**: 2026-03-20 | **Duration**: ~6 min | **Branch**: RAFFY-608
>
> ### Tool Usage (32 calls in main conversation)
>
> | Tool | Count |
> |------|-------|
> | Read | 7 |
> | Agent | 7 |
> | Bash | 5 |
> | Jira MCP | 5 |
> | Skill | 3 |
> | ToolSearch | 2 |
> | Write | 2 |
> | Edit | 1 |
>
> ### Sub-agents (7 total)
> All Explore type, spawned in parallel for codebase research.
> The GraphQL agent was heaviest at 43 tool calls.

### Example: Self-Analysis

The transcript-reader was used to analyze the very session that created it. The prompt:

```
Use the transcript-reader skill to analyze this session transcript:

<path to transcript>

This is the CURRENT live session, so it's still being written to.
That's fine — just analyze what's there so far.

Run both scripts:
1. python3 <plugin>/scripts/analyze_transcript.py on it
2. python3 <plugin>/scripts/detect_meandering.py on it

Give me a full narrative summary:
- What has this session been about?
- How has it progressed over time?
- How many tool calls, what kinds?
- Any sub-agents? How did they do?
- Any meandering or inefficiency?
- What's the token usage like?
- Overall assessment of how this session has gone.
```

The sub-agent used exactly **2 tool calls** (the analysis script + the meandering detector) and produced this:

---

**This Session: Self-Portrait**

Duration: ~3 hours | 96 main tool calls + 102 sub-agent calls | 10.6M cache tokens

**The Story Arc**

1. **Exploration phase (55 min)** — 3 parallel Explore agents investigated transcript file formats. This was the messiest phase: 100 combined sub-agent tool calls, multiple Read failures on JSONL files, and 71 API overload errors (529s) that forced the user to type "Continue" repeatedly.
2. **Skill creation (24 min)** — Built the initial SKILL.md based on the format research.
3. **Optimization loop (92 min)** — The meat of the session. 5 iterations:
   - Iterations 1-4: Tried adding rules to the skill body ("NEVER use Read", "NEVER spawn agents"). None worked because the skill body was never loaded.
   - Iteration 5 breakthrough: Realized the `description` field is the only thing Claude sees before Skill invocation. Rewrote it to say "MUST activate" — tool calls dropped from 19 to 2.
4. **Validation + extension (14 min)** — Tested on a completely different transcript (7 sub-agents). Added `detect_meandering.py`.

**Meandering in Our Own Session**

The detector found legitimate inefficiency in the exploration phase — trying `head -2`, then `head -1`, then `sed -n '2p'` on the same file. The sub-agents also repeatedly tried Read on JSONL files, failed, then fell back to Bash.

But most "circular" patterns were false positives — the repeated `claude -p` runs and skill rewrites are the whole point of an optimization loop.

**The Irony**

The exploration sub-agents that researched transcript formats made the exact same mistakes (Read on JSONL, too many tool calls) that we later taught the transcript-reader skill to avoid. We learned from our own inefficiency.

---

## How It Works

### The Description Trick

The skill's `description` field says "MUST activate before reading any .jsonl transcript file" — this forces Claude to invoke the Skill tool, which loads the full instructions. Without this, Claude defaults to using the Read tool on JSONL files, which fails because each line can be 100K+ characters.

This was discovered through 5 optimization iterations: the skill body had clear rules ("NEVER use Read"), but those rules were invisible until the Skill tool was invoked. The description is the only thing Claude sees by default.

### The Scripts

**`analyze_transcript.py`** — Single-pass Python script that reads the entire JSONL file once and extracts:
- Session metadata (ID, branch, version, model)
- Message type counts
- Tool usage with per-tool counts
- All user messages and assistant text responses
- Thinking blocks (truncated)
- Token usage (input, output, cache)
- Sub-agent discovery and analysis (reads meta files + agent transcripts)
- Session outcome (completed, interrupted, or normal end)

**`detect_meandering.py`** — Pattern detection script that identifies:
- Repeated similar tool calls (>70% input similarity)
- Read failures from token limits
- Circular patterns (same call made 3+ times)
- Silent stretches (8+ consecutive tool calls with no text output)
- Sub-agents with elevated (>15) or high (>30) tool counts
- All tool errors

Both scripts handle sub-agents automatically by looking in `<session-dir>/subagents/`.

## Requirements

- Python 3 (uses only standard library)
- Access to `~/.claude/projects/` directory

## License

MIT
