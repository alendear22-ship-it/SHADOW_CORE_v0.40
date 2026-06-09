extends Node

var cores_by_faction: Dictionary = {}
var shards_by_faction: Dictionary = {}
var counters_by_faction: Dictionary = {}
var hero_levels: Dictionary = {}
var unlocked_auto_attacks: Dictionary = {}
var meta_currency: int = 0 # legacy generic meta currency; not used for direct stat growth.
var essence_core: int = 0 # Ядро эссенции; unlock currency only.
var bosses_defeated_ever: Array[String] = []
var boss_abilities_seen: Array[String] = []
var boss_abilities_unlocked_meta: Array[String] = []


func _ready() -> void:
	load_meta()


func _default_save() -> Dictionary:
	return {
		"cores_by_faction": {},
		"shards_by_faction": {},
		"counters_by_faction": {},
		"hero_levels": {"HERO_KAEL": 1},
		"unlocked_auto_attacks": {"HERO_KAEL": ["Теневая сечка"]},
		"meta_currency": 0,
		"essence_core": 0,
		"core_essence": 0,
		"bosses_defeated_ever": [],
		"boss_abilities_seen": [],
		"boss_abilities_unlocked_meta": []
	}


func load_meta() -> void:
	var data: Dictionary = SaveManager.load_meta_save()
	if data.is_empty():
		data = _default_save()
	cores_by_faction = data.get("cores_by_faction", {})
	shards_by_faction = data.get("shards_by_faction", {})
	counters_by_faction = data.get("counters_by_faction", {})
	hero_levels = data.get("hero_levels", {"HERO_KAEL": 1})
	unlocked_auto_attacks = data.get("unlocked_auto_attacks", {"HERO_KAEL": ["Теневая сечка"]})
	meta_currency = int(data.get("meta_currency", 0))
	essence_core = int(data.get("essence_core", data.get("core_essence", 0)))
	bosses_defeated_ever = _normalize_string_array(data.get("bosses_defeated_ever", data.get("defeated_boss_ids", [])))
	boss_abilities_seen = _normalize_string_array(data.get("boss_abilities_seen", []))
	boss_abilities_unlocked_meta = _normalize_string_array(data.get("boss_abilities_unlocked_meta", []))


func save_meta() -> void:
	SaveManager.save_meta_save({
		"cores_by_faction": cores_by_faction,
		"shards_by_faction": shards_by_faction,
		"counters_by_faction": counters_by_faction,
		"hero_levels": hero_levels,
		"unlocked_auto_attacks": unlocked_auto_attacks,
		"meta_currency": meta_currency,
		"essence_core": essence_core,
		"core_essence": essence_core,
		"bosses_defeated_ever": _copy_string_array(bosses_defeated_ever),
		"defeated_boss_ids": _copy_string_array(bosses_defeated_ever), # backwards-compatible read key only; not a new runtime source.
		"boss_abilities_seen": _copy_string_array(boss_abilities_seen),
		"boss_abilities_unlocked_meta": _copy_string_array(boss_abilities_unlocked_meta)
	})


func add_faction_counter(faction_id: String, amount: int) -> void:
	if faction_id.is_empty() or amount <= 0:
		return
	counters_by_faction[faction_id] = int(counters_by_faction.get(faction_id, 0)) + amount
	while int(counters_by_faction[faction_id]) >= 100:
		counters_by_faction[faction_id] = int(counters_by_faction[faction_id]) - 100
		add_core(faction_id, 1, false)
	save_meta()


func add_shards(faction_id: String, amount: int) -> void:
	if faction_id.is_empty() or amount <= 0:
		return
	shards_by_faction[faction_id] = int(shards_by_faction.get(faction_id, 0)) + amount
	while int(shards_by_faction[faction_id]) >= 10:
		shards_by_faction[faction_id] = int(shards_by_faction[faction_id]) - 10
		add_core(faction_id, 1, false)
	save_meta()


func add_core(faction_id: String, amount: int = 1, should_save: bool = true) -> void:
	if faction_id.is_empty() or amount <= 0:
		return
	cores_by_faction[faction_id] = int(cores_by_faction.get(faction_id, 0)) + amount
	if should_save:
		save_meta()


func add_meta_currency(amount: int) -> void:
	meta_currency += max(amount, 0)
	save_meta()


func get_hero_level(hero_id: String) -> int:
	return int(hero_levels.get(hero_id, 1))


func get_essence_core() -> int:
	return max(0, essence_core)


func set_essence_core(amount: int) -> void:
	essence_core = max(0, amount)
	save_meta()


func add_essence_core(amount: int, _reason: String = "") -> int:
	var safe_amount: int = max(0, amount)
	if safe_amount <= 0:
		return 0
	essence_core += safe_amount
	save_meta()
	return safe_amount


func spend_essence_core(amount: int, _reason: String = "") -> bool:
	var safe_amount: int = max(0, amount)
	if safe_amount <= 0:
		return true
	if essence_core < safe_amount:
		return false
	essence_core -= safe_amount
	save_meta()
	return true


func mark_boss_defeated_ever(boss_id: String, should_save: bool = true) -> bool:
	var clean_id: String = str(boss_id).strip_edges()
	if clean_id.is_empty():
		return false
	if bosses_defeated_ever.has(clean_id):
		return false
	bosses_defeated_ever.append(clean_id)
	if should_save:
		save_meta()
	return true


func add_boss_defeated_ever(boss_id: String) -> bool:
	return mark_boss_defeated_ever(boss_id)


func has_defeated_boss_ever(boss_id: String) -> bool:
	return bosses_defeated_ever.has(str(boss_id))


func get_defeated_boss_ids() -> Array[String]:
	return _copy_string_array(bosses_defeated_ever)


func get_bosses_defeated_ever() -> Array[String]:
	return get_defeated_boss_ids()


func mark_boss_ability_seen(boss_ability_id: String, should_save: bool = true) -> bool:
	var clean_id: String = str(boss_ability_id).strip_edges()
	if clean_id.is_empty():
		return false
	if boss_abilities_seen.has(clean_id):
		return false
	boss_abilities_seen.append(clean_id)
	if should_save:
		save_meta()
	return true


func get_boss_abilities_seen() -> Array[String]:
	return _copy_string_array(boss_abilities_seen)


func mark_boss_ability_unlocked_meta(boss_ability_id: String, should_save: bool = true) -> bool:
	var clean_id: String = str(boss_ability_id).strip_edges()
	if clean_id.is_empty():
		return false
	if boss_abilities_unlocked_meta.has(clean_id):
		return false
	boss_abilities_unlocked_meta.append(clean_id)
	if should_save:
		save_meta()
	return true


func get_boss_abilities_unlocked_meta() -> Array[String]:
	return _copy_string_array(boss_abilities_unlocked_meta)


func is_boss_ability_unlocked_meta(boss_ability_id: String) -> bool:
	return boss_abilities_unlocked_meta.has(str(boss_ability_id))



func reset_run() -> void:
	# Meta progression is persistent by design. reset_run() is intentionally a no-op.
	# Run-only state must be reset by RunManager and run managers, not by MetaProgression.
	pass


func get_state() -> Dictionary:
	return {
		"cores_by_faction": cores_by_faction.duplicate(true),
		"shards_by_faction": shards_by_faction.duplicate(true),
		"counters_by_faction": counters_by_faction.duplicate(true),
		"hero_levels": hero_levels.duplicate(true),
		"unlocked_auto_attacks": unlocked_auto_attacks.duplicate(true),
		"meta_currency": meta_currency,
		"essence_core": essence_core,
		"core_essence": essence_core,
		"bosses_defeated_ever": _copy_string_array(bosses_defeated_ever),
		"boss_abilities_seen": _copy_string_array(boss_abilities_seen),
		"boss_abilities_unlocked_meta": _copy_string_array(boss_abilities_unlocked_meta)
	}


func set_state(state: Variant) -> void:
	if not (state is Dictionary):
		return
	var data: Dictionary = state
	cores_by_faction = data.get("cores_by_faction", {}) if data.get("cores_by_faction", {}) is Dictionary else {}
	shards_by_faction = data.get("shards_by_faction", {}) if data.get("shards_by_faction", {}) is Dictionary else {}
	counters_by_faction = data.get("counters_by_faction", {}) if data.get("counters_by_faction", {}) is Dictionary else {}
	hero_levels = data.get("hero_levels", {"HERO_KAEL": 1}) if data.get("hero_levels", {}) is Dictionary else {"HERO_KAEL": 1}
	unlocked_auto_attacks = data.get("unlocked_auto_attacks", {"HERO_KAEL": ["Теневая сечка"]}) if data.get("unlocked_auto_attacks", {}) is Dictionary else {"HERO_KAEL": ["Теневая сечка"]}
	meta_currency = int(data.get("meta_currency", 0))
	essence_core = int(data.get("essence_core", data.get("core_essence", 0)))
	bosses_defeated_ever = _normalize_string_array(data.get("bosses_defeated_ever", data.get("defeated_boss_ids", [])))
	boss_abilities_seen = _normalize_string_array(data.get("boss_abilities_seen", []))
	boss_abilities_unlocked_meta = _normalize_string_array(data.get("boss_abilities_unlocked_meta", []))
	save_meta()


func _normalize_string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for value in raw:
			var clean_value: String = str(value).strip_edges()
			if not clean_value.is_empty() and not result.has(clean_value):
				result.append(clean_value)
	return result


func _copy_string_array(source: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in source:
		var clean_value: String = str(value).strip_edges()
		if not clean_value.is_empty() and not result.has(clean_value):
			result.append(clean_value)
	return result
