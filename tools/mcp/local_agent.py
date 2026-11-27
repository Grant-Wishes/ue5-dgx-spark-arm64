#!/usr/bin/env python3
"""A minimal agent: a local LLM drives the Unreal Editor through Epic's MCP server. 27 Nov 2026 (DGX Spark).

The model is served by any OpenAI-style /v1/chat/completions endpoint with tool calling (here DwarfStar's ds4-server
with DeepSeek V4.1 Flash, on the same machine). The agent lists the editor's MCP tools, offers them to the model as
functions, runs every call the model makes against the editor, feeds the results back, and stops when the model
answers without calling a tool. The model gets nothing but the editor's MCP tools: no shell, no files.

Standard library only. Every step goes to a JSON-lines log with a wall-clock timestamp.
Usage:
  local_agent.py --prompt "Create a MetaHuman at /Game/MCP/Ada ..." [--llm http://127.0.0.1:8000/v1]
                 [--model deepseek-v4.1-flash] [--mcp http://localhost:8100/mcp] [--log agent.jsonl]
"""
import argparse
import json
import sys
import time
import urllib.request

ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
ap.add_argument('--prompt', required=True)
ap.add_argument('--llm', default='http://127.0.0.1:8000/v1', help='OpenAI-style base URL of the local model server')
ap.add_argument('--model', default='deepseek-v4.1-flash')
ap.add_argument('--mcp', default='http://localhost:8100/mcp', help="the editor's MCP server")
ap.add_argument('--max-steps', type=int, default=40, help='model turns before giving up')
ap.add_argument('--max-tokens', type=int, default=4096, help='output budget per model turn')
ap.add_argument('--max-result-chars', type=int, default=16000, help='longer tool results are cut, with a note')
ap.add_argument('--no-think', action='store_true', help='ask the model to answer without its thinking phase')
ap.add_argument('--timeout', type=float, default=900, help='seconds per HTTP request')
ap.add_argument('--log', default='agent.jsonl')
a = ap.parse_args()

SYSTEM = ('You control a running Unreal Engine 5.8 editor through its MCP tools. Use the tools to do what the user '
          'asks; do not invent tool names, results or asset paths. Toolset tools are reached through call_tool: '
          'find the toolset with list_toolsets, read its tools and input schemas with describe_toolset, then call '
          'a tool with call_tool(toolset_name, tool_name, arguments), where tool_name is the short name. '
          'When the task is done, answer with a short summary and no tool call.')
log = open(a.log, 'a', buffering=1)
t_start = time.time()


def record(kind, **fields):
    entry = {'t': round(time.time(), 3), 'elapsed': round(time.time() - t_start, 2), 'kind': kind, **fields}
    log.write(json.dumps(entry, ensure_ascii=False) + '\n')
    return entry


def show(text):
    print(f'[{time.time() - t_start:6.1f}s] {text}', flush=True)


def http_json(url, body, headers=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method='POST',
                                 headers={'Content-Type': 'application/json', **(headers or {})})
    with urllib.request.urlopen(req, timeout=a.timeout) as r:
        return r.headers, r.read().decode()


class MCP:
    """Streamable-HTTP MCP client: JSON-RPC over POST, session id in a header, replies as JSON or SSE."""

    def __init__(self, url):
        self.url, self.session, self.next_id = url, None, 0

    def request(self, method, params=None, notify=False):
        msg = {'jsonrpc': '2.0', 'method': method, **({'params': params} if params is not None else {})}
        if not notify:
            self.next_id += 1
            msg['id'] = self.next_id
        headers, body = http_json(self.url, msg, {'Accept': 'application/json, text/event-stream',
                                                  **({'Mcp-Session-Id': self.session} if self.session else {})})
        self.session = headers.get('Mcp-Session-Id') or self.session
        if notify or not body.strip():
            return None
        if headers.get('Content-Type', '').startswith('text/event-stream'):
            body = [l[5:].strip() for l in body.splitlines() if l.startswith('data:')][-1]
        reply = json.loads(body)
        if 'error' in reply:
            raise RuntimeError(f"MCP {method}: {reply['error']}")
        return reply['result']


mcp = MCP(a.mcp)
init = mcp.request('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {},
                                  'clientInfo': {'name': 'local_agent', 'version': '1.0'}})
mcp.request('notifications/initialized', notify=True)
mcp_tools = mcp.request('tools/list', {})['tools']
tools = [{'type': 'function', 'function': {'name': t['name'], 'description': t.get('description', ''),
                                           'parameters': t.get('inputSchema') or {'type': 'object', 'properties': {}}}}
         for t in mcp_tools]
record('start', prompt=a.prompt, model=a.model, llm=a.llm, mcp=a.mcp, tools=[t['name'] for t in mcp_tools],
       protocol=init.get('protocolVersion'))
show(f"MCP: {len(mcp_tools)} tools ({', '.join(t['name'] for t in mcp_tools)}); model {a.model} at {a.llm}")

messages = [{'role': 'system', 'content': SYSTEM}, {'role': 'user', 'content': a.prompt}]
for step in range(1, a.max_steps + 1):
    body = {'model': a.model, 'messages': messages, 'tools': tools, 'max_tokens': a.max_tokens}
    if a.no_think:
        body['think'] = False
    t0 = time.time()
    _, raw = http_json(a.llm.rstrip('/') + '/chat/completions', body)
    reply = json.loads(raw)
    choice = reply['choices'][0]
    msg = choice['message']
    usage = reply.get('usage', {})
    calls = msg.get('tool_calls') or []
    record('model', step=step, seconds=round(time.time() - t0, 2), finish=choice.get('finish_reason'),
           text=msg.get('content'), calls=[{'name': c['function']['name'], 'arguments': c['function']['arguments']}
                                           for c in calls], usage=usage)
    show(f"model turn {step}: {time.time() - t0:.1f} s, {usage.get('prompt_tokens', '?')} in / "
         f"{usage.get('completion_tokens', '?')} out, {len(calls)} tool call(s)")
    messages.append({k: v for k, v in msg.items() if k in ('role', 'content', 'tool_calls', 'reasoning_content')})
    if not calls:
        record('done', text=msg.get('content'), steps=step, seconds=round(time.time() - t_start, 2))
        show('answer:\n' + (msg.get('content') or '').strip())
        sys.exit(0)
    for c in calls:
        name = c['function']['name']
        try:
            args = json.loads(c['function']['arguments'] or '{}')
        except json.JSONDecodeError as e:
            args, result, is_error = None, f'invalid JSON arguments: {e}', True
        if args is not None:
            t1 = time.time()
            try:
                res = mcp.request('tools/call', {'name': name, 'arguments': args})
                result = '\n'.join(x.get('text', f"[{x.get('type')}]") for x in res.get('content', []))
                is_error = bool(res.get('isError'))
            except Exception as e:   # the model sees the error and can correct itself
                result, is_error = f'error: {e}', True
            if len(result) > a.max_result_chars:
                result = result[:a.max_result_chars] + f'\n[cut: {len(result)} characters in all]'
            record('tool', name=name, arguments=args, seconds=round(time.time() - t1, 2), error=is_error,
                   result=result[:2000])
            brief = (args.get('tool_name') or args.get('toolset_name') or '') if isinstance(args, dict) else ''
            show(f"  {name} {brief}: {'ERROR ' if is_error else ''}{result[:120]!r}")
        messages.append({'role': 'tool', 'tool_call_id': c.get('id'), 'content': result})

record('gave_up', steps=a.max_steps)
show(f'no answer after {a.max_steps} model turns')
sys.exit(2)
