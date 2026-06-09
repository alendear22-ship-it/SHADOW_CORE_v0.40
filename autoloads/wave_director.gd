extends Node

var _run_scene: Node = null
var _enemy_parent: Node = null
var _player: Node2D = null
var _room_data: Dictionary = {}
var _room_card: Dictionary = {}
var _wave_index: int = 0
var _time_until_next_wave: float = 0.0
var _running: bool = false
var _difficulty_multiplier: float = 1.0
var _room_started_msec: int = 0

func start_survival_room(run_scene: Node, enemy_parent: Node, player: Node2D, room_data: Dictionary, room_card: Dictionary) -> void:
	_run_scene = run_scene
	_enemy_parent = enemy_parent
	_player = player
	_room_data = room_data.duplicate(true)
	_room_card = room_card.duplicate(true)
	_wave_index = 0
	_time_until_next_wave = 0.25
	_running = true
	_difficulty_multiplier = max(0.25, float(room_card.get("difficulty", 1.0)))
	_room_started_msec = Time.get_ticks_msec()
	EventBus.run_resource_changed.emit()

func stop() -> void:
	_running = false

func _process(delta: float) -> void:
	if not _running:
		return
	_time_until_next_wave -= delta
	if _time_until_next_wave <= 0.0:
		_spawn_next_wave()
	if _wave_index >= _get_total_waves() and _enemy_parent != null and _enemy_parent.get_child_count() == 0:
		_complete_room()

func _spawn_next_wave() -> void:
	var budgets: Array = _room_card.get("spawn_budget_per_wave", _room_data.get("spawn_budget_per_wave", [5, 6, 7, 8]))
	if _wave_index >= budgets.size():
		_time_until_next_wave = 9999.0
		return
	SpawnDirector.spawn_wave(_enemy_parent, _player, _room_card, float(budgets[_wave_index]), _difficulty_multiplier)
	_wave_index += 1
	_time_until_next_wave = float(_room_data.get("wave_interval_seconds", 6.0))
	EventBus.run_resource_changed.emit()

func _complete_room() -> void:
	_running = false
	if bool(DataRegistry.get_rewards().get("mvp_upgrade_stipend", {}).get("enabled", false)):
		EssenceBank.debug_add_mvp_upgrade_stipend()
	EventBus.room_completed.emit({
		"room_id": _room_data.get("id", ""),
		"room_type": _room_data.get("type", "survival_waves"),
		"waves_cleared": _wave_index,
		"room_card": _room_card.duplicate(true),
		"duration_seconds": int((Time.get_ticks_msec() - _room_started_msec) / 1000),
		"mvp_stipend_applied": bool(DataRegistry.get_rewards().get("mvp_upgrade_stipend", {}).get("enabled", false))
	})

func _get_total_waves() -> int:
	var budgets: Array = _room_card.get("spawn_budget_per_wave", _room_data.get("spawn_budget_per_wave", [5, 6, 7, 8]))
	if not budgets.is_empty():
		return budgets.size()
	return int(_room_data.get("mvp_fixed_waves", 4))

func get_wave_index() -> int:
	return _wave_index

func is_running() -> bool:
	return _running

func get_status() -> Dictionary:
	var total_waves: int = _get_total_waves()
	var active_enemies: int = 0
	if _enemy_parent != null:
		active_enemies = _enemy_parent.get_child_count()
	return {
		"running": _running,
		"room_type": _room_data.get("type", "?"),
		"wave_index": _wave_index,
		"wave_total": total_waves,
		"remaining_seconds": max(0, int(ceil(_time_until_next_wave))),
		"active_enemies": active_enemies,
		"difficulty": _difficulty_multiplier
	}

func reset_run() -> void:
	# transient wave coordinator. No run-local reset required.
	pass

func get_state() -> Dictionary:
	return {"stateless": true, "note": "transient wave coordinator"}

func set_state(state: Variant = {}) -> void:
	# transient wave coordinator. Incoming state intentionally ignored.
	pass
