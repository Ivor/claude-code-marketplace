# Skill Checker Marketplace

A Claude Code plugin marketplace containing workflow automation tools.

## Available Plugins

### skill-checker

Enforces skill activation before using specific tools. Ensures Claude loads required skills (like `elixir-best-practices`, `test-debugger`) before editing files or running commands.

**[View Plugin Documentation](./plugins/skill-checker/README.md)**

## Installation

### Add this marketplace to Claude Code:

```bash
# From GitHub (recommended)
claude plugin marketplace add https://github.com/Ivor/claude-code-marketplace

# Or from local directory (for development)
claude plugin marketplace add /path/to/skill-checker
```

### Install plugins:

```bash
claude plugin install skill-checker@ivors-claude-code-marketplace
```

## Plugin Structure

This marketplace follows the official Claude Code plugin structure:

```
skill-checker/                        # Marketplace root
├── .claude-plugin/
│   └── marketplace.json              # Marketplace catalog
└── plugins/
    └── skill-checker/                # Individual plugin
        ├── .claude-plugin/
        │   └── plugin.json           # Plugin manifest
        ├── hooks/                    # Hook scripts and config
        ├── commands/                 # Slash commands
        └── config-templates/         # Template configs
```

## Contributing

To add a new plugin to this marketplace:

1. Create a new directory under `plugins/`
2. Add the plugin structure with `.claude-plugin/plugin.json`
3. Update `.claude-plugin/marketplace.json` to include your plugin
4. Submit a pull request

## License

MIT
