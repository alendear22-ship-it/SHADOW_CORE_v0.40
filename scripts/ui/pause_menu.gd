extends CanvasLayer
class_name PauseMenu

func _ready() -> void:
    visible = false
    EventBus.request_pause_toggle.connect(toggle_pause)

func toggle_pause() -> void:
    visible = not visible
    get_tree().paused = visible
