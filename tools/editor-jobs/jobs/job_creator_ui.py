"""Opens the MetaHuman Creator's own asset editor (the Creator UI, all local) on a fresh character that no script has
taken for editing (the subsystem allows one editing session per character)."""
import time


def run():
    t0 = time.time()
    path = "/Game/Demo/MHC_UI"
    if unreal.EditorAssetLibrary.does_asset_exist(path):
        unreal.EditorAssetLibrary.delete_asset(path)
    ch = unreal.AssetToolsHelpers.get_asset_tools().create_asset("MHC_UI", "/Game/Demo", unreal.MetaHumanCharacter,
                                                                 unreal.MetaHumanCharacterFactoryNew())
    unreal.EditorAssetLibrary.save_loaded_asset(ch, False)
    ok = unreal.get_editor_subsystem(unreal.AssetEditorSubsystem).open_editor_for_assets([ch])
    log(opened=bool(ok), seconds=round(time.time() - t0, 2))
    for _ in range(40):
        yield 0.5
    log(seconds_total=round(time.time() - t0, 2))
