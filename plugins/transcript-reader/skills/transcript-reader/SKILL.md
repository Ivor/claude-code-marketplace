---
name: transcript-reader
description: Find, read, and analyze Claude Code session transcripts. Use when the user asks about past sessions, wants to review what happened in a conversation, search for specific interactions, or reflect on how Claude performed. Understands the full transcript JSONL format including sub-agent conversations.
---

# Claude Code Transcript Reader

You are an expert at finding and analyzing Claude Code session transcripts. You understand the exact file formats and directory structure used by Claude Code to store conversation history.

## Directory Structure

All transcripts live under `~/.claude/`:

```
~/.claude/
├── history.jsonl                              # Global history (all sessions, large)
├── projects/                                  # Per-project session data
│   └── <encoded-project-path>/                # e.g. -Users-ivorpaul-code-myproject
│       ├── sessions-index.json                # Session metadata index (when present)
│       ├── <session-uuid>.jsonl               # Main session transcript
│       └── <session-uuid>/                    # Session artifacts
│           ├── subagents/                     # Sub-agent transcripts
│           │   ├── agent-<agentId>.jsonl      # Sub-agent conversation
│           │   └── agent-<agentId>.meta.json  # Sub-agent metadata
│           └── tool-results/                  # Cached tool results
└── sessions/                                  # Session lock files (runtime only)
```

**Project directory naming**: Absolute paths with `/` replaced by `-`, e.g. `/Users/ivorpaul/code/myproject` becomes `-Users-ivorpaul-code-myproject`.

## Finding Sessions

### Step 1: Locate the project directory

```bash
ls ~/.claude/projects/ | grep "<keyword>"
```

### Step 2: Check the sessions index (fastest way to find sessions)

The `sessions-index.json` file (when present) contains metadata for all sessions in that project:

```json
{
  "version": 1,
  "entries": [
    {
      "sessionId": "uuid",
      "fullPath": "/absolute/path/to/session.jsonl",
      "fileMtime": 1769422684163,
      "firstPrompt": "the user's opening message",
      "summary": "AI-generated session summary",
      "messageCount": 14,
      "created": "2026-03-04T10:23:00.000Z",
      "modified": "2026-03-04T11:45:00.000Z",
      "gitBranch": "feature-branch",
      "projectPath": "/Users/ivorpaul/code/myproject",
      "isSidechain": false
    }
  ],
  "originalPath": "/Users/ivorpaul/code/myproject"
}
```

Use `firstPrompt`, `summary`, `gitBranch`, and `created`/`modified` to identify the right session.

### Step 3: If no sessions-index.json, list JSONL files by date

```bash
ls -lt ~/.claude/projects/<project-dir>/*.jsonl
```

Then read the first line of each to see the opening user message.

## Transcript JSONL Format

Each `.jsonl` file has one JSON object per line. There are 7 message types:

### 1. User Messages (`type: "user"`)

```json
{
  "type": "user",
  "uuid": "uuid",
  "parentUuid": "uuid or null",
  "timestamp": "ISO-8601",
  "sessionId": "uuid",
  "isSidechain": false,
  "cwd": "/working/directory",
  "version": "2.1.85",
  "gitBranch": "main",
  "userType": "external",
  "entrypoint": "cli",
  "permissionMode": "default|bypassPermissions",
  "message": {
    "role": "user",
    "content": "string (plain text) OR array (tool results)"
  }
}
```

When content is an array, it contains tool results:
```json
{
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_...",
        "content": "result string or array",
        "is_error": false
      }
    ]
  }
}
```

### 2. Assistant Messages (`type: "assistant"`)

```json
{
  "type": "assistant",
  "uuid": "uuid",
  "parentUuid": "uuid",
  "timestamp": "ISO-8601",
  "sessionId": "uuid",
  "requestId": "req_...",
  "isSidechain": false,
  "cwd": "/working/directory",
  "version": "2.1.85",
  "gitBranch": "main",
  "message": {
    "model": "claude-opus-4-6",
    "id": "msg_...",
    "role": "assistant",
    "type": "message",
    "stop_reason": "end_turn|tool_use|null",
    "content": [
      { "type": "thinking", "thinking": "internal reasoning text" },
      { "type": "text", "text": "visible response text" },
      {
        "type": "tool_use",
        "id": "toolu_...",
        "name": "Bash|Read|Write|Edit|Grep|Glob|Agent|Skill|etc",
        "input": { "...tool-specific parameters..." }
      }
    ],
    "usage": {
      "input_tokens": 3,
      "cache_creation_input_tokens": 208,
      "cache_read_input_tokens": 19176,
      "output_tokens": 40
    }
  }
}
```

### 3. Progress Messages (`type: "progress"`)

Hook execution events:
```json
{
  "type": "progress",
  "parentUuid": "uuid",
  "toolUseID": "toolu_...",
  "data": {
    "type": "hook_progress",
    "hookEvent": "PreToolUse|PostToolUse",
    "hookName": "PreToolUse:Bash",
    "command": "/path/to/hook.sh"
  }
}
```

### 4. System Messages (`type: "system"`)

Two important subtypes:

**Turn duration** (marks end of an assistant turn):
```json
{
  "type": "system",
  "subtype": "turn_duration",
  "durationMs": 33823,
  "slug": "creative-name-adjective"
}
```

**Local command output** (user ran `! command`):
```json
{
  "type": "system",
  "subtype": "local_command",
  "content": "<local-command-stdout>output</local-command-stdout>",
  "level": "info"
}
```

### 5. Queue Operation (`type: "queue-operation"`)
```json
{ "type": "queue-operation", "operation": "enqueue|remove", "content": "queued text" }
```

### 6. File History Snapshot (`type: "file-history-snapshot"`)
```json
{ "type": "file-history-snapshot", "messageId": "uuid", "snapshot": { "trackedFileBackups": {} } }
```

### 7. Last Prompt (`type: "last-prompt"`)
```json
{ "type": "last-prompt", "lastPrompt": "final user text", "sessionId": "uuid" }
```

## Sub-agent Transcripts

When Claude spawns agents (via the Agent tool), each gets its own transcript.

**Location**: `~/.claude/projects/<project>/<session-uuid>/subagents/`

**Meta file** (`agent-<agentId>.meta.json`):
```json
{ "agentType": "Explore|general-purpose|Plan|browser-automation|etc", "description": "optional task description" }
```

**Transcript** (`agent-<agentId>.jsonl`): Same JSONL format as main transcripts, but with extra fields:
- `"isSidechain": true` — always true for sub-agents
- `"agentId": "a253aa0fd71eb5010"` — identifies which agent

Sub-agent results appear in the main transcript as tool results with this structure:
```json
{
  "type": "tool_result",
  "tool_use_id": "toolu_...",
  "content": [
    { "type": "text", "text": "Agent's final response" },
    { "type": "text", "text": "agentId: a253aa0fd71eb5010 (use SendMessage...)\n<usage>total_tokens: 15588\ntool_uses: 1\nduration_ms: 3027</usage>" }
  ]
}
```

## Reading Transcripts Efficiently

Transcripts can be large. Use these strategies:

### Quick overview — count messages by type
```bash
cat <file>.jsonl | python3 -c "
import sys, json, collections
counts = collections.Counter()
for line in sys.stdin:
    d = json.loads(line)
    t = d.get('type','?')
    sub = d.get('subtype','')
    counts[f'{t}:{sub}' if sub else t] += 1
for k,v in counts.most_common(): print(f'{v:4d}  {k}')
"
```

### Extract user messages only
```bash
cat <file>.jsonl | python3 -c "
import sys, json
for line in sys.stdin:
    d = json.loads(line)
    if d.get('type') == 'user' and isinstance(d.get('message',{}).get('content'), str):
        print(f\"[{d['timestamp']}] {d['message']['content'][:200]}\")
"
```

### Extract assistant text responses (no tool calls)
```bash
cat <file>.jsonl | python3 -c "
import sys, json
for line in sys.stdin:
    d = json.loads(line)
    if d.get('type') == 'assistant':
        for block in d.get('message',{}).get('content',[]):
            if block.get('type') == 'text':
                print(f\"[{d['timestamp']}] {block['text'][:300]}\")
                print('---')
"
```

### Extract tool usage summary
```bash
cat <file>.jsonl | python3 -c "
import sys, json, collections
tools = collections.Counter()
for line in sys.stdin:
    d = json.loads(line)
    if d.get('type') == 'assistant':
        for block in d.get('message',{}).get('content',[]):
            if block.get('type') == 'tool_use':
                tools[block['name']] += 1
for name, count in tools.most_common(): print(f'{count:4d}  {name}')
"
```

### Search for keywords across all sessions in a project
```bash
grep -l "keyword" ~/.claude/projects/<project-dir>/*.jsonl
```

### List sub-agents for a session
```bash
for f in ~/.claude/projects/<project>/<session-id>/subagents/*.meta.json; do
  echo "$(basename $f .meta.json): $(cat $f)"
done
```

### Token usage summary
```bash
cat <file>.jsonl | python3 -c "
import sys, json
total_in, total_out, total_cache = 0, 0, 0
for line in sys.stdin:
    d = json.loads(line)
    u = d.get('message',{}).get('usage',{})
    if u:
        total_in += u.get('input_tokens', 0)
        total_out += u.get('output_tokens', 0)
        total_cache += u.get('cache_read_input_tokens', 0)
print(f'Input: {total_in:,}  Output: {total_out:,}  Cache reads: {total_cache:,}')
"
```

## Analysis Patterns

When asked to analyze a session, follow this order:

1. **Find the session** — use sessions-index.json or grep for keywords
2. **Get overview** — message counts by type, token usage, duration
3. **Read user messages** — understand what was asked
4. **Read assistant text** — understand what was answered
5. **Check tool usage** — what tools were used and how often
6. **Check sub-agents** — list meta files, read their transcripts if relevant
7. **Identify patterns** — errors, retries, corrections, back-and-forth

When reflecting on Claude's performance:
- Look for user corrections ("no", "don't", "wrong", "stop")
- Count retries and failed tool calls (`is_error: true`)
- Check if thinking blocks show good reasoning
- Note when sub-agents were spawned vs inline work
- Track token efficiency (cache hits vs new input)
