---
name: elixir-quick-context
description: Use at the start of any Elixir/Phoenix task to understand a module's dependencies and what depends on it, so you can plan changes that consider the broader scope and blast radius. Maps forward dependencies (what this module needs) and reverse dependencies (what breaks if this module changes) by querying the compile manifest — no code search needed.
---

# Quick Project Context

Instantly discover what files are related to a given source file or module by querying the Elixir compile manifest. This replaces the need for broad codebase searches when starting work on a file.

## When to use

- At the start of a task that involves working on one or more Elixir source files
- When asked to explain, modify, or debug a module
- When planning what files to read before making changes
- When assessing the blast radius of a change

## Scripts

Run all scripts from the Elixir project's root directory (where `mix.exs` lives). The scripts auto-detect the compile manifest at `_build/dev/lib/<app>/.mix/compile.elixir`. If auto-detection fails (e.g. multiple apps in an umbrella), pass the manifest path as the last argument to any script.

### Search — discover modules by keyword

When the user's prompt doesn't reference specific modules, use the search script to find entry points:

```bash
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_search.exs <keyword>
```

This searches all module names and source file paths in the manifest for a case-insensitive keyword match. Use it to discover which modules exist for a given domain before running the lookup.

### Tree — view the namespace structure

See the module namespace hierarchy as a tree. Supports `--depth N` to limit how deep the tree goes — collapsed branches show their module count.

```bash
# Project-wide overview (top-level namespaces with module counts)
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_tree.exs --depth 1

# Full detail for a specific namespace
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_tree.exs Some.Namespace
```

Use `--depth 1` as a starting point to see the full project map, then zoom into a specific namespace without the depth flag to see every module.

### Lookup — explore a module's dependency graph

```bash
# By file path
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_lookup.exs lib/backend/some_file.ex

# By module name
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_lookup.exs Some.Module

# Multiple targets (comma-separated)
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_lookup.exs Some.Module,Another.Module
```

The lookup script outputs a structured summary with four sections:

**Forward dependencies (what does this module need?):**

1. **Export dependencies** — the most useful category. These are the modules whose public interface (functions, structs, components) this file actually uses. Prioritise reading these.
2. **Runtime dependencies** — modules called at runtime. Overlaps with export deps, plus some framework modules.
3. **Compile-time dependencies** — modules whose macros run during compilation. Mostly framework boilerplate — rarely need to read these.

**Reverse dependencies (what needs this module?):**

4. **Depended on by** — every file in the project that depends on this module, grouped by layer (business logic, controllers, GraphQL resolvers, GraphQL types, LiveViews, web infra, workers, tests). Use this to assess blast radius and find consumers.

## Reading strategy

After running the lookup, prioritise reading files in this order:

1. **Sibling files** — files in the same directory or `components/` subdirectory (from export deps)
2. **Context/domain modules** — the business logic layer (from export deps)
3. **The target file itself** — now with full context of what it depends on
4. **Shared helpers** — common helper modules (from runtime deps) — only if needed

Skip framework/infrastructure files unless the task specifically involves routing or infrastructure.

## Exploring a system or area

When the user asks about a **system** or **area** rather than a single file, one level of lookup is not enough. The first run gives you the module's direct dependencies, but the closely related modules have their own dependency graphs that complete the picture.

**Strategy:**

1. If the user's prompt doesn't mention specific modules, **search first** to discover the relevant modules in the manifest
2. Run the lookup on the entry-point module(s) you identify
3. From the export dependencies, identify **closely related project modules** — ones in the same domain or that represent key relationships
4. Run the lookup again on those related modules in a second pass
5. The **reverse dependencies** section ("Depended on by") surfaces the consumers: controllers, LiveViews, GraphQL resolvers, workers — these are often missed by forward-only lookups

This gives you the full bidirectional picture: what the system depends on, what depends on it, and where it's consumed across the web and worker layers.

## How it works

The scripts read `_build/dev/lib/<app>/.mix/compile.elixir` — a binary file (Erlang Term Format) that Mix maintains as its compilation manifest. It contains the full dependency graph for every source file and module in the project. The scripts deserialise it and print a human-readable summary. The binary is never loaded into context.

## Requirements

- Run from the Elixir project's root directory (where `mix.exs` lives)
- The scripts auto-detect the manifest. If multiple apps exist under `_build/dev/lib/`, pass the manifest path as the last argument
- If the script reports the manifest is not found, surface that error to the user — do NOT run `mix compile` to fix it
- If the manifest is stale (files changed since last compile), the dependency info may be incomplete for newly added files — this is fine, proceed with what's available
