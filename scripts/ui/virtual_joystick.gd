extends Control
class_name VirtualJoystick

var _dragging: bool = false
var _center: Vector2 = Vector2.ZERO
var _radius: float = 72.0
var _direction: Vector2 = Vector2.ZERO

func _ready() -> void:
    anchor_left = 0.0
    anchor_top = 1.0
    anchor_right = 0.0
    anchor_bottom = 1.0
    offset_left = 44
    offset_top = -180
    offset_right = 204
    offset_bottom = -20
    mouse_filter = Control.MOUSE_FILTER_STOP
    _center = size * 0.5

func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        _dragging = event.pressed
        _update_direction(event.position)
    elif event is InputEventScreenDrag:
        _dragging = true
        _update_direction(event.position)
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _dragging = event.pressed
        _update_direction(event.position)
    elif event is InputEventMouseMotion and _dragging:
        _update_direction(event.position)
    if not _dragging:
        _direction = Vector2.ZERO
        EventBus.movement_input_changed.emit(_direction)
        queue_redraw()

func _update_direction(local_pos: Vector2) -> void:
    var offset: Vector2 = local_pos - _center
    _direction = offset.limit_length(_radius) / _radius
    if _direction.length() < 0.1:
        _direction = Vector2.ZERO
    EventBus.movement_input_changed.emit(_direction)
    queue_redraw()

func _draw() -> void:
    draw_circle(_center, _radius, Color(0.08, 0.08, 0.12, 0.55))
    draw_arc(_center, _radius, 0.0, TAU, 48, Color(0.55, 0.65, 0.9, 0.8), 2.0)
    draw_circle(_center + _direction * _radius, 26.0, Color(0.55, 0.65, 0.9, 0.9))
