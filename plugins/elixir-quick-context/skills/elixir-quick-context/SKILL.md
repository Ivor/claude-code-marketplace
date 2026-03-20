---
name: elixir-quick-context
description: Use at the start of any Elixir/Phoenix task to understand a module's dependencies and what depends on it, so you can plan changes that consider the broader scope and blast radius. Maps forward dependencies (what this module needs) and reverse dependencies (what breaks if this module changes) by querying the compile manifest — no code search needed.
---

# Quick Project Context

Run scripts from the Elixir project root (where `mix.exs` lives). They auto-detect the manifest at `_build/dev/lib/<app>/.mix/compile.elixir`. For umbrella apps, pass the manifest path as the last argument.

## Search — discover modules by keyword

```bash
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_search.exs <keyword>
```

Use when the user's prompt doesn't reference specific modules. Find entry points before running lookup.

## Tree — view namespace structure

```bash
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_tree.exs --depth 1
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_tree.exs Some.Namespace
```

## Lookup — explore dependency graph

```bash
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_lookup.exs lib/backend/some_file.ex
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_lookup.exs Some.Module
elixir ${CLAUDE_PLUGIN_ROOT}/scripts/manifest_lookup.exs Some.Module,Another.Module
```

Outputs four sections. Prioritise **export dependencies** — these are the modules whose public interface this file actually uses. Read these first. Compile-time deps are mostly framework boilerplate — skip unless relevant.

The **reverse dependencies** section shows every file that depends on this module, grouped by layer. Use this to assess blast radius.

## Multi-level exploration

When exploring a system rather than a single file, search first, lookup the entry points, then run a second lookup on the closely related modules from the export deps. The reverse deps surface consumers (controllers, LiveViews, resolvers, workers) that forward-only lookups miss.

## Constraints

- If the manifest is not found, surface the error to the user — do NOT run `mix compile` to fix it
- Stale manifests may be incomplete for newly added files — proceed with what's available
