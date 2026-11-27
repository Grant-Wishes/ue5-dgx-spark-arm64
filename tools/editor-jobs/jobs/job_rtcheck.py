"""Which ray tracing paths are live: the console variables Lumen reads (hardware ray tracing vs software)."""
def run():
    world = S.get("world") or unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
    out = {}
    for name in ("r.RayTracing", "r.RayTracing.Enable", "r.Lumen.HardwareRayTracing", "r.Lumen.HardwareRayTracing.LightingMode",
                 "r.DynamicGlobalIlluminationMethod", "r.ReflectionMethod", "r.Shadow.Virtual.Enable", "r.ScreenPercentage"):
        try:
            out[name] = unreal.SystemLibrary.get_console_variable_int_value(name)
        except Exception as e:
            out[name] = repr(e)[:60]
    log(**out)
    yield
