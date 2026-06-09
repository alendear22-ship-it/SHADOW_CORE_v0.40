extends Node2D
class_name SequenceSpriteEffect

var duration: float = 0.35
var elapsed: float = 0.0
var auto_free: bool = true
var _frames: Array[Texture2D] = []
var _sprite: Sprite2D = null

func _ready() -> void:
	add_to_group("room_effects")
	add_to_group("combat_effects")
	_ensure_sprite()

func setup_from_paths(texture_paths: Array, p_duration: float = 0.35, p_scale: float = 1.0, p_rotation: float = 0.0, p_modulate: Color = Color.WHITE, p_offset: Vector2 = Vector2.ZERO, p_z_index: int = 50) -> bool:
	_ensure_sprite()
	_frames.clear()
	for path_value in texture_paths:
		var texture_path: String = str(path_value)
		if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
			continue
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture != null:
			_frames.append(texture)
	if _frames.is_empty():
		visible = false
		return false
	duration = max(0.05, p_duration)
	elapsed = 0.0
	rotation = p_rotation
	modulate = p_modulate
	z_index = p_z_index
	_sprite.position = p_offset
	_sprite.centered = true
	_sprite.scale = Vector2.ONE * max(0.01, p_scale)
	_sprite.texture = _frames[0]
	visible = true
	return true

func _process(delta: float) -> void:
	if _frames.is_empty():
		if auto_free:
			queue_free()
		return
	elapsed += delta
	var t: float = clampf(elapsed / duration, 0.0, 1.0)
	var index: int = clampi(int(floor(t * float(_frames.size()))), 0, _frames.size() - 1)
	_sprite.texture = _frames[index]
	modulate.a = 1.0 - max(0.0, (t - 0.78) / 0.22)
	if elapsed >= duration and auto_free:
		queue_free()

func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		_sprite.centered = true
		add_child(_sprite)
