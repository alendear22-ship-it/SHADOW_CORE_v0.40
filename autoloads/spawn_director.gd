extends Node

const DEFAULT_ENEMY_SCENE: String = "res://scenes/enemies/enemy_base.tscn"

func build_room_cards(floor_index: int, room_in_floor: int, count: int = 2) -> Array:
	var playable: Array = _get_playable_enemies_for_floor(floor_index)
	if playable.size() < 3:
		playable = _get_all_playable_enemies()
	if playable.size() < 3:
		return [DataRegistry.get_room("ROOM_SURVIVAL_WAVES_MVP").get("default_card", {})]
	playable.shuffle()
	var cards: Array = []
	for i in range(count):
		var primary: Dictionary = playable[i % playable.size()]
		var secondary: Dictionary = playable[(i + 1) % playable.size()]
		var hidden: Dictionary = playable[(i + 2) % playable.size()]
		cards.append(_build_room_card(primary, secondary, hidden, floor_index, room_in_floor, i, false))
	return cards

func build_final_preparation_card() -> Dictionary:
	var enemies: Array = _get_all_playable_enemies()
	if enemies.size() < 3:
		enemies = DataRegistry.get_items("enemies")
	enemies.shuffle()
	var primary: Dictionary = _find_enemy(enemies, "ENEMY_KR_ORC_COMMANDER", 0)
	var secondary: Dictionary = _find_enemy(enemies, "ENEMY_PR_POISON_SLIME", 1)
	var hidden: Dictionary = _find_enemy(enemies, "ENEMY_EF_VOID_SPIRIT", 2)
	return _build_room_card(primary, secondary, hidden, RunManager.current_floor_index, 1, 0, true)

func spawn_wave(enemy_parent: Node, player: Node2D, room_card: Dictionary, budget: float, difficulty_multiplier: float = 1.0) -> void:
	if enemy_parent == null or player == null:
		return
	var remaining_budget: float = budget * max(0.25, difficulty_multiplier)
	var guard: int = 0
	while remaining_budget > 0.0 and guard < 96:
		guard += 1
		var enemy_id: String = _choose_enemy_id(room_card)
		var enemy_data: Dictionary = DataRegistry.get_enemy(enemy_id)
		if enemy_data.is_empty():
			continue
		var weight: float = max(0.5, float(enemy_data.get("threat_weight", 1.0)))
		if weight > remaining_budget and remaining_budget < 1.0:
			break
		_spawn_enemy(enemy_parent, player, enemy_data, difficulty_multiplier)
		remaining_budget -= weight

func spawn_boss(enemy_parent: Node, player: Node2D, boss_data: Dictionary) -> Node2D:
	if enemy_parent == null:
		return null
	var scene_path: String = str(boss_data.get("scene_path", "res://scenes/bosses/test_floor_boss.tscn"))
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		push_error("SpawnDirector: cannot load boss scene: " + scene_path)
		return null
	var boss: Node2D = scene.instantiate() as Node2D
	if boss == null:
		return null
	var base_pos: Vector2 = Vector2(420.0, 0.0)
	if player != null:
		base_pos = player.global_position + Vector2(420.0, 0.0)
	boss.global_position = base_pos
	enemy_parent.add_child(boss)
	if boss.has_method("setup"):
		boss.setup(boss_data)
	return boss

func clear_combatants(enemy_parent: Node) -> void:
	if enemy_parent == null:
		return
	for child in enemy_parent.get_children():
		child.queue_free()

func _build_room_card(primary: Dictionary, secondary: Dictionary, hidden: Dictionary, floor_index: int, room_in_floor: int, variant_index: int, final_prep: bool) -> Dictionary:
	var primary_creature: Dictionary = DataRegistry.get_creature_type(str(primary.get("creature_type_id", "")))
	var secondary_creature: Dictionary = DataRegistry.get_creature_type(str(secondary.get("creature_type_id", "")))
	var base_difficulty: float = 1.0 + float(max(0, floor_index - 1)) * 0.28 + float(max(0, room_in_floor - 1)) * 0.16 + float(variant_index) * 0.06
	var difficulty_label: String = "Средняя"
	if base_difficulty >= 1.55:
		difficulty_label = "Высокая"
	elif base_difficulty >= 1.25:
		difficulty_label = "Средне-высокая"
	if final_prep:
		base_difficulty = 1.78
		difficulty_label = "Финальная подготовка"
	return {
		"room_type": "survival_waves",
		"room_type_name": "Последняя подготовка" if final_prep else "Волны выживания",
		"is_final_preparation": final_prep,
		"floor": floor_index,
		"room_in_floor": room_in_floor,
		"primary_enemy_id": primary.get("id", ""),
		"primary_enemy_name": primary.get("name", "?"),
		"primary_creature_type_id": primary.get("creature_type_id", ""),
		"secondary_enemy_id": secondary.get("id", ""),
		"secondary_enemy_name": secondary.get("name", "?"),
		"secondary_creature_type_id": secondary.get("creature_type_id", ""),
		"hidden_enemy_id": hidden.get("id", ""),
		"hidden_enemy_name": hidden.get("name", "?"),
		"difficulty": base_difficulty,
		"difficulty_label": difficulty_label,
		"spawn_budget_per_wave": [8, 10, 12, 14, 16] if final_prep else [5, 6, 7, 8],
		"reward_preview": _build_reward_preview(primary_creature, secondary_creature, primary, secondary, final_prep)
	}

func _build_reward_preview(primary_creature: Dictionary, secondary_creature: Dictionary, primary: Dictionary, secondary: Dictionary, final_prep: bool) -> String:
	if final_prep:
		return "много эссенции перед финальным боссом, шанс добрать билд"
	return "Ресурс: %s / %s. Билд: %s" % [
		primary_creature.get("name", primary.get("name", "?")),
		secondary_creature.get("name", secondary.get("name", "?")),
		_build_boss_ability_preview(primary.get("creature_type_id", ""), secondary.get("creature_type_id", ""))
	]

func _build_boss_ability_preview(primary_creature_id: String, secondary_creature_id: String) -> String:
	var names: Array[String] = []
	for ability_data in DataRegistry.get_items("boss_abilities"):
		var creature_type_id: String = str(ability_data.get("creature_type_id", ""))
		if creature_type_id == primary_creature_id or creature_type_id == secondary_creature_id:
			names.append(str(ability_data.get("name_ru", ability_data.get("id", ""))))
		if names.size() >= 3:
			break
	if names.is_empty():
		return "фракционная эссенция"
	return ", ".join(names)

func _choose_enemy_id(room_card: Dictionary) -> String:
	var roll: float = randf()
	if roll < 0.60:
		return room_card.get("primary_enemy_id", "ENEMY_KR_ORC_FIGHTER")
	if roll < 0.90:
		return room_card.get("secondary_enemy_id", "ENEMY_PR_WATER_SLIME")
	return room_card.get("hidden_enemy_id", "ENEMY_EF_AIR_SPIRIT")

func _spawn_enemy(enemy_parent: Node, player: Node2D, enemy_data: Dictionary, difficulty_multiplier: float = 1.0) -> void:
	var scene_path: String = enemy_data.get("scene_path", DEFAULT_ENEMY_SCENE)
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		scene = load(DEFAULT_ENEMY_SCENE) as PackedScene
	if scene == null:
		push_error("SpawnDirector: cannot load enemy scene")
		return
	var enemy: Node2D = scene.instantiate() as Node2D
	if enemy == null:
		return
	enemy.global_position = _get_spawn_position_around(player.global_position)
	enemy_parent.add_child(enemy)
	var runtime_data: Dictionary = enemy_data.duplicate(true)
	runtime_data["runtime_difficulty_multiplier"] = difficulty_multiplier
	if enemy.has_method("setup"):
		enemy.setup(runtime_data)

func _get_playable_enemies_for_floor(floor_index: int) -> Array:
	var ids: Array[String] = []
	if floor_index <= 1:
		ids = ["ENEMY_KR_ORC_FIGHTER", "ENEMY_PR_WATER_SLIME", "ENEMY_EF_AIR_SPIRIT"]
	elif floor_index == 2:
		ids = ["ENEMY_KR_ORC_FIGHTER", "ENEMY_KR_ORC_WARRIOR", "ENEMY_PR_FIRE_SLIME", "ENEMY_PR_WATER_SLIME", "ENEMY_EF_LIGHTNING_SPIRIT", "ENEMY_EF_AIR_SPIRIT"]
	else:
		ids = ["ENEMY_KR_ORC_WARRIOR", "ENEMY_KR_ORC_COMMANDER", "ENEMY_PR_POISON_SLIME", "ENEMY_PR_FIRE_SLIME", "ENEMY_EF_VOID_SPIRIT", "ENEMY_EF_LIGHTNING_SPIRIT"]
	var result: Array = []
	for enemy_id in ids:
		var enemy: Dictionary = DataRegistry.get_enemy(enemy_id)
		if not enemy.is_empty():
			result.append(enemy)
	return result

func _get_all_playable_enemies() -> Array:
	var result: Array = []
	for enemy in DataRegistry.get_items("enemies"):
		if bool(enemy.get("is_fully_playable_in_mvp", false)):
			result.append(enemy)
	return result

func _find_enemy(enemies: Array, enemy_id: String, fallback_index: int) -> Dictionary:
	for enemy in enemies:
		if str(enemy.get("id", "")) == enemy_id:
			return enemy
	if enemies.is_empty():
		return {}
	return enemies[min(fallback_index, enemies.size() - 1)]

func _get_spawn_position_around(center: Vector2) -> Vector2:
	var angle: float = randf() * TAU
	var distance: float = randf_range(420.0, 640.0)
	return center + Vector2(cos(angle), sin(angle)) * distance

func reset_run() -> void:
	# transient spawn coordinator. No run-local reset required.
	pass

func get_state() -> Dictionary:
	return {"stateless": true, "note": "transient spawn coordinator"}

func set_state(state: Variant = {}) -> void:
	# transient spawn coordinator. Incoming state intentionally ignored.
	pass
