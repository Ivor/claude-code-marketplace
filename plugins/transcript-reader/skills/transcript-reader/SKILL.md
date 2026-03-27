---
name: transcript-reader
description: Find, read, and analyze Claude Code session transcripts. Use when the user asks about past sessions, wants to review what happened in a conversation, search for specific interactions, or reflect on how Claude performed. Understands the full transcript JSONL format including sub-agent conversations.
---

# Transcript Reader

## Step 1: Run the analysis script

For ANY transcript analysis, your first action MUST be this Bash command:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze_transcript.py /path/to/transcript.jsonl
```

This single script extracts all session data in one pass: message types, tool usage, user messages, assistant responses, thinking blocks, token usage, sub-agent analysis, and session outcome. It handles everything — including discovering and parsing sub-agent transcripts automatically.

**Do NOT use the Read tool on .jsonl files.** Each JSONL line is a single JSON object that can be 100K+ characters — Read will fail or exhaust token limits. The analysis script uses streaming python3 parsing instead.

**Do NOT spawn sub-agents (Agent tool) for this work.** The script output gives you everything. Analyze the output directly.

After running the script, write your analysis based on its output. For most requests, this single Bash call is all you need.

## Step 2: Deep-dive (only if the user asks for specifics)

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

### Specific tool call details
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
pattern = re.compile(r'\b(no|don.t|wrong|stop|not that|ugh|damn)\b', re.I)
with open(sys.argv[1]) as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        if d.get('type') == 'user' and isinstance(d.get('message',{}).get('content'), str):
            if pattern.search(d['message']['content']):
                print(f'[{d.get(\"timestamp\",\"\")[:19]}] {d[\"message\"][\"content\"][:300]}')
" /path/to/transcript.jsonl
```

### Analyze a sub-agent in isolation
The main script already summarizes sub-agents. For full detail on a specific one, run the same analysis script on the sub-agent's JSONL:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze_transcript.py ~/.claude/projects/<project>/<session-id>/subagents/agent-<id>.jsonl
```

## Finding sessions

### If the user provides a file path
Skip straight to Step 1.

### If the user asks to find a session by keyword

```bash
# Find project directories
ls ~/.claude/projects/ | grep "<keyword>"

# Search sessions index for matching sessions
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    idx = json.load(f)
for e in idx.get('entries', []):
    print(f\"{e.get('created','')[:10]}  {e['sessionId'][:8]}...  branch={e.get('gitBranch','')}  msgs={e.get('messageCount','')}  {e.get('firstPrompt','')[:120]}\")
" ~/.claude/projects/<project-dir>/sessions-index.json

# Or grep across all transcripts
grep -l "keyword" ~/.claude/projects/<project-dir>/*.jsonl
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

## Performance checklist

When evaluating Claude's performance in a session:
- **Completeness**: Did it produce the deliverable? Check session outcome.
- **User corrections**: Run the frustration search script.
- **Failed tools**: Error count from the analysis output.
- **Efficiency**: Total tool calls, cache hit ratio.
- **Skill activation**: Did Claude use relevant skills?
- **Sub-agents**: Appropriate or wasteful?
