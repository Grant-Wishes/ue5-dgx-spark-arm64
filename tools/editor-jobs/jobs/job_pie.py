"""Play In Editor: starts a play session in the level viewport, lets it run, checks it is live, then stops it."""
import time


def run():
    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    t0 = time.time()
    les.editor_request_begin_play()
    for _ in range(100):
        if les.is_in_play_in_editor():
            break
        yield 0.1
    log(playing=bool(les.is_in_play_in_editor()), seconds=round(time.time() - t0, 2))
    yield 8.0
    log(still_playing=bool(les.is_in_play_in_editor()))
    les.editor_request_end_play()
    yield 2.0
    log(stopped=not les.is_in_play_in_editor())
