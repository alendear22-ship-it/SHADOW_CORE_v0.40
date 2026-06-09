extends Node

signal developer_mode_changed(enabled: bool)

const DEV_MAX_HEALTH: float = 10000.0

var enabled: bool = false
var _last_normal_max_health: float = 0.0

func toggle() -> bool:
	set_enabled(not enabled)
	return enabled

func set_enabled(value: bool) -> void:
	if enabled == value:
		_apply_to_current_player()
		developer_mode_changed.emit(enabled)
		return
	enabled = value
	_apply_to_current_player()
	developer_mode_changed.emit(enabled)
	EventBus.run_resource_changed.emit()

func apply_to_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	var health_component: HealthComponent = player.get("health_component") as HealthComponent
	if health_component == null:
		return
	if enabled:
		if _last_normal_max_health <= 0.0 or health_component.max_health < DEV_MAX_HEALTH * 0.5:
			_last_normal_max_health = health_component.max_health
		health_component.configure(DEV_MAX_HEALTH)
	else:
		var target_max: float = _last_normal_max_health
		if target_max <= 0.0 and player.get("stats") != null:
			var stats = player.get("stats")
			target_max = float(stats.get("max_hp"))
		if target_max <= 0.0:
			target_max = 100.0
		health_component.configure(target_max)

func _apply_to_current_player() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var players: Array = tree.get_nodes_in_group("player")
	if players.is_empty():
		return
	apply_to_player(players[0])

func is_zero_cooldown_enabled() -> bool:
	return enabled

func run_command(command_line: String) -> bool:
	# DEV/DEBUG command hook. Not exposed to player UI.
	if not OS.is_debug_build() and not Engine.is_editor_hint():
		return false
	var parts: PackedStringArray = command_line.strip_edges().split(" ", false)
	if parts.is_empty():
		return false
	match parts[0]:
		"weak_stage":
			if parts.size() < 2:
				return false
			var creature_type_id: String = str(parts[1])
			if parts.size() >= 3:
				var count: int = max(0, int(parts[2]))
				if MobWeakAbilitySystem != null and MobWeakAbilitySystem.has_method("debug_force_defeat_count"):
					MobWeakAbilitySystem.debug_force_defeat_count(creature_type_id, count)
			if MobWeakAbilitySystem != null and MobWeakAbilitySystem.has_method("debug_print_weak_stage"):
				MobWeakAbilitySystem.debug_print_weak_stage(creature_type_id)
			return true
		_:
			return false

func reset_run() -> void:
	# developer settings service; no run-local state. No run-local reset required.
	pass

func get_state() -> Dictionary:
	return {"stateless": true, "note": "developer settings service; no run-local state"}

func set_state(state: Variant = {}) -> void:
	# developer settings service; no run-local state. Incoming state intentionally ignored.
	pass
