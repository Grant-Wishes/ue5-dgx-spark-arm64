"""FBX import test: two small files from ufbx's own test data (MIT), a static cube and a skinned, animated mesh, imported
the way the editor's Import button does (AssetImportTask, Interchange). Logs what came in, per file."""
import os
import time

D = os.environ.get("UE_TEST_FBX_DIR", "/tmp/ue-test-fbx")   # maya_cube_7500_binary.fbx etc. from github.com/ufbx/ufbx data/
FILES = ["maya_cube_7500_binary.fbx", "maya_game_sausage_7500_binary_combined.fbx"]


def run():
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    for f in FILES:
        dest = "/Game/FbxTest/" + os.path.splitext(f)[0]
        if unreal.EditorAssetLibrary.does_directory_exist(dest):
            unreal.EditorAssetLibrary.delete_directory(dest)
        t0 = time.time()
        task = unreal.AssetImportTask()
        task.filename = os.path.join(D, f)
        task.destination_path = dest
        task.automated = task.replace_existing = task.save = True
        tools.import_asset_tasks([task])
        got = {}
        for p in task.imported_object_paths:
            a = unreal.load_asset(p)
            got.setdefault(a.get_class().get_name() if a else "None", []).append(p.split("/")[-1])
        info = {}
        for p in task.imported_object_paths:
            a = unreal.load_asset(p)
            if isinstance(a, unreal.StaticMesh):
                info["static_vertices"] = a.get_num_vertices(0)
            if isinstance(a, unreal.AnimSequence):
                info["anim_seconds"] = round(a.get_editor_property("sequence_length") if hasattr(a, "sequence_length") else a.get_play_length(), 2)
        log(file=f, seconds=round(time.time() - t0, 2), imported=got, **info)
        yield
