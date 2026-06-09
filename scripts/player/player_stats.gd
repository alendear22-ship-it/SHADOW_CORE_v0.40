extends Node
class_name PlayerStats

const PIXELS_PER_METER: float = 48.0

var hero_id: String = "HERO_KAEL"
var max_hp: float = 100.0
var movement_speed_px: float = 250.0
var pickup_radius_px: float = 144.0

func configure_from_hero(p_hero_id: String) -> void:
	hero_id = p_hero_id
	var hero: Dictionary = DataRegistry.get_hero(hero_id)
	var stats: Dictionary = hero.get("base_stats", {})
	var stat_upgrades: Node = get_node_or_null("/root/StatUpgradeSystem")
	var hp_bonus: float = 0.0
	var speed_multiplier: float = 1.0
	if stat_upgrades != null:
		if stat_upgrades.has_method("get_max_hp_bonus"):
			hp_bonus = float(stat_upgrades.call("get_max_hp_bonus"))
		if stat_upgrades.has_method("get_move_speed_multiplier"):
			speed_multiplier = float(stat_upgrades.call("get_move_speed_multiplier"))
	var essence_scaling: Node = get_node_or_null("/root/EssenceAutoScaling")
	var hp_multiplier: float = 1.0
	var essence_speed_multiplier: float = 1.0
	if essence_scaling != null:
		if essence_scaling.has_method("get_hp_multiplier"):
			hp_multiplier = float(essence_scaling.call("get_hp_multiplier"))
		if essence_scaling.has_method("get_move_speed_multiplier"):
			essence_speed_multiplier = float(essence_scaling.call("get_move_speed_multiplier"))
	max_hp = (float(stats.get("hp", 100.0)) + hp_bonus) * hp_multiplier
	movement_speed_px = float(stats.get("movement_speed_m_per_sec", 5.0)) * PIXELS_PER_METER * speed_multiplier * essence_speed_multiplier
	pickup_radius_px = float(stats.get("essence_pickup_radius_m", 3.0)) * PIXELS_PER_METER
