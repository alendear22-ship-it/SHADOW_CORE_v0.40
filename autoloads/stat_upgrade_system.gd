extends Node

# StatUpgradeSystem remains as internal altar-card stat effect handler, not as legacy stat shop.

signal stat_upgrade_changed(upgrade_id: String, level: int)

const MAX_LEVEL: int = 5
const COSTS: Array[int] = [5, 10, 15, 25, 40]
const ATTACK_VALUES: Array[float] = [5.0, 7.0, 10.0, 14.0, 20.0]
const AUTO_ATTACK_RANGE_VALUES: Array[float] = [5.0, 8.0, 12.0, 16.0, 20.0]
const ABILITY_RANGE_VALUES: Array[float] = [1.0, 3.0, 5.0, 7.0, 10.0]
const HP_VALUES: Array[float] = [10.0, 20.0, 40.0, 60.0, 100.0]
const SPEED_VALUES: Array[float] = [2.0, 4.0, 6.0, 9.0, 12.0]

var levels: Dictionary = {
	"attack": 0,
	"range": 0,
	"max_hp": 0,
	"move_speed": 0
}
var _last_error: String = ""
var _revision: int = 0

func reset_run() -> void:
	levels = {"attack": 0, "range": 0, "max_hp": 0, "move_speed": 0}
	_last_error = ""
	_revision += 1
	EventBus.run_resource_changed.emit()

func get_state() -> Dictionary:
	return levels.duplicate(true)

func set_state(data: Dictionary) -> void:
	for key in levels.keys():
		levels[key] = clampi(int(data.get(key, 0)), 0, MAX_LEVEL)
	_revision += 1
	EventBus.run_resource_changed.emit()

func get_revision() -> int:
	return _revision

func get_last_error() -> String:
	return _last_error

func get_level(upgrade_id: String) -> int:
	return int(levels.get(upgrade_id, 0))

func get_upgrade_ids() -> Array[String]:
	return ["attack", "range", "max_hp", "move_speed"]

func get_preview(upgrade_id: String, source_creature_type_id: String, faction_id: String) -> Dictionary:
	var level: int = get_level(upgrade_id)
	var next_level: int = level + 1
	var maxed: bool = level >= MAX_LEVEL
	var cost: int = 0 if maxed else COSTS[next_level - 1]
	var available: int = _available_within_faction(faction_id)
	return {
		"id": upgrade_id,
		"name": get_display_name(upgrade_id),
		"level": level,
		"next_level": min(next_level, MAX_LEVEL),
		"max_level": MAX_LEVEL,
		"maxed": maxed,
		"cost": cost,
		"available": available,
		"can_afford": (not maxed) and EssenceBank.can_spend_within_faction(source_creature_type_id, faction_id, cost),
		"value_text": _value_text(upgrade_id, next_level),
		"description": get_description(upgrade_id)
	}

func try_upgrade(upgrade_id: String, source_creature_type_id: String, faction_id: String) -> bool:
	_last_error = "Direct stat purchase is disabled. Stat upgrades are granted only by Altar cards."
	push_warning(_last_error)
	return false
	if not levels.has(upgrade_id):
		_last_error = "Неизвестная прокачка: " + upgrade_id
		return false
	var level: int = get_level(upgrade_id)
	if level >= MAX_LEVEL:
		_last_error = "Эта характеристика уже достигла максимального уровня."
		return false
	var cost: int = COSTS[level]
	if not EssenceBank.can_spend_within_faction(source_creature_type_id, faction_id, cost):
		_last_error = "Не хватает выбранного ресурса: нужно %d, доступно %d." % [cost, _available_within_faction(faction_id)]
		return false
	if not EssenceBank.spend_within_faction(source_creature_type_id, faction_id, cost):
		_last_error = "Не удалось списать выбранный ресурс."
		return false
	levels[upgrade_id] = level + 1
	_revision += 1
	_apply_to_active_player()
	stat_upgrade_changed.emit(upgrade_id, level + 1)
	EventBus.run_resource_changed.emit()
	return true

func grant_free_upgrade(upgrade_id: String, reason: String = "altar_card") -> bool:
	_last_error = ""
	if not levels.has(upgrade_id):
		_last_error = "Неизвестная прокачка: " + upgrade_id
		return false
	var level: int = get_level(upgrade_id)
	if level >= MAX_LEVEL:
		_last_error = "Эта характеристика уже достигла максимального уровня."
		return false
	levels[upgrade_id] = level + 1
	_revision += 1
	_apply_to_active_player()
	stat_upgrade_changed.emit(upgrade_id, level + 1)
	EventBus.run_resource_changed.emit()
	return true

func get_display_name(upgrade_id: String) -> String:
	match upgrade_id:
		"attack":
			return "Усиление атаки"
		"range":
			return "Дальность атаки"
		"max_hp":
			return "Максимальное здоровье"
		"move_speed":
			return "Скорость передвижения"
		_:
			return upgrade_id

func get_description(upgrade_id: String) -> String:
	match upgrade_id:
		"attack":
			return "Увеличивает урон автоатаки и активных способностей."
		"range":
			return "Увеличивает дальность автоатаки сильнее, а радиус/дальность активных способностей — осторожнее."
		"max_hp":
			return "Увеличивает максимальное здоровье героя. При применении текущее здоровье растёт на величину прироста."
		"move_speed":
			return "Увеличивает скорость перемещения героя."
		_:
			return ""

func get_attack_multiplier() -> float:
	return 1.0 + _sum_percent(ATTACK_VALUES, get_level("attack")) / 100.0

func get_auto_attack_range_multiplier() -> float:
	return 1.0 + _sum_percent(AUTO_ATTACK_RANGE_VALUES, get_level("range")) / 100.0

func get_ability_range_multiplier() -> float:
	return 1.0 + _sum_percent(ABILITY_RANGE_VALUES, get_level("range")) / 100.0

# Backward-compatible fallback for older callers. Active abilities should use get_ability_range_multiplier();
# auto-attack should use get_auto_attack_range_multiplier().
func get_range_multiplier() -> float:
	return get_ability_range_multiplier()

func get_move_speed_multiplier() -> float:
	return 1.0 + _sum_percent(SPEED_VALUES, get_level("move_speed")) / 100.0

func get_max_hp_bonus() -> float:
	return _sum_percent(HP_VALUES, get_level("max_hp"))

func _sum_percent(values: Array[float], level: int) -> float:
	var total: float = 0.0
	for i in range(clampi(level, 0, values.size())):
		total += float(values[i])
	return total

func _value_text(upgrade_id: String, level: int) -> String:
	if level < 1 or level > MAX_LEVEL:
		return "макс."
	match upgrade_id:
		"attack":
			return "+%d%% урона" % int(ATTACK_VALUES[level - 1])
		"range":
			return "+%d%% авто / +%d%% способн." % [int(AUTO_ATTACK_RANGE_VALUES[level - 1]), int(ABILITY_RANGE_VALUES[level - 1])]
		"max_hp":
			return "+%d здоровья" % int(HP_VALUES[level - 1])
		"move_speed":
			return "+%d%% скорости" % int(SPEED_VALUES[level - 1])
		_:
			return ""

func _available_within_faction(faction_id: String) -> int:
	var total: int = 0
	for creature_type_id in DataRegistry.get_creature_type_ids_for_faction(faction_id):
		total += EssenceBank.get_amount(creature_type_id)
	return total

func _apply_to_active_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	for player in players:
		if player != null and is_instance_valid(player) and player.has_method("apply_stat_upgrade_runtime"):
			player.call("apply_stat_upgrade_runtime")
