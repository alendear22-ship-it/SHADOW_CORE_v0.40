extends Node
class_name HealthComponent

signal health_changed(current: float, maximum: float)
signal died(payload: DamagePayload)

@export var max_health: float = 100.0
var current_health: float = 100.0
var _dead: bool = false

func _ready() -> void:
    current_health = max_health
    health_changed.emit(current_health, max_health)

func configure(value: float) -> void:
    max_health = max(1.0, value)
    current_health = max_health
    _dead = false
    health_changed.emit(current_health, max_health)

func damage(amount: float, payload: DamagePayload = null) -> void:
    if _dead or amount <= 0.0:
        return
    current_health = max(0.0, current_health - amount)
    health_changed.emit(current_health, max_health)
    if current_health <= 0.0:
        _dead = true
        died.emit(payload)

func heal(amount: float) -> void:
    if _dead or amount <= 0.0:
        return
    current_health = min(max_health, current_health + amount)
    health_changed.emit(current_health, max_health)

func revive_with_ratio(ratio: float) -> void:
    var safe_ratio: float = clampf(ratio, 0.01, 1.0)
    _dead = false
    current_health = clampf(max_health * safe_ratio, 1.0, max_health)
    health_changed.emit(current_health, max_health)

func is_dead() -> bool:
    return _dead
