extends Button
class_name AbilityButton

@export var slot: String = "active_1"

const HOLD_TARGET_SLOTS: Array[String] = ["active_1", "active_2", "ultimate"]
const CANCEL_DISTANCE_MULTIPLIER: float = 4.0
const MIN_DIRECTION_DISTANCE_PX: float = 8.0
const BUTTON_SIZE: Vector2 = Vector2(94, 94)

var _base_text: String = ""
var _holding: bool = false
var _touch_index: int = -1
var _hold_origin_screen: Vector2 = Vector2.ZERO
var _hold_direction: Vector2 = Vector2.RIGHT
var _hold_canceled: bool = false
var _cancel_radius_px: float = 256.0
var _icon_texture: Texture2D = null
var _cooldown_text: String = ""

func _ready() -> void:
	_base_text = text
	custom_minimum_size = BUTTON_SIZE
	clip_contents = true
	icon = null
	expand_icon = false
	_load_button_icon()
	_apply_round_style()
	pressed.connect(_on_pressed)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var radius: float = min(size.x, size.y) * 0.5
	var center: Vector2 = size * 0.5
	var bg: Color = Color(0.08, 0.08, 0.13, 0.88)
	var border: Color = Color(0.54, 0.62, 0.96, 0.92)
	if disabled:
		bg = Color(0.05, 0.05, 0.07, 0.75)
		border = Color(0.25, 0.28, 0.36, 0.75)
	draw_circle(center, radius - 2.0, bg)
	draw_arc(center, radius - 3.0, 0.0, TAU, 64, border, 2.5, true)
	if _icon_texture != null:
		var icon_size: float = radius * 1.22
		var rect: Rect2 = Rect2(center - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size)
		draw_texture_rect(_icon_texture, rect, false, Color(1.0, 1.0, 1.0, 0.88 if not disabled else 0.35))

func _on_pressed() -> void:
	# Directional/area abilities use press-hold-release targeting on touch/mouse.
	if _uses_hold_targeting():
		return
	EventBus.ability_button_pressed.emit(slot)

func _gui_input(event: InputEvent) -> void:
	if disabled or not _uses_hold_targeting():
		return
	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		if touch_event.pressed:
			_begin_hold(touch_event.position, touch_event.index)
			accept_event()
		elif _holding and touch_event.index == _touch_index:
			_finish_hold(touch_event.position)
			accept_event()
	elif event is InputEventScreenDrag:
		var drag_event: InputEventScreenDrag = event as InputEventScreenDrag
		if _holding and drag_event.index == _touch_index:
			_update_hold(drag_event.position)
			accept_event()
	elif event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_begin_hold(get_viewport().get_mouse_position(), -2)
			accept_event()
		elif _holding and _touch_index == -2:
			_finish_hold(get_viewport().get_mouse_position())
			accept_event()
	elif event is InputEventMouseMotion:
		if _holding and _touch_index == -2:
			_update_hold(get_viewport().get_mouse_position())
			accept_event()

func _input(event: InputEvent) -> void:
	if not _holding:
		return
	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		if touch_event.index != _touch_index:
			return
		if touch_event.pressed:
			_update_hold(touch_event.position)
		else:
			_finish_hold(touch_event.position)
	elif event is InputEventScreenDrag:
		var drag_event: InputEventScreenDrag = event as InputEventScreenDrag
		if drag_event.index == _touch_index:
			_update_hold(drag_event.position)
	elif event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if _touch_index == -2 and mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
			_finish_hold(get_viewport().get_mouse_position())
	elif event is InputEventMouseMotion:
		if _touch_index == -2:
			_update_hold(get_viewport().get_mouse_position())

func _load_button_icon() -> void:
	var texture_path: String = ShadowCoreAssetPaths.ability_icon_path(slot)
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		_icon_texture = load(texture_path) as Texture2D
		if _icon_texture != null:
			return
	var ability_data: Dictionary = _get_hero_ability_data()
	if ability_data.is_empty():
		ability_data = {"id": slot, "slot": slot}
	var factory: Node = get_node_or_null("/root/ProceduralIconFactory")
	if factory != null and factory.has_method("get_icon_for_hero_ability"):
		var generated: Variant = factory.call("get_icon_for_hero_ability", ability_data, 64)
		if generated is Texture2D:
			_icon_texture = generated

func _get_hero_ability_data() -> Dictionary:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_hero_ability"):
		var ability: Variant = registry.call("get_hero_ability", "HERO_KAEL", slot)
		if ability is Dictionary:
			return ability
	return {}

func _apply_round_style() -> void:
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("hover", empty)
	add_theme_stylebox_override("pressed", empty)
	add_theme_stylebox_override("disabled", empty)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.45))
	add_theme_font_size_override("font_size", 15)

func set_cooldown(remaining: float, duration: float) -> void:
	disabled = remaining > 0.05
	if remaining > 0.05:
		text = _base_text + "\n" + str(snapped(remaining, 0.1))
	else:
		text = _base_text
	queue_redraw()

func _uses_hold_targeting() -> bool:
	return HOLD_TARGET_SLOTS.has(slot)

func _begin_hold(screen_position: Vector2, pointer_index: int) -> void:
	_holding = true
	_touch_index = pointer_index
	_hold_origin_screen = global_position + size * 0.5
	_cancel_radius_px = max(size.x, size.y) * CANCEL_DISTANCE_MULTIPLIER
	_hold_direction = Vector2.RIGHT
	_hold_canceled = false
	_update_hold(screen_position)
	EventBus.ability_targeting_started.emit(slot, _hold_direction, _cancel_radius_px)

func _update_hold(screen_position: Vector2) -> void:
	var delta: Vector2 = screen_position - _hold_origin_screen
	_hold_canceled = delta.length() > _cancel_radius_px
	if delta.length() >= MIN_DIRECTION_DISTANCE_PX:
		_hold_direction = delta.normalized()
	EventBus.ability_targeting_changed.emit(slot, _hold_direction, _hold_canceled)

func _finish_hold(screen_position: Vector2) -> void:
	var delta: Vector2 = screen_position - _hold_origin_screen
	if delta.length() < MIN_DIRECTION_DISTANCE_PX:
		EventBus.ability_targeting_finished.emit(slot, Vector2.ZERO, false)
	else:
		_update_hold(screen_position)
		EventBus.ability_targeting_finished.emit(slot, _hold_direction, _hold_canceled)
	_holding = false
	_touch_index = -1
	_hold_canceled = false
