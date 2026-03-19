# Elixir Quick Context Plugin

Instantly discover file dependencies and module relationships in Elixir projects by querying the compile manifest. No code search needed.

## What It Does

When Claude starts working on an Elixir file, this plugin provides three scripts that query the compile manifest to map out the dependency graph:

- **Search** — find modules by keyword
- **Tree** — view the namespace hierarchy
- **Lookup** — explore a module's full dependency graph (forward and reverse)

This replaces broad codebase searches with precise, instant results.

## Installation

```bash
claude plugin marketplace add https://github.com/Ivor/claude-code-marketplace
claude plugin install elixir-quick-context@ivors-claude-code-marketplace
```

## Usage

The plugin activates automatically when Claude works on Elixir/Phoenix source files. You can also invoke it directly:

```
/elixir-quick-context:quick-project-context
```

### Search

```bash
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_search.exs account
```

Finds all modules matching "account" — grouped by namespace with module counts.

### Tree

```bash
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_tree.exs --depth 1
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_tree.exs Backend.Accounts
```

Shows the module namespace hierarchy. Use `--depth 1` for an overview, then zoom into specific namespaces.

### Lookup

```bash
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_lookup.exs lib/backend/accounts/user.ex
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_lookup.exs Backend.Accounts.User
```

Shows four sections:
1. **Export dependencies** — modules whose public interface this file uses (read these first)
2. **Runtime dependencies** — modules called at runtime
3. **Compile-time dependencies** — macro dependencies (usually skip)
4. **Reverse dependencies** — every file that depends on this module, grouped by layer

## How It Works

The scripts read `_build/dev/lib/<app>/.mix/compile.elixir` — a binary file (Erlang Term Format) that Mix maintains as its compilation manifest. It contains the full dependency graph for every source file and module. The scripts deserialise it and print a human-readable summary.

## Requirements

- Elixir installed
- Run from the project root (where `mix.exs` lives)
- Project must have been compiled at least once (`_build/` must exist)

## License

MIT
