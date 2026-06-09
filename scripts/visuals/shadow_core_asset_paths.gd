extends Node
class_name ShadowCoreAssetPaths

static func player_animation_paths(hero_id: String = "HERO_KAEL") -> Dictionary:
	var base: String = "res://assets/sprites/player/heroes/swordsman-1-3-level-man/Swordsman_lvl1/Without_shadow/"
	return {
		"idle": base + "Swordsman_lvl1_Idle_without_shadow.png",
		"walk": base + "Swordsman_lvl1_Walk_without_shadow.png",
		"run": base + "Swordsman_lvl1_Run_without_shadow.png",
		"attack": base + "Swordsman_lvl1_attack_without_shadow.png",
		"hurt": base + "Swordsman_lvl1_Hurt_without_shadow.png",
		"death": base + "Swordsman_lvl1_Death_without_shadow.png"
	}

static func enemy_animation_paths(enemy_id: String) -> Dictionary:
	var base: String = _enemy_base_path(enemy_id)
	var prefix: String = _enemy_file_prefix(enemy_id)
	if base.is_empty() or prefix.is_empty():
		return {}
	return {
		"idle": base + prefix + _enemy_anim_name(enemy_id, "idle") + "_without_shadow.png",
		"walk": base + prefix + _enemy_anim_name(enemy_id, "walk") + "_without_shadow.png",
		"run": base + prefix + _enemy_anim_name(enemy_id, "run") + "_without_shadow.png",
		"attack": base + prefix + _enemy_anim_name(enemy_id, "attack") + "_without_shadow.png",
		"hurt": base + prefix + _enemy_anim_name(enemy_id, "hurt") + "_without_shadow.png",
		"death": base + prefix + _enemy_anim_name(enemy_id, "death") + "_without_shadow.png"
	}


static func enemy_animation_grid(enemy_id: String, anim: String) -> Vector2i:
	# Confirmed orc sheet layouts from the current asset pack. Other enemy families keep
	# the existing 8x4 layout that worked best visually in the previous patch.
	if enemy_id.begins_with("ENEMY_KR_ORC"):
		match anim:
			"attack":
				return Vector2i(8, 4)
			"death":
				return Vector2i(6, 4)
			"hurt":
				return Vector2i(6, 4)
			"idle":
				return Vector2i(4, 4)
			"run":
				return Vector2i(8, 4)
			"walk":
				return Vector2i(6, 4)
			_:
				return Vector2i(4, 4)
	return Vector2i(8, 4)

static func boss_visual_enemy_id(boss_id: String, creature_type_id: String, faction_id: String = "", is_final_boss: bool = false) -> String:
	if is_final_boss:
		return "ENEMY_KR_ORC_COMMANDER"
	match boss_id:
		"BOSS_KR_B_BRUKK":
			return "ENEMY_KR_ORC_FIGHTER"
		"BOSS_KR_V_GARR":
			return "ENEMY_KR_ORC_WARRIOR"
		"BOSS_KR_K_VARGAT":
			return "ENEMY_KR_ORC_COMMANDER"
		"BOSS_PR_V_MORR":
			return "ENEMY_PR_WATER_SLIME"
		"BOSS_PR_O_IGNIS":
			return "ENEMY_PR_FIRE_SLIME"
		"BOSS_PR_YA_NOX":
			return "ENEMY_PR_POISON_SLIME"
		"BOSS_EF_V_AERTAL":
			return "ENEMY_EF_AIR_SPIRIT"
		"BOSS_EF_M_VOLTREX":
			return "ENEMY_EF_LIGHTNING_SPIRIT"
		"BOSS_EF_P_KAIRNULL":
			return "ENEMY_EF_VOID_SPIRIT"
		_:
			pass
	match creature_type_id:
		"CREATURE_KR_ORC_FIGHTER":
			return "ENEMY_KR_ORC_FIGHTER"
		"CREATURE_KR_ORC_WARRIOR":
			return "ENEMY_KR_ORC_WARRIOR"
		"CREATURE_KR_ORC_COMMANDER":
			return "ENEMY_KR_ORC_COMMANDER"
		"CREATURE_PR_WATER_SLIME":
			return "ENEMY_PR_WATER_SLIME"
		"CREATURE_PR_FIRE_SLIME":
			return "ENEMY_PR_FIRE_SLIME"
		"CREATURE_PR_POISON_SLIME":
			return "ENEMY_PR_POISON_SLIME"
		"CREATURE_EF_AIR_SPIRIT":
			return "ENEMY_EF_AIR_SPIRIT"
		"CREATURE_EF_LIGHTNING_SPIRIT":
			return "ENEMY_EF_LIGHTNING_SPIRIT"
		"CREATURE_EF_VOID_SPIRIT":
			return "ENEMY_EF_VOID_SPIRIT"
		_:
			pass
	match faction_id:
		"FACTION_KRUSHERS":
			return "ENEMY_KR_ORC_COMMANDER"
		"FACTION_NATURE":
			return "ENEMY_PR_WATER_SLIME"
		"FACTION_ETHERS":
			return "ENEMY_EF_VOID_SPIRIT"
		_:
			return "ENEMY_KR_ORC_COMMANDER"

static func boss_animation_paths(boss_id: String, creature_type_id: String, is_final_boss: bool) -> Dictionary:
	return enemy_animation_paths(boss_visual_enemy_id(boss_id, creature_type_id, "", is_final_boss))

static func essence_animation_paths(faction_id: String) -> Array:
	# Primary path requested for the new pickup models. Fallback keeps compatibility with
	# the older smal_effect location that exists in the previous project structure JSON.
	match faction_id:
		"FACTION_KRUSHERS":
			return _first_existing_sequence([
				_number_sequence("res://assets/sprites/ui/essence/", "flame_", 0, 2, 0, ".png"),
				_number_sequence("res://assets/sprites/projectiles/smal_effect/", "flame_", 0, 2, 0, ".png")
			])
		"FACTION_NATURE":
			return _first_existing_sequence([
				_number_sequence("res://assets/sprites/ui/essence/", "sting_", 0, 2, 0, ".png"),
				_number_sequence("res://assets/sprites/projectiles/smal_effect/", "sting_", 0, 2, 0, ".png")
			])
		"FACTION_ETHERS":
			return _first_existing_sequence([
				_number_sequence("res://assets/sprites/ui/essence/", "magic_dart_", 0, 5, 0, ".png"),
				_number_sequence("res://assets/sprites/projectiles/smal_effect/", "magic_dart_", 0, 5, 0, ".png")
			])
		_:
			return []

static func essence_texture_path(faction_id: String) -> String:
	# Static fallback only. Runtime pickups prefer essence_animation_paths().
	var sequence: Array = essence_animation_paths(faction_id)
	if not sequence.is_empty():
		return str(sequence[0])
	match faction_id:
		"FACTION_KRUSHERS":
			return "res://assets/sprites/ui/Objects-tileset/objects-crystals/Assets/Red_crystal1.png"
		"FACTION_NATURE":
			return "res://assets/sprites/ui/Objects-tileset/objects-crystals/Assets/Green_crystal1.png"
		"FACTION_ETHERS":
			return "res://assets/sprites/ui/Objects-tileset/objects-crystals/Assets/Violet_crystal1.png"
		_:
			return "res://assets/sprites/ui/Objects-tileset/objects-crystals/Assets/Blue_crystal1.png"

static func ability_icon_path(slot_or_ability_id: String) -> String:
	match slot_or_ability_id:
		"auto_attack", "ABILITY_KAEL_AUTO":
			return "res://assets/sprites/ui/icons-spell/painterly-spell-icons-4/slice-spirit-1.png"
		"active_1", "ABILITY_KAEL_ACTIVE_1":
			return "res://assets/sprites/ui/icons-spell/painterly-spell-icons-4/needles-royal-1.png"
		"active_2", "ABILITY_KAEL_ACTIVE_2":
			return "res://assets/sprites/ui/icons-spell/painterly-spell-icons-4/rip-magenta-1.png"
		"ultimate", "ABILITY_KAEL_ULTIMATE":
			return "res://assets/sprites/ui/icons-spell/painterly-spell-icons-3/runes-magenta-1.png"
		"passive", "ABILITY_KAEL_PASSIVE":
			return "res://assets/sprites/ui/icons-spell/painterly-spell-icons-1/evil-eye-eerie-1.png"
		"stat_attack":
			return "res://assets/sprites/ui/icons-spell/painterly-spell-icons-4/slice-orange-1.png"
		"stat_health", "stat_max_hp":
			return "res://assets/sprites/ui/icons-spell/painterly-spell-icons-1/heal-jade-1.png"
		"stat_range":
			return "res://assets/sprites/ui/icons-spell/painterly-spell-icons-2/beam-orange-1.png"
		"stat_speed", "stat_move_speed":
			return "res://assets/sprites/ui/icons-spell/painterly-spell-icons-2/haste-sky-1.png"
		_:
			return ""

static func effect_sequence(effect_id: String) -> Array:
	match effect_id:
		"auto_slash":
			return _number_sequence("res://assets/sprites/slash-sprite-cartoon-effects/4/", "", 1, 8, 0, ".png")
		"dagger":
			return _number_sequence("res://assets/sprites/projectiles/smal_effect/", "arrow_", 0, 7, 0, ".png")
		"scythe_slash":
			return _number_sequence("res://assets/sprites/slash_effects/slash9/png/", "slash9_", 1, 9, 5, ".png")
		"enemy_slash":
			return _number_sequence("res://assets/sprites/slash_effects/slash/png/", "skash_", 1, 12, 5, ".png")
		"night_core":
			return _number_sequence("res://assets/sprites/projectiles/Arcane_Effect/06/", "Arcane_Effect_", 1, 7, 0, ".png")
		"impact_purple":
			return _number_sequence("res://assets/sprites/animated-explosion-sprite/Explosion_9/", "Explosion_", 1, 10, 0, ".png")
		"water":
			# Patch S: use a low, flat cold-cloud sequence instead of the tall blue smoke/splash sprite.
			return [
				"res://assets/sprites/projectiles/smal_effect/cloud_cold_0.png",
				"res://assets/sprites/projectiles/smal_effect/cloud_cold_1.png",
				"res://assets/sprites/projectiles/smal_effect/cloud_cold_2.png"
			]
		"lightning":
			# Use small zap frames instead of the large lightning sprite sheets, which render as a whole strip.
			return _number_sequence("res://assets/sprites/projectiles/smal_effect/", "zap_", 0, 2, 0, ".png")
		"wind":
			return [
				"res://assets/sprites/projectiles/smal_effect/tornado_1.png",
				"res://assets/sprites/projectiles/smal_effect/tornado_2.png"
			]
		"void":
			return _number_sequence("res://assets/sprites/projectiles/smal_effect/", "umbra_", 0, 3, 0, ".png")
		"fire":
			return _number_sequence("res://assets/sprites/projectiles/smal_effect/", "cloud_fire_", 0, 2, 0, ".png")
		"poison":
			return [
				"res://assets/sprites/projectiles/smal_effect/cloud_poison_0.png",
				"res://assets/sprites/projectiles/smal_effect/cloud_poison_1.png",
				"res://assets/sprites/projectiles/smal_effect/cloud_poison_2.png"
			]
		_:
			return []


static func _enemy_base_path(enemy_id: String) -> String:
	match enemy_id:
		"ENEMY_KR_ORC_FIGHTER":
			return "res://assets/sprites/enemies/mob/mobs-orc/Orc1/Without_shadow/"
		"ENEMY_KR_ORC_WARRIOR":
			return "res://assets/sprites/enemies/mob/mobs-orc/Orc2/Without_shadow/"
		"ENEMY_KR_ORC_COMMANDER":
			return "res://assets/sprites/enemies/mob/mobs-orc/Orc3/Without_shadow/"
		"ENEMY_PR_WATER_SLIME":
			return "res://assets/sprites/enemies/mob/mobs-slime/Slime1/Without_shadow/"
		"ENEMY_PR_FIRE_SLIME":
			# Patch U: fire/poison slime visuals swapped by request.
			return "res://assets/sprites/enemies/mob/mobs-slime/Slime3/Without_shadow/"
		"ENEMY_PR_POISON_SLIME":
			return "res://assets/sprites/enemies/mob/mobs-slime/Slime2/Without_shadow/"
		"ENEMY_EF_AIR_SPIRIT":
			return "res://assets/sprites/enemies/mob/mobs-vampires/Vampires1/Without_shadow/"
		"ENEMY_EF_LIGHTNING_SPIRIT":
			return "res://assets/sprites/enemies/mob/mobs-vampires/Vampires2/Without_shadow/"
		"ENEMY_EF_VOID_SPIRIT":
			return "res://assets/sprites/enemies/mob/mobs-vampires/Vampires3/Without_shadow/"
		_:
			return ""

static func _enemy_file_prefix(enemy_id: String) -> String:
	match enemy_id:
		"ENEMY_KR_ORC_FIGHTER":
			return "orc1_"
		"ENEMY_KR_ORC_WARRIOR":
			return "orc2_"
		"ENEMY_KR_ORC_COMMANDER":
			return "orc3_"
		"ENEMY_PR_WATER_SLIME":
			return "Slime1_"
		"ENEMY_PR_FIRE_SLIME":
			return "Slime3_"
		"ENEMY_PR_POISON_SLIME":
			return "Slime2_"
		"ENEMY_EF_AIR_SPIRIT":
			return "Vampires1_"
		"ENEMY_EF_LIGHTNING_SPIRIT":
			return "Vampires2_"
		"ENEMY_EF_VOID_SPIRIT":
			return "Vampires3_"
		_:
			return ""

static func _enemy_anim_name(enemy_id: String, anim: String) -> String:
	var is_orc: bool = enemy_id.begins_with("ENEMY_KR_ORC")
	match anim:
		"idle":
			return "idle" if is_orc else "Idle"
		"walk":
			return "walk" if is_orc else "Walk"
		"run":
			return "run" if is_orc else "Run"
		"attack":
			return "attack" if is_orc else "Attack"
		"hurt":
			return "hurt" if is_orc else "Hurt"
		"death":
			return "death" if is_orc else "Death"
		_:
			return anim

static func _first_existing_sequence(candidates: Array) -> Array:
	for candidate in candidates:
		if not (candidate is Array):
			continue
		var sequence: Array = candidate
		if sequence.is_empty():
			continue
		var any_exists: bool = false
		for path_value in sequence:
			if ResourceLoader.exists(str(path_value)):
				any_exists = true
				break
		if any_exists:
			return sequence
	if not candidates.is_empty() and (candidates[0] is Array):
		return candidates[0]
	return []

static func _number_sequence(base_path: String, prefix: String, first: int, last: int, pad: int, suffix: String) -> Array:
	var result: Array = []
	for i in range(first, last + 1):
		var number_text: String = str(i)
		if pad > 0:
			number_text = number_text.lpad(pad, "0")
		result.append(base_path + prefix + number_text + suffix)
	return result
