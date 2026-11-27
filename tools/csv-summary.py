"""Summarises an Unreal CSV profiler capture: frame, game, render, RHI and GPU times, after the first SKIP frames."""
import csv, sys
csv.field_size_limit(sys.maxsize)
path, skip = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 600

def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None

rows = [r for r in csv.DictReader(open(path, newline="")) if num(r.get("FrameTime")) is not None]
data = rows[skip:] if len(rows) > skip else rows
print(f"{path}: {len(rows)} frames captured, {len(data)} summarised (first {skip} skipped)")
for c, name in (("FrameTime", "frame"), ("GameThreadTime", "game"), ("RenderThreadTime", "render"),
                ("RHIThreadTime", "rhi"), ("GPUTime", "gpu")):
    v = sorted(x for x in (num(r.get(c)) for r in data) if x is not None)
    if v:
        print(f"  {name:6s} ms: mean {sum(v)/len(v):6.2f}  median {v[len(v)//2]:6.2f}  p95 {v[int(len(v)*0.95)]:6.2f}")
f = [num(r["FrameTime"]) for r in data]
print(f"  fps mean {1000 * len(f) / sum(f):.1f}")
