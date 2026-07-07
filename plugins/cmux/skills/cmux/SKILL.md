---
name: cmux
description: "MUST activate when CMUX_WORKSPACE_ID is set (you are then running inside cmux) — drive workspaces, panes, tabs, the sidebar, and the browser with cmux CLI commands, never bare keyboard-shortcut suggestions. Also activate when the user asks about cmux shortcuts, navigation, or terminal management."
---

# cmux — Terminal Multiplexer for AI Agents

cmux is a native macOS terminal built for managing AI coding agent sessions. It provides keyboard shortcuts for users and a full CLI for agents.

## User Keyboard Shortcuts

See [references/keyboard-shortcuts.md](references/keyboard-shortcuts.md).

## Naming Hierarchy

```
Window (window:1)                        ← the application window
└── Workspace ("Main Backend")           ← sidebar entry, like a project/session
    ├── Pane (pane:1)                    ← a visual split region within a workspace
    │   ├── Surface/Tab ("lazygit")      ← a terminal tab within a pane
    │   └── Surface/Tab ("mix test")
    └── Pane (pane:2)                    ← created by `new-split`
        └── Surface/Tab ("iex")
```

- **Window** = the application window. Most setups have one. Ref: `window:N`.
- **Workspace** = a sidebar grouping containing panes. Ref: `workspace:N`. Rename with `cmux rename-workspace`.
- **Pane** = a split region within a workspace. Ref: `pane:N`. Created by `cmux new-split` (which also creates a surface inside it).
- **Surface/Tab** = a terminal (or browser) tab within a pane. Ref: `surface:N` or `tab:N` (interchangeable — same IDs). Created by `cmux new-surface --pane <ref>`. Rename with `cmux rename-tab`.

Key distinctions:
- **`new-split`** creates a new **pane** (with one surface in it) — a visual split.
- **`new-surface`** adds a new **tab** to an existing pane — no visual split.
- **When the user says "new tab"** → `cmux new-surface --pane <ref>`, NOT `cmux new-split`.
- **When the user says "rename this tab"** → `cmux rename-tab`, NOT `cmux rename-workspace`.

## Creating Things

| What | Command | Returns | Notes |
|------|---------|---------|-------|
| Workspace | `cmux new-workspace --cwd <path> "Name"` | `workspace:N` | Only command with `--cwd` |
| Split (pane + surface) | `cmux new-split <left\|right\|up\|down>` | `surface:N workspace:N` | Visual split — creates a new pane with one surface |
| Pane (pane + surface) | `cmux new-pane --direction <dir>` | `surface:N pane:N workspace:N` | Same as `new-split` |
| Tab in existing pane | `cmux new-surface --pane <ref>` | `surface:N pane:N workspace:N` | No visual split — adds a tab |

**Rules:**
- Only `new-workspace` supports `--cwd`. For splits/tabs, send a `cd` command after creating.
- All commands default to your own workspace. Pass `--workspace` when targeting a different one.
- After `new-workspace`, note the returned ref and target it explicitly — it does not become "current".

## Sending Messages Between Terminals

`cmux send` types text but does **not** press Enter. Always follow with `cmux send-key ... Enter`.

| Target | Flags needed | Example |
|--------|-------------|---------|
| Self | none | `cmux send "text"` |
| Same workspace, other surface | `--surface` | `cmux send --surface surface:44 "text"` |
| Different workspace, specific surface | `--workspace` + `--surface` | `cmux send --workspace workspace:1 --surface surface:37 "text"` |
| Different workspace, selected surface | `--workspace` only | `cmux send --workspace workspace:1 "text"` |

**Rules (verified):**
- Cross-workspace without `--workspace` **errors**: `"Surface is not a terminal"`.
- `--workspace` without `--surface` sends to whichever surface is currently selected — use with caution.
- Always follow `cmux send` with `cmux send-key [same flags] Enter`.
- Always check the `OK` response — it echoes the actual surface and workspace delivered to.

### Agent-to-Agent Communication

When sending a message to another terminal that has a Claude agent running, **always include reply-back instructions** so the receiving agent knows how to respond. The receiving agent does not know your refs unless you tell it.

**Pattern:**
```bash
# 1. Run cmux identify to get your own refs
# 2. Include them in the message to the other agent
cmux send --workspace workspace:X --surface surface:Y \
  "Your task here. When done, reply by running: cmux send --workspace workspace:MINE --surface surface:MINE 'your response here' && cmux send-key --workspace workspace:MINE --surface surface:MINE Enter"
cmux send-key --workspace workspace:X --surface surface:Y Enter
```

This enables two-way communication between agents across workspaces. Without reply-back instructions, the receiving agent has no way to report results back.

> **Skip reply-back when no reply is wanted or possible** — e.g. you asked the receiver to close the very workspace you're sending from, or you're about to exit. A reply-to pointing at a dead surface is wasted; fire-and-forget is correct for self-closing requests.

### Blocking on another terminal (signals)

For handoffs where you must wait for another terminal to finish, use a named signal instead of polling its screen:

```bash
# Waiter (blocks up to --timeout seconds, default 30):
cmux wait-for build-done --timeout 600
# Signaller (the other terminal, when done):
cmux wait-for -S build-done
```

Both sides must agree on the token name. Prefer this over a `read-screen` poll-loop when the other side can signal.

## Reading a Surface

To see what another terminal is showing (monitoring a build, checking an agent's last output, confirming a prompt appeared), read its text — don't guess:

```bash
cmux read-screen --surface <ref> --workspace <ref>            # visible viewport
cmux read-screen --surface <ref> --workspace <ref> --lines 200 # last 200 lines of scrollback
```

- `--scrollback` (or `--lines <n>`, which implies it) reaches beyond the visible viewport.
- Defaults to your own surface when flags are omitted.
- `cmux capture-pane` is a tmux-compatible alias for the same thing.
- To wait for a condition, prefer a signal (see above) over a tight `read-screen` poll-loop; if you must poll, use an `until`-loop, not fixed sleeps.

## Renaming Things

| What | Command | Accepts |
|------|---------|---------|
| Workspace | `cmux rename-workspace "Name"` | `--workspace` to target another workspace |
| Tab/Surface | `cmux rename-tab "Name"` | `--surface` or `--tab` (interchangeable) |

Without flags, both rename the caller's own workspace/tab.

## Closing Things

| What | Command | Behaviour |
|------|---------|-----------|
| A workspace | `cmux close-workspace --workspace <ref>` | Closes all surfaces/panes in the workspace at once |
| A surface | `cmux close-surface --surface <ref>` | Pane auto-removes if it was the last surface in it |
| Last surface in workspace | (blocked by `close-surface`) | Errors: `"Cannot close the last surface"` — use `close-workspace` instead |

**Prefer `close-workspace`** when tearing down an entire workspace — it's one command instead of manually stopping processes and exiting shells in each surface.

**Never close your own workspace or surface** — it kills your terminal session. Always check `cmux tree` first (your surface is marked `◀ here`).

## Restarting a Phoenix server (BEAM) in another surface

Sending `Ctrl-C` to a `mix phx.server` surface drops the BEAM into the `BREAK:` menu — it does **not** abort by itself. Without sending the `a` + `Enter` follow-up, the port stays held and the next `mix phx.server` will fail.

```bash
# 1. Send Ctrl-C
cmux send-key --surface <surface> --workspace <workspace> ctrl-c

# 2. Confirm the BREAK: menu appeared
cmux read-screen --surface <surface> --workspace <workspace> --lines 8
# Expect: "BREAK: (a)bort (A)bort with dump (c)ontinue ..."

# 3. Type 'a' then Enter (treat as one atomic action)
cmux send     --surface <surface> --workspace <workspace> "a"
cmux send-key --surface <surface> --workspace <workspace> Enter

# 4. Wait for the port to free (don't poll-spin; use until-loop)
until ! lsof -nP -iTCP:<port> -sTCP:LISTEN 2>/dev/null | grep -q LISTEN; do sleep 1; done

# 5. Re-export env in the same shell, then start. `direnv allow` only marks the file
#    trusted — it does NOT export. Use `direnv reload` (or `cd .`, or `source .envrc`).
cmux send     --surface <surface> --workspace <workspace> "direnv reload && iex -S mix phx.server"
cmux send-key --surface <surface> --workspace <workspace> Enter
```

Notes:
- Whenever `.envrc` has changed, the previously-running shell still holds the OLD env. You must either re-export in that shell (`direnv reload` / `cd .` / `source .envrc`) or open a fresh shell — otherwise `mix phx.server` will silently re-launch with stale config.
- Prefer `iex -S mix phx.server` over plain `mix phx.server` so you have an attached REPL for runtime verification.
- Verify the new env reached the BEAM via Tidewave / IEx (e.g. `Application.get_env(:my_app, MyClient)`) before reporting the restart as done.

## CRITICAL: Always Verify Refs Before Acting

**Never assume or reuse stale refs.** Workspace, surface, pane, and tab refs can change at any time (surfaces close, workspaces are created/destroyed, the user rearranges things). Before any cross-workspace operation:

1. **Run `cmux identify`** to confirm your own refs and see what's currently focused.
2. **Run `cmux tree --workspace <ref>`** (or `--all`) to confirm the target workspace/surface still exists and has the layout you expect.
3. **Only then** issue commands with `--workspace` and `--surface` flags using the verified refs.

Sending to the wrong surface can type commands into the wrong terminal — potentially destructive. Treat ref verification as mandatory, not optional.

## Identifying Things

| What | Command | Shows |
|------|---------|-------|
| Your own refs | `cmux identify` | `caller.surface_ref`, `caller.workspace_ref`, plus focused surface |
| One workspace's layout | `cmux tree --workspace <ref>` | All panes and surfaces in that workspace |
| Full layout | `cmux tree --all` | All windows, workspaces, panes, surfaces |
| Current surface is marked | `◀ here` in tree output | |

## Verify Your Work

After any mutating operation (creating, renaming, or closing workspaces/panes/surfaces), always verify the result:

- **Create/Rename**: Run `cmux tree --workspace <ref>` (or `--all`) to confirm the new state matches expectations.
- **Close**: Run `cmux tree --workspace <ref>` and check for an error (`Workspace not found` = success) or confirm the surface/pane is gone from the tree.

Do not report success to the user until verification passes. If verification shows the operation didn't take effect, retry or investigate before reporting.

## Surfacing State to the User

The sidebar can show your progress without the user watching the terminal scroll. Use it for long-running work (builds, test suites, migrations) and to draw attention on completion or failure.

| What | Command | Appears as |
|------|---------|-----------|
| Status pill | `cmux set-status <key> "<value>" [--icon <name>] [--color "#hex"]` | A pill in the workspace's tab row; `<key>` namespaces it (e.g. `claude`, `build`) so entries don't clobber each other |
| Clear a pill | `cmux clear-status <key>` | Removes that pill |
| Progress bar | `cmux set-progress <0.0-1.0> [--label "<text>"]` / `cmux clear-progress` | A bar in the sidebar |
| Log line | `cmux log [--level info\|success\|warning\|error] [--source <name>] "<message>"` | An entry in the workspace log |
| Desktop notification | `cmux notify --title "<text>" [--subtitle <text>] [--body <text>]` | An OS notification |
| Flash for attention | `cmux trigger-flash [--surface <ref>]` | The unread-flash indicator on a surface |

- All default to your own workspace/surface; pass `--workspace`/`--surface` to report into another.
- Reserve `notify` and `error`-level logs for things the user genuinely needs to act on — noise trains them to ignore it.
- `claude_code` is the pill the Claude Code hook already manages — pick your own key (e.g. `build`, `tests`) so you don't clobber it.

## Checking Surface Health

`cmux surface-health [--workspace <ref>]` lists each surface with its `type` (terminal/browser) and whether it's live (`in_window=true`) — use it to confirm a surface exists and is attached before sending to it, or that one you just spawned came up.

## Viewing Files

For **markdown**, use the native viewer: `cmux markdown open <path>` — it renders the markdown in a formatted panel with live-reload, in the caller's workspace. Do **not** open a `.md` in a browser pane (over `file://` it shows raw plaintext), and prefer this over `glow`.

For **code/other text files**, use `bat`.

## Browser

For **viewing web content for the user** (a generated HTML report, a URL), open a browser pane in **your own (caller's) workspace**, not the focused surface (the focused one may be an unrelated workspace's browser):

```bash
cmux new-pane --type browser --direction right --url <url>   # defaults to caller's workspace
```

Markdown is the exception — use `cmux markdown open` (see Viewing Files), not a browser pane.

For **browser automation/testing** (click, type, eval, snapshot, screenshot) the cmux `browser` subcommands exist, but this project's standing rule is to use the `playwright-cli` terminal tool for that work — do not drive automation through `cmux browser`.

## Links

- Docs: https://cmux.dev/docs
- Discord: https://discord.gg/xsgFEVrWCZ
- GitHub: https://github.com/manaflow-ai/cmux
- Email: founders@manaflow.com
