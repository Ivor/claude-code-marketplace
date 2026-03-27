# Ivor's Claude Code Marketplace

A collection of Claude Code plugins for workflow automation and best practices.

## Available Plugins

### skill-checker

Enforces skill activation before using specific tools. Ensures Claude loads required skills (like `elixir-best-practices`, `test-debugger`) before editing files or running commands.

**[View Plugin Documentation](./plugins/skill-checker/README.md)**

### elixir-quick-context

Instantly discover file dependencies and module relationships in Elixir projects by querying the compile manifest. Includes search, tree, and dependency lookup scripts — no code search needed.

**[View Plugin Documentation](./plugins/elixir-quick-context/README.md)**

### skill-optimizer

Iteratively improve Claude Code skills through measured test-refine-commit cycles. Run a skill via `claude -p`, analyze the transcript, identify waste, improve, and repeat. Includes the "Description Trick" — a key insight about how skill descriptions control whether the skill body is ever loaded.

**[View Plugin Documentation](./plugins/skill-optimizer/README.md)**

### transcript-reader

Analyze Claude Code session transcripts — what happened, which tools were used, how sub-agents performed, and where things went wrong. Includes meandering detection to find retries, circular patterns, and wasted effort.

**[View Plugin Documentation](./plugins/transcript-reader/README.md)**

## Installation

### Step 1: Add the marketplace

```bash
claude plugin marketplace add Ivor/claude-code-marketplace
```

### Step 2: Install plugins

```bash
claude plugin install skill-checker@ivors-claude-code-marketplace
claude plugin install elixir-quick-context@ivors-claude-code-marketplace
claude plugin install transcript-reader@ivors-claude-code-marketplace
claude plugin install skill-optimizer@ivors-claude-code-marketplace
```

### Step 3: Enable auto-update

Third-party marketplaces don't auto-update by default. To receive updates automatically:

1. Run `/plugin` in Claude Code
2. Go to the **Marketplaces** tab
3. Select `ivors-claude-code-marketplace`
4. Enable **auto-update**

Without this, you'll need to manually update plugins with:

```bash
claude plugin update skill-checker@ivors-claude-code-marketplace
```

## Plugin Structure

This marketplace follows the official Claude Code plugin structure:

```
claude-code-marketplace/              # Marketplace root
├── .claude-plugin/
│   └── marketplace.json              # Marketplace catalog
└── plugins/
    ├── skill-checker/                # Skill enforcement hooks
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   ├── hooks/
    │   ├── skills/
    │   └── test/
    ├── elixir-quick-context/         # Elixir dependency explorer
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   ├── skills/
    │   └── scripts/
    ├── transcript-reader/            # Session transcript analysis
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   ├── skills/
    │   └── scripts/
    └── skill-optimizer/              # Skill optimization loop
        ├── .claude-plugin/
        │   └── plugin.json
        ├── skills/
        └── references/
```

## Contributing

To add a new plugin to this marketplace:

1. Create a new directory under `plugins/`
2. Add the plugin structure with `.claude-plugin/plugin.json`
3. Update `.claude-plugin/marketplace.json` to include your plugin
4. Submit a pull request

## License

MIT
