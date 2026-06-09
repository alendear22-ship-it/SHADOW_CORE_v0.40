extends Node

const PROJECTILE_SCENE: String = "res://scenes/projectiles/projectile_base.tscn"
var _pool: Array = []

func get_projectile() -> ProjectileBase:
    if not _pool.is_empty():
        var projectile: ProjectileBase = _pool.pop_back() as ProjectileBase
        projectile.visible = true
        projectile.set_physics_process(true)
        return projectile
    var scene: PackedScene = load(PROJECTILE_SCENE) as PackedScene
    if scene == null:
        push_error("ProjectilePool: missing projectile scene")
        return null
    return scene.instantiate() as ProjectileBase

func recycle(projectile: ProjectileBase) -> void:
    if projectile == null:
        return
    projectile.reset_projectile()
    if projectile.get_parent() != null:
        projectile.get_parent().remove_child(projectile)
    _pool.append(projectile)

func reset_run() -> void:
    # transient projectile pool. No run-local reset required.
    pass

func get_state() -> Dictionary:
    return {"stateless": true, "note": "transient projectile pool"}

func set_state(state: Variant = {}) -> void:
    # transient projectile pool. Incoming state intentionally ignored.
    pass
