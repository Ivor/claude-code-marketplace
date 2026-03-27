#!/usr/bin/env python3
"""Detect meandering, retries, and inefficient patterns in a Claude Code transcript.

Usage: python3 detect_meandering.py <transcript.jsonl>

Detects:
- Repeated similar tool calls (retries with slight variations)
- Read tool failures followed by fallback approaches
- Circular patterns (A → B → A)
- Sub-agents with suspiciously high tool counts
- Long stretches with no user text output (all tool calls, no progress shown)
- Tool calls that produced errors
"""
import json, sys, collections, os, glob, re
from difflib import SequenceMatcher

if len(sys.argv) < 2:
    print("Usage: python3 detect_meandering.py <transcript.jsonl>", file=sys.stderr)
    sys.exit(1)

f = sys.argv[1]
session_dir = f.replace('.jsonl', '')

def analyze_file(filepath, label="main"):
    """Analyze a single JSONL file for meandering patterns."""
    msgs = []
    with open(filepath) as fh:
        for line in fh:
            msgs.append(json.loads(line))

    findings = []
    tool_sequence = []  # (line_num, tool_name, input_summary, timestamp)
    error_lines = []
    text_output_lines = []
    total_tool_calls = 0

    for i, m in enumerate(msgs):
        if m.get('type') == 'assistant':
            for block in m.get('message', {}).get('content', []):
                if block.get('type') == 'tool_use':
                    name = block['name']
                    inp = block.get('input', {})
                    # Create a normalized summary of the input for similarity comparison
                    if name == 'Read':
                        summary = inp.get('file_path', '')
                    elif name == 'Bash':
                        summary = inp.get('command', '')[:200]
                    elif name == 'Grep':
                        summary = f"{inp.get('pattern', '')} in {inp.get('path', '')}"
                    elif name == 'Agent':
                        summary = inp.get('prompt', '')[:200]
                    else:
                        summary = json.dumps(inp)[:200]
                    ts = m.get('timestamp', '')
                    tool_sequence.append((i, name, summary, ts))
                    total_tool_calls += 1
                elif block.get('type') == 'text' and block.get('text', '').strip():
                    text_output_lines.append(i)

        elif m.get('type') == 'user' and isinstance(m.get('message', {}).get('content'), list):
            for item in m['message']['content']:
                if item.get('is_error'):
                    error_lines.append((i, item.get('content', '')[:200] if isinstance(item.get('content'), str) else str(item.get('content', ''))[:200]))

    # --- Detection 1: Repeated similar tool calls ---
    for idx in range(1, len(tool_sequence)):
        curr_line, curr_name, curr_summary, curr_ts = tool_sequence[idx]
        prev_line, prev_name, prev_summary, prev_ts = tool_sequence[idx - 1]

        if curr_name == prev_name:
            similarity = SequenceMatcher(None, curr_summary, prev_summary).ratio()
            if similarity > 0.7 and curr_name in ('Read', 'Bash', 'Grep', 'Glob'):
                findings.append({
                    'type': 'RETRY',
                    'severity': 'medium' if similarity > 0.9 else 'low',
                    'line': curr_line,
                    'detail': f'Similar {curr_name} call repeated (similarity={similarity:.0%})',
                    'prev': f'  L{prev_line}: {prev_summary[:120]}',
                    'curr': f'  L{curr_line}: {curr_summary[:120]}',
                })

    # --- Detection 2: Read failures (Read followed by error, then different approach) ---
    for idx, (line, name, summary, ts) in enumerate(tool_sequence):
        if name == 'Read':
            # Check if next user message has an error for this tool call
            for err_line, err_content in error_lines:
                if err_line > line and err_line < line + 5:
                    if 'token' in err_content.lower() or 'large' in err_content.lower() or 'exceed' in err_content.lower():
                        findings.append({
                            'type': 'READ_FAILURE',
                            'severity': 'high',
                            'line': line,
                            'detail': f'Read tool failed (likely token limit): {summary[:100]}',
                            'error': err_content[:150],
                        })

    # --- Detection 3: Circular patterns (A→B→...→A with same inputs) ---
    seen_calls = {}  # (name, summary_hash) -> [line_numbers]
    for line, name, summary, ts in tool_sequence:
        key = (name, summary[:80])
        if key not in seen_calls:
            seen_calls[key] = []
        seen_calls[key].append(line)

    for key, lines in seen_calls.items():
        if len(lines) > 2:
            findings.append({
                'type': 'CIRCULAR',
                'severity': 'high',
                'line': lines[-1],
                'detail': f'{key[0]} called {len(lines)} times with similar input',
                'lines': lines,
                'input': key[1][:120],
            })
        elif len(lines) == 2 and (lines[1] - lines[0]) > 5:
            findings.append({
                'type': 'REVISIT',
                'severity': 'low',
                'line': lines[1],
                'detail': f'{key[0]} revisited after {lines[1]-lines[0]} messages apart',
                'input': key[1][:120],
            })

    # --- Detection 4: Long tool-only stretches (no text output to user) ---
    if tool_sequence and text_output_lines:
        consecutive_tools = 0
        last_text_line = 0
        for line, name, summary, ts in tool_sequence:
            # Find the most recent text output before this tool call
            recent_text = max((t for t in text_output_lines if t < line), default=0)
            tools_since_text = sum(1 for l, n, s, t in tool_sequence if recent_text < l <= line)
            if tools_since_text > 8:
                findings.append({
                    'type': 'SILENT_STRETCH',
                    'severity': 'medium',
                    'line': line,
                    'detail': f'{tools_since_text} consecutive tool calls with no text output to user (lines {recent_text}-{line})',
                })
                break  # Only report the first one to avoid spam

    # --- Detection 5: Tool errors ---
    for err_line, err_content in error_lines:
        findings.append({
            'type': 'ERROR',
            'severity': 'medium',
            'line': err_line,
            'detail': f'Tool returned error: {err_content[:150]}',
        })

    return findings, tool_sequence, total_tool_calls


# Analyze main transcript
print('=' * 60)
print(f'MEANDERING DETECTION: {os.path.basename(f)}')
print('=' * 60)

main_findings, main_tools, main_count = analyze_file(f, "main")

# Print tool sequence (the timeline view)
print(f'\n--- Tool Call Timeline ({main_count} calls) ---')
for line, name, summary, ts in main_tools:
    prefix = f'  L{line:3d} [{ts[11:19] if len(ts) > 18 else "?"}]'
    print(f'{prefix} {name:12s} {summary[:100]}')

# Print findings
print(f'\n--- Findings ({len(main_findings)}) ---')
if not main_findings:
    print('  No meandering detected.')
else:
    by_severity = {'high': [], 'medium': [], 'low': []}
    for finding in main_findings:
        by_severity[finding['severity']].append(finding)

    for sev in ['high', 'medium', 'low']:
        if by_severity[sev]:
            print(f'\n  [{sev.upper()}]')
            for finding in by_severity[sev]:
                print(f'    L{finding["line"]:3d} {finding["type"]}: {finding["detail"]}')
                if 'prev' in finding:
                    print(f'         {finding["prev"]}')
                    print(f'         {finding["curr"]}')
                if 'error' in finding:
                    print(f'         Error: {finding["error"]}')
                if 'input' in finding:
                    print(f'         Input: {finding["input"]}')

# Analyze sub-agents
subagent_dir = os.path.join(session_dir, 'subagents')
if os.path.isdir(subagent_dir):
    print(f'\n--- Sub-agent Analysis ---')
    for meta_file in sorted(glob.glob(os.path.join(subagent_dir, '*.meta.json'))):
        agent_id = os.path.basename(meta_file).replace('.meta.json', '')
        with open(meta_file) as mf:
            meta = json.load(mf)
        jsonl_file = meta_file.replace('.meta.json', '.jsonl')

        if os.path.exists(jsonl_file):
            sa_findings, sa_tools, sa_count = analyze_file(jsonl_file, agent_id)

            flag = ''
            if sa_count > 30:
                flag = ' *** HIGH TOOL COUNT ***'
            elif sa_count > 15:
                flag = ' * elevated'

            print(f'\n  {agent_id} ({meta.get("agentType", "?")}) — {sa_count} tool calls{flag}')
            if meta.get('description'):
                print(f'    desc: {meta["description"]}')

            if sa_findings:
                high = [f for f in sa_findings if f['severity'] == 'high']
                med = [f for f in sa_findings if f['severity'] == 'medium']
                if high or med:
                    for finding in (high + med)[:5]:
                        print(f'    L{finding["line"]:3d} {finding["type"]}: {finding["detail"][:120]}')
            else:
                print(f'    No issues detected.')

print('\n' + '=' * 60)
