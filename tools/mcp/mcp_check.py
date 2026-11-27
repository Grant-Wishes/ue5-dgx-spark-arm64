#!/usr/bin/env python3
"""Talks to the editor's MCP server (Epic's ModelContextProtocol plugin) the way an MCP client does, 27 Nov (DGX Spark).

initialize -> notifications/initialized -> tools/list, then optional tools/call requests. Standard library only, so it
runs on the Spark itself or on another machine through an SSH tunnel (ssh -L 8000:localhost:8000 spark).
Usage: mcp_check.py [--url http://localhost:8000/mcp] [--call TOOL JSON_ARGS]...
Prints one JSON line per step.
"""
import argparse
import json
import sys
import urllib.request

ap = argparse.ArgumentParser()
ap.add_argument('--url', default='http://localhost:8000/mcp')
ap.add_argument('--call', nargs=2, action='append', default=[], metavar=('TOOL', 'JSON_ARGS'))
ap.add_argument('--timeout', type=float, default=120)
a = ap.parse_args()
session = None
next_id = 0


def post(method, params=None, notify=False):
    global session, next_id
    msg = {'jsonrpc': '2.0', 'method': method}
    if params is not None:
        msg['params'] = params
    if not notify:
        next_id += 1
        msg['id'] = next_id
    req = urllib.request.Request(a.url, data=json.dumps(msg).encode(), method='POST', headers={
        'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream',
        **({'Mcp-Session-Id': session} if session else {})})
    with urllib.request.urlopen(req, timeout=a.timeout) as r:
        session = r.headers.get('Mcp-Session-Id') or session
        body = r.read().decode()
        if notify or not body.strip():
            return None
        if r.headers.get('Content-Type', '').startswith('text/event-stream'):   # the last "data:" line holds the reply
            body = [l[5:].strip() for l in body.splitlines() if l.startswith('data:')][-1]
        return json.loads(body)


def show(step, reply):
    print(json.dumps({'step': step, **(reply or {})}), flush=True)


init = post('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {},
                           'clientInfo': {'name': 'mcp_check', 'version': '1.0'}})
show('initialize', {'server': init.get('result', {}).get('serverInfo'),
                    'protocol': init.get('result', {}).get('protocolVersion'), 'session': bool(session)})
post('notifications/initialized', notify=True)
tools = post('tools/list', {})
names = [t['name'] for t in tools.get('result', {}).get('tools', [])]
show('tools/list', {'count': len(names), 'tools': names})
for tool, args in a.call:
    r = post('tools/call', {'name': tool, 'arguments': json.loads(args)})
    show('tools/call ' + tool, r)
    if 'error' in r or r.get('result', {}).get('isError'):
        sys.exit(1)
