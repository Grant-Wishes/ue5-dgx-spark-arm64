"""Job runner inside the Unreal editor (DGX Spark, 24 Nov; neutral copy for the public port, 26 Nov). Started once with
-ExecutePythonScript (editor.sh); then it runs "jobs": Python files dropped into the jobs folder (job_*.py), one at a time,
from a Slate post-tick callback, so the editor keeps ticking between and during them (restarting the editor for every
try costs minutes).

A job is a Python file run in a fresh namespace that also gets:
  unreal, OUT (its own output folder), S (a dict shared by all jobs), log(**data).
If it defines run(), run() is called; if run() is a generator, each `yield` waits for the next frame and `yield 2.5`
waits 2.5 seconds (async work in the editor, e.g. MetaHuman grooms or shader compiles, completes between frames).
Results: <jobs>/done/<name>.json (ok/error, timings, log lines, traceback). A job named job_quit.py closes the editor.
Heartbeat every 60 s in <jobs>/server.json. Jobs folder: UE_JOBS_DIR, default <project>/Saved/Jobs."""
import glob
import json
import os
import time
import traceback
import types

import unreal

JOBS = os.environ.get("UE_JOBS_DIR") or os.path.join(os.path.abspath(unreal.Paths.project_saved_dir()), "Jobs")
DONE = os.path.join(JOBS, "done")
RUNNING = os.path.join(JOBS, "running")
for d in (JOBS, DONE, RUNNING):
    os.makedirs(d, exist_ok=True)

S = {}          # shared between jobs
state = {"gen": None, "job": None, "wait_until": 0.0, "t0": 0.0, "lines": [], "beat": 0.0, "handle": None, "busy": False}


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1, default=str)
    os.replace(tmp, path)


def finish(ok, error=None):
    name = state["job"]
    write_json(os.path.join(DONE, name + ".json"), {
        "job": name, "ok": ok, "seconds": round(time.time() - state["t0"], 2), "lines": state["lines"],
        "error": error})
    try:
        os.remove(os.path.join(RUNNING, name + ".py"))
    except OSError:
        pass
    unreal.log(f"JOBS end {name} ok={ok}")
    state.update(gen=None, job=None, lines=[])
    if name == "job_quit":
        unreal.unregister_slate_post_tick_callback(state["handle"])
        unreal.EditorPythonScripting.set_keep_python_script_alive(False)
        unreal.SystemLibrary.quit_editor()


def start(path):
    name = os.path.splitext(os.path.basename(path))[0]
    running = os.path.join(RUNNING, name + ".py")
    os.replace(path, running)
    state.update(job=name, t0=time.time(), lines=[], gen=None, wait_until=0.0)
    out = os.path.join(JOBS, "out", name)
    os.makedirs(out, exist_ok=True)

    def log(**data):
        state["lines"].append({"t": round(time.time() - state["t0"], 2), **data})
        unreal.log(f"JOBS {name} {data}")

    ns = {"__name__": "__job__", "__file__": running, "unreal": unreal, "OUT": out, "S": S, "log": log}
    unreal.log(f"JOBS start {name}")
    code = compile(open(running).read(), running, "exec")
    exec(code, ns)
    if callable(ns.get("run")):
        r = ns["run"]()
        if isinstance(r, types.GeneratorType):
            state["gen"] = r
            return
    finish(True)


def tick(dt):
    # re-entrancy guard: compilation waits, render flushes and progress dialogs tick Slate from inside a job step
    # (24 Nov: the Creator test's render callback ran six times over itself)
    if state["busy"]:
        return
    state["busy"] = True
    try:
        now = time.time()
        if now - state["beat"] > 60:
            state["beat"] = now
            write_json(os.path.join(JOBS, "server.json"), {"alive": time.strftime("%H:%M:%S"), "job": state["job"]})
        if state["gen"] is not None:
            if now < state["wait_until"]:
                return
            try:
                w = next(state["gen"])
                state["wait_until"] = now + (float(w) if w else 0.0)
            except StopIteration:
                finish(True)
            return
        jobs = sorted(glob.glob(os.path.join(JOBS, "job_*.py")))
        if jobs:
            start(jobs[0])
    except Exception as e:
        if state["job"]:
            finish(False, f"{e!r}\n{traceback.format_exc()}")
        else:
            unreal.log_error(f"JOBS {e!r}")
    finally:
        state["busy"] = False


# -ExecutePythonScript closes the editor when the script returns, unless it asks to stay alive
unreal.EditorPythonScripting.set_keep_python_script_alive(True)
state["handle"] = unreal.register_slate_post_tick_callback(tick)
write_json(os.path.join(JOBS, "server.json"), {"alive": time.strftime("%H:%M:%S"), "job": None, "started": True})
unreal.log("JOBS ready")
