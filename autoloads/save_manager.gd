extends Node

const META_SAVE_PATH: String = "user://shadow_core_meta_save.json"
const SUSPEND_SAVE_PATH: String = "user://shadow_core_suspend_save.json"

func load_json(path: String, fallback: Dictionary = {}) -> Dictionary:
    if not FileAccess.file_exists(path):
        return fallback.duplicate(true)
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("SaveManager: cannot open save file: " + path)
        return fallback.duplicate(true)
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        return parsed
    push_warning("SaveManager: save file is invalid, using fallback: " + path)
    return fallback.duplicate(true)

func save_json(path: String, data: Dictionary) -> void:
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("SaveManager: cannot write save file: " + path)
        return
    file.store_string(JSON.stringify(data, "	"))

func load_meta_save() -> Dictionary:
    return load_json(META_SAVE_PATH, {})

func save_meta_save(data: Dictionary) -> void:
    save_json(META_SAVE_PATH, data)

func has_suspend_save() -> bool:
    return FileAccess.file_exists(SUSPEND_SAVE_PATH)

func save_suspend(data: Dictionary) -> void:
    save_json(SUSPEND_SAVE_PATH, data)

func load_suspend_and_consume() -> Dictionary:
    var data: Dictionary = load_json(SUSPEND_SAVE_PATH, {})
    if FileAccess.file_exists(SUSPEND_SAVE_PATH):
        DirAccess.remove_absolute(SUSPEND_SAVE_PATH)
    return data

func clear_suspend() -> void:
    if FileAccess.file_exists(SUSPEND_SAVE_PATH):
        DirAccess.remove_absolute(SUSPEND_SAVE_PATH)


func save_run_state(state: Dictionary) -> bool:
    if state.is_empty():
        push_warning("SaveManager: refused to save empty run state.")
        return false
    save_suspend(state)
    return true

func load_run_state() -> Dictionary:
    return load_json(SUSPEND_SAVE_PATH, {})

func consume_run_state() -> Dictionary:
    return load_suspend_and_consume()

func clear_run_state() -> void:
    clear_suspend()

func reset_run() -> void:
    # SaveManager owns persistent files. reset_run must not delete meta or suspend data.
    pass

func get_state() -> Dictionary:
    return {"stateless": true, "note": "persistent IO service; no run-local state"}

func set_state(state: Variant = {}) -> void:
    # persistent IO service; no run-local state. Incoming state intentionally ignored.
    pass
