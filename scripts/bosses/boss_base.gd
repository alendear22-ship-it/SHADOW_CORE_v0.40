extends CharacterBody2D
class_name BossBase

const BOSS_ABILITY_TELEGRAPH_SECONDS: float = 0.7
const DRAW_EFFECT_SCRIPT: String = "res://scripts/effects/simple_draw_effect.gd"
const BOSS_COOLDOWN_MULTIPLIER: float = 1.30
const BOSS_POST_CAST_LOCK_SECONDS: float = 0.65
const LEAD_CAST_DISTANCE_PX: float = 24.0

@export var boss_id: String = "BOSS_KR_B_BRUKK"
@export var is_final_boss: bool = false
@onready var health_component: HealthComponent = $HealthComponent as HealthComponent
@onready var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem

var data: Dictionary = {}
var phase: int = 1
var _player: Node2D = null
var _attack_timer: float = 1.5
var _phase_thresholds: Array = []
var _triggered_thresholds: Array = []
var _reward_already_granted: bool = false
var _runtime_health_scale: float = 1.0
var _move_speed: float = 120.0
var _attack_damage: float = 18.0
var _attack_range: float = 120.0
var _attack_interval: float = 1.8
var _boss_ability_previews: Array = []
var _boss_hud_emit_accum: float = 0.0
var _attack_windup_timer: float = 0.0
var _pending_attack_position: Vector2 = Vector2.ZERO
var _sprite_visual: SpriteSheetAnimator = null
var _visual_action_lock: float = 0.0
var _boss_next_ability_index: int = 0
var _pending_boss_ability: String = "area"
var _pending_attack_direction: Vector2 = Vector2.RIGHT
var _post_cast_lock_timer: float = 0.0

func _ready() -> void:
	add_to_group("bosses")
	add_to_group("enemies")
	health_component.died.connect(_on_died)
	if not health_component.health_changed.is_connected(_on_health_changed):
		health_component.health_changed.connect(_on_health_changed)
	if data.is_empty():
		setup(DataRegistry.get_by_id("bosses", boss_id))

func setup(boss_data: Dictionary) -> void:
	data = boss_data.duplicate(true)
	boss_id = str(data.get("id", boss_id))
	is_final_boss = bool(data.get("is_final_boss", is_final_boss))
	_reward_already_granted = false
	var difficulty: String = str(data.get("difficulty", "Средняя"))
	_runtime_health_scale = max(0.5, float(data.get("runtime_floor_scale", 1.0)))
	_phase_thresholds = BossController.get_phase_thresholds_for_difficulty(difficulty)
	_triggered_thresholds.clear()
	phase = 1
	var max_health: float = BossController.get_boss_max_health(difficulty, is_final_boss) * _runtime_health_scale
	health_component.configure(max_health)
	_configure_runtime_numbers(difficulty)
	_build_boss_ability_previews()
	_apply_visual_from_data()
	_emit_boss_hud_state()

func _physics_process(delta: float) -> void:
	_attack_timer -= delta
	_post_cast_lock_timer = max(0.0, _post_cast_lock_timer - delta)
	_update_sprite_visual(delta)
	_boss_hud_emit_accum += delta
	if _boss_hud_emit_accum >= 0.10:
		_boss_hud_emit_accum = 0.0
		_emit_boss_hud_state()
	_player = _get_player()
	if _player == null:
		return
	if _update_attack_windup(delta):
		move_and_slide()
		_update_phase()
		return
	var to_player: Vector2 = _player.global_position - global_position
	if to_player.length() > _attack_range:
		velocity = to_player.normalized() * _move_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		move_and_slide()
		if _attack_timer <= 0.0 and _post_cast_lock_timer <= 0.0:
			_begin_attack_windup()
	_update_phase()

func apply_damage(payload: DamagePayload) -> void:
	health_component.damage(payload.amount, payload)
	_emit_boss_hud_state()

func _update_phase() -> void:
	if health_component.max_health <= 0.0:
		return
	var ratio: float = health_component.current_health / health_component.max_health
	var reached_count: int = 0
	for threshold in _phase_thresholds:
		var threshold_value: float = float(threshold)
		if ratio <= threshold_value:
			reached_count += 1
			var key: int = int(round(threshold_value * 1000.0))
			if not _triggered_thresholds.has(key):
				_triggered_thresholds.append(key)
				_attack_interval = max(0.85, _attack_interval - 0.12)
				_move_speed += 8.0
				EventBus.boss_phase_reached.emit(boss_id, reached_count, threshold_value, global_position)
	phase = max(1, reached_count + 1)


func _begin_attack_windup() -> void:
	_attack_timer = _attack_interval
	_attack_windup_timer = BOSS_ABILITY_TELEGRAPH_SECONDS
	_pending_boss_ability = _select_next_boss_ability()
	_pending_attack_direction = (_player.global_position - global_position).normalized() if _player != null and is_instance_valid(_player) else Vector2.RIGHT
	match _pending_boss_ability:
		"line":
			_pending_attack_position = global_position
		"nova":
			_pending_attack_position = global_position
		_:
			_pending_attack_position = _predict_player_position(LEAD_CAST_DISTANCE_PX)
	velocity = Vector2.ZERO
	# Keep boss sprite stable: boss abilities are communicated through telegraph/VFX, not attack sheet frames.
	_spawn_boss_telegraph()

func _update_attack_windup(delta: float) -> bool:
	if _attack_windup_timer <= 0.0:
		return false
	velocity = Vector2.ZERO
	_attack_windup_timer -= delta
	if _attack_windup_timer <= 0.0:
		_execute_boss_attack()
		_post_cast_lock_timer = BOSS_POST_CAST_LOCK_SECONDS
	return true

func _execute_boss_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dir: Vector2 = _pending_attack_direction.normalized() if _pending_attack_direction.length_squared() > 0.001 else (_player.global_position - global_position).normalized()
	_spawn_attack_feedback(dir)
	var hits_player: bool = false
	match _pending_boss_ability:
		"line":
			hits_player = _distance_to_segment(_player.global_position, global_position, global_position + dir * (_attack_range * 1.65)) <= 34.0
		"nova":
			hits_player = _player.global_position.distance_to(global_position) <= _attack_range * 1.10
		_:
			hits_player = _player.global_position.distance_to(_pending_attack_position) <= _attack_range
	if not hits_player:
		return
	var damage_multiplier: float = 1.18 if _pending_boss_ability == "nova" else 1.0
	var damage_type: String = "physical" if _pending_boss_ability == "line" else "magical"
	var payload: DamagePayload = CombatSystem.build_payload(_attack_damage * damage_multiplier, damage_type, boss_id, str(data.get("faction_id", "")), "", DamagePayload.SOURCE_BOSS_AI_ABILITY_DAMAGE)
	payload.can_trigger_secondary_effects = false
	payload.can_trigger_boss_abilities = false
	payload.can_trigger_reactions = false
	payload.can_apply_reaction_prerequisites = false
	payload.normalize_source_type()
	CombatSystem.apply_damage(_player, payload)

func _spawn_boss_telegraph() -> void:
	var script: Script = load(DRAW_EFFECT_SCRIPT) as Script
	if script == null:
		return
	var effect: Node2D = script.new() as Node2D
	if effect == null:
		return
	var current: Node = get_tree().current_scene
	if current == null:
		return
	current.add_child(effect)
	var color: Color = Color(0.95, 0.25, 0.85, 0.78) if is_final_boss else Color(1.0, 0.42, 0.22, 0.72)
	match _pending_boss_ability:
		"line":
			effect.global_position = global_position
			if effect.has_method("setup"):
				effect.call("setup", "telegraph_line", 34.0, _pending_attack_direction, _attack_range * 1.65, color, BOSS_ABILITY_TELEGRAPH_SECONDS, 0.0)
		"nova":
			effect.global_position = global_position
			if effect.has_method("setup"):
				effect.call("setup", "telegraph_circle", _attack_range * 1.10, Vector2.RIGHT, _attack_range, color, BOSS_ABILITY_TELEGRAPH_SECONDS, TAU)
		_:
			effect.global_position = _pending_attack_position
			if effect.has_method("setup"):
				effect.call("setup", "telegraph_circle", _attack_range, Vector2.RIGHT, _attack_range, color, BOSS_ABILITY_TELEGRAPH_SECONDS, TAU)

func _configure_runtime_numbers(difficulty: String) -> void:
	_move_speed = 135.0 if is_final_boss else 118.0
	_attack_damage = 26.0 if is_final_boss else 18.0
	_attack_range = 136.0 if is_final_boss else 118.0
	_attack_interval = (1.48 if is_final_boss else 1.80) * BOSS_COOLDOWN_MULTIPLIER
	if difficulty.contains("Высок") or difficulty.contains("высок"):
		_move_speed += 12.0
		_attack_damage += 5.0
		_attack_interval -= 0.12
	elif difficulty.contains("Средне-высок") or difficulty.contains("средне-высок"):
		_move_speed += 6.0
		_attack_damage += 3.0
	_attack_damage *= max(0.75, _runtime_health_scale)

func _apply_visual_from_data() -> void:
	_setup_sprite_visual()
	if visual == null and _sprite_visual == null:
		return
	var faction_id: String = str(data.get("faction_id", ""))
	if is_final_boss:
		_set_visual_tint(Color(0.72, 0.18, 0.90, 1.0))
		_apply_boss_visual_scale()
		return
	match faction_id:
		"FACTION_KRUSHERS":
			_set_visual_tint(Color(0.92, 0.75, 0.65, 1.0))
		"FACTION_NATURE":
			_set_visual_tint(Color(0.82, 1.0, 0.86, 1.0))
		"FACTION_ETHERS":
			_set_visual_tint(Color(0.82, 0.74, 1.0, 1.0))
		_:
			_set_visual_tint(Color(1.0, 1.0, 1.0, 1.0))
	_apply_boss_visual_scale()

func _setup_sprite_visual() -> void:
	if _sprite_visual != null and is_instance_valid(_sprite_visual):
		return
	_sprite_visual = SpriteSheetAnimator.new()
	_sprite_visual.name = "SpriteVisual"
	_sprite_visual.position = Vector2(0, -14)
	_sprite_visual.scale = Vector2.ONE
	add_child(_sprite_visual)
	move_child(_sprite_visual, 0)
	var boss_visual_enemy_id: String = ShadowCoreAssetPaths.boss_visual_enemy_id(boss_id, str(data.get("creature_type_id", "")), str(data.get("faction_id", "")), is_final_boss)
	var paths: Dictionary = ShadowCoreAssetPaths.enemy_animation_paths(boss_visual_enemy_id)
	var loaded: bool = false
	loaded = _add_boss_anim("idle", paths, boss_visual_enemy_id, 3.8, true) or loaded
	loaded = _add_boss_anim("walk", paths, boss_visual_enemy_id, 4.0, true) or loaded
	loaded = _add_boss_anim("run", paths, boss_visual_enemy_id, 4.0, true) or loaded
	loaded = _add_boss_anim("hurt", paths, boss_visual_enemy_id, 4.0, false) or loaded
	loaded = _add_boss_anim("death", paths, boss_visual_enemy_id, 4.0, false) or loaded
	if loaded:
		if visual != null:
			visual.visible = false
		_sprite_visual.play_if_available("idle")
	else:
		_sprite_visual.queue_free()
		_sprite_visual = null


func _add_boss_anim(anim_name: String, paths: Dictionary, visual_enemy_id: String, fps: float, loop: bool) -> bool:
	if _sprite_visual == null or not is_instance_valid(_sprite_visual):
		return false
	var grid: Vector2i = ShadowCoreAssetPaths.enemy_animation_grid(visual_enemy_id, anim_name)
	return _sprite_visual.add_sheet_animation(anim_name, str(paths.get(anim_name, "")), fps, loop, grid.x, grid.y, 0)

func _apply_boss_visual_scale() -> void:
	# Patch S: all bosses use ordinary mob sprites, only scaled up to 5x visually.
	scale = Vector2.ONE
	var visual_scale: float = 5.0
	if _sprite_visual != null and is_instance_valid(_sprite_visual):
		_sprite_visual.scale = Vector2.ONE * visual_scale
	if visual != null:
		visual.scale = Vector2.ONE * visual_scale

func _set_visual_tint(tint: Color) -> void:
	if visual != null:
		visual.modulate = tint
	if _sprite_visual != null and is_instance_valid(_sprite_visual):
		_sprite_visual.modulate = tint

func _play_sprite_action(anim_name: String, lock_seconds: float = 0.30) -> void:
	if _sprite_visual == null or not is_instance_valid(_sprite_visual):
		return
	if _sprite_visual.play_if_available(anim_name):
		_visual_action_lock = max(_visual_action_lock, lock_seconds)

func _update_sprite_visual(delta: float) -> void:
	if _sprite_visual == null or not is_instance_valid(_sprite_visual):
		return
	if _player != null and is_instance_valid(_player):
		var dx: float = _player.global_position.x - global_position.x
		if dx < -2.0:
			_sprite_visual.flip_h = true
		elif dx > 2.0:
			_sprite_visual.flip_h = false
	_visual_action_lock = max(0.0, _visual_action_lock - delta)
	if _visual_action_lock > 0.0:
		return
	if velocity.length() > 8.0:
		_sprite_visual.play_if_available("walk")
	else:
		_sprite_visual.play_if_available("idle")

func _spawn_sequence_effect(effect_id: String, origin: Vector2, duration: float, scale_value: float, rotation_value: float = 0.0, tint: Color = Color.WHITE) -> void:
	var script: Script = load("res://scripts/visuals/sequence_sprite_effect.gd") as Script
	if script == null:
		return
	var effect: Node2D = script.new() as Node2D
	if effect == null:
		return
	var current: Node = get_tree().current_scene
	if current == null:
		effect.queue_free()
		return
	current.add_child(effect)
	effect.global_position = origin
	if effect.has_method("setup_from_paths"):
		var ok: bool = bool(effect.call("setup_from_paths", ShadowCoreAssetPaths.effect_sequence(effect_id), duration, scale_value, rotation_value, tint, Vector2.ZERO, 65))
		if not ok:
			effect.queue_free()

func _boss_effect_id() -> String:
	if is_final_boss:
		return "void"
	match str(data.get("faction_id", "")):
		"FACTION_KRUSHERS":
			return "enemy_slash"
		"FACTION_NATURE":
			return "water"
		"FACTION_ETHERS":
			return "void"
		_:
			return "impact_purple"

func _spawn_attack_feedback(direction: Vector2) -> void:
	var script: Script = load(DRAW_EFFECT_SCRIPT) as Script
	if script == null:
		return
	var effect: Node2D = script.new() as Node2D
	if effect == null:
		return
	var current: Node = get_tree().current_scene
	if current == null:
		return
	current.add_child(effect)
	effect.global_position = global_position
	if effect.has_method("setup"):
		effect.call("setup", "impact", 84.0 if is_final_boss else 58.0, direction, _attack_range, Color(0.95, 0.25, 0.85, 0.80) if is_final_boss else Color(1.0, 0.40, 0.22, 0.80), 0.25, TAU)
	_spawn_sequence_effect(_boss_effect_id(), global_position + direction.normalized() * 38.0, 0.34, 1.0 if not is_final_boss else 1.35, direction.angle(), Color(1.0, 0.82, 1.0, 0.96))

func _select_next_boss_ability() -> String:
	var cycle: Array[String] = ["area", "line", "nova"]
	var result: String = cycle[_boss_next_ability_index % cycle.size()]
	_boss_next_ability_index += 1
	return result

func _predict_player_position(lead_distance_px: float) -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return global_position
	var predicted: Vector2 = _player.global_position
	var move_dir: Vector2 = Vector2.ZERO
	if _player.has_method("get_current_move_direction"):
		move_dir = _player.call("get_current_move_direction")
	elif _player is CharacterBody2D:
		var body: CharacterBody2D = _player as CharacterBody2D
		move_dir = body.velocity.normalized() if body.velocity.length_squared() > 1.0 else Vector2.ZERO
	if move_dir.length_squared() > 0.001:
		predicted += move_dir.normalized() * max(0.0, lead_distance_px)
	return predicted

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var denom: float = ab.length_squared()
	if denom <= 0.001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)

func _on_health_changed(current: float, maximum: float) -> void:
	EventBus.boss_health_changed.emit(boss_id, str(data.get("name", boss_id)), current, maximum, is_final_boss)

func _emit_boss_hud_state() -> void:
	if health_component == null:
		return
	EventBus.boss_health_changed.emit(boss_id, str(data.get("name", boss_id)), health_component.current_health, health_component.max_health, is_final_boss)
	EventBus.boss_ability_cooldowns_changed.emit(boss_id, _get_boss_ability_cooldown_payload())

func _build_boss_ability_previews() -> void:
	_boss_ability_previews.clear()
	var phase_data: Dictionary = data.get("phase_1", {})
	var attacks: Array = phase_data.get("attacks", [])
	for attack in attacks:
		if not (attack is Dictionary):
			continue
		var attack_dict: Dictionary = attack
		_boss_ability_previews.append({
			"name": str(attack_dict.get("name", "Атака")),
			"telegraph": float(attack_dict.get("telegraph_seconds", BOSS_ABILITY_TELEGRAPH_SECONDS)),
			"shape": str(attack_dict.get("shape", attack_dict.get("effect", "")))
		})
		if _boss_ability_previews.size() >= 3:
			break
	if _boss_ability_previews.is_empty():
		_boss_ability_previews.append({"name": "Разлом", "telegraph": BOSS_ABILITY_TELEGRAPH_SECONDS, "shape": "область с упреждением"})
		_boss_ability_previews.append({"name": "Сечение", "telegraph": BOSS_ABILITY_TELEGRAPH_SECONDS, "shape": "линия"})
		_boss_ability_previews.append({"name": "Нова", "telegraph": BOSS_ABILITY_TELEGRAPH_SECONDS, "shape": "круг вокруг босса"})

func _get_boss_ability_cooldown_payload() -> Array:
	var result: Array = []
	var base_duration: float = max(0.1, _attack_interval)
	for i in range(_boss_ability_previews.size()):
		var entry: Dictionary = _boss_ability_previews[i]
		var stagger: float = float(i) * 0.35
		var remaining: float = clampf(_attack_timer + stagger, 0.0, base_duration + stagger)
		result.append({
			"index": i,
			"icon": str(i + 1),
			"name": str(entry.get("name", "Атака")),
			"shape": str(entry.get("shape", "")),
			"remaining": remaining,
			"duration": base_duration + stagger,
			"telegraph": float(entry.get("telegraph", BOSS_ABILITY_TELEGRAPH_SECONDS))
		})
	return result

func _on_died(_payload: DamagePayload) -> void:
	EventBus.boss_hud_hidden.emit()
	if _reward_already_granted:
		return
	_reward_already_granted = true
	if is_final_boss:
		var run_flow: Node = get_node_or_null("/root/RunFlow")
		if run_flow != null and run_flow.has_method("notify_final_boss_defeated"):
			run_flow.call("notify_final_boss_defeated", boss_id)
		else:
			EventBus.run_finished.emit({"result": "victory", "reason": "final_boss_defeated"})
	else:
		BossController.grant_floor_boss_rewards(boss_id, max(1, RunManager.current_boss_number + 1))
	queue_free()

func _get_player() -> Node2D:
	var players: Array = get_tree().get_nodes_in_group("player")
	return players[0] as Node2D if not players.is_empty() else null
