# Deep-dive recipes and transcript format

For requests the main analysis script doesn't answer directly: targeted extraction scripts, plus the JSONL format for writing custom queries.

## Full thinking blocks

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

## Specific tool call details

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

## Search for user corrections / frustration

```bash
python3 -c "
import json, sys, re
pattern = re.compile(r'\b(no|don.t|wrong|stop|not that|ugh|damn)\b', re.I)
with open(sys.argv[1]) as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        if d.get('type') == 'user' and isinstance(d.get('message',{}).get('content'), str):
            if pattern.search(d['message']['content']):
                print(f'[{d.get(\"timestamp\",\"\")[:19]}] {d[\"message\"][\"content\"][:300]}')
" /path/to/transcript.jsonl
```

## Directory layout

```
~/.claude/projects/<encoded-path>/           # / replaced by -, e.g. -Users-alice-code-myproject
├── sessions-index.json                      # {entries: [{sessionId, firstPrompt, summary, messageCount, created, modified, gitBranch}]}
├── <session-uuid>.jsonl                     # Main transcript
└── <session-uuid>/subagents/                # Sub-agent data
    ├── agent-<id>.meta.json                 # {agentType, description}
    └── agent-<id>.jsonl                     # Sub-agent transcript (same format)
```

## JSONL message types

| Type | What it contains |
|------|-----------------|
| `user` | User text (content=string) or tool results (content=array of `tool_result`) |
| `assistant` | `content[]` with `thinking`, `text`, `tool_use` blocks. `usage` has token counts. |
| `system:turn_duration` | End-of-turn with `durationMs` |
| `system:local_command` | Output from `!` commands |
| `progress` | Hook events (skip these) |
| `last-prompt` | Session end marker |
