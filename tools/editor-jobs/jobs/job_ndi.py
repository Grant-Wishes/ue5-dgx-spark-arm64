"""Sends the active level viewport out as an NDI source named "SparkUE" for SECONDS, logging the capture state, then
stops the capture. Meanwhile an independent receiver checks the stream: tools/ndi/ndi_recv_check (see its header).
Needs the NDIMedia plugin and the NDI runtime (build.sh with NDI_SDK_DIR)."""
import time

SECONDS = 40


def run():
    t0 = time.time()
    out = unreal.NDIMediaOutput()
    out.set_editor_property("source_name", "SparkUE")
    cap = out.create_media_capture()
    ok = cap.capture_active_scene_viewport(unreal.MediaCaptureOptions())
    log(started=bool(ok), output=out.get_editor_property("source_name"))
    for i in range(SECONDS * 2):
        yield 0.5
        if i % 10 == 0:
            log(state=str(cap.get_state()), t=round(time.time() - t0, 1))
    cap.stop_capture(False)
    yield 0.5
    log(state_after_stop=str(cap.get_state()))
