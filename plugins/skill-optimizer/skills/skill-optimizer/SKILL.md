---
name: skill-optimizer
description: Iteratively improve a Claude Code skill by running it via `claude -p`, scoring the transcript, refining, and committing each iteration. Use when optimizing a skill to reduce tool calls, execution time, or improve output quality.
---

# Skill Optimizer

Run a skill repeatedly, measure, refine, commit. Each iteration is diffable, and a worse score is reverted — the skill only ever ratchets forward.

The loop: pre-flight → execute → evaluate → log & commit → improve (or revert on regression) → repeat until N iterations, then summarize.

## Inputs

Collect before starting:

1. **Target skill path** — absolute path to SKILL.md (must be in a git repo)
2. **Working directory** — where `claude -p` executes
3. **Target function** — the prompt (phrased as a real user would)
4. **Evaluation criteria** — what "better" means (default: fewer tool calls)
5. **N** — iterations (default: 5)

## Pre-flight

Verify the `claude -p` environment can run the target function: read the skill, identify dependencies (MCP servers, running services, DB access), and run a minimal feasibility test before entering the loop. If it fails, fix the environment first. Log prerequisites in `progress-log.md` under `environment_notes`.

## Step 1: Execute

Run the target function in a fresh session. **The prompt must read as a normal user request — no mention of optimization, scoring, or testing.**

```bash
claude -p "<target_function>" \
  --output-format json \
  --permission-mode bypassPermissions \
  --max-budget-usd <budget> \
  > /tmp/skill-optimizer-result-<iteration>.json \
  2>/dev/null
```

Loading the target skill depends on what it is:

- **Plugin skill** (has `.claude-plugin/plugin.json`): add `--plugin-dir <path-to-plugin-root>`. Makes the skill available for activation and resolves `${CLAUDE_PLUGIN_ROOT}`. Working directory can be anything.
- **Standalone SKILL.md** (not in a plugin): add `--add-dir <directory-containing-skill>`. Does NOT resolve `${CLAUDE_PLUGIN_ROOT}`.
- **Already-installed plugin**: no extra flags.

**Do NOT use `--bare`** — it strips skills, subagents, MCP servers, hooks, and plugins, producing unrepresentative results. The JSON result contains `session_id`, `cost`, `num_turns`, `duration_ms` — but **not** the full transcript.

## Step 2: Evaluate

Locate the transcript, count tool calls, and verify Skill activation using the recipes in `${CLAUDE_PLUGIN_ROOT}/references/transcript-analysis.md`. The score must cover the main session **plus every subagent transcript** — a main-only count silently rewards subagent thrashing.

Then answer, comparing against previous iterations:

- Did the skill succeed?
- **Was the Skill tool invoked?** If not, the skill body was never loaded and nothing inside it could have mattered — fix the description first (see Step 4).
- Where did it waste effort (retries, wrong approaches, unnecessary exploration)?
- What did it re-discover at runtime that the skill could have provided directly?
- Did the last change help or hurt?

## Step 3: Log & Commit

Log results and commit using the format in `${CLAUDE_PLUGIN_ROOT}/references/progress-log-format.md`.

## Step 4: Improve the Skill

### The description first

The skill's `description` field is the **only thing Claude sees by default** — the SKILL.md body is invisible until the Skill tool is invoked. If the test session never called the Skill tool, rewrite the description before touching anything else. The pattern that works:

**"MUST activate" + the consequence of not activating + what the skill provides.**

```
description: MUST activate before doing X. Without this skill, Y will fail because Z. Provides scripts and decision trees for the correct approach.
```

### Extract logic to standalone scripts

Put complex logic in standalone scripts under `scripts/` and reference them via `${CLAUDE_PLUGIN_ROOT}/scripts/` instead of embedding snippets in the body. Claude runs the provided script rather than writing its own (fewer tool calls), scripts are testable outside Claude, and nothing gets miscopied. Requires the skill to be a plugin.

### Other strategies

- **Pre-document runtime discoveries** — schemas, paths, common values the agent kept looking up
- **Add decision trees** — eliminate trial-and-error exploration
- **Provide exact commands/snippets** — not descriptions of what to do
- **Add "do not" rules** — where the agent consistently wastes effort
- **Restructure freely** — reorder, split, merge sections if the current structure isn't working

### Anti-regression

If the score is **worse** than the previous iteration: log it fully (the data is valuable), then revert SKILL.md to the last good version via `git checkout <sha> -- <path>`. Never repeat a strategy that already failed.

## Notes

- Execution happens in the working directory; skill edits and commits happen in the skill's repo — these are different locations.
- If `claude -p` crashes entirely, log as a failed iteration and still attempt an improvement.
