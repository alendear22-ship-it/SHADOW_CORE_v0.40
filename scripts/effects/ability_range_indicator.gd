extends Node2D
class_name AbilityRangeIndicator

var target_node: Node2D = null
var mode: String = "circle"
var radius_px: float = 160.0
var direction: Vector2 = Vector2.RIGHT
var cone_angle_rad: float = deg_to_rad(100.0)
var canceled: bool = false
var area_radius_px: float = 0.0

func _ready() -> void:
	add_to_group("room_effects")
	add_to_group("combat_effects")

func setup(p_target: Node2D, p_mode: String, p_radius_px: float, p_direction: Vector2 = Vector2.RIGHT, p_canceled: bool = false, p_area_radius_px: float = 0.0) -> void:
	target_node = p_target
	mode = p_mode
	radius_px = max(8.0, p_radius_px)
	area_radius_px = max(0.0, p_area_radius_px)
	update_indicator(p_direction, p_canceled)
	if target_node != null and is_instance_valid(target_node):
		global_position = target_node.global_position

func update_indicator(p_direction: Vector2, p_canceled: bool = false) -> void:
	if p_direction.length_squared() > 0.001:
		direction = p_direction.normalized()
	canceled = p_canceled
	queue_redraw()

func _process(_delta: float) -> void:
	if target_node != null and is_instance_valid(target_node):
		global_position = target_node.global_position
	queue_redraw()

func _draw() -> void:
	var color: Color = Color(1.0, 0.22, 0.18, 0.78) if canceled else Color(0.55, 0.72, 1.0, 0.62)
	var fill_color: Color = Color(color.r, color.g, color.b, 0.08)
	match mode:
		"cone":
			_draw_cone(color, fill_color)
		"line":
			_draw_line(color)
		"target_area":
			_draw_target_area(color, fill_color)
		_:
			_draw_circle(color, fill_color)

func _draw_circle(color: Color, fill_color: Color) -> void:
	draw_circle(Vector2.ZERO, radius_px, fill_color)
	draw_arc(Vector2.ZERO, radius_px, 0.0, TAU, 96, color, 3.0, true)
	draw_arc(Vector2.ZERO, radius_px * 0.45, 0.0, TAU, 72, Color(color.r, color.g, color.b, color.a * 0.45), 2.0, true)

func _draw_cone(color: Color, fill_color: Color) -> void:
	var center_angle: float = direction.angle()
	var half_angle: float = cone_angle_rad * 0.5
	var left: Vector2 = Vector2.from_angle(center_angle - half_angle) * radius_px
	var right: Vector2 = Vector2.from_angle(center_angle + half_angle) * radius_px
	var poly: PackedVector2Array = PackedVector2Array()
	poly.append(Vector2.ZERO)
	for i in range(25):
		var t: float = float(i) / 24.0
		var a: float = lerpf(center_angle - half_angle, center_angle + half_angle, t)
		poly.append(Vector2.from_angle(a) * radius_px)
	draw_colored_polygon(poly, fill_color)
	draw_line(Vector2.ZERO, left, color, 3.0, true)
	draw_line(Vector2.ZERO, right, color, 3.0, true)
	draw_arc(Vector2.ZERO, radius_px, center_angle - half_angle, center_angle + half_angle, 48, color, 3.0, true)

func _draw_line(color: Color) -> void:
	var end: Vector2 = direction.normalized() * radius_px
	draw_line(Vector2.ZERO, end, Color(color.r, color.g, color.b, 0.30), 18.0, true)
	draw_line(Vector2.ZERO, end, color, 4.0, true)
	draw_circle(end, 10.0, Color(color.r, color.g, color.b, 0.35))

func _draw_target_area(color: Color, fill_color: Color) -> void:
	var target: Vector2 = direction.normalized() * radius_px
	draw_arc(Vector2.ZERO, radius_px, 0.0, TAU, 72, Color(color.r, color.g, color.b, 0.28), 2.0, true)
	draw_line(Vector2.ZERO, target, Color(color.r, color.g, color.b, 0.35), 2.0, true)
	var area: float = area_radius_px if area_radius_px > 0.0 else radius_px * 0.85
	draw_circle(target, area, fill_color)
	draw_arc(target, area, 0.0, TAU, 72, color, 3.0, true)
	draw_arc(target, area * 0.50, 0.0, TAU, 48, Color(color.r, color.g, color.b, color.a * 0.45), 2.0, true)
