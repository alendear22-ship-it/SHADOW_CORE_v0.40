extends Node2D

var _profile: Dictionary = {}
var _context: Dictionary = {}
var _elapsed: float = 0.0
var _duration: float = 0.25
var _base_scale: float = 1.0
var _primary_color: Color = Color.WHITE
var _secondary_color: Color = Color(0.65, 0.45, 1.0, 1.0)
var _layers: Array = []
var _shape: String = "burst"
var _direction: Vector2 = Vector2.RIGHT
var _rng_seed: int = 1

func setup(profile: Dictionary, context: Dictionary = {}) -> void:
	_profile = profile.duplicate(true)
	_context = context.duplicate(true)
	_duration = max(0.05, float(_profile.get("duration", context.get("duration", 0.25))))
	_base_scale = max(0.01, float(_profile.get("scale", 1.0))) * max(0.01, float(context.get("power_scale", 1.0)))
	var level_key: String = str(int(context.get("level", 1)))
	var overrides_raw: Variant = _profile.get("level_visual_overrides", {})
	if overrides_raw is Dictionary:
		var level_override: Variant = overrides_raw.get(level_key, {})
		if level_override is Dictionary:
			_base_scale *= max(0.01, float(level_override.get("scale", 1.0)))
	_primary_color = Color(str(_profile.get("color", "#FFFFFF")))
	_secondary_color = Color(str(_profile.get("secondary_color", "#B88CFF")))
	_layers = _profile.get("layers", []) if _profile.get("layers", []) is Array else []
	_shape = str(_profile.get("shape", "burst"))
	_direction = context.get("direction", Vector2.RIGHT) if context.get("direction", Vector2.RIGHT) is Vector2 else Vector2.RIGHT
	if _direction.length() < 0.01:
		_direction = Vector2.RIGHT
	_direction = _direction.normalized()
	_rng_seed = int(abs(hash(str(_profile.get("id", "VISUAL_GENERIC_HIT"))))) % 9973
	var position_value: Variant = context.get("position", context.get("start_position", Vector2.ZERO))
	if position_value is Vector2:
		global_position = position_value
	add_to_group("combat_effects")
	add_to_group("room_effects")
	z_index = int(context.get("z_index", 82))
	modulate.a = 0.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var fade_in: float = smoothstep(0.0, 0.18, t)
	var fade_out: float = 1.0 - smoothstep(0.64, 1.0, t)
	modulate.a = clampf(fade_in * fade_out, 0.0, 1.0)
	scale = Vector2.ONE * (_base_scale * (1.0 + 0.10 * sin(t * PI)))
	queue_redraw()
	if _elapsed >= _duration:
		queue_free()

func _draw() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	if _layers.is_empty():
		_draw_fallback(t)
		return
	for layer_value in _layers:
		if layer_value is Dictionary:
			_draw_layer(layer_value, t)

func _draw_layer(layer: Dictionary, t: float) -> void:
	var layer_type: String = str(layer.get("type", "circle"))
	var alpha: float = float(layer.get("alpha", 0.5)) * (1.0 - smoothstep(0.70, 1.0, t))
	var color: Color = _primary_color
	color.a *= clampf(alpha, 0.0, 1.0)
	var radius: float = float(layer.get("radius_px", _context.get("radius_px", 28.0)))
	if bool(layer.get("expand", false)):
		radius *= lerpf(0.55, 1.30, smoothstep(0.0, 1.0, t))
	match layer_type:
		"circle":
			draw_circle(Vector2.ZERO, radius, color)
		"ring":
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, color, max(1.5, radius * 0.06), true)
		"spark":
			_draw_sparks(int(layer.get("count", 6)), float(layer.get("length_px", 18.0)), color, t)
		"arc":
			draw_arc(Vector2.ZERO, radius, -0.85, 0.85, 32, color, max(2.0, radius * 0.10), true)
		"line":
			var length_px: float = float(layer.get("length_px", _context.get("range_px", 96.0)))
			var width_px: float = float(layer.get("width_px", 5.0))
			draw_line(-_direction * length_px * 0.45, _direction * length_px * 0.55, color, width_px, true)
		"cone":
			_draw_cone(float(layer.get("radius_px", _context.get("range_px", 92.0))), float(layer.get("angle_deg", _context.get("angle_deg", 70.0))), color)
		"spiral":
			_draw_spiral(radius, float(layer.get("turns", 1.4)), color)
		"crack":
			_draw_crack(radius, color, t)
		"inward":
			_draw_inward_arrows(radius, color)
		"telegraph_ring":
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, color, max(2.0, radius * 0.05), true)
		"falling_line":
			var length_px: float = float(layer.get("length_px", 84.0))
			draw_line(Vector2(0, -length_px * lerpf(0.75, 0.10, t)), Vector2.ZERO, color, max(2.0, length_px * 0.035), true)
		"wave_arc":
			draw_arc(Vector2.ZERO, radius * lerpf(0.75, 1.35, t), -0.55, 0.55, 28, color, max(2.0, radius * 0.06), true)
		"banner":
			_draw_banner(radius, color)
		"rune":
			_draw_rune(radius, color)
		"splat":
			_draw_splat(radius, color)
		"bubble":
			_draw_bubbles(int(layer.get("count", 5)), radius, color)
		"orb":
			draw_circle(Vector2.ZERO, radius, color)
			_draw_sparks(5, radius * 0.9, color, t)
		"lightning":
			_draw_lightning(float(layer.get("length_px", 92.0)), color)
		_:
			_draw_fallback(t)

func _draw_sparks(count: int, length_px: float, color: Color, t: float) -> void:
	var safe_count: int = clampi(count, 1, 24)
	for i in range(safe_count):
		var angle: float = TAU * float(i) / float(safe_count) + float(_rng_seed % 31) * 0.01
		var dir: Vector2 = Vector2.RIGHT.rotated(angle)
		var inner: Vector2 = dir * length_px * 0.25
		var outer: Vector2 = dir * length_px * lerpf(0.55, 1.15, t)
		draw_line(inner, outer, color, 2.0, true)

func _draw_cone(radius: float, angle_deg: float, color: Color) -> void:
	var half: float = deg_to_rad(angle_deg) * 0.5
	var points: PackedVector2Array = PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(14):
		var ratio: float = float(i) / 13.0
		var angle: float = lerpf(-half, half, ratio)
		points.append(_direction.rotated(angle) * radius)
	points.append(Vector2.ZERO)
	draw_colored_polygon(points, color)


func _draw_spiral(radius: float, turns: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = 44
	for i in range(steps):
		var ratio: float = float(i) / float(steps - 1)
		var angle: float = TAU * turns * ratio + _elapsed * 3.0
		points.append(Vector2.RIGHT.rotated(angle) * radius * ratio)
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, 2.0, true)

func _draw_crack(radius: float, color: Color, t: float) -> void:
	var points: Array[Vector2] = [Vector2(-radius * 0.45, radius * 0.10), Vector2(-radius * 0.18, -radius * 0.10), Vector2(radius * 0.02, radius * 0.05), Vector2(radius * 0.28, -radius * 0.18), Vector2(radius * 0.48, radius * 0.02)]
	for i in range(points.size() - 1):
		draw_line(points[i] * lerpf(0.7, 1.1, t), points[i + 1] * lerpf(0.7, 1.1, t), color, 3.0, true)

func _draw_inward_arrows(radius: float, color: Color) -> void:
	for i in range(6):
		var angle: float = TAU * float(i) / 6.0
		var dir: Vector2 = Vector2.RIGHT.rotated(angle)
		draw_line(dir * radius, dir * radius * 0.35, color, 2.0, true)
		draw_line(dir * radius * 0.35, dir.rotated(0.35) * radius * 0.48, color, 1.5, true)
		draw_line(dir * radius * 0.35, dir.rotated(-0.35) * radius * 0.48, color, 1.5, true)

func _draw_banner(radius: float, color: Color) -> void:
	draw_line(Vector2(0, -radius * 0.65), Vector2(0, radius * 0.60), color, 3.0, true)
	var points: PackedVector2Array = PackedVector2Array([Vector2(0, -radius * 0.60), Vector2(radius * 0.42, -radius * 0.45), Vector2(radius * 0.20, -radius * 0.12), Vector2(0, -radius * 0.24)])
	draw_colored_polygon(points, color)

func _draw_rune(radius: float, color: Color) -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, color, 2.5, true)
	draw_line(Vector2(-radius * 0.55, 0), Vector2(radius * 0.55, 0), color, 2.0, true)
	draw_line(Vector2(0, -radius * 0.55), Vector2(0, radius * 0.55), color, 2.0, true)

func _draw_splat(radius: float, color: Color) -> void:
	draw_circle(Vector2.ZERO, radius * 0.50, color)
	for i in range(7):
		var dir: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / 7.0)
		draw_circle(dir * radius * 0.44, radius * 0.18, color)

func _draw_bubbles(count: int, radius: float, color: Color) -> void:
	for i in range(clampi(count, 1, 12)):
		var angle: float = TAU * float(i) / float(max(1, count))
		var bubble_radius: float = radius * (0.08 + 0.02 * float(i % 3))
		draw_arc(Vector2.RIGHT.rotated(angle) * radius * 0.45, bubble_radius, 0.0, TAU, 14, color, 1.5, true)

func _draw_lightning(length_px: float, color: Color) -> void:
	var a: Vector2 = -_direction * length_px * 0.45
	var b: Vector2 = a + _direction.rotated(0.42) * length_px * 0.24
	var c: Vector2 = b + _direction.rotated(-0.58) * length_px * 0.24
	var d: Vector2 = _direction * length_px * 0.45
	draw_line(a, b, color, 3.0, true)
	draw_line(b, c, color, 3.0, true)
	draw_line(c, d, color, 3.0, true)

func _draw_fallback(t: float) -> void:
	var color: Color = _primary_color
	color.a *= 0.55 * (1.0 - t)
	draw_circle(Vector2.ZERO, 24.0 * lerpf(0.8, 1.3, t), color)
	var spark_color: Color = _secondary_color
	spark_color.a *= 0.82 * (1.0 - t)
	_draw_sparks(6, 18.0, spark_color, t)
