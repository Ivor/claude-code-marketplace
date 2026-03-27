# Progress Log Format

All state lives in `progress-log.md` in the same directory as the target skill. The file supports multiple runs — each identified by its target function.

Read existing `progress-log.md` before starting. Append to an existing run section if one matches, otherwise create a new one.

## Run Header

```markdown
# Run: <target_function summary>

**Target skill:** <absolute path to SKILL.md>
**Working directory:** <project directory>
**Target function:** <the prompt given to claude -p>
**Evaluation criteria:** <what better means>
**Iterations requested:** <N>
**Iterations completed:** 0
```

Update `Iterations completed` after each iteration.

## Iteration Entry

```markdown
## Iteration <N>

**Tool calls:** <count>
**Succeeded:** yes/no
**Observations:** <what went well, what was wasteful>
**Skill change made after this iteration:** <description, or "baseline" for iteration 1>
```

## Run Summary (after all iterations)

```markdown
## Summary

| Iteration | Tool calls | Change |
|-----------|-----------|--------|
| 1         | <count>   | baseline |
| 2         | <count>   | <+/- vs previous> |

**Best iteration:** <N> (<count> tool calls)
**Most impactful change:** <description>
**Regressions:** <iterations that got worse and why>
**Recommendation:** <whether more iterations would help>
```

## Commit Format

```
skill-optimizer: iteration <N> — <tool_call_count> tool calls
```

Stage both `progress-log.md` and the target `SKILL.md` for each commit.
