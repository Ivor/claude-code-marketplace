#!/usr/bin/env python3
"""Analyze a Claude Code session transcript JSONL file.

Usage: python3 analyze_transcript.py <transcript.jsonl>
"""
import json, sys, collections, os, glob

if len(sys.argv) < 2:
    print("Usage: python3 analyze_transcript.py <transcript.jsonl>", file=sys.stderr)
    sys.exit(1)

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
        if model:
            models.add(model)
        for block in m.get('message', {}).get('content', []):
            if block.get('type') == 'tool_use':
                tool_counts[block['name']] += 1
            elif block.get('type') == 'text' and block.get('text', '').strip():
                assistant_texts.append((m.get('timestamp', ''), block['text']))
            elif block.get('type') == 'thinking':
                thinking_blocks.append(block.get('thinking', '')[:500])
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
        agent_texts = []
        if os.path.exists(jsonl_file):
            with open(jsonl_file) as af:
                for line in af:
                    am = json.loads(line)
                    agent_msgs += 1
                    if am.get('type') == 'assistant':
                        for block in am.get('message', {}).get('content', []):
                            if block.get('type') == 'tool_use':
                                agent_tool_counts[block['name']] += 1
                            elif block.get('type') == 'text' and block.get('text', '').strip():
                                agent_texts.append(block['text'][:200])
                    elif am.get('type') == 'user' and isinstance(am.get('message', {}).get('content'), str):
                        agent_user_prompts.append(am['message']['content'][:200])
        subagents.append({
            'id': agent_id,
            'type': meta.get('agentType', '?'),
            'description': meta.get('description', ''),
            'messages': agent_msgs,
            'tools': dict(agent_tool_counts.most_common()),
            'total_tool_calls': sum(agent_tool_counts.values()),
            'prompt': agent_user_prompts[0] if agent_user_prompts else '',
            'texts': agent_texts[:3],
        })

# Session outcome
last = msgs[-1] if msgs else {}
lt = last.get('type', '?')
if lt == 'last-prompt':
    outcome = 'Normal end (last-prompt marker)'
elif lt == 'user':
    outcome = 'Interrupted mid-turn (ended on tool result, no response followed)'
elif lt == 'assistant' and last.get('message', {}).get('stop_reason') == 'end_turn':
    outcome = 'Completed (end_turn)'
elif lt == 'system' and last.get('subtype') == 'turn_duration':
    outcome = 'Completed (turn_duration marker)'
else:
    outcome = f'Unknown ({lt})'

# Find session metadata from first message that has it
session_id = branch = version = '?'
for m in msgs:
    if m.get('sessionId'):
        session_id = m['sessionId']
        branch = m.get('gitBranch', '?')
        version = m.get('version', '?')
        break

# Output
print('=' * 60)
print('SESSION ANALYSIS')
print('=' * 60)

print(f"""
Session ID: {session_id}
Branch: {branch}
Version: {version}
Models: {', '.join(models) if models else '?'}
Total JSONL lines: {len(msgs)}
Total duration: {sum(durations):,}ms ({sum(durations)/1000:.1f}s)
Tokens — Input: {total_in:,}  Output: {total_out:,}  Cache: {total_cache:,}
Outcome: {outcome}
""")

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
    print(f'\n--- Thinking Blocks ({len(thinking_blocks)}) ---')
    for i, t in enumerate(thinking_blocks):
        print(f'  [{i+1}] {t}')
        print()

print(f'--- Sub-agents ({len(subagents)}) ---')
if not subagents:
    print('  None')
else:
    for sa in subagents:
        print(f'  {sa["id"]}  type={sa["type"]}  msgs={sa["messages"]}  tool_calls={sa["total_tool_calls"]}')
        if sa['description']:
            print(f'    desc: {sa["description"]}')
        if sa['prompt']:
            print(f'    prompt: {sa["prompt"][:200]}')
        if sa['tools']:
            print(f'    tools: {sa["tools"]}')
        if sa['texts']:
            print(f'    sample responses:')
            for t in sa['texts']:
                print(f'      - {t[:150]}')
        print()

print('=' * 60)
