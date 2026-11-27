"""Demo scene for the arm64 editor: a lit level with a stock MetaHuman Creator character (Epic's template face, grooms
from the plugin's wardrobe), assembled for preview locally (no cloud auto-rig), the viewport framed on the head.
Leaves in S: world, character, actor, head."""
import time

G = "/MetaHumanCharacter/Optional/Grooms/Bindings"
GROOMS = {"Hair": f"{G}/Hair/WI_Hair_M_BobBangs.WI_Hair_M_BobBangs",
          "Eyebrows": f"{G}/Eyebrows/WI_Eyebrows_M_Natural.WI_Eyebrows_M_Natural",
          "Eyelashes": f"{G}/Eyelashes/WI_Eyelashes_L_SlightCurl.WI_Eyelashes_L_SlightCurl",
          "Peachfuzz": f"{G}/Peachfuzz/WI_Peachfuzz_M_Thin.WI_Peachfuzz_M_Thin"}
PKG = "/Game/Demo"


def sub(cls):
    return unreal.get_editor_subsystem(cls)


def run():
    t0 = time.time()
    eas, les = sub(unreal.EditorActorSubsystem), sub(unreal.LevelEditorSubsystem)
    les.new_level(PKG + "/L_Demo_" + str(int(time.time())))   # a fresh level every run
    world = sub(unreal.UnrealEditorSubsystem).get_editor_world()
    for a in eas.get_all_level_actors():
        if not isinstance(a, unreal.WorldSettings):
            eas.destroy_actor(a)
    sun = eas.spawn_actor_from_class(unreal.DirectionalLight, unreal.Vector(0, 0, 500), unreal.Rotator(roll=0, pitch=-35, yaw=-130))
    sun.light_component.set_editor_property("intensity", 8.0)
    sun.light_component.set_editor_property("atmosphere_sun_light", True)
    sun.light_component.set_mobility(unreal.ComponentMobility.MOVABLE)   # Lumen, nothing baked
    eas.spawn_actor_from_class(unreal.SkyAtmosphere, unreal.Vector(0, 0, 0))
    sky = eas.spawn_actor_from_class(unreal.SkyLight, unreal.Vector(0, 0, 300))
    sky.light_component.set_mobility(unreal.ComponentMobility.MOVABLE)
    sky.light_component.set_editor_property("real_time_capture", True)
    unreal.SystemLibrary.execute_console_command(world, "DisableAllScreenMessages")
    eas.spawn_actor_from_class(unreal.ExponentialHeightFog, unreal.Vector(0, 0, 0))
    floor = eas.spawn_actor_from_object(unreal.load_asset("/Engine/BasicShapes/Plane.Plane"), unreal.Vector(0, 0, 0))
    floor.set_actor_scale3d(unreal.Vector(20, 20, 1))
    log(step="level", seconds=round(time.time() - t0, 1))
    yield

    mhs = sub(unreal.MetaHumanCharacterEditorSubsystem)
    path = f"{PKG}/MHC_Demo"
    if unreal.EditorAssetLibrary.does_asset_exist(path):
        unreal.EditorAssetLibrary.delete_asset(path)
    character = unreal.AssetToolsHelpers.get_asset_tools().create_asset("MHC_Demo", PKG, unreal.MetaHumanCharacter,
                                                                        unreal.MetaHumanCharacterFactoryNew())
    character.preview_material_type = unreal.MetaHumanCharacterSkinPreviewMaterial.EDITABLE   # skin synthesized locally
    outfit = unreal.load_asset("/MetaHumanCharacter/Optional/Clothing/WI_DefaultGarment.WI_DefaultGarment")
    for slot in ("Outfits", "Outfit", "Clothing", "Garments"):
        item = character.internal_collection.try_add_item_from_wardrobe_item(slot, outfit)
        if item:
            character.internal_collection.default_instance.try_add_slot_selection(
                unreal.MetaHumanPipelineSlotSelection(slot_name=slot, selected_item=item))
            log(step="outfit", slot=slot)
            break
    for slot, gp in GROOMS.items():
        item = character.internal_collection.try_add_item_from_wardrobe_item(slot, unreal.load_asset(gp))
        character.internal_collection.default_instance.try_add_slot_selection(
            unreal.MetaHumanPipelineSlotSelection(slot_name=slot, selected_item=item))
    if not mhs.try_add_object_to_edit(character):
        raise RuntimeError("character not editable")
    skin = unreal.MetaHumanCharacterSkinProperties()
    skin.u, skin.v, skin.roughness = 0.45, 0.35, 0.8
    settings = unreal.MetaHumanCharacterSkinSettings()
    settings.skin = skin
    mhs.commit_skin_settings(character, settings)
    log(step="character", seconds=round(time.time() - t0, 1))
    yield
    mhs.assemble_for_preview(character=character)
    unreal.EditorAssetLibrary.save_loaded_asset(character, False)
    actor = mhs.spawn_meta_human_actor(character)
    log(step="actor", seconds=round(time.time() - t0, 1), actor_class=actor.get_class().get_name())
    for _ in range(1800):   # the grooms arrive over the next frames
        g = {c.get_name(): c.get_editor_property("groom_asset") for c in actor.get_components_by_class(unreal.GroomComponent)}
        if g.get("Hair") and g.get("Eyebrows"):
            break
        yield 0.1
    log(step="grooms", grooms={k: (v.get_name() if v else None) for k, v in g.items()}, seconds=round(time.time() - t0, 1))
    o, e = actor.get_actor_bounds(False)
    head = unreal.Vector(o.x, o.y, o.z + e.z - 14.0)
    for _ in range(20):   # skin textures and shaders settle over the next frames
        yield 0.5
    cam = head + unreal.Vector(0.0, 55.0, 2.0)
    sub(unreal.UnrealEditorSubsystem).set_level_viewport_camera_info(cam, unreal.MathLibrary.find_look_at_rotation(cam, head))
    S.update(world=world, character=character, actor=actor, head=head)
    log(step="done", seconds=round(time.time() - t0, 1), head=[round(head.x, 1), round(head.y, 1), round(head.z, 1)])
