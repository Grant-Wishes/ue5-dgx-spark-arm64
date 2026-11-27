"""Orbits the level viewport camera around the MetaHuman's head (from job_scene.py) for SECONDS and measures the editor's
frame times meanwhile (the Slate tick of a realtime viewport: what a user sees). Writes OUT/fps.json."""
import json
import math
import os
import time

SECONDS, DIST, TURNS = 40.0, 70.0, 1.0


def run():
    ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    head = S["head"]
    world = S["world"]
    for c in ("t.MaxFPS 0", "r.VSync 0", "stat fps", "stat unit"):
        unreal.SystemLibrary.execute_console_command(world, c)
    times, t0, last = [], time.time(), time.time()
    while True:
        now = time.time()
        times.append(now - last)
        last = now
        a = 2 * math.pi * TURNS * min(1.0, (now - t0) / SECONDS)
        cam = head + unreal.Vector(DIST * math.sin(a), DIST * math.cos(a), 6.0 * math.sin(2 * a))
        ues.set_level_viewport_camera_info(cam, unreal.MathLibrary.find_look_at_rotation(cam, head))
        if now - t0 >= SECONDS:
            break
        yield
    ft = sorted(times[5:])
    res = {"frames": len(ft), "seconds": round(time.time() - t0, 2), "fps_mean": round(len(ft) / sum(ft), 1),
           "ms_median": round(1000 * ft[len(ft) // 2], 2), "ms_p95": round(1000 * ft[int(len(ft) * 0.95)], 2),
           "ms_max": round(1000 * ft[-1], 2)}
    json.dump(res, open(os.path.join(OUT, "fps.json"), "w"), indent=1)
    log(**res)
