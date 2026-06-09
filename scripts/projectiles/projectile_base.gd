extends Area2D
class_name ProjectileBase

var velocity: Vector2 = Vector2.ZERO
var payload: DamagePayload = null
var lifetime: float = 2.0

func _ready() -> void:
    add_to_group("projectiles")
    body_entered.connect(_on_body_entered)

func setup(start_position: Vector2, direction: Vector2, speed: float, p_payload: DamagePayload, p_lifetime: float = 2.0) -> void:
    global_position = start_position
    velocity = direction.normalized() * speed
    payload = p_payload
    if payload != null:
        payload.normalize_source_type()
    lifetime = p_lifetime

func _physics_process(delta: float) -> void:
    global_position += velocity * delta
    lifetime -= delta
    if lifetime <= 0.0:
        ProjectilePool.recycle(self)

func reset_projectile() -> void:
    velocity = Vector2.ZERO
    payload = null
    lifetime = 0.0
    visible = false
    set_physics_process(false)

func _on_body_entered(body: Node) -> void:
    if payload != null and body.is_in_group("enemies"):
        CombatSystem.apply_damage(body, payload.duplicate_payload())
        ProjectilePool.recycle(self)
