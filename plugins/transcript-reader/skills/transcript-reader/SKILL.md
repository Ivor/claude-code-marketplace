---
name: transcript-reader
description: Find, read, and analyze Claude Code session transcripts. Use when the user asks about past sessions, wants to review what happened in a conversation, search for specific interactions, or reflect on how Claude performed. Understands the full transcript JSONL format including sub-agent conversations.
---

# Claude Code Transcript Reader

You are an expert at finding and analyzing Claude Code session transcripts.

## Critical Rules

1. **NEVER use the Read tool on JSONL transcript files.** Each line in a JSONL file can be 100K+ characters (a single JSON object per line). The Read tool will hit token limits and fail. Always use `Bash` with `python3` or `jq` to parse JSONL files.
2. **NEVER spawn sub-agents (Agent tool) for transcript analysis.** Do all analysis directly — the python3 scripts below are self-contained and efficient.
3. **Use the fewest possible Bash calls.** The comprehensive script below extracts everything in one pass. Only run additional scripts if you need to drill into specific details.

## Directory Structure

```
~/.claude/
├── projects/                                  # Per-project session data
│   └── <encoded-project-path>/                # Path with / replaced by -, e.g. -Users-alice-code-myproject
│       ├── sessions-index.json                # Session metadata index (when present)
│       ├── <session-uuid>.jsonl               # Main session transcript
│       └── <session-uuid>/                    # Session artifacts
│           ├── subagents/                     # Sub-agent transcripts
│           │   ├── agent-<agentId>.jsonl      # Sub-agent conversation (same JSONL format)
│           │   └── agent-<agentId>.meta.json  # {"agentType": "Explore|general-purpose|Plan|...", "description": "..."}
│           └── tool-results/                  # Cached tool results
└── history.jsonl                              # Global history (very large, avoid reading entirely)
```

## Finding Sessions

### By keyword — search sessions-index.json

```bash
# Find project directories
ls ~/.claude/projects/ | grep "<keyword>"

# Read sessions index (this is a regular JSON file — Read tool is OK here)
cat ~/.claude/projects/<project-dir>/sessions-index.json | python3 -c "
import sys, json
idx = json.load(sys.stdin)
for e in idx.get('entries', []):
    print(f\"{e['created'][:10]}  {e['sessionId'][:8]}...  branch={e.get('gitBranch','')}  msgs={e.get('messageCount','')}  {e.get('firstPrompt','')[:100]}\")
"
```

### By grep — search across all transcripts in a project

```bash
grep -l "keyword" ~/.claude/projects/<project-dir>/*.jsonl
```

## Comprehensive Session Analysis (ONE script)

This is your primary tool. Run this FIRST for any transcript analysis — it extracts everything in a single pass:

```bash
python3 -c "
import json, sys, collections, os, glob

f = '<TRANSCRIPT_PATH>'  # Replace with actual path
session_dir = f.replace('.jsonl', '')

# Parse main transcript
msgs = []
with open(f) as fh:
    for line in fh:
        msgs.append(json.loads(line))

# Basic counts
type_counts = collections.Counter()
tool_counts = collections.Counter()
user_messages = []
assistant_texts = []
thinking_blocks = []
errors = []
total_in = total_out = total_cache = 0
durations = []
models = set()

for m in msgs:
    t = m.get('type', '?')
    sub = m.get('subtype', '')
    type_counts[f'{t}:{sub}' if sub else t] += 1

    if t == 'user' and isinstance(m.get('message', {}).get('content'), str):
        user_messages.append((m.get('timestamp', ''), m['message']['content']))
    elif t == 'user' and isinstance(m.get('message', {}).get('content'), list):
        for item in m['message']['content']:
            if item.get('is_error'):
                errors.append((m.get('timestamp', ''), str(item.get('content', ''))[:200]))
    elif t == 'assistant':
        usage = m.get('message', {}).get('usage', {})
        if usage:
            total_in += usage.get('input_tokens', 0)
            total_out += usage.get('output_tokens', 0)
            total_cache += usage.get('cache_read_input_tokens', 0)
        model = m.get('message', {}).get('model', '')
        if model: models.add(model)
        for block in m.get('message', {}).get('content', []):
            if block.get('type') == 'tool_use':
                tool_counts[block['name']] += 1
            elif block.get('type') == 'text' and block.get('text', '').strip():
                assistant_texts.append((m.get('timestamp', ''), block['text']))
            elif block.get('type') == 'thinking':
                thinking_blocks.append(block.get('thinking', '')[:300])
    elif t == 'system' and sub == 'turn_duration':
        durations.append(m.get('durationMs', 0))

# Sub-agents
subagent_dir = os.path.join(session_dir, 'subagents')
subagents = []
if os.path.isdir(subagent_dir):
    for meta_file in sorted(glob.glob(os.path.join(subagent_dir, '*.meta.json'))):
        agent_id = os.path.basename(meta_file).replace('.meta.json', '')
        with open(meta_file) as mf:
            meta = json.load(mf)
        jsonl_file = meta_file.replace('.meta.json', '.jsonl')
        agent_tool_counts = collections.Counter()
        agent_msgs = 0
        agent_user_prompts = []
        if os.path.exists(jsonl_file):
            with open(jsonl_file) as af:
                for line in af:
                    am = json.loads(line)
                    agent_msgs += 1
                    if am.get('type') == 'assistant':
                        for block in am.get('message', {}).get('content', []):
                            if block.get('type') == 'tool_use':
                                agent_tool_counts[block['name']] += 1
                    elif am.get('type') == 'user' and isinstance(am.get('message', {}).get('content'), str):
                        agent_user_prompts.append(am['message']['content'][:200])
        subagents.append({
            'id': agent_id,
            'type': meta.get('agentType', '?'),
            'description': meta.get('description', ''),
            'messages': agent_msgs,
            'tools': dict(agent_tool_counts.most_common()),
            'prompt': agent_user_prompts[0] if agent_user_prompts else ''
        })

# Output report
print('=' * 60)
print('SESSION ANALYSIS')
print('=' * 60)

print(f'\nSession ID: {msgs[0].get(\"sessionId\", \"?\") if msgs else \"?\"}')
print(f'Branch: {msgs[0].get(\"gitBranch\", \"?\") if msgs else \"?\"}')
print(f'Version: {msgs[0].get(\"version\", \"?\") if msgs else \"?\"}')
print(f'Models: {\", \".join(models) if models else \"?\"}')
print(f'Total messages (JSONL lines): {len(msgs)}')
print(f'Turn durations: {durations}ms') if durations else None
print(f'Total duration: {sum(durations):,}ms ({sum(durations)/1000:.1f}s)') if durations else None

print(f'\n--- Message Types ---')
for k, v in type_counts.most_common():
    print(f'  {v:4d}  {k}')

print(f'\n--- Tool Usage ---')
total_tools = sum(tool_counts.values())
print(f'  Total tool calls: {total_tools}')
for name, count in tool_counts.most_common():
    print(f'  {count:4d}  {name}')

print(f'\n--- Token Usage ---')
print(f'  Input: {total_in:,}  Output: {total_out:,}  Cache reads: {total_cache:,}')

print(f'\n--- User Messages ({len(user_messages)}) ---')
for ts, content in user_messages:
    print(f'  [{ts[:19]}] {content[:200]}')

print(f'\n--- Assistant Responses ({len(assistant_texts)}) ---')
for ts, text in assistant_texts:
    print(f'  [{ts[:19]}] {text[:300]}')
    print()

if errors:
    print(f'\n--- Errors ({len(errors)}) ---')
    for ts, err in errors:
        print(f'  [{ts[:19]}] {err}')

if thinking_blocks:
    print(f'\n--- Thinking Blocks ({len(thinking_blocks)}) ---')
    for i, t in enumerate(thinking_blocks):
        print(f'  [{i+1}] {t}')
        print()

print(f'\n--- Sub-agents ({len(subagents)}) ---')
if not subagents:
    print('  None')
else:
    for sa in subagents:
        print(f'  Agent: {sa[\"id\"]}')
        print(f'    Type: {sa[\"type\"]}')
        print(f'    Description: {sa[\"description\"]}')
        print(f'    Messages: {sa[\"messages\"]}')
        print(f'    Prompt: {sa[\"prompt\"][:200]}')
        print(f'    Tools: {sa[\"tools\"]}')
        print()

print('=' * 60)
"
```

**Replace `<TRANSCRIPT_PATH>` with the actual `.jsonl` file path before running.**

## Drilling Deeper

After running the comprehensive script, you may need to investigate specific details:

### Read a specific user message in full
```bash
python3 -c "
import json
with open('<TRANSCRIPT_PATH>') as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        if d.get('type') == 'user' and isinstance(d.get('message',{}).get('content'), str):
            if '<KEYWORD>' in d['message']['content'].lower():
                print(f'Line {i}: {d[\"message\"][\"content\"]}')"
```

### Read a specific assistant response in full
```bash
python3 -c "
import json
with open('<TRANSCRIPT_PATH>') as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        if d.get('type') == 'assistant':
            for block in d.get('message',{}).get('content',[]):
                if block.get('type') == 'text' and '<KEYWORD>' in block.get('text','').lower():
                    print(f'Line {i}: {block[\"text\"]}')"
```

### Read thinking blocks in full
```bash
python3 -c "
import json
with open('<TRANSCRIPT_PATH>') as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        if d.get('type') == 'assistant':
            for block in d.get('message',{}).get('content',[]):
                if block.get('type') == 'thinking':
                    print(f'=== Line {i} ===')
                    print(block['thinking'])
                    print()"
```

### Check tool call details (inputs/outputs for a specific tool)
```bash
python3 -c "
import json
TOOL = '<TOOL_NAME>'  # e.g. 'Bash', 'Read', 'Agent'
with open('<TRANSCRIPT_PATH>') as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        if d.get('type') == 'assistant':
            for block in d.get('message',{}).get('content',[]):
                if block.get('type') == 'tool_use' and block.get('name') == TOOL:
                    inp = json.dumps(block.get('input',{}))[:500]
                    print(f'Line {i}: {block[\"name\"]} -> {inp}')
                    print()"
```

### Analyze a specific sub-agent transcript
Use the comprehensive script above but change the file path to the sub-agent's `.jsonl` file (found in `<session-dir>/subagents/agent-<id>.jsonl`).

## JSONL Message Types Reference

| Type | Key Fields | Notes |
|------|-----------|-------|
| `user` | `message.content` (string or array) | String = user text. Array = tool results. |
| `assistant` | `message.content[]` (thinking/text/tool_use), `message.usage` | Main conversation turns |
| `progress` | `data.hookEvent`, `data.hookName` | Hook execution events — usually noise |
| `system` | `subtype`: `turn_duration` or `local_command` | Turn timing and `!` commands |
| `queue-operation` | `operation`, `content` | Queued user input |
| `file-history-snapshot` | `snapshot.trackedFileBackups` | File tracking checkpoints |
| `last-prompt` | `lastPrompt` | Final message marker |

## Sub-agent Meta Format

```json
{ "agentType": "Explore|general-purpose|Plan|browser-automation|claude-code-guide", "description": "optional task description" }
```

Sub-agent transcripts use the same JSONL format with extra fields: `"isSidechain": true`, `"agentId": "<id>"`.

## Performance Reflection Checklist

When asked to evaluate how Claude performed in a session:

- **Completeness**: Did the session produce the requested deliverable?
- **User corrections**: Search for messages containing "no", "don't", "wrong", "stop", "not that"
- **Failed tool calls**: Count `is_error: true` in tool results
- **Retries**: Same tool called multiple times with similar inputs
- **Efficiency**: Total tool calls, token usage, cache hit ratio (`cache_read / (input + cache_read)`)
- **Skill usage**: Did Claude activate relevant skills when it should have?
- **Sub-agent usage**: Were sub-agents spawned appropriately or wastefully?
- **Session outcome**: Check if the last message is `last-prompt` (normal end), `tool_result` (interrupted mid-turn), or `assistant` with `stop_reason: "end_turn"` (completed)
