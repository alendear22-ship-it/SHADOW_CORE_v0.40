extends Node2D
class_name SimpleDrawEffect

var mode: String = "circle"
var radius_px: float = 48.0
var range_px: float = 96.0
var direction: Vector2 = Vector2.RIGHT
var angle_rad: float = deg_to_rad(90.0)
var color: Color = Color(1.0, 1.0, 1.0, 0.9)
var duration: float = 0.35
var elapsed: float = 0.0
var target_node: Node2D = null
var follow_target: bool = false

func _ready() -> void:
	add_to_group("room_effects")
	add_to_group("combat_effects")

func setup(p_mode: String, p_radius_px: float = 48.0, p_direction: Vector2 = Vector2.RIGHT, p_range_px: float = 96.0, p_color: Color = Color(1, 1, 1, 0.9), p_duration: float = 0.35, p_angle_rad: float = 1.5708) -> void:
	mode = p_mode
	radius_px = max(1.0, p_radius_px)
	range_px = max(1.0, p_range_px)
	if p_direction.length_squared() > 0.001:
		direction = p_direction.normalized()
	color = p_color
	duration = max(0.05, p_duration)
	angle_rad = max(0.01, p_angle_rad)
	queue_redraw()

func follow(node: Node2D) -> void:
	target_node = node
	follow_target = true
	if target_node != null and is_instance_valid(target_node):
		global_position = target_node.global_position

func _process(delta: float) -> void:
	elapsed += delta
	if follow_target and target_node != null and is_instance_valid(target_node):
		global_position = target_node.global_position
	if elapsed >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = clampf(elapsed / duration, 0.0, 1.0)
	var alpha: float = color.a * (1.0 - t)
	var c: Color = Color(color.r, color.g, color.b, alpha)
	var soft: Color = Color(color.r, color.g, color.b, alpha * 0.16)
	match mode:
		"cone":
			_draw_cone(c, soft, t)
		"line":
			_draw_line_effect(c, t)
		"impact":
			_draw_impact(c, soft, t)
		"slash":
			_draw_slash(c, t)
		"telegraph_circle":
			_draw_telegraph_circle(c, soft, t)
		"telegraph_line":
			_draw_telegraph_line(c, t)
		"telegraph_cone":
			_draw_telegraph_cone(c, soft, t)
		_:
			_draw_circle_effect(c, soft, t)

func _draw_circle_effect(c: Color, soft: Color, t: float) -> void:
	var r: float = lerpf(radius_px * 0.82, radius_px, t)
	draw_circle(Vector2.ZERO, r, soft)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 72, c, 3.0, true)
	draw_arc(Vector2.ZERO, max(4.0, r * 0.45), 0.0, TAU, 48, Color(c.r, c.g, c.b, c.a * 0.45), 2.0, true)

func _draw_cone(c: Color, soft: Color, _t: float) -> void:
	var center_angle: float = direction.angle()
	var half_angle: float = angle_rad * 0.5
	var poly: PackedVector2Array = PackedVector2Array()
	poly.append(Vector2.ZERO)
	for i in range(20):
		var f: float = float(i) / 19.0
		poly.append(Vector2.from_angle(lerpf(center_angle - half_angle, center_angle + half_angle, f)) * range_px)
	draw_colored_polygon(poly, soft)
	draw_line(Vector2.ZERO, Vector2.from_angle(center_angle - half_angle) * range_px, c, 4.0, true)
	draw_line(Vector2.ZERO, Vector2.from_angle(center_angle + half_angle) * range_px, c, 4.0, true)
	draw_arc(Vector2.ZERO, range_px, center_angle - half_angle, center_angle + half_angle, 48, c, 4.0, true)

func _draw_line_effect(c: Color, t: float) -> void:
	var end: Vector2 = direction.normalized() * range_px
	draw_line(Vector2.ZERO, end, c, lerpf(7.0, 2.0, t), true)
	draw_circle(end, max(4.0, radius_px * (1.0 - t)), Color(c.r, c.g, c.b, c.a * 0.25))

func _draw_impact(c: Color, soft: Color, t: float) -> void:
	var r: float = lerpf(6.0, radius_px, t)
	draw_circle(Vector2.ZERO, r, soft)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, c, 3.0, true)
	draw_line(Vector2(-r, 0), Vector2(r, 0), Color(c.r, c.g, c.b, c.a * 0.55), 2.0, true)
	draw_line(Vector2(0, -r), Vector2(0, r), Color(c.r, c.g, c.b, c.a * 0.55), 2.0, true)

func _draw_slash(c: Color, t: float) -> void:
	var center_angle: float = direction.angle()
	var half_angle: float = angle_rad * 0.5
	var inner: float = range_px * 0.38
	var outer: float = range_px
	var width: float = lerpf(8.0, 2.0, t)
	for k in range(2):
		var points: PackedVector2Array = PackedVector2Array()
		var offset: float = float(k) * 0.12
		for i in range(24):
			var f: float = float(i) / 23.0
			var a: float = lerpf(center_angle - half_angle + offset, center_angle + half_angle + offset, f)
			var r: float = lerpf(inner, outer, f)
			points.append(Vector2.from_angle(a) * r)
		draw_polyline(points, Color(c.r, c.g, c.b, c.a * (1.0 - float(k) * 0.35)), width, true)


func _draw_telegraph_circle(c: Color, soft: Color, t: float) -> void:
	var outline: Color = Color(c.r, c.g, c.b, max(c.a, 0.28))
	var fill_radius: float = lerpf(2.0, radius_px, t)
	draw_circle(Vector2.ZERO, radius_px, Color(c.r, c.g, c.b, 0.08))
	draw_circle(Vector2.ZERO, fill_radius, Color(c.r, c.g, c.b, 0.20 + 0.18 * t))
	draw_arc(Vector2.ZERO, radius_px, 0.0, TAU, 72, outline, 3.0, true)
	draw_arc(Vector2.ZERO, max(4.0, fill_radius), 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.55), 2.0, true)

func _draw_telegraph_line(c: Color, t: float) -> void:
	var full_end: Vector2 = direction.normalized() * range_px
	var fill_end: Vector2 = direction.normalized() * lerpf(0.0, range_px, t)
	draw_line(Vector2.ZERO, full_end, Color(c.r, c.g, c.b, 0.18), max(10.0, radius_px * 0.22), true)
	draw_line(Vector2.ZERO, fill_end, Color(c.r, c.g, c.b, 0.65), max(7.0, radius_px * 0.18), true)
	draw_circle(full_end, max(4.0, radius_px * 0.24), Color(c.r, c.g, c.b, 0.35))

func _draw_telegraph_cone(c: Color, soft: Color, t: float) -> void:
	var center_angle: float = direction.angle()
	var half_angle: float = angle_rad * 0.5
	var fill_range: float = lerpf(4.0, range_px, t)
	var poly: PackedVector2Array = PackedVector2Array()
	poly.append(Vector2.ZERO)
	for i in range(20):
		var f: float = float(i) / 19.0
		poly.append(Vector2.from_angle(lerpf(center_angle - half_angle, center_angle + half_angle, f)) * fill_range)
	draw_colored_polygon(poly, Color(c.r, c.g, c.b, 0.18 + 0.14 * t))
	draw_line(Vector2.ZERO, Vector2.from_angle(center_angle - half_angle) * range_px, Color(c.r, c.g, c.b, 0.45), 3.0, true)
	draw_line(Vector2.ZERO, Vector2.from_angle(center_angle + half_angle) * range_px, Color(c.r, c.g, c.b, 0.45), 3.0, true)
	draw_arc(Vector2.ZERO, range_px, center_angle - half_angle, center_angle + half_angle, 48, Color(c.r, c.g, c.b, 0.55), 3.0, true)
