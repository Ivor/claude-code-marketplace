# Skill Optimizer Plugin

Iteratively improve Claude Code skills through measured test-refine-commit cycles.

## What It Does

Given a skill and a test prompt, this plugin runs a loop:

1. **Execute** — run the skill via `claude -p` against the test prompt
2. **Evaluate** — parse the transcript, count tool calls, check if the Skill tool was invoked
3. **Log & commit** — record metrics in a progress log, commit the iteration
4. **Improve** — analyze what went wrong and rewrite the skill
5. **Repeat** — if the score regressed, revert; otherwise keep iterating

Each iteration is a separate git commit, so the full optimization history is diffable.

## Installation

```bash
claude plugin marketplace add Ivor/claude-code-marketplace
claude plugin install skill-optimizer@ivors-claude-code-marketplace
```

## Usage

```
/skill-optimizer
```

Then provide:
- Path to the SKILL.md you want to optimize
- A working directory for test execution
- A test prompt (phrased as a real user would)
- What "better" means (default: fewer tool calls)
- Number of iterations (default: 5)

## Key Insight: The Description Trick

The most important thing this plugin teaches:

> A skill's `description` field is the **only thing Claude sees by default**. The full SKILL.md body is invisible until the Skill tool is invoked.

If your test runs show Claude ignoring your skill's rules, check whether the Skill tool was ever called. If not, rewrite the description from passive:

```
description: Use when the user asks about X...
```

To urgent:

```
description: MUST activate before doing X. Without this skill, Y will fail because Z.
```

This single change took the transcript-reader skill from 19 tool calls to 2.

## Loading Skills for Testing

The plugin documents three ways to load a target skill during `claude -p` testing:

| Skill Type | Flag | Notes |
|-----------|------|-------|
| **Plugin** (has `.claude-plugin/`) | `--plugin-dir /path/to/plugin` | Resolves `${CLAUDE_PLUGIN_ROOT}` |
| **Standalone** (just a SKILL.md) | `--add-dir /path/to/skill-dir` | No `${CLAUDE_PLUGIN_ROOT}` |
| **Already installed** | _(none needed)_ | Loaded automatically |

## Enhanced Evaluation

For deeper transcript analysis, install the companion plugin:

```bash
claude plugin install transcript-reader@ivors-claude-code-marketplace
```

This gives you single-command analysis of tool counts, sub-agent breakdowns, token usage, and meandering detection (retries, circular patterns, wasted effort).

## Requirements

- `jq` installed (for transcript parsing)
- Target skill must be in a git repo (for commit/revert)

## License

MIT
