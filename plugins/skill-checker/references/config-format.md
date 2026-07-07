# skill-checker config format

The config is JSON with a single `mappings` array. Each mapping says: "when a tool use matches, require this skill to have been activated first."

```json
{
  "mappings": [
    {
      "skill": "skill-name",
      "tool_matcher": "Read|Write|Edit|Grep|Glob",
      "file_patterns": ["^lib/.*\\.ex$"],
      "tool_input_matcher": "optional-pattern",
      "agent_type_matcher": "optional-pattern"
    }
  ]
}
```

## Fields

- **skill** (required) — skill name to require. Use the short name (e.g. `elixir-quick-context`); the hook matches qualified `plugin:name` forms automatically.
- **tool_matcher** (required) — regex matched against the tool name. Use `|` for alternatives: `"Read|Write|Edit"`, `"Bash"`, `"mcp__.*"`.
- **file_patterns** (optional) — array of regexes matched against the file path **relative to the project root**. Anchor with `^`: `"^lib/.*\\.ex$"`, `"^test/.*\\.exs$"`, `"^src/.*\\.tsx$"`. A mapping with file_patterns only matches tool uses that carry a file path.
- **tool_input_matcher** (optional) — regex matched against the tool input JSON: `"mix test"` for Bash commands, `"worktree"` for Skill inputs.
- **agent_type_matcher** (optional) — regex matched against the agent type (e.g. `"Explore"`, `"general-purpose"`); the mapping then only applies inside matching subagents.

## Constraint

A mapping whose `tool_matcher` can match the `Skill` tool MUST include a `tool_input_matcher` — otherwise it would block loading the required skill itself. The hook silently skips Skill-tool mappings without one.
