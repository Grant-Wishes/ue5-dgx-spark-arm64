"""The same MetaHuman orbit (job_scene.py) under three lighting setups, fps measured for each, one screenshot each (the
whole display, through display.sh): no dynamic GI + screen-space reflections (the engine default when a project sets
nothing), Lumen with software ray tracing, Lumen with hardware ray tracing (the third-person template's Lumen setup)."""
import json, math, os, subprocess, time

MODES = [("noGI_SSR", {"r.DynamicGlobalIlluminationMethod": 0, "r.ReflectionMethod": 2, "r.Lumen.HardwareRayTracing": 0}),
         ("lumen_software", {"r.DynamicGlobalIlluminationMethod": 1, "r.ReflectionMethod": 1, "r.Lumen.HardwareRayTracing": 0}),
         ("lumen_hardware_rt", {"r.DynamicGlobalIlluminationMethod": 1, "r.ReflectionMethod": 1, "r.Lumen.HardwareRayTracing": 1})]
SECONDS, DIST = 25.0, 70.0
SHOT = os.environ.get("UE_DISPLAY_SH", "display.sh")   # set by server.sh
SHOTS = os.environ.get("UE_SHOTS_DIR", "/tmp")


def run():
    ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    world, head = S["world"], S["head"]
    for c in ("t.MaxFPS 0", "r.VSync 0", "stat none", "stat fps", "stat unit"):
        unreal.SystemLibrary.execute_console_command(world, c)
    results = {}
    for name, cvars in MODES:
        for k, v in cvars.items():
            unreal.SystemLibrary.execute_console_command(world, f"{k} {v}")
        t_settle = time.time()
        while time.time() - t_settle < 6.0:   # shaders and Lumen caches settle
            yield
        times, t0, last, shot = [], time.time(), time.time(), False
        while True:
            now = time.time()
            times.append(now - last); last = now
            a = 2 * math.pi * min(1.0, (now - t0) / SECONDS)
            cam = head + unreal.Vector(DIST * math.sin(a), DIST * math.cos(a), 6.0 * math.sin(2 * a))
            ues.set_level_viewport_camera_info(cam, unreal.MathLibrary.find_look_at_rotation(cam, head))
            if not shot and now - t0 > SECONDS * 0.15:
                subprocess.Popen([SHOT, "shot", os.path.join(SHOTS, f"lighting-{name}.png")])
                shot = True
            if now - t0 >= SECONDS:
                break
            yield
        ft = sorted(times[5:])
        results[name] = {"fps_mean": round(len(ft) / sum(ft), 1), "ms_median": round(1000 * ft[len(ft) // 2], 2),
                         "ms_p95": round(1000 * ft[int(len(ft) * 0.95)], 2), "cvars": cvars}
        log(mode=name, **results[name])
    json.dump(results, open(os.path.join(OUT, "lighting_modes.json"), "w"), indent=1)
