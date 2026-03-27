# Skill Optimizer Progress Log: transcript-reader

## Environment Notes
- claude CLI: v2.1.85
- jq: 1.8.1
- Target skill: `/Users/ivorpaul/code/claude-code-marketplace/plugins/transcript-reader/skills/transcript-reader/SKILL.md`
- Working directory: `/Users/ivorpaul/code/sona/backend` (project containing test transcripts)
- Plugin dir: `/Users/ivorpaul/code/claude-code-marketplace/plugins/transcript-reader`

## Test Transcripts
1. **Simple (no sub-agents)**: `8e2949e8-95ce-42dd-b888-bf629865a12e.jsonl` (419K, PR review, March 4)
2. **Complex (with sub-agents)**: `18d637f0-9b1b-4ac7-b7de-9914ba461fd8.jsonl` (490K, March 26, 2 sub-agents)

## Iterations

### Iteration 1 — Baseline (simple transcript, no sub-agents)
- **Prompt**: "Analyze the Claude Code session transcript at .../8e2949e8-...jsonl — summarize what happened, tools used, Claude performance. Check for sub-agents."
- **Session ID**: `32255753-45bd-424c-84dc-0332374a45b8`
- **Duration**: 265,297ms
- **Turns**: 3
- **Tool calls**: 19 total (2 main + 17 sub-agent)
  - Main: 1 Read, 1 Agent
  - Sub-agent (general-purpose): 10 Bash, 7 Read
- **Result quality**: Good — accurate summary, correct identification of incomplete session, tool counts correct, performance assessment insightful
- **Score**: 19 tool calls

**Issues identified:**
1. **Used Read on JSONL files** — each line can be 100K+ chars, causing "file too large" errors and retries (Read limit 50 → Read limit 30 → Read limit 10 → gave up)
2. **Spawned a sub-agent** unnecessarily — the main session could have done this directly with Bash+python3
3. **Sequential python3 scripts** — 10 separate Bash calls, each parsing the file from scratch. Should be 1-2 comprehensive scripts
4. **No sub-agent directory check** — never ran `ls` or `find` on the session's subagents/ dir

**Plan for iteration 2:**
- Add critical warning: NEVER use Read on JSONL files — use Bash with python3/jq
- Provide a single comprehensive python3 analysis script that extracts everything in one pass
- Add explicit "do NOT spawn sub-agents for transcript analysis" guidance
- Add sub-agent discovery step

### Iteration 2 — Improved skill (simple transcript, no sub-agents)
- **Prompt**: Same as iteration 1
- **Session ID**: `d2767369-897b-454c-b652-26564909c788`
- **Duration**: 98,849ms (63% faster than baseline)
- **Turns**: 9
- **Tool calls**: 8 total (all main session, no sub-agents)
  - 6 Bash, 2 Read
- **Result quality**: Good — accurate, more detailed than iteration 1, correct tool counts, good performance assessment
- **Score**: 8 tool calls (58% reduction from baseline)

**Issues identified:**
1. **Still used Read on JSONL** — tried Read first (failed with token limit), then Read with limit=200, then fell back to Bash. The "NEVER use Read" rule was ignored.
2. **Didn't use the comprehensive script** — wrote 6 separate python3 scripts sequentially instead of the provided one-pass script. Each re-opened and re-parsed the file.
3. **No sub-agents spawned** — this rule was followed.

**Diagnosis:** The skill puts the comprehensive script deep in the document. Claude reads the rules but still defaults to its instincts (Read tool first). The script must be the FIRST thing Claude sees after the rules, and must be trivially copy-pasteable (no placeholders to think about).

**Plan for iteration 3:**
- Restructure: put the comprehensive script FIRST, before any reference material
- Make script accept file path as command-line argument (no placeholder replacement)
- Reduce reference material — move format docs to the bottom as an appendix
- Make the "NEVER Read JSONL" rule louder and explain WHY (lines are 100K+ chars)
- Add instruction: "Run this script FIRST, then answer from its output"

### Iteration 3 — Script-first layout (REVERTED — regression)
- **Session ID**: `a5c3ecda-3ae3-435b-aef3-043993467c2a`
- **Duration**: 166,390ms
- **Tool calls**: 15 total (2 main + 13 sub-agent) — WORSE than iteration 2
- **Score**: 15 (regression from 8)
- **Reverted**: Skill reverted to iteration 2 version

**Root cause:** Same as iterations 1-2 — Skill tool was never invoked. Restructuring the SKILL.md body had no effect because Claude never loaded it.

### Iteration 4 — Standalone script + CLAUDE_PLUGIN_ROOT (REVERTED — regression)
- **Session ID**: `c4575da8-6097-47b4-b4f4-dab24ee217e4`
- **Duration**: 160,510ms
- **Tool calls**: 17 total (3 main + 14 sub-agent) — WORSE
- **Score**: 17 (regression)
- **Reverted**: Skill reverted to iteration 2 version

**Key discovery:** The Skill tool was NEVER invoked in any iteration. The full SKILL.md content is only loaded when the Skill tool is called. Claude only sees the short `description` field in the skills list. All the rules, scripts, and instructions inside the skill body were invisible.

### Iteration 5 — Compelling description forces Skill activation (BREAKTHROUGH)
- **Session ID**: `60d40917-127b-4904-8152-1ab7bc0d6ed0`
- **Duration**: 33,797ms (87% faster than baseline)
- **Turns**: 4
- **Tool calls**: 2 total (1 Skill, 1 Bash) — **89% reduction from baseline**
- **Result quality**: Excellent — accurate, well-structured, correct analysis
- **Score**: 2 tool calls

**What changed:** Rewrote the `description` field from passive ("Use when the user asks about...") to active/urgent ("MUST activate before reading any .jsonl transcript file. Read tool will fail. This skill provides a single-command analysis script."). Claude's thinking now shows: "I have a skill for reading transcripts - let me use that first."

**Flow:** Skill invocation → loaded full SKILL.md → ran `analyze_transcript.py` via CLAUDE_PLUGIN_ROOT → wrote analysis from script output. Perfect.

### Iteration 5b — Complex transcript with sub-agents
- **Session ID**: `2c4e281c-b6e0-4c99-b19e-a5cff9e3b5a0`
- **Duration**: 53,211ms
- **Turns**: 6
- **Tool calls**: 4 total (1 Skill, 3 Bash)
- **Result quality**: Outstanding — detailed sub-agent analysis, identified failure patterns, gave recommendations
- **Score**: 4 tool calls

**Flow:** Skill → main analysis script → 2 sub-agent deep-dive scripts. Exactly the right amount of work.

## Score Summary

| Iteration | Tool Calls | Duration | Notes |
|-----------|-----------|----------|-------|
| 1 (baseline) | 19 | 265s | Sub-agent thrashing, Read failures |
| 2 | 8 | 99s | No sub-agent, but 6 sequential scripts |
| 3 (reverted) | 15 | 166s | Regression — Skill never invoked |
| 4 (reverted) | 17 | 161s | Regression — Skill never invoked |
| **5 (final)** | **2** | **34s** | **Skill invoked, one-shot script** |
| 5b (sub-agents) | 4 | 53s | Skill + main script + 2 sub-agent scripts |

## Key Learnings

1. **Skill descriptions are the ONLY thing Claude sees by default** — the full SKILL.md body is invisible until the Skill tool is invoked. Write descriptions that compel activation.
2. **"MUST activate" + explaining WHY** in the description is far more effective than rules inside the skill body.
3. **Standalone scripts via CLAUDE_PLUGIN_ROOT** eliminate the temptation to use Read/write custom scripts — Claude just runs the provided script.
4. **A single comprehensive script** is better than many small snippets — it gives Claude everything it needs in one tool call.
