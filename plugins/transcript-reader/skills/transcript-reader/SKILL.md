---
name: transcript-reader
description: Find, read, and analyze Claude Code session transcripts. Use when the user asks about past sessions, wants to review what happened in a conversation, search for specific interactions, or reflect on how Claude performed. Understands the full transcript JSONL format including sub-agent conversations.
---

# Claude Code Transcript Reader

## How to Analyze a Transcript

When given a transcript path (or after finding one), run this **single Bash command** as your FIRST action. Do NOT read the file with the Read tool — JSONL lines are 100K+ characters and will fail. This script extracts everything in one pass:

```bash
python3 -c "
import json, sys, collections, os, glob

f = sys.argv[1]
session_dir = f.replace('.jsonl', '')

msgs = []
with open(f) as fh:
    for line in fh:
        msgs.append(json.loads(line))

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
                thinking_blocks.append(block.get('thinking', '')[:500])
    elif t == 'system' and sub == 'turn_duration':
        durations.append(m.get('durationMs', 0))

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
            'id': agent_id, 'type': meta.get('agentType', '?'),
            'description': meta.get('description', ''), 'messages': agent_msgs,
            'tools': dict(agent_tool_counts.most_common()),
            'prompt': agent_user_prompts[0] if agent_user_prompts else ''
        })

print('=' * 60)
print('SESSION ANALYSIS')
print('=' * 60)
print(f\"\"\"
Session ID: {msgs[0].get('sessionId', '?') if msgs else '?'}
Branch: {msgs[0].get('gitBranch', '?') if msgs else '?'}
Version: {msgs[0].get('version', '?') if msgs else '?'}
Models: {', '.join(models) if models else '?'}
Total JSONL lines: {len(msgs)}
Total duration: {sum(durations):,}ms ({sum(durations)/1000:.1f}s)
Tokens — Input: {total_in:,}  Output: {total_out:,}  Cache: {total_cache:,}
\"\"\")

print('--- Message Types ---')
for k, v in type_counts.most_common():
    print(f'  {v:4d}  {k}')

print(f'\n--- Tool Usage ({sum(tool_counts.values())} calls) ---')
for name, count in tool_counts.most_common():
    print(f'  {count:4d}  {name}')

print(f'\n--- User Messages ({len(user_messages)}) ---')
for ts, content in user_messages:
    print(f'  [{ts[:19]}] {content[:300]}')

print(f'\n--- Assistant Responses ({len(assistant_texts)}) ---')
for ts, text in assistant_texts:
    print(f'  [{ts[:19]}] {text[:400]}')
    print()

if errors:
    print(f'--- Errors ({len(errors)}) ---')
    for ts, err in errors:
        print(f'  [{ts[:19]}] {err}')

if thinking_blocks:
    print(f'--- Thinking Blocks ({len(thinking_blocks)}) ---')
    for i, t in enumerate(thinking_blocks):
        print(f'  [{i+1}] {t}')
        print()

print(f'--- Sub-agents ({len(subagents)}) ---')
if not subagents:
    print('  None')
else:
    for sa in subagents:
        print(f'  {sa[\"id\"]}  type={sa[\"type\"]}  msgs={sa[\"messages\"]}  tools={sa[\"tools\"]}')
        if sa['description']: print(f'    desc: {sa[\"description\"]}')
        if sa['prompt']: print(f'    prompt: {sa[\"prompt\"][:200]}')
        print()

# Session outcome
last = msgs[-1] if msgs else {}
lt = last.get('type','?')
if lt == 'last-prompt': outcome = 'Normal end (last-prompt marker)'
elif lt == 'user': outcome = 'Interrupted mid-turn (ended on tool result, no assistant response followed)'
elif lt == 'assistant' and last.get('message',{}).get('stop_reason') == 'end_turn': outcome = 'Completed (assistant end_turn)'
elif lt == 'system' and last.get('subtype') == 'turn_duration': outcome = 'Completed (turn_duration marker)'
else: outcome = f'Unknown ({lt})'
print(f'\n--- Session Outcome ---')
print(f'  Last message type: {lt}')
print(f'  Outcome: {outcome}')
print('=' * 60)
" /path/to/transcript.jsonl
```

**After running this script, you have all the data needed to write your analysis.** Only run additional scripts if the user asks for specific deep-dive details.

## Finding Sessions

### If the user provides a file path
Skip straight to the analysis script above.

### If the user asks to find a session by keyword

**Step 1** — Locate the project directory:
```bash
ls ~/.claude/projects/ | grep "<keyword>"
```

**Step 2** — Check sessions-index.json (fastest):
```bash
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    idx = json.load(f)
for e in idx.get('entries', []):
    print(f\"{e.get('created','')[:10]}  {e['sessionId'][:8]}...  branch={e.get('gitBranch','')}  msgs={e.get('messageCount','')}  {e.get('firstPrompt','')[:120]}\")
" ~/.claude/projects/<project-dir>/sessions-index.json
```

**Step 3** — If no index, grep across transcripts:
```bash
grep -l "keyword" ~/.claude/projects/<project-dir>/*.jsonl
```

## Deep-Dive Scripts (only when needed)

### Full thinking blocks
```bash
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        if d.get('type') == 'assistant':
            for block in d.get('message',{}).get('content',[]):
                if block.get('type') == 'thinking':
                    print(f'=== Line {i} ===')
                    print(block['thinking'])
                    print()
" /path/to/transcript.jsonl
```

### Full text of a specific tool call
```bash
python3 -c "
import json, sys
TOOL = sys.argv[2]
with open(sys.argv[1]) as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        if d.get('type') == 'assistant':
            for block in d.get('message',{}).get('content',[]):
                if block.get('type') == 'tool_use' and block.get('name') == TOOL:
                    print(f'Line {i}: {json.dumps(block.get(\"input\",{}))[:500]}')
                    print()
" /path/to/transcript.jsonl Bash
```

### Search for user corrections / frustration
```bash
python3 -c "
import json, sys, re
pattern = re.compile(r'\b(no|don.t|wrong|stop|not that|ugh|damn|wtf|fuck)\b', re.I)
with open(sys.argv[1]) as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        if d.get('type') == 'user' and isinstance(d.get('message',{}).get('content'), str):
            if pattern.search(d['message']['content']):
                print(f'[{d.get(\"timestamp\",\"\")[:19]}] {d[\"message\"][\"content\"][:300]}')
" /path/to/transcript.jsonl
```

### Analyze a specific sub-agent in detail
Run the main analysis script but pass the sub-agent's `.jsonl` path instead:
```bash
# Find sub-agent files
ls ~/.claude/projects/<project>/<session-id>/subagents/

# Then run the main analysis script on the sub-agent transcript
python3 -c "..." ~/.claude/projects/<project>/<session-id>/subagents/agent-<id>.jsonl
```

## Directory Layout Reference

```
~/.claude/
├── projects/<encoded-path>/              # Path with / → -, e.g. -Users-alice-code-myproject
│   ├── sessions-index.json               # {"version":1, "entries":[{sessionId, firstPrompt, summary, messageCount, created, modified, gitBranch, ...}]}
│   ├── <session-uuid>.jsonl              # Main transcript (one JSON object per line)
│   └── <session-uuid>/subagents/         # Sub-agent data
│       ├── agent-<id>.meta.json          # {"agentType":"Explore|general-purpose|Plan|...", "description":"..."}
│       └── agent-<id>.jsonl              # Sub-agent transcript (same format as main)
└── history.jsonl                         # Global history (very large — avoid)
```

## JSONL Message Types Quick Reference

| Type | Subtype | What it is |
|------|---------|------------|
| `user` | — | User text (content=string) or tool results (content=array with `tool_result` items) |
| `assistant` | — | Claude response: `content[]` has `thinking`, `text`, and `tool_use` blocks. Has `usage` with token counts. |
| `progress` | — | Hook events (noise, skip) |
| `system` | `turn_duration` | End-of-turn marker with `durationMs` |
| `system` | `local_command` | User ran `! command` |
| `queue-operation` | — | Queued input |
| `file-history-snapshot` | — | File tracking checkpoint |
| `last-prompt` | — | Session end marker |

## Performance Reflection Checklist

When evaluating Claude's performance:
- **Completeness**: Did the session produce the deliverable? Check session outcome.
- **User corrections**: Run the corrections search script above.
- **Failed tool calls**: Check errors count from main analysis.
- **Retries**: Same tool called multiple times with similar inputs.
- **Efficiency**: Tool call count, token cache hit ratio.
- **Skill usage**: Did Claude activate relevant skills?
- **Sub-agent usage**: Appropriate or wasteful?
