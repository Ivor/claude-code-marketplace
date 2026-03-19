# Skill Checker Plugin

A Claude Code hook that enforces skill activation before using specific tools. This ensures Claude automatically loads required skills (like `elixir-best-practices`, `test-debugger`, `liveview-templates`) before editing files or running commands.

## What It Does

The skill-checker hook intercepts tool usage and checks if required skills are loaded in the conversation. If a tool use matches your configured mappings but required skills are not active, the hook:

1. **Denies the tool execution**
2. **Prompts Claude to load the missing skills**
3. **Allows Claude to retry after loading skills**

This prevents Claude from working on code without the proper context and best practices loaded.

## Getting Started

After installing, just run in your project:

```
/skill-checker:setup-skill-checker
```

Claude will ask what skills you use and create the configuration automatically. The config is stored in the plugin's data directory — nothing is added to your project.

You can also add individual checks anytime:

```
/skill-checker:add-skill-check elixir-best-practices
```

Without configuration, the hook does nothing (fail-open behavior for safety).

## Installation

### Step 1: Add the Marketplace and Install the Plugin

```bash
# Add the skill-checker marketplace from GitHub
claude plugin marketplace add https://github.com/Ivor/claude-code-marketplace

# Install the skill-checker plugin
claude plugin install skill-checker@ivors-claude-code-marketplace
```

### Step 2: Configure for Your Project

Run the setup skill in your project:

```
/skill-checker:setup-skill-checker
```

Claude will walk you through creating your configuration.

## Configuration

The hook looks for config in two locations (in priority order):

1. **Plugin data directory** (managed by skills, per-project) — `${CLAUDE_PLUGIN_DATA}/projects/<project-key>/config.json`
2. **Project-level** (for team-shared configs) — `.claude/hooks/skill-checker.json`

Use `/skill-checker:setup-skill-checker` to manage config automatically. The format is the same in both locations:

### Configuration Structure

```json
{
  "mappings": [
    {
      "skill": "skill-name",
      "tool_matcher": "ToolName|AnotherTool",
      "tool_input_matcher": "optional-regex-pattern",
      "file_patterns": [".*\\.ext$", "^path/.*\\.ex$"]
    }
  ]
}
```

### Configuration Fields

- **`skill`** (required): The name of the skill to require
- **`tool_matcher`** (required): Regex pattern matching tool names (e.g., `"Write|Edit"`)
- **`tool_input_matcher`** (optional): Regex pattern matching tool input JSON (e.g., `"mix test"`)
- **`file_patterns`** (optional): Array of **regex patterns** matching file paths (e.g., `[".*\\.heex$", ".*/live/.*\\.ex$"]`)

### Example Configurations

#### Elixir Project

```json
{
  "mappings": [
    {
      "skill": "liveview-templates",
      "tool_matcher": "Write|Edit",
      "file_patterns": [".*\\.heex$", ".*/live/.*\\.ex$"]
    },
    {
      "skill": "elixir-best-practices",
      "tool_matcher": "Write|Edit",
      "file_patterns": ["^lib/.*\\.ex$", ".*/test/.*\\.exs$"]
    },
    {
      "skill": "test-debugger",
      "tool_matcher": "Bash",
      "tool_input_matcher": "mix test"
    }
  ]
}
```

#### JavaScript/TypeScript Project

```json
{
  "mappings": [
    {
      "skill": "react-best-practices",
      "tool_matcher": "Write|Edit",
      "file_patterns": ["^src/.*\\.(tsx|jsx)$"]
    },
    {
      "skill": "typescript-patterns",
      "tool_matcher": "Write|Edit",
      "file_patterns": ["^src/.*\\.tsx?$"]
    }
  ]
}
```

#### MCP Tool Enforcement

```json
{
  "mappings": [
    {
      "skill": "tidewave",
      "tool_matcher": "mcp__tidewave__get_logs"
    }
  ]
}
```

## How It Works

### Pattern Matching

1. **Tool Matcher**: Uses regex to match tool names exactly as they appear (case-sensitive)

   - `"Write"` - matches only the Write tool
   - `"Write|Edit"` - matches either Write or Edit
   - `"Bash"` - matches the Bash tool
   - `"mcp__.*"` - matches any MCP tool

2. **Tool Input Matcher** (optional): Uses regex to match the JSON representation of tool inputs

   - Useful for matching specific commands: `"mix test"`, `"npm run"`
   - Matches against the entire tool input JSON string

3. **File Patterns** (optional): Uses regex patterns to match file paths
   - `.*\.ex$` - all .ex files at any level
   - `^lib/.*\.ex$` - .ex files only under lib/ directory
   - `.*/test/.*\.exs$` - .exs files in any test directory

   **Note**: Patterns are matched against the relative path from your project root. Remember to escape special regex characters like `.` with `\.`

### Conversation Continuation

The hook intelligently handles conversation continuation:

- When a conversation is resumed, only skills loaded **after** the continuation are checked
- This prevents false positives from skills loaded in previous conversation sessions

### Fail-Open Safety

The hook is designed to fail-open (allow tool use) if:

- The config file is missing or malformed
- `jq` is not installed
- The transcript is unavailable
- Any other error occurs

This ensures Claude can continue working even if the hook encounters issues.

## Available Skills

This plugin provides the following skills:

| Skill | Description |
|-------|-------------|
| `/skill-checker:setup-skill-checker` | Create or review the config file for your project |
| `/skill-checker:add-skill-check` | Add a new skill enforcement mapping |
| `/skill-checker:explain-skill-checker` | Learn how the plugin works |
| `/skill-checker:explain-skill-check` | Understand an existing mapping in detail |

## Debugging

Debug logging is opt-in. To enable it:

```bash
export SKILL_CHECKER_DEBUG=1
```

Debug output goes to `/tmp/skill-checker-debug.log`:

```bash
tail -f /tmp/skill-checker-debug.log
```

## Troubleshooting

### Hook Not Working

1. **Check config file exists**:
   ```bash
   ls -la .claude/hooks/skill-checker.json
   ```

2. **Validate JSON syntax**:
   ```bash
   jq '.' .claude/hooks/skill-checker.json
   ```

### Skills Not Being Detected

- Ensure skill names in your config exactly match the skill names used in your Skills directory
- Check that skills are being loaded AFTER conversation continuation (if applicable)
- Enable debug logging and review the log

### Hook Allowing Tool Use When It Shouldn't

- Verify your `tool_matcher` patterns are case-sensitive and exact
- Check that `file_patterns` are using proper regex syntax
- Test patterns match relative paths from your project root

## Requirements

- **jq**: Required for JSON parsing. Install with:
  - macOS: `brew install jq`
  - Linux: `apt-get install jq` or `yum install jq`

## Development

### Project Structure

```
skill-checker/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── hooks/
│   ├── hooks.json           # Hook configuration
│   └── skill-checker.sh     # Hook script
├── skills/                  # Plugin skills
│   ├── setup-skill-checker/
│   ├── add-skill-check/
│   ├── explain-skill-checker/
│   └── explain-skill-check/
├── config-templates/
│   └── skill-checker.example.json
├── CHANGELOG.md
└── README.md
```

## License

MIT
