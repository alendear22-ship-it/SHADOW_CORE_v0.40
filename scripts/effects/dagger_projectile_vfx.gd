extends Node2D
class_name DaggerProjectileVFX

var start_position: Vector2 = Vector2.ZERO
var end_position: Vector2 = Vector2.ZERO
var duration: float = 0.25
var elapsed: float = 0.0
var _sprite: Sprite2D = null
var _frames: Array[Texture2D] = []
var _fallback_draw: bool = true

func _ready() -> void:
	add_to_group("room_effects")
	add_to_group("combat_effects")
	_ensure_sprite()

func setup(p_start: Vector2, p_end: Vector2, p_duration: float, p_scale: float = 0.55, p_tint: Color = Color.WHITE) -> void:
	start_position = p_start
	end_position = p_end
	duration = max(0.06, p_duration)
	elapsed = 0.0
	global_position = start_position
	rotation = (end_position - start_position).angle()
	modulate = p_tint
	_ensure_sprite()
	_load_frames()
	if _sprite != null:
		_sprite.scale = Vector2.ONE * max(0.05, p_scale)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	var t: float = clampf(elapsed / duration, 0.0, 1.0)
	global_position = start_position.lerp(end_position, _ease_out_quad(t))
	if not _frames.is_empty() and _sprite != null:
		var index: int = clampi(int(floor(t * float(_frames.size()))), 0, _frames.size() - 1)
		_sprite.texture = _frames[index]
	modulate.a = 1.0 - max(0.0, (t - 0.82) / 0.18)
	queue_redraw()
	if elapsed >= duration:
		queue_free()

func _draw() -> void:
	if not _fallback_draw:
		return
	var c: Color = Color(0.82, 0.62, 1.0, 0.95)
	var points: PackedVector2Array = PackedVector2Array()
	points.append(Vector2(20.0, 0.0))
	points.append(Vector2(-10.0, -5.0))
	points.append(Vector2(-5.0, 0.0))
	points.append(Vector2(-10.0, 5.0))
	draw_colored_polygon(points, c)
	draw_line(Vector2(-22.0, 0.0), Vector2(-6.0, 0.0), Color(c.r, c.g, c.b, 0.50), 4.0, true)

func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	_sprite = Sprite2D.new()
	_sprite.name = "DaggerSprite"
	_sprite.centered = true
	_sprite.z_index = 70
	add_child(_sprite)

func _load_frames() -> void:
	_frames.clear()
	for path_value in ShadowCoreAssetPaths.effect_sequence("dagger"):
		var path: String = str(path_value)
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var texture: Texture2D = load(path) as Texture2D
		if texture != null:
			_frames.append(texture)
	if _frames.is_empty():
		_fallback_draw = true
		if _sprite != null:
			_sprite.visible = false
	else:
		_fallback_draw = false
		_sprite.visible = true
		_sprite.texture = _frames[0]

func _ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)
