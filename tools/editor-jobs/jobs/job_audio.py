"""Audio import test (libsndfile, patch 0023): a 2 s 440 Hz tone written here as WAV, imported like the Import button."""
import math, os, struct, time, wave


def run():
    path = os.path.join(OUT, "tone_440.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
        w.writeframes(b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * 440 * i / 48000))) for i in range(96000)))
    dest = "/Game/AudioTest"
    if unreal.EditorAssetLibrary.does_directory_exist(dest):
        unreal.EditorAssetLibrary.delete_directory(dest)
    t0 = time.time()
    task = unreal.AssetImportTask()
    task.filename, task.destination_path = path, dest
    task.automated = task.replace_existing = task.save = True
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
    res = {}
    for p in task.imported_object_paths:
        a = unreal.load_asset(p)
        res[p.split("/")[-1]] = a.get_class().get_name()
        if isinstance(a, unreal.SoundWave):
            res["duration_s"] = round(a.get_editor_property("duration"), 3)
            res["channels"] = a.get_editor_property("num_channels") if hasattr(a, "num_channels") else None
    log(seconds=round(time.time() - t0, 2), imported=res)
    yield
