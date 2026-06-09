extends Node

const DATA_FILES: Dictionary = {
    "run_config": "res://data/run_config.json",
    "run_state_schema": "res://data/run_state_schema.json",
    "factions": "res://data/factions.json",
    "creature_types": "res://data/creature_types.json",
    "enemies": "res://data/enemies.json",
    "enemy_elites": "res://data/enemy_elites.json",
    "boss_abilities": "res://data/boss_abilities.json",
    "heroes": "res://data/heroes.json",
    "hero_progression": "res://data/hero_progression.json",
    "abilities": "res://data/abilities.json",
    "bosses": "res://data/bosses.json",
    "final_bosses": "res://data/final_bosses.json",
    "rooms": "res://data/rooms.json",
    "rewards": "res://data/rewards.json",
    "altar_cards": "res://data/altar_cards.json",
    "meta_unlocks": "res://data/meta_unlocks.json",
    "meta_progression": "res://data/meta_progression.json",
    "effect_visual_profiles": "res://data/effect_visual_profiles.json"
}

var _data: Dictionary = {}
var _by_id: Dictionary = {}

func _ready() -> void:
    load_all()

func load_all() -> void:
    _data.clear()
    _by_id.clear()
    for collection_name in DATA_FILES.keys():
        var path: String = DATA_FILES[collection_name]
        var parsed: Variant = _load_json(path)
        if parsed == null:
            push_error("DataRegistry: failed to load " + path)
            _data[collection_name] = {}
            continue
        _data[collection_name] = parsed
        _index_collection(collection_name, parsed)
    _validate_required_content()

func _load_json(path: String) -> Variant:
    if not FileAccess.file_exists(path):
        push_error("DataRegistry: missing JSON file: " + path)
        return null
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("DataRegistry: cannot open JSON file: " + path)
        return null
    var text: String = file.get_as_text()
    var parsed: Variant = JSON.parse_string(text)
    if parsed == null:
        push_error("DataRegistry: invalid JSON in " + path)
    return parsed

func _index_collection(collection_name: String, parsed: Variant) -> void:
    _by_id[collection_name] = {}
    if parsed is Dictionary and parsed.has("items") and parsed["items"] is Array:
        for item in parsed["items"]:
            if item is Dictionary:
                var item_dict: Dictionary = item
                var item_id: String = str(item_dict.get("id", ""))
                if item_id.is_empty() and item_dict.has("boss_id"):
                    item_id = str(item_dict.get("boss_id", ""))
                if not item_id.is_empty():
                    _by_id[collection_name][item_id] = item_dict

func _validate_required_content() -> void:
    _expect_count("factions", 3)
    _expect_count("creature_types", 9)
    _expect_count("boss_abilities", 27)
    _expect_count("enemies", 9)
    _expect_count("enemy_elites", 9)
    _expect_count("heroes", 3)
    _expect_count("bosses", 9)
    _expect_count("final_bosses", 1)
    _expect_count("altar_cards", 6)
    _expect_count("meta_unlocks", 5)
    _validate_all_collection_ids()
    _validate_run_config()
    _validate_boss_progression_data()
    _validate_altar_cards()
    _validate_ability_icon_profiles()
    _validate_meta_unlocks()
    _validate_meta_progression_config()
    _validate_run_state_schema()
    _validate_effect_visual_profiles()

func _expect_count(collection_name: String, minimum: int) -> void:
    var items: Array = get_items(collection_name)
    if items.size() < minimum:
        push_error("DataRegistry: " + collection_name + " has " + str(items.size()) + ", expected at least " + str(minimum))

func _validate_all_collection_ids() -> void:
    # Validate ID-bearing collections only. Some legacy/config collections, such as hero_progression,
    # intentionally use item arrays without per-row ids and must not fail startup validation.
    var id_collections: Array = [
        "factions",
        "creature_types",
        "enemies",
        "enemy_elites",
        "boss_abilities",
        "heroes",
        "abilities",
        "bosses",
        "final_bosses",
        "rooms",
        "altar_cards",
        "meta_unlocks",
        "effect_visual_profiles"
    ]
    for collection_name in id_collections:
        _validate_collection_ids(str(collection_name))

func _validate_collection_ids(collection_name: String) -> void:
    var seen: Dictionary = {}
    for item in get_items(collection_name):
        if not (item is Dictionary):
            push_error("DataRegistry: non-dictionary item in " + collection_name)
            continue
        var item_dict: Dictionary = item
        var item_id: String = str(item_dict.get("id", ""))
        if item_id.is_empty() and item_dict.has("boss_id"):
            item_id = str(item_dict.get("boss_id", ""))
        if item_id.is_empty():
            push_error("DataRegistry: empty id in " + collection_name)
            continue
        if seen.has(item_id):
            push_error("DataRegistry: duplicate id '" + item_id + "' in " + collection_name)
        seen[item_id] = true

func _validate_run_config() -> void:
    var raw: Variant = get_raw("run_config")
    if not (raw is Dictionary):
        push_error("DataRegistry: run_config must be a Dictionary")
        return
    var config: Dictionary = raw
    var total_floors: int = int(config.get("floors_total", 0))
    if total_floors != 7:
        push_error("DataRegistry: run_config.floors_total must be 7")
    var rooms_by_floor_raw: Variant = config.get("rooms_by_floor", {})
    if not (rooms_by_floor_raw is Dictionary):
        push_error("DataRegistry: run_config.rooms_by_floor must be a Dictionary")
        return
    var rooms_by_floor: Dictionary = rooms_by_floor_raw
    for floor_index in range(1, total_floors + 1):
        var floor_key: String = str(floor_index)
        if not rooms_by_floor.has(floor_key):
            push_error("DataRegistry: run_config.rooms_by_floor missing floor " + floor_key)
        elif int(rooms_by_floor.get(floor_key, 0)) <= 0:
            push_error("DataRegistry: run_config.rooms_by_floor floor " + floor_key + " must be > 0")
    var pairs_raw: Variant = config.get("optional_boss_pairs", [])
    if not (pairs_raw is Array):
        push_error("DataRegistry: run_config.optional_boss_pairs must be an Array")
    else:
        var pairs: Array = pairs_raw
        if pairs.size() != 3:
            push_error("DataRegistry: run_config.optional_boss_pairs must contain 3 pairs")
        for pair_value in pairs:
            if not (pair_value is Dictionary):
                push_error("DataRegistry: run_config optional boss pair must be Dictionary")
                continue
            var pair: Dictionary = pair_value
            var floors_raw: Variant = pair.get("floors", [])
            if not (floors_raw is Array):
                push_error("DataRegistry: optional boss pair " + str(pair.get("pair_id", "")) + " must contain floors [a, b]")
                continue
            var floors: Array = floors_raw
            if floors.size() != 2:
                push_error("DataRegistry: optional boss pair " + str(pair.get("pair_id", "")) + " must contain exactly 2 floors")
                continue
            var first_floor: int = int(floors[0])
            var second_floor: int = int(floors[1])
            if first_floor < 1 or second_floor > total_floors or second_floor != first_floor + 1:
                push_error("DataRegistry: invalid optional boss pair floors " + str(floors_raw))
    var final_preparation_raw: Variant = config.get("final_preparation", {})
    if not (final_preparation_raw is Dictionary):
        push_error("DataRegistry: run_config.final_preparation must be a Dictionary")
    else:
        var final_preparation: Dictionary = final_preparation_raw
        if not bool(final_preparation.get("enabled", false)):
            push_error("DataRegistry: run_config.final_preparation.enabled must be true")
        if int(final_preparation.get("elite_waves", 0)) != 1:
            push_error("DataRegistry: run_config.final_preparation.elite_waves must be 1")
    var final_boss_raw: Variant = config.get("final_boss", {})
    if not (final_boss_raw is Dictionary):
        push_error("DataRegistry: run_config.final_boss must be a Dictionary")
    else:
        var final_boss: Dictionary = final_boss_raw
        var final_boss_id: String = str(final_boss.get("boss_id", ""))
        if final_boss_id.is_empty():
            push_error("DataRegistry: run_config.final_boss.boss_id is required")
        elif get_by_id("final_bosses", final_boss_id).is_empty():
            push_error("DataRegistry: run_config.final_boss.boss_id not found in final_bosses: " + final_boss_id)
        if not bool(final_boss.get("ends_run", false)):
            push_error("DataRegistry: run_config.final_boss.ends_run must be true")
    var table_raw: Variant = config.get("boss_choice_probability_table", [])
    if not (table_raw is Array):
        push_error("DataRegistry: run_config.boss_choice_probability_table must be an Array")
    else:
        var table: Array = table_raw
        if table.size() != 5:
            push_error("DataRegistry: boss_choice_probability_table must contain 5 bands")
        for row_value in table:
            if not (row_value is Dictionary):
                push_error("DataRegistry: probability table row must be Dictionary")
                continue
            var row: Dictionary = row_value
            for card_key in ["card_1", "card_2"]:
                var card_raw: Variant = row.get(card_key, {})
                if not (card_raw is Dictionary):
                    push_error("DataRegistry: probability row missing " + card_key)
                    continue
                var card: Dictionary = card_raw
                var new_prob: float = float(card.get("new", -1.0))
                var echo_prob: float = float(card.get("echo", -1.0))
                if new_prob < 0.0 or echo_prob < 0.0 or abs((new_prob + echo_prob) - 1.0) > 0.001:
                    push_error("DataRegistry: " + card_key + " probabilities must sum to 1.0")


func _validate_icon_profile(owner_id: String, item: Dictionary, category: String) -> void:
    var icon_path: String = str(item.get("icon_path", ""))
    var icon_path_exists: bool = false
    if not icon_path.is_empty():
        icon_path_exists = ResourceLoader.exists(icon_path)
    var profile_raw: Variant = item.get("icon_profile", {})
    var profile: Dictionary = {}
    if profile_raw is Dictionary:
        profile = profile_raw
    var has_profile: bool = not profile.is_empty()
    if icon_path.is_empty() or not icon_path_exists:
        if not has_profile:
            push_error("DataRegistry: " + category + " " + owner_id + " missing icon_profile fallback for absent/missing icon_path")
            return
    if has_profile:
        for field_name in ["glyph", "base_color", "accent_color"]:
            if str(profile.get(field_name, "")).is_empty():
                push_error("DataRegistry: " + category + " " + owner_id + " icon_profile missing " + str(field_name))

func _validate_boss_progression_data() -> void:
    var raw: Variant = get_raw("boss_abilities")
    if not (raw is Dictionary):
        push_error("DataRegistry: boss_abilities must be a Dictionary")
        return
    var boss_abilities_raw: Dictionary = raw
    if str(boss_abilities_raw.get("schema_version", "")) != "boss_abilities_v2":
        push_warning("Legacy boss_abilities schema detected. Migration to boss_abilities_v2 required.")
        push_error("DataRegistry: data/boss_abilities.json must use schema_version boss_abilities_v2")
        return
    var items: Array = get_items("boss_abilities")
    if items.size() != 27:
        push_error("DataRegistry: boss_abilities_v2 must contain exactly 27 items")

    var ability_ids_seen: Dictionary = {}
    var boss_index_map: Dictionary = {}
    for ability in items:
        if not (ability is Dictionary):
            push_error("DataRegistry: boss_abilities item must be Dictionary")
            continue
        var ability_dict: Dictionary = ability
        var ability_id: String = str(ability_dict.get("boss_ability_id", ability_dict.get("id", "")))
        if ability_id.is_empty():
            push_error("DataRegistry: boss ability has empty boss_ability_id")
            continue
        if ability_ids_seen.has(ability_id):
            push_error("DataRegistry: duplicate boss_ability_id " + ability_id)
        ability_ids_seen[ability_id] = true
        for field_name in ["boss_id", "creature_type_id", "faction_id", "ability_index", "name_ru", "icon_path", "boss_version", "player_version", "weak_mob_version"]:
            if not ability_dict.has(field_name):
                push_error("DataRegistry: boss ability " + ability_id + " missing " + str(field_name))
        _validate_icon_profile(ability_id, ability_dict, "boss_ability")
        _validate_boss_ability_player_visual_profile(ability_id, ability_dict)
        if not bool(ability_dict.get("independent_ability", false)):
            push_error("DataRegistry: boss ability " + ability_id + " must be independent_ability=true")
        if bool(ability_dict.get("requires_other_ability", true)):
            push_error("DataRegistry: boss ability " + ability_id + " must be requires_other_ability=false")
        var ability_index: int = int(ability_dict.get("ability_index", 0))
        if ability_index < 1 or ability_index > 3:
            push_error("DataRegistry: boss ability " + ability_id + " ability_index must be 1, 2 or 3")
        var boss_id: String = str(ability_dict.get("boss_id", ""))
        if boss_id.is_empty():
            push_error("DataRegistry: boss ability " + ability_id + " missing boss_id")
        else:
            if not boss_index_map.has(boss_id):
                boss_index_map[boss_id] = {}
            var index_map: Dictionary = boss_index_map[boss_id]
            if index_map.has(ability_index):
                push_error("DataRegistry: boss " + boss_id + " has duplicate ability_index " + str(ability_index))
            index_map[ability_index] = ability_id
        _validate_boss_ability_version(ability_id, ability_dict, "boss_version")
        _validate_boss_ability_version(ability_id, ability_dict, "player_version")
        _validate_weak_mob_version_v2(ability_id, ability_dict)

    for boss in get_items("bosses"):
        if not (boss is Dictionary):
            continue
        var boss_dict: Dictionary = boss
        var boss_id: String = str(boss_dict.get("boss_id", boss_dict.get("id", "")))
        if boss_id.is_empty():
            push_error("DataRegistry: boss with empty boss_id")
            continue
        var ability_ids_raw: Variant = boss_dict.get("ability_ids", [])
        if not (ability_ids_raw is Array):
            push_error("DataRegistry: boss " + boss_id + " ability_ids must be an Array")
            continue
        var ability_ids: Array = ability_ids_raw
        if ability_ids.size() != 3:
            push_error("DataRegistry: boss " + boss_id + " must have exactly 3 ability_ids")
        for ability_id_value in ability_ids:
            var ability_id: String = str(ability_id_value)
            if ability_id.is_empty():
                push_error("DataRegistry: boss " + boss_id + " has empty ability_id")
            elif get_by_id("boss_abilities", ability_id).is_empty():
                push_error("DataRegistry: boss " + boss_id + " references missing boss ability " + ability_id)
        if not boss_index_map.has(boss_id):
            push_error("DataRegistry: boss_abilities missing boss " + boss_id)
            continue
        var index_map: Dictionary = boss_index_map[boss_id]
        for required_index in [1, 2, 3]:
            if not index_map.has(required_index):
                push_error("DataRegistry: boss " + boss_id + " missing boss ability index " + str(required_index))

func _validate_boss_ability_version(ability_id: String, ability_dict: Dictionary, version_key: String) -> void:
    var version_raw: Variant = ability_dict.get(version_key, {})
    if not (version_raw is Dictionary):
        push_error("DataRegistry: boss ability " + ability_id + " missing " + version_key)
        return
    var version: Dictionary = version_raw
    var levels_raw: Variant = version.get("levels", {})
    if not (levels_raw is Dictionary):
        push_error("DataRegistry: boss ability " + ability_id + " " + version_key + ".levels must be a Dictionary")
        return
    for level_key in ["1", "2", "3"]:
        var level_raw: Variant = levels_raw.get(level_key, {})
        if not (level_raw is Dictionary):
            push_error("DataRegistry: boss ability " + ability_id + " " + version_key + " missing level " + level_key)
            continue
        var level: Dictionary = level_raw
        if str(level.get("description_ru", "")).strip_edges().is_empty():
            push_error("DataRegistry: boss ability " + ability_id + " " + version_key + " L" + level_key + " missing description_ru")
        if not (level.get("effect_tags", []) is Array):
            push_error("DataRegistry: boss ability " + ability_id + " " + version_key + " L" + level_key + " effect_tags must be an Array")
        if not (level.get("source_type", "") is String) or str(level.get("source_type", "")).is_empty():
            push_error("DataRegistry: boss ability " + ability_id + " " + version_key + " L" + level_key + " source_type is required")
        if not (level.get("effect_data", {}) is Dictionary):
            push_error("DataRegistry: boss ability " + ability_id + " " + version_key + " L" + level_key + " effect_data must be a Dictionary")
        if not (level.get("reaction_tags", []) is Array):
            push_error("DataRegistry: boss ability " + ability_id + " " + version_key + " L" + level_key + " reaction_tags must be an Array")
    if version_key == "player_version":
        var allowed_slots: Variant = version.get("allowed_slots", [])
        var forbidden_slots: Variant = version.get("forbidden_slots", [])
        if allowed_slots is Array and allowed_slots.has("auto_attack"):
            push_error("DataRegistry: boss ability " + ability_id + " player_version.allowed_slots must not contain auto_attack")
        if not (forbidden_slots is Array) or not forbidden_slots.has("auto_attack") or not forbidden_slots.has("passive"):
            push_error("DataRegistry: boss ability " + ability_id + " player_version.forbidden_slots must contain auto_attack and passive")
        if not bool(version.get("local_to_installed_active_ability", false)):
            push_error("DataRegistry: boss ability " + ability_id + " player_version.local_to_installed_active_ability must be true")

func _validate_weak_mob_version_v2(ability_id: String, ability_dict: Dictionary) -> void:
    var version_raw: Variant = ability_dict.get("weak_mob_version", {})
    if not (version_raw is Dictionary):
        push_error("DataRegistry: boss ability " + ability_id + " weak_mob_version must be a Dictionary")
        return
    var version: Dictionary = version_raw
    if float(version.get("base_power_scale", 0.0)) <= 0.0:
        push_error("DataRegistry: boss ability " + ability_id + " weak_mob_version.base_power_scale must be positive")
    if float(version.get("escalated_power_scale", 0.0)) <= 0.0:
        push_error("DataRegistry: boss ability " + ability_id + " weak_mob_version.escalated_power_scale must be positive")
    var levels_raw: Variant = version.get("levels", {})
    if not (levels_raw is Dictionary):
        push_error("DataRegistry: boss ability " + ability_id + " weak_mob_version.levels must be a Dictionary")
        return
    for level_key in ["1", "2", "3"]:
        var level_raw: Variant = levels_raw.get(level_key, {})
        if not (level_raw is Dictionary):
            push_error("DataRegistry: boss ability " + ability_id + " weak_mob_version missing level " + level_key)
            continue
        var level: Dictionary = level_raw
        if str(level.get("description_ru", "")).strip_edges().is_empty():
            push_error("DataRegistry: boss ability " + ability_id + " weak_mob_version L" + level_key + " missing description_ru")
        if not (level.get("effect_tags", []) is Array):
            push_error("DataRegistry: boss ability " + ability_id + " weak_mob_version L" + level_key + " effect_tags must be an Array")
        if str(level.get("source_type", "")).is_empty():
            push_error("DataRegistry: boss ability " + ability_id + " weak_mob_version L" + level_key + " source_type is required")
        if not (level.get("effect_data", {}) is Dictionary):
            push_error("DataRegistry: boss ability " + ability_id + " weak_mob_version L" + level_key + " effect_data must be a Dictionary")


func _validate_boss_ability_player_visual_profile(ability_id: String, ability: Dictionary) -> void:
    var profile_raw: Variant = ability.get("visual_profile", {})
    if not (profile_raw is Dictionary):
        push_error("DataRegistry: boss ability " + ability_id + " missing visual_profile")
        return
    var visual_profile: Dictionary = profile_raw
    var player_raw: Variant = visual_profile.get("player_version", {})
    if not (player_raw is Dictionary):
        push_error("DataRegistry: boss ability " + ability_id + " missing visual_profile.player_version")
        return
    var player_profile: Dictionary = player_raw
    for required_key in ["cast_visual_id", "impact_visual_id"]:
        var visual_id: String = str(player_profile.get(required_key, ""))
        if visual_id.is_empty():
            push_error("DataRegistry: boss ability " + ability_id + " missing " + required_key)
        elif get_by_id("effect_visual_profiles", visual_id).is_empty():
            push_error("DataRegistry: boss ability " + ability_id + " references missing visual profile " + visual_id)
    for optional_key in ["travel_visual_id", "zone_visual_id", "status_visual_id", "delayed_visual_id"]:
        var optional_id: String = str(player_profile.get(optional_key, ""))
        if optional_id.is_empty():
            continue
        if get_by_id("effect_visual_profiles", optional_id).is_empty():
            push_error("DataRegistry: boss ability " + ability_id + " references missing visual profile " + optional_id)

func _validate_altar_cards() -> void:
    var active_required_types: Array = ["weapon_upgrade", "stat_upgrade", "boss_ability_upgrade", "heal"]
    var disabled_types: Array = ["reroll", "service"]
    var seen_ids: Dictionary = {}
    for card in get_items("altar_cards"):
        if not (card is Dictionary):
            push_error("DataRegistry: altar card entry must be a Dictionary")
            continue
        var card_id: String = str(card.get("id", ""))
        var card_type: String = str(card.get("card_type", ""))
        if card_id.is_empty():
            push_error("DataRegistry: altar card has empty id")
        elif seen_ids.has(card_id):
            push_error("DataRegistry: duplicate altar card id " + card_id)
        else:
            seen_ids[card_id] = true
        if card_type.is_empty():
            push_error("DataRegistry: altar card " + card_id + " has empty card_type")
        if str(card.get("title_ru", card.get("name_ru", ""))).is_empty():
            push_error("DataRegistry: altar card " + card_id + " missing title_ru/name_ru")
        if str(card.get("description_ru", "")).is_empty():
            push_error("DataRegistry: altar card " + card_id + " missing description_ru")
        _validate_icon_profile(card_id, card, "altar_card")
        var is_enabled: bool = bool(card.get("enabled", true)) and bool(card.get("main_flow", true))
        if is_enabled:
            if not active_required_types.has(card_type):
                push_error("DataRegistry: unsupported active altar card type " + card_type)
            var payload = card.get("effect_payload", {})
            if not (payload is Dictionary):
                push_error("DataRegistry: active altar card " + card_id + " missing effect_payload Dictionary")
            elif str(payload.get("handler", "")).is_empty():
                push_error("DataRegistry: active altar card " + card_id + " missing effect_payload.handler")
        if disabled_types.has(card_type) and is_enabled:
            push_error("DataRegistry: altar card type " + card_type + " must remain disabled until full implementation")
    for required_type in active_required_types:
        var found: bool = false
        for card in get_items("altar_cards"):
            if card is Dictionary and str(card.get("card_type", "")) == str(required_type) and bool(card.get("enabled", true)) and bool(card.get("main_flow", true)):
                found = true
                break
        if not found:
            push_error("DataRegistry: missing active altar card type " + str(required_type))


func _validate_ability_icon_profiles() -> void:
    for ability in get_items("abilities"):
        if not (ability is Dictionary):
            push_error("DataRegistry: abilities item must be Dictionary")
            continue
        var ability_dict: Dictionary = ability
        var ability_id: String = str(ability_dict.get("id", ""))
        if ability_id.is_empty():
            push_error("DataRegistry: hero ability has empty id")
            continue
        _validate_icon_profile(ability_id, ability_dict, "hero_ability")

func _validate_meta_unlocks() -> void:
    var required_types: Array = ["boss_ability_unlock", "hero_unlock", "cosmetic_unlock", "alternative_start", "codex_entry"]
    for required_type in required_types:
        var found: bool = false
        for unlock in get_items("meta_unlocks"):
            if unlock is Dictionary and str(unlock.get("unlock_type", "")) == str(required_type):
                found = true
                break
        if not found:
            push_error("DataRegistry: missing meta unlock type " + str(required_type))

func _validate_meta_progression_config() -> void:
    var raw: Variant = get_raw("meta_progression")
    if not (raw is Dictionary):
        push_error("DataRegistry: meta_progression must be a Dictionary")
        return
    var config: Dictionary = raw
    var currency_raw: Variant = config.get("meta_currency", {})
    if not (currency_raw is Dictionary):
        push_error("DataRegistry: meta_progression.meta_currency must be a Dictionary")
        return
    var currency: Dictionary = currency_raw
    if str(currency.get("currency_id", "")) != "ESSENCE_CORE":
        push_error("DataRegistry: meta_progression.meta_currency.currency_id must be ESSENCE_CORE")
    if str(currency.get("name_ru", "")) != "Ядро эссенции":
        push_error("DataRegistry: meta_progression.meta_currency.name_ru must be Ядро эссенции")
    var forbidden: Variant = currency.get("forbidden_uses", [])
    if not (forbidden is Array) or forbidden.is_empty():
        push_error("DataRegistry: meta_progression.meta_currency.forbidden_uses must document forbidden permanent stat growth")

func _validate_run_state_schema() -> void:
    var raw: Variant = get_raw("run_state_schema")
    if not (raw is Dictionary):
        push_error("DataRegistry: run_state_schema must be a Dictionary")
        return
    var required: Variant = raw.get("required_fields", {})
    if not (required is Dictionary):
        push_error("DataRegistry: run_state_schema.required_fields must be a Dictionary")
        return
    var required_keys: Array[String] = [
        "floor_index",
        "room_index_on_floor",
        "current_flow_state",
        "current_route_context",
        "essence_by_faction",
        "soul_ash",
        "altar_used_by_floor",
        "optional_boss_state_by_pair",
        "unique_bosses_seen_this_run",
        "unique_bosses_defeated_this_run",
        "boss_defeat_count_by_creature_type",
        "boss_ability_levels",
        "installed_boss_abilities",
        "final_preparation_started",
        "final_preparation_completed",
        "morgath_started",
        "morgath_defeated",
        "current_pending_reward",
        "current_pending_install"
    ]
    for key in required_keys:
        if not required.has(key):
            push_error("DataRegistry: run_state_schema.required_fields missing " + key)

func get_run_state_schema() -> Dictionary:
    var raw: Variant = get_raw("run_state_schema")
    return raw.duplicate(true) if raw is Dictionary else {}


func get_run_config() -> Dictionary:
    var raw: Variant = get_raw("run_config")
    return raw if raw is Dictionary else {}

func get_rooms_by_floor() -> Dictionary:
    var config: Dictionary = get_run_config()
    var raw: Variant = config.get("rooms_by_floor", {})
    if raw is Dictionary:
        return raw.duplicate(true)
    return {}

func get_total_floors() -> int:
    return int(get_run_config().get("floors_total", 0))

func get_optional_boss_pairs() -> Array:
    var raw: Variant = get_run_config().get("optional_boss_pairs", [])
    return raw.duplicate(true) if raw is Array else []

func get_final_preparation_config() -> Dictionary:
    var raw: Variant = get_run_config().get("final_preparation", {})
    return raw.duplicate(true) if raw is Dictionary else {}

func get_final_boss_config() -> Dictionary:
    var raw: Variant = get_run_config().get("final_boss", {})
    return raw.duplicate(true) if raw is Dictionary else {}

func get_final_boss_id() -> String:
    return str(get_final_boss_config().get("boss_id", ""))

func get_boss_choice_probability_row(seen_count: int) -> Dictionary:
    var table_raw: Variant = get_run_config().get("boss_choice_probability_table", [])
    if not (table_raw is Array):
        return {}
    for row_value in table_raw:
        if not (row_value is Dictionary):
            continue
        var row: Dictionary = row_value
        var seen_min: int = int(row.get("seen_min", 0))
        var seen_max: int = int(row.get("seen_max", seen_min))
        if seen_count >= seen_min and seen_count <= seen_max:
            return row.duplicate(true)
    return {}

func get_boss_choice_new_probability(slot_index: int, seen_count: int) -> float:
    var row: Dictionary = get_boss_choice_probability_row(seen_count)
    if row.is_empty():
        push_error("DataRegistry: missing boss choice probability row for seen_count=" + str(seen_count))
        return 0.0
    var card_key: String = "card_1" if slot_index <= 0 else "card_2"
    var card_raw: Variant = row.get(card_key, {})
    if not (card_raw is Dictionary):
        push_error("DataRegistry: missing boss choice probability " + card_key)
        return 0.0
    return clampf(float(card_raw.get("new", 0.0)), 0.0, 1.0)

func _validate_effect_visual_profiles() -> void:
    var raw: Variant = get_raw("effect_visual_profiles")
    if not (raw is Dictionary):
        push_error("DataRegistry: effect_visual_profiles must be a Dictionary")
        return
    var profiles: Dictionary = raw
    var visual_schema: String = str(profiles.get("schema_version", ""))
    if visual_schema != "effect_visual_profiles_v1" and visual_schema != "effect_visual_profiles_v2_player_boss_vfx":
        push_error("DataRegistry: effect_visual_profiles.schema_version must be effect_visual_profiles_v1 or effect_visual_profiles_v2_player_boss_vfx")
    var items_raw: Variant = profiles.get("items", [])
    if not (items_raw is Array):
        push_error("DataRegistry: effect_visual_profiles.items must be an Array")
        return
    var required_ids: Array[String] = [
        "VISUAL_GENERIC_HIT",
        "VISUAL_GENERIC_CAST",
        "VISUAL_GENERIC_TELEGRAPH_CIRCLE",
        "VISUAL_GENERIC_TELEGRAPH_CONE",
        "VISUAL_GENERIC_TELEGRAPH_LINE",
        "VISUAL_GENERIC_ZONE",
        "VISUAL_GENERIC_PROJECTILE",
        "VISUAL_GENERIC_STATUS_AURA",
        "VISUAL_GENERIC_REACTION_BURST"
    ]
    var seen: Dictionary = {}
    for item_value in items_raw:
        if not (item_value is Dictionary):
            push_error("DataRegistry: effect_visual_profiles item must be a Dictionary")
            continue
        var item: Dictionary = item_value
        var profile_id: String = str(item.get("id", ""))
        if profile_id.is_empty():
            push_error("DataRegistry: effect_visual_profiles item has empty id")
            continue
        seen[profile_id] = true
        for field_name in ["name_ru", "visual_type", "color", "duration", "layers"]:
            if not item.has(field_name):
                push_error("DataRegistry: visual profile " + profile_id + " missing " + str(field_name))
        if not (item.get("layers", []) is Array):
            push_error("DataRegistry: visual profile " + profile_id + " layers must be an Array")
    for required_id in required_ids:
        if not seen.has(required_id):
            push_error("DataRegistry: missing required visual profile " + required_id)

func get_raw(collection_name: String) -> Variant:
    return _data.get(collection_name, {})

func get_items(collection_name: String) -> Array:
    var raw: Variant = _data.get(collection_name, {})
    if raw is Dictionary and raw.has("items") and raw["items"] is Array:
        return raw["items"]
    return []

func get_by_id(collection_name: String, id: String) -> Dictionary:
    return _by_id.get(collection_name, {}).get(id, {})

func get_enemy(enemy_id: String) -> Dictionary:
    return get_by_id("enemies", enemy_id)


func get_boss_ability(ability_id: String) -> Dictionary:
    return get_by_id("boss_abilities", ability_id)

func get_boss_ability_effect(ability_id: String) -> Dictionary:
    return get_boss_ability(ability_id)

func get_boss_abilities_for_boss(boss_id: String) -> Array:
    var result: Array = []
    for ability in get_items("boss_abilities"):
        if ability is Dictionary and str(ability.get("boss_id", "")) == boss_id:
            result.append(ability)
    result.sort_custom(Callable(self, "_sort_boss_ability_by_index"))
    return result

func get_boss_ability_by_index(boss_id: String, ability_index: int) -> Dictionary:
    for ability in get_boss_abilities_for_boss(boss_id):
        if ability is Dictionary and int(ability.get("ability_index", 0)) == ability_index:
            return ability
    return {}

func get_boss_abilities_for_creature_type(creature_type_id: String) -> Array:
    var result: Array = []
    for ability in get_items("boss_abilities"):
        if ability is Dictionary and str(ability.get("creature_type_id", "")) == creature_type_id:
            result.append(ability)
    result.sort_custom(Callable(self, "_sort_boss_ability_by_index"))
    return result

func _sort_boss_ability_by_index(a: Dictionary, b: Dictionary) -> bool:
    var a_index: int = int(a.get("ability_index", 0))
    var b_index: int = int(b.get("ability_index", 0))
    if a_index == b_index:
        return str(a.get("boss_ability_id", a.get("id", ""))) < str(b.get("boss_ability_id", b.get("id", "")))
    return a_index < b_index

func get_effect_visual_profile(profile_id: String) -> Dictionary:
    return get_by_id("effect_visual_profiles", profile_id)

func get_effect_visual_profiles() -> Array:
    return get_items("effect_visual_profiles")

func get_altar_card(card_id: String) -> Dictionary:
    return get_by_id("altar_cards", card_id)

func get_meta_unlock(unlock_id: String) -> Dictionary:
    return get_by_id("meta_unlocks", unlock_id)

func get_hero(hero_id: String) -> Dictionary:
    return get_by_id("heroes", hero_id)

func get_ability(ability_id: String) -> Dictionary:
    return get_by_id("abilities", ability_id)

func get_hero_ability(hero_id: String, slot: String) -> Dictionary:
    for ability in get_items("abilities"):
        if ability.get("hero_id", "") == hero_id and ability.get("slot", "") == slot:
            return ability
    return {}

func get_creature_type(creature_type_id: String) -> Dictionary:
    return get_by_id("creature_types", creature_type_id)

func get_creature_type_ids_for_faction(faction_id: String) -> Array:
    var result: Array = []
    for creature in get_items("creature_types"):
        if creature.get("faction_id", "") == faction_id:
            result.append(creature.get("id", ""))
    return result

func get_room(room_id: String) -> Dictionary:
    return get_by_id("rooms", room_id)

func get_rewards() -> Dictionary:
    var raw: Variant = get_raw("rewards")
    return raw if raw is Dictionary else {}


func get_altar_cards() -> Array:
    return get_items("altar_cards")

func get_altar_cards_by_type(card_type: String) -> Array:
    var result: Array = []
    for card in get_items("altar_cards"):
        if card is Dictionary and str(card.get("card_type", "")) == card_type:
            result.append(card)
    return result

func reset_run() -> void:
    # data registry; source-of-truth is JSON data. No run-local reset required.
    pass

func get_state() -> Dictionary:
    return {"stateless": true, "note": "data registry; source-of-truth is JSON data"}

func set_state(state: Variant = {}) -> void:
    # data registry; source-of-truth is JSON data. Incoming state intentionally ignored.
    pass
