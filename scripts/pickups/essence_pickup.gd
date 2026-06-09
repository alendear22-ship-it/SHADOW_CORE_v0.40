extends Area2D
class_name EssencePickup

const BASE_MAGNET_RADIUS_PX: float = 160.0
const BASE_MAGNET_SPEED_PX: float = 260.0
const DIRECT_COLLECT_DISTANCE_PX: float = 18.0
const HEAL_PER_ESSENCE: float = 2.0

var creature_type_id: String = ""
var faction_id: String = ""
var amount: int = 1

var _target: Node2D = null
var _magnet_radius_multiplier: float = 1.0
var _magnet_speed_multiplier: float = 1.0
var _force_room_clear_magnet: bool = false
var _collected: bool = false
var _sprite_visual: SpriteSheetAnimator = null
@onready var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem

func _ready() -> void:
	add_to_group("room_effects")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	monitoring = true
	monitorable = true
	_setup_essence_sprite()
	_apply_faction_color()

func setup(p_creature_type_id: String, p_faction_id: String, p_amount: int) -> void:
	creature_type_id = p_creature_type_id
	faction_id = p_faction_id
	var creature_data: Dictionary = DataRegistry.get_creature_type(creature_type_id) if not creature_type_id.is_empty() else {}
	if not creature_data.is_empty():
		var correct_faction: String = str(creature_data.get("faction_id", ""))
		if not correct_faction.is_empty():
			faction_id = correct_faction
	amount = max(1, p_amount)
	_setup_essence_sprite()
	_apply_faction_color()

func start_room_clear_magnet(player: Node2D, multiplier: float = 10.0) -> void:
	_target = player
	_magnet_radius_multiplier = max(1.0, multiplier)
	_magnet_speed_multiplier = max(1.0, sqrt(_magnet_radius_multiplier))
	_force_room_clear_magnet = true

func stop_room_clear_magnet() -> void:
	_magnet_radius_multiplier = 1.0
	_magnet_speed_multiplier = 1.0
	_force_room_clear_magnet = false

func is_inside_collection_radius(player: Node2D, multiplier: float = 1.0) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return global_position.distance_to(player.global_position) <= BASE_MAGNET_RADIUS_PX * max(1.0, multiplier)

func _process(delta: float) -> void:
	_update_essence_visual(delta)
	if _collected:
		return
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()
	if _target == null:
		return
	var radius: float = BASE_MAGNET_RADIUS_PX * _magnet_radius_multiplier
	var distance: float = global_position.distance_to(_target.global_position)
	if _force_room_clear_magnet or distance <= radius:
		var speed: float = BASE_MAGNET_SPEED_PX * _magnet_speed_multiplier
		global_position = global_position.move_toward(_target.global_position, speed * delta)
		if global_position.distance_to(_target.global_position) <= DIRECT_COLLECT_DISTANCE_PX:
			_collect()

func _on_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_collect()

func _collect() -> void:
	if _collected:
		return
	_collected = true
	EssenceBank.add_essence(creature_type_id, faction_id, amount)
	_heal_player_from_essence()
	queue_free()

func _heal_player_from_essence() -> void:
	var player: Node = _target
	if player == null or not is_instance_valid(player):
		player = _find_player()
	if player != null and is_instance_valid(player) and player.has_method("heal_from_essence"):
		player.call("heal_from_essence", float(amount) * HEAL_PER_ESSENCE)

func _find_player() -> Node2D:
	var players: Array = get_tree().get_nodes_in_group("player")
	return players[0] as Node2D if not players.is_empty() else null

func _setup_essence_sprite() -> void:
	var sequence: Array = ShadowCoreAssetPaths.essence_animation_paths(faction_id)
	if sequence.is_empty():
		var fallback_texture: String = ShadowCoreAssetPaths.essence_texture_path(faction_id)
		if not fallback_texture.is_empty():
			sequence = [fallback_texture]
	if sequence.is_empty():
		return
	if _sprite_visual == null or not is_instance_valid(_sprite_visual):
		_sprite_visual = SpriteSheetAnimator.new()
		_sprite_visual.name = "EssenceSprite"
		_sprite_visual.centered = true
		_sprite_visual.z_index = 3
		_sprite_visual.scale = Vector2.ONE * _base_visual_scale()
		add_child(_sprite_visual)
	else:
		_sprite_visual.clear_all()
	var loaded: bool = _sprite_visual.add_sequence_animation("idle", sequence, _essence_fps(), true)
	if loaded:
		_sprite_visual.play_if_available("idle")
		if visual != null:
			visual.visible = false
	else:
		_sprite_visual.queue_free()
		_sprite_visual = null

func _update_essence_visual(delta: float) -> void:
	if _sprite_visual == null or not is_instance_valid(_sprite_visual):
		return
	var t: float = Time.get_ticks_msec() / 210.0 + float(get_instance_id() % 100)
	_sprite_visual.position.y = sin(t) * 1.5
	_sprite_visual.scale = Vector2.ONE * (_base_visual_scale() + sin(t * 0.85) * 0.035)
	# Do not rotate the new flame/sting/magic_dart pickups: their orientation reads as faction identity.

func _base_visual_scale() -> float:
	match faction_id:
		"FACTION_KRUSHERS":
			return 0.72
		"FACTION_NATURE":
			return 0.68
		"FACTION_ETHERS":
			return 0.64
		_:
			return 0.70

func _essence_fps() -> float:
	match faction_id:
		"FACTION_ETHERS":
			return 12.0
		_:
			return 8.0

func _apply_faction_color() -> void:
	if visual == null:
		visual = get_node_or_null("Visual") as CanvasItem
	if visual == null:
		return
	match faction_id:
		"FACTION_KRUSHERS":
			visual.modulate = Color(1.0, 0.18, 0.12, 1.0)
		"FACTION_NATURE":
			visual.modulate = Color(0.16, 1.0, 0.38, 1.0)
		"FACTION_ETHERS":
			visual.modulate = Color(0.72, 0.30, 1.0, 1.0)
		_:
			visual.modulate = Color(0.45, 0.9, 0.75, 1.0)
