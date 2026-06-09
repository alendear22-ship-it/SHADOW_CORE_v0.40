extends Node
class_name CooldownComponent

signal cooldown_changed(remaining: float, duration: float)

var remaining: float = 0.0
var duration: float = 0.0

func start(seconds: float) -> void:
    duration = max(0.0, seconds)
    remaining = duration
    cooldown_changed.emit(remaining, duration)

func _process(delta: float) -> void:
    if remaining <= 0.0:
        return
    remaining = max(0.0, remaining - delta)
    cooldown_changed.emit(remaining, duration)

func is_ready() -> bool:
    return remaining <= 0.0
