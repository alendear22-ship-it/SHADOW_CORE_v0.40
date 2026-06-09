extends Node2D
class_name HitEffect

var lifetime: float = 0.18
var _max_lifetime: float = 0.18
var _sprite_effect: Node2D = null
@onready var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem

func _ready() -> void:
	add_to_group("room_effects")
	add_to_group("combat_effects")
	_spawn_sprite_feedback()

func _process(delta: float) -> void:
	lifetime -= delta
	modulate.a = max(0.0, lifetime / _max_lifetime)
	if lifetime <= 0.0:
		queue_free()

func _spawn_sprite_feedback() -> void:
	var script: Script = load("res://scripts/visuals/sequence_sprite_effect.gd") as Script
	if script == null:
		return
	_sprite_effect = script.new() as Node2D
	if _sprite_effect == null:
		return
	add_child(_sprite_effect)
	if _sprite_effect.has_method("setup_from_paths"):
		var ok: bool = bool(_sprite_effect.call("setup_from_paths", ShadowCoreAssetPaths.effect_sequence("impact_purple"), _max_lifetime, 0.32, randf() * TAU, Color(0.86, 0.74, 1.0, 0.95), Vector2.ZERO, 80))
		if ok and visual != null:
			visual.visible = false
		elif not ok:
			_sprite_effect.queue_free()
			_sprite_effect = null
