extends Node

func _get_configured_final_boss_id() -> String:
	if DataRegistry != null and DataRegistry.has_method("get_final_boss_id"):
		return str(DataRegistry.get_final_boss_id())
	return ""

func get_boss_cards_for_floor(floor_index: int) -> Array:
	var candidates: Array = []
	for boss in DataRegistry.get_items("bosses"):
		var boss_id: String = str(boss.get("id", ""))
		if RunManager.bosses_defeated.has(boss_id):
			continue
		if _boss_matches_floor_band(boss, floor_index):
			candidates.append(boss)
	if candidates.size() < 2:
		for boss in DataRegistry.get_items("bosses"):
			var boss_id: String = str(boss.get("id", ""))
			if not RunManager.bosses_defeated.has(boss_id) and not candidates.has(boss):
				candidates.append(boss)
	if candidates.is_empty():
		candidates = DataRegistry.get_items("bosses")
	candidates.shuffle()
	var result: Array = []
	for boss in candidates:
		result.append(_make_boss_card(boss, floor_index))
		if result.size() >= 2:
			break
	return result

func get_final_boss_cards() -> Array:
	var cards: Array = []
	for final_boss in DataRegistry.get_items("final_bosses"):
		var faction_names: Array[String] = []
		for faction_name in final_boss.get("factions", []):
			faction_names.append(str(faction_name))
		cards.append({
			"boss_id": str(final_boss.get("id", _get_configured_final_boss_id())),
			"final_boss_id": str(final_boss.get("id", _get_configured_final_boss_id())),
			"is_final_boss": true,
			"name": str(final_boss.get("name", "Финальный босс")),
			"faction_id": "FACTION_KRUSHERS/FACTION_ETHERS",
			"faction_name": " / ".join(faction_names) if not faction_names.is_empty() else "Финал",
			"difficulty": str(final_boss.get("difficulty", "Высокая")),
			"threat": str(final_boss.get("role", "финальная проверка билда")),
			"support_enemy_names": ["финальная арена", "фантомы", "разломы"],
			"ultimate_boss_ability": "Финальный бой",
			"reward_preview": "+1 Ядро эссенции, победа в забеге; не даёт силу в текущем run"
		})
	if cards.is_empty():
		var final_boss_id: String = _get_configured_final_boss_id()
		if final_boss_id.is_empty():
			push_error("BossController: run_config.final_boss.boss_id is missing; cannot build final boss card.")
			return []
		cards.append({
			"boss_id": final_boss_id,
			"final_boss_id": final_boss_id,
			"is_final_boss": true,
			"name": "Морграт Разломанный",
			"faction_name": "Крушители / Эфиры",
			"difficulty": "Высокая",
			"threat": "физический burst / фантомы / разломы",
			"support_enemy_names": ["финальная арена"],
			"reward_preview": "+1 Ядро эссенции, победа в забеге; не даёт силу в текущем run"
		})
	return cards

func get_final_boss_data(final_boss_id: String) -> Dictionary:
	var data: Dictionary = DataRegistry.get_by_id("final_bosses", final_boss_id).duplicate(true)
	if data.is_empty():
		data = {
			"id": final_boss_id,
			"name": "Морграт Разломанный",
			"difficulty": "Высокая",
			"faction_ids": ["FACTION_KRUSHERS", "FACTION_ETHERS"]
		}
	data["is_final_boss"] = true
	data["scene_path"] = str(data.get("scene_path", "res://scenes/bosses/boss_base.tscn"))
	data["faction_id"] = "FACTION_KRUSHERS"
	data["creature_type_id"] = "CREATURE_EF_VOID_SPIRIT"
	data["runtime_floor_scale"] = 1.0
	return data

func get_phase_thresholds_for_difficulty(difficulty: String) -> Array:
	if difficulty.contains("высок") or difficulty.contains("Высок"):
		return [0.75, 0.50, 0.20]
	if difficulty.contains("Средне-высок") or difficulty.contains("средне-высок"):
		return [0.70, 0.40, 0.18]
	return [0.66, 0.33]

func get_boss_max_health(difficulty: String, is_final_boss: bool = false) -> float:
	if is_final_boss:
		return 980.0
	if difficulty.contains("высок") or difficulty.contains("Высок"):
		return 620.0
	if difficulty.contains("Средне-высок") or difficulty.contains("средне-высок"):
		return 540.0
	return 430.0

func grant_floor_boss_rewards(boss_id: String, boss_number: int) -> Dictionary:
	var boss: Dictionary = DataRegistry.get_by_id("bosses", boss_id)
	if boss.is_empty():
		return {}
	var faction_id: String = boss.get("faction_id", "")
	var creature_type_id: String = boss.get("creature_type_id", "")
	var essence_reward: int = 8 + boss_number * 2
	EssenceBank.add_essence(creature_type_id, faction_id, essence_reward)
	var shards: int = _roll_floor_boss_shards(boss_number)
	if shards > 0:
		MetaProgression.add_shards(faction_id, shards)
	RunManager.mark_boss_defeated(boss_id)
	if boss_number == 2:
		RunManager.create_suspend_after_second_boss()
	EventBus.boss_defeated.emit(boss_id)
	return {"boss_id": boss_id, "essence": essence_reward, "soul_ash_on_decline": 5, "shards": shards}

func grant_final_boss_rewards(final_boss_id: String) -> Dictionary:
	# Compatibility wrapper. Main flow awards Ядро эссенции through MetaCurrencyManager in RunFlow.notify_final_boss_defeated().
	# Keep this method non-destructive: no current-run power and no old generic meta_currency grant.
	var manager: Node = get_node_or_null("/root/MetaCurrencyManager")
	if manager != null and manager.has_method("award_morgath_victory"):
		var result: Variant = manager.call("award_morgath_victory", {"final_boss_id": final_boss_id, "legacy_wrapper": true})
		if result is Dictionary:
			return result
	return {"final_boss_id": final_boss_id, "currency_id": "ESSENCE_CORE", "storage_key": "core_essence", "amount": 0, "legacy_wrapper": true}

func _make_boss_card(boss: Dictionary, floor_index: int) -> Dictionary:
	var boss_number: int = RunManager.current_boss_number + 1
	return {
		"boss_id": boss.get("id", ""),
		"name": boss.get("name", ""),
		"faction_id": boss.get("faction_id", ""),
		"faction_name": boss.get("faction_name", boss.get("faction", "")),
		"creature_type_id": boss.get("creature_type_id", ""),
		"difficulty": boss.get("difficulty", "Средняя"),
		"threat": boss.get("card", {}).get("threat", boss.get("role", "")),
		"support_enemy_names": _get_support_enemy_names(str(boss.get("faction_id", ""))),
		"ultimate_boss_ability": boss.get("card", {}).get("ultimate_boss_ability", ""),
		"boss_health_scale": 1.0 + max(0, floor_index - 1) * 0.16,
		"floor": floor_index,
		"boss_number": boss_number,
		"reward_preview": "%d эссенции, шанс осколков ядра; отказ от награды босса: +5 Пепла Душ" % [8 + boss_number * 2]
	}

func _boss_matches_floor_band(boss: Dictionary, floor_index: int) -> bool:
	var difficulty: String = str(boss.get("difficulty", ""))
	if floor_index <= 1:
		return difficulty == "Средняя"
	if floor_index == 2:
		return difficulty.contains("Средне-высок") or difficulty.contains("Средняя")
	return difficulty.contains("Высок")

func _roll_floor_boss_shards(boss_number: int) -> int:
	var roll: float = randf()
	if boss_number <= 1:
		if roll < 0.30:
			return 0
		if roll < 0.90:
			return 1
		return 2
	if boss_number == 2:
		if roll < 0.10:
			return 0
		if roll < 0.50:
			return 1
		return 2
	if roll < 0.10:
		return 1
	if roll < 0.60:
		return 2
	return 3

func _get_support_enemy_names(faction_id: String) -> Array[String]:
	var names: Array[String] = []
	for enemy in DataRegistry.get_items("enemies"):
		if enemy.get("faction_id", "") == faction_id and bool(enemy.get("is_fully_playable_in_mvp", false)):
			names.append(str(enemy.get("name", enemy.get("id", ""))))
		if names.size() >= 3:
			break
	return names

func reset_run() -> void:
	# compatibility boss data/controller helper. No run-local reset required.
	pass

func get_state() -> Dictionary:
	return {"stateless": true, "note": "compatibility boss data/controller helper"}

func set_state(state: Variant = {}) -> void:
	# compatibility boss data/controller helper. Incoming state intentionally ignored.
	pass
