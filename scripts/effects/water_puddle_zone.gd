extends Area2D
class_name WaterPuddleZone

var slow_percent: float = 20.0
var duration: float = 3.0
var _radius_px: float = 64.0
var _sprite_effect: Node2D = null

func _enter_tree() -> void:
	_ensure_runtime_nodes()

func _ready() -> void:
	add_to_group("room_effects")
	add_to_group("combat_effects")
	_ensure_runtime_nodes()
	_connect_signals_once()
	_apply_radius(_radius_px)
	monitoring = true
	monitorable = true

func setup(p_slow_percent: float, radius_px: float, p_duration: float) -> void:
	slow_percent = p_slow_percent
	duration = p_duration
	_radius_px = max(1.0, radius_px)
	_ensure_runtime_nodes()
	_apply_radius(_radius_px)
	monitoring = true
	monitorable = true
	scale = Vector2.ONE

func _process(delta: float) -> void:
	duration -= delta
	for body in get_overlapping_bodies():
		if body != null and body.has_method("apply_slow_status"):
			body.apply_slow_status("water_puddle_pr_v1", slow_percent, 0.25)
	if duration <= 0.0:
		queue_free()

func _connect_signals_once() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _ensure_runtime_nodes() -> void:
	_get_or_create_collision_shape()
	_get_or_create_visual()

func _get_or_create_collision_shape() -> CollisionShape2D:
	var found: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if found != null:
		return found
	for child in get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	found = CollisionShape2D.new()
	found.name = "CollisionShape2D"
	add_child(found)
	return found

func _get_or_create_visual() -> Polygon2D:
	var found: Polygon2D = get_node_or_null("Visual") as Polygon2D
	if found != null:
		return found
	for child in get_children():
		if child is Polygon2D:
			return child as Polygon2D
	found = Polygon2D.new()
	found.name = "Visual"
	found.color = Color(0.1, 0.35, 0.85, 0.20)
	add_child(found)
	return found

func _apply_radius(radius_px: float) -> void:
	_radius_px = max(1.0, radius_px)
	var collision_shape_node: CollisionShape2D = _get_or_create_collision_shape()
	if collision_shape_node == null:
		return
	var circle_shape: CircleShape2D = collision_shape_node.shape as CircleShape2D
	if circle_shape == null:
		circle_shape = CircleShape2D.new()
	else:
		circle_shape = circle_shape.duplicate() as CircleShape2D
	circle_shape.radius = _radius_px
	collision_shape_node.shape = circle_shape
	_rebuild_visual(_radius_px)
	_setup_water_sprite(_radius_px)

func _rebuild_visual(radius_px: float) -> void:
	var visual_node: Polygon2D = _get_or_create_visual()
	if visual_node == null:
		return
	var points: PackedVector2Array = PackedVector2Array()
	var point_count: int = 16
	for i in range(point_count):
		var angle: float = (TAU * float(i)) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius_px)
	visual_node.polygon = points

func _on_body_entered(body: Node) -> void:
	if body != null and body.has_method("apply_slow_status"):
		body.apply_slow_status("water_puddle_pr_v1", slow_percent, 0.35)

func _on_body_exited(_body: Node) -> void:
	pass

func _setup_water_sprite(radius_px: float) -> void:
	if _sprite_effect != null and is_instance_valid(_sprite_effect):
		return
	var script: Script = load("res://scripts/visuals/sequence_sprite_effect.gd") as Script
	if script == null:
		return
	_sprite_effect = script.new() as Node2D
	if _sprite_effect == null:
		return
	_sprite_effect.name = "WaterSpriteEffect"
	add_child(_sprite_effect)
	if _sprite_effect.has_method("setup_from_paths"):
		var ok: bool = bool(_sprite_effect.call("setup_from_paths", ShadowCoreAssetPaths.effect_sequence("water"), max(0.35, duration), max(0.42, radius_px / 120.0), 0.0, Color(0.62, 0.86, 1.0, 0.46), Vector2.ZERO, 1))
		if not ok:
			_sprite_effect.queue_free()
			_sprite_effect = null
