extends Node2D
class_name AutoAttackSlashEffect

var lifetime: float = 0.16
var _max_lifetime: float = 0.16
var _line: Line2D = null
var _spark: Polygon2D = null
var _sprite_effect: Node2D = null

func _ready() -> void:
	add_to_group("room_effects")
	add_to_group("combat_effects")
	_ensure_nodes()

func setup(from_global: Vector2, to_global: Vector2) -> void:
	_ensure_nodes()
	global_position = from_global
	var local_to: Vector2 = to_global - from_global
	if _line != null:
		_line.points = PackedVector2Array([Vector2.ZERO, local_to])
	if _spark != null:
		_spark.position = local_to
		_spark.rotation = local_to.angle() if local_to.length() > 0.01 else 0.0
	_spawn_sprite_slash(local_to)

func _process(delta: float) -> void:
	lifetime -= delta
	modulate.a = clampf(lifetime / _max_lifetime, 0.0, 1.0)
	if lifetime <= 0.0:
		queue_free()

func _ensure_nodes() -> void:
	if _line == null:
		_line = get_node_or_null("Line2D") as Line2D
	if _line == null:
		_line = Line2D.new()
		_line.name = "Line2D"
		_line.width = 4.0
		_line.default_color = Color(0.75, 0.55, 1.0, 0.85)
		_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(_line)
	if _spark == null:
		_spark = get_node_or_null("Spark") as Polygon2D
	if _spark == null:
		_spark = Polygon2D.new()
		_spark.name = "Spark"
		_spark.polygon = PackedVector2Array([Vector2(0, -7), Vector2(12, 0), Vector2(0, 7), Vector2(-5, 0)])
		_spark.color = Color(0.95, 0.85, 1.0, 0.90)
		add_child(_spark)

func _spawn_sprite_slash(local_to: Vector2) -> void:
	var script: Script = load("res://scripts/visuals/sequence_sprite_effect.gd") as Script
	if script == null:
		return
	var effect: Node2D = script.new() as Node2D
	if effect == null:
		return
	add_child(effect)
	effect.position = local_to * 0.5
	var angle: float = local_to.angle() if local_to.length() > 0.01 else 0.0
	var scale_value: float = clampf(local_to.length() / 96.0, 0.65, 1.45)
	if effect.has_method("setup_from_paths"):
		var ok: bool = bool(effect.call("setup_from_paths", ShadowCoreAssetPaths.effect_sequence("auto_slash"), 0.16, scale_value, angle, Color(0.92, 0.78, 1.0, 0.98), Vector2.ZERO, 70))
		if not ok:
			effect.queue_free()
