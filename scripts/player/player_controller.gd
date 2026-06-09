extends CharacterBody2D
class_name PlayerController

@onready var health_component: HealthComponent = $HealthComponent as HealthComponent
@onready var stats: PlayerStats = $PlayerStats as PlayerStats
@onready var auto_attack: PlayerAutoAttack = $PlayerAutoAttack as PlayerAutoAttack
@onready var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem

const MOVEMENT_RESPONSE_SECONDS: float = 0.20
const DODGE_DISTANCE_PX: float = 96.0 # 2 meters at 48 px/m
const DODGE_DURATION_SECONDS: float = 0.20
const DODGE_INVULNERABILITY_SECONDS: float = 0.40
const DODGE_MAX_CHARGES: int = 2
const DODGE_CHARGE_COOLDOWN_SECONDS: float = 10.0
const DODGE_GLOBAL_COOLDOWN_SECONDS: float = 2.0

var _virtual_movement: Vector2 = Vector2.ZERO
var _last_direction: Vector2 = Vector2.RIGHT
var _post_damage_invulnerability: float = 0.0
var _death_locked: bool = false
var _slows: Dictionary = {}
var _sprite_visual: SpriteSheetAnimator = null
var _visual_action_lock: float = 0.0

var _dodge_charges: int = DODGE_MAX_CHARGES
var _dodge_charge_timers: Array[float] = []
var _dodge_global_cooldown: float = 0.0
var _is_dodging: bool = false
var _dodge_timer: float = 0.0
var _dodge_direction: Vector2 = Vector2.RIGHT
var _dodge_speed_px: float = DODGE_DISTANCE_PX / DODGE_DURATION_SECONDS
var _saved_collision_mask: int = 0

func _ready() -> void:
	stats.configure_from_hero(RunManager.current_hero_id)
	health_component.configure(stats.max_hp)
	health_component.health_changed.connect(_on_health_changed)
	health_component.died.connect(_on_died)
	EventBus.movement_input_changed.connect(_on_movement_input_changed)
	if EventBus.has_signal("dodge_button_pressed"):
		EventBus.dodge_button_pressed.connect(_request_dodge)
	AbilityManager.register_player(self)
	add_to_group("player")
	_saved_collision_mask = collision_mask
	var dev: Node = get_node_or_null("/root/DeveloperTools")
	if dev != null:
		if dev.has_signal("developer_mode_changed") and not dev.is_connected("developer_mode_changed", Callable(self, "_on_developer_mode_changed")):
			dev.connect("developer_mode_changed", Callable(self, "_on_developer_mode_changed"))
		if dev.has_method("apply_to_player"):
			dev.call_deferred("apply_to_player", self)
	_setup_player_sprite()
	call_deferred("_emit_current_health")
	_emit_dodge_state()

func _emit_current_health() -> void:
	if health_component == null:
		return
	EventBus.player_health_changed.emit(health_component.current_health, health_component.max_health)

func _physics_process(delta: float) -> void:
	_update_slows(delta)
	_update_dodge_cooldowns(delta)
	_update_player_visual(delta)
	if _death_locked:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_post_damage_invulnerability = max(0.0, _post_damage_invulnerability - delta)
	if _update_dodge_motion(delta):
		return
	var input_direction: Vector2 = _get_raw_move_input_direction()
	if input_direction.length() > 0.05:
		_last_direction = input_direction.normalized()
	var speed_multiplier: float = _get_speed_multiplier()
	var target_velocity: Vector2 = input_direction.normalized() * stats.movement_speed_px * speed_multiplier if input_direction.length() > 0.05 else Vector2.ZERO
	var blend: float = 1.0 if MOVEMENT_RESPONSE_SECONDS <= 0.0 else clampf(delta / MOVEMENT_RESPONSE_SECONDS, 0.0, 1.0)
	velocity = velocity.lerp(target_velocity, blend)
	if target_velocity == Vector2.ZERO and velocity.length_squared() < 1.0:
		velocity = Vector2.ZERO
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if _death_locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				AbilityManager.request_cast("active_1")
			KEY_E:
				AbilityManager.request_cast("active_2")
			KEY_R:
				AbilityManager.request_cast("ultimate")
			KEY_SPACE:
				_request_dodge()
			KEY_ESCAPE:
				EventBus.request_pause_toggle.emit()

func _read_keyboard_movement() -> Vector2:
	var result: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		result.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		result.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		result.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		result.y += 1.0
	return result

func _get_raw_move_input_direction() -> Vector2:
	var input_direction: Vector2 = _read_keyboard_movement()
	if _virtual_movement.length() > 0.05:
		input_direction = _virtual_movement
	return input_direction

func _on_movement_input_changed(direction: Vector2) -> void:
	_virtual_movement = direction

func get_aim_direction() -> Vector2:
	return _last_direction

func get_current_move_direction() -> Vector2:
	var raw: Vector2 = _get_raw_move_input_direction()
	if raw.length_squared() > 0.001:
		return raw.normalized()
	if velocity.length_squared() > 4.0:
		return velocity.normalized()
	return _last_direction

func play_visual_action(action_name: String, lock_seconds: float = 0.22) -> void:
	if _sprite_visual == null or not is_instance_valid(_sprite_visual):
		return
	if _sprite_visual.play_if_available(action_name):
		_visual_action_lock = max(_visual_action_lock, lock_seconds)

func perform_dash(direction: Vector2, distance_px: float) -> void:
	# Legacy fallback retained for old data. New Patch R active_1 is a dagger, not movement.
	if _death_locked:
		return
	if direction.length() <= 0.01:
		direction = _last_direction
	global_position += direction.normalized() * distance_px
	_post_damage_invulnerability = max(_post_damage_invulnerability, 0.15)

func _request_dodge() -> void:
	if _death_locked or _is_dodging:
		return
	if _dodge_charges <= 0 or _dodge_global_cooldown > 0.0:
		return
	var direction: Vector2 = get_current_move_direction()
	if direction.length_squared() <= 0.001:
		direction = _last_direction
	_start_dodge(direction.normalized())

func _start_dodge(direction: Vector2) -> void:
	_dodge_charges = max(0, _dodge_charges - 1)
	_dodge_charge_timers.append(DODGE_CHARGE_COOLDOWN_SECONDS)
	_dodge_global_cooldown = DODGE_GLOBAL_COOLDOWN_SECONDS
	_is_dodging = true
	_dodge_timer = DODGE_DURATION_SECONDS
	_dodge_direction = direction.normalized()
	velocity = _dodge_direction * _dodge_speed_px
	_post_damage_invulnerability = max(_post_damage_invulnerability, DODGE_INVULNERABILITY_SECONDS)
	_saved_collision_mask = collision_mask
	collision_mask = 0
	play_visual_action("run", DODGE_DURATION_SECONDS)
	_emit_dodge_state()

func _update_dodge_motion(delta: float) -> bool:
	if not _is_dodging:
		return false
	_dodge_timer -= delta
	velocity = _dodge_direction * _dodge_speed_px
	move_and_slide()
	if _dodge_timer <= 0.0:
		_is_dodging = false
		collision_mask = _saved_collision_mask
		velocity *= 0.35
		_emit_dodge_state()
	return true

func _update_dodge_cooldowns(delta: float) -> void:
	var changed: bool = false
	_dodge_global_cooldown = max(0.0, _dodge_global_cooldown - delta)
	for i in range(_dodge_charge_timers.size() - 1, -1, -1):
		_dodge_charge_timers[i] = float(_dodge_charge_timers[i]) - delta
		if float(_dodge_charge_timers[i]) <= 0.0:
			_dodge_charge_timers.remove_at(i)
			_dodge_charges = min(DODGE_MAX_CHARGES, _dodge_charges + 1)
			changed = true
	if changed or _dodge_global_cooldown > 0.0 or not _dodge_charge_timers.is_empty():
		_emit_dodge_state()

func _emit_dodge_state() -> void:
	if not EventBus.has_signal("dodge_cooldown_changed"):
		return
	var next_remaining: float = 0.0
	if not _dodge_charge_timers.is_empty():
		next_remaining = max(0.0, float(_dodge_charge_timers[0]))
	EventBus.dodge_cooldown_changed.emit(_dodge_charges, DODGE_MAX_CHARGES, next_remaining, DODGE_CHARGE_COOLDOWN_SECONDS, _dodge_global_cooldown)

func apply_damage(payload: DamagePayload) -> void:
	if _death_locked or _post_damage_invulnerability > 0.0:
		return
	health_component.damage(payload.amount, payload)
	_post_damage_invulnerability = 0.45
	EventBus.player_damaged.emit(payload.amount)

func apply_slow_status(status_id: String, slow_percent: float, duration: float) -> void:
	_slows[status_id] = {"percent": max(0.0, slow_percent), "time": max(0.0, duration)}

func revive_with_health_ratio(ratio: float) -> void:
	_death_locked = false
	health_component.revive_with_ratio(ratio)
	_post_damage_invulnerability = 1.25
	global_position = Vector2.ZERO
	_reset_dodge_state()
	_emit_current_health()

func reset_for_new_run(hero_id: String = "HERO_KAEL") -> void:
	_death_locked = false
	_post_damage_invulnerability = 0.75
	_slows.clear()
	_virtual_movement = Vector2.ZERO
	_last_direction = Vector2.RIGHT
	velocity = Vector2.ZERO
	global_position = Vector2.ZERO
	_reset_dodge_state()
	if not hero_id.is_empty():
		RunManager.current_hero_id = hero_id
	stats.configure_from_hero(RunManager.current_hero_id)
	health_component.configure(stats.max_hp)
	if auto_attack != null:
		auto_attack.enabled = true
	AbilityManager.register_player(self)
	var dev: Node = get_node_or_null("/root/DeveloperTools")
	if dev != null and dev.has_method("apply_to_player"):
		dev.call("apply_to_player", self)
	_emit_current_health()

func _reset_dodge_state() -> void:
	_dodge_charges = DODGE_MAX_CHARGES
	_dodge_charge_timers.clear()
	_dodge_global_cooldown = 0.0
	_is_dodging = false
	_dodge_timer = 0.0
	collision_mask = _saved_collision_mask
	_emit_dodge_state()

func apply_stat_upgrade_runtime() -> void:
	if stats == null or health_component == null:
		return
	var old_max: float = health_component.max_health
	var old_current: float = health_component.current_health
	stats.configure_from_hero(RunManager.current_hero_id)
	var new_max: float = max(1.0, stats.max_hp)
	health_component.max_health = new_max
	var gained_max: float = max(0.0, new_max - old_max)
	health_component.current_health = clampf(old_current + gained_max, 1.0, new_max)
	if auto_attack != null and auto_attack.has_method("force_reconfigure"):
		auto_attack.call("force_reconfigure")
	EventBus.player_health_changed.emit(health_component.current_health, health_component.max_health)

func heal_from_essence(amount: float) -> void:
	if _death_locked or health_component == null:
		return
	health_component.heal(amount)

func _on_health_changed(current: float, maximum: float) -> void:
	EventBus.player_health_changed.emit(current, maximum)

func _on_died(_payload: DamagePayload) -> void:
	_death_locked = true
	var run_flow: Node = get_node_or_null("/root/RunFlow")
	if run_flow != null and run_flow.has_method("handle_player_death"):
		if bool(run_flow.call("handle_player_death", self)):
			return
	EventBus.run_finished.emit({"result": "defeat", "reason": "player_dead"})

func _update_slows(delta: float) -> void:
	var remove: Array = []
	for key in _slows.keys():
		_slows[key]["time"] = float(_slows[key].get("time", 0.0)) - delta
		if float(_slows[key]["time"]) <= 0.0:
			remove.append(key)
	for key in remove:
		_slows.erase(key)

func _get_speed_multiplier() -> float:
	var strongest: float = 0.0
	for key in _slows.keys():
		strongest = max(strongest, float(_slows[key].get("percent", 0.0)))
	return clampf(1.0 - strongest / 100.0, 0.30, 1.0)

func _setup_player_sprite() -> void:
	if _sprite_visual != null and is_instance_valid(_sprite_visual):
		return
	_sprite_visual = SpriteSheetAnimator.new()
	_sprite_visual.name = "SpriteVisual"
	_sprite_visual.position = Vector2(0, -10)
	# Hero should read as about 2x a normal mob. Collision remains unchanged.
	_sprite_visual.scale = Vector2.ONE * 2.0
	add_child(_sprite_visual)
	move_child(_sprite_visual, 0)
	var paths: Dictionary = ShadowCoreAssetPaths.player_animation_paths(RunManager.current_hero_id)
	var loaded: bool = false
	loaded = _sprite_visual.add_sheet_animation("idle", str(paths.get("idle", "")), 6.0, true) or loaded
	loaded = _sprite_visual.add_sheet_animation("walk", str(paths.get("walk", "")), 7.0, true) or loaded
	loaded = _sprite_visual.add_sheet_animation("run", str(paths.get("run", "")), 8.0, true) or loaded
	loaded = _sprite_visual.add_sheet_animation("attack", str(paths.get("attack", "")), 10.0, false) or loaded
	loaded = _sprite_visual.add_sheet_animation("hurt", str(paths.get("hurt", "")), 7.0, false) or loaded
	loaded = _sprite_visual.add_sheet_animation("death", str(paths.get("death", "")), 6.0, false) or loaded
	if loaded:
		if visual != null:
			visual.visible = false
		_sprite_visual.play_if_available("idle")
	else:
		_sprite_visual.queue_free()
		_sprite_visual = null

func _update_player_visual(delta: float) -> void:
	if _sprite_visual == null or not is_instance_valid(_sprite_visual):
		return
	if _last_direction.x < -0.05:
		_sprite_visual.flip_h = true
	elif _last_direction.x > 0.05:
		_sprite_visual.flip_h = false
	_visual_action_lock = max(0.0, _visual_action_lock - delta)
	if _visual_action_lock > 0.0:
		return
	if _death_locked:
		_sprite_visual.play_if_available("death")
	elif _is_dodging:
		_sprite_visual.play_if_available("run")
	elif velocity.length() > stats.movement_speed_px * 0.65:
		_sprite_visual.play_if_available("run")
	elif velocity.length() > 6.0:
		_sprite_visual.play_if_available("walk")
	else:
		_sprite_visual.play_if_available("idle")

func _on_developer_mode_changed(_enabled: bool) -> void:
	var dev: Node = get_node_or_null("/root/DeveloperTools")
	if dev != null and dev.has_method("apply_to_player"):
		dev.call("apply_to_player", self)
	_emit_current_health()
