extends Node

signal enemy_died(enemy_id: String, faction_id: String, creature_type_id: String, essence_amount: int)
signal enemy_died_with_position(enemy_id: String, faction_id: String, creature_type_id: String, essence_amount: int, position: Vector2)
signal essence_collected(creature_type_id: String, faction_id: String, amount: int)
signal player_damaged(amount: float)
signal room_completed(room_result: Dictionary)
signal upgrade_selected(upgrade_data: Dictionary)
signal boss_defeated(boss_id: String)
signal boss_phase_reached(boss_id: String, phase_index: int, threshold_ratio: float, position: Vector2)
signal boss_health_changed(boss_id: String, boss_name: String, current: float, maximum: float, is_final_boss: bool)
signal boss_ability_cooldowns_changed(boss_id: String, abilities: Array)
signal boss_hud_hidden()
signal run_finished(result: Dictionary)

signal reaction_triggered_event(reaction_data: Dictionary)
signal reaction_visual_requested(reaction_data: Dictionary)
signal reaction_blocked_event(reaction_data: Dictionary)
signal route_choice_requested(route_context: Dictionary)
signal boss_choice_requested(route_context: Dictionary)

signal movement_input_changed(direction: Vector2)
signal ability_button_pressed(slot: String)
signal ability_targeting_started(slot: String, direction: Vector2, cancel_radius_px: float)
signal ability_targeting_changed(slot: String, direction: Vector2, canceled: bool)
signal ability_targeting_finished(slot: String, direction: Vector2, canceled: bool)
signal dodge_button_pressed()
signal dodge_cooldown_changed(charges: int, max_charges: int, next_charge_remaining: float, next_charge_duration: float, global_cooldown_remaining: float)
signal ability_cooldown_changed(slot: String, remaining: float, duration: float)
signal player_health_changed(current: float, maximum: float)
signal run_resource_changed()
signal run_debug_changed(debug_data: Dictionary)
signal request_pause_toggle()

func reset_run() -> void:
	# signal bus; no persistent state. No run-local reset required.
	pass

func get_state() -> Dictionary:
	return {"stateless": true, "note": "signal bus; no persistent state"}

func set_state(state: Variant = {}) -> void:
	# signal bus; no persistent state. Incoming state intentionally ignored.
	pass
