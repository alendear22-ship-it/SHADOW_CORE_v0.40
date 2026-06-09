extends Node
class_name PlayerAutoAttack

const AUTO_ATTACK_EFFECT_SCENE: String = "res://scenes/effects/auto_attack_slash.tscn"

@export var enabled: bool = true

var _timer: float = 0.0
var _range_px: float = 105.0
var _interval: float = 0.8
var _damage: float = 8.0
var _effect_scene: PackedScene = null
var _configured_hero_id: String = ""
var _ability_id: String = "ABILITY_KAEL_AUTO"
var _damage_type: String = "physical"
var _configured_stat_revision: int = -1

func _ready() -> void:
	_configure()
	_effect_scene = load(AUTO_ATTACK_EFFECT_SCENE) as PackedScene
	_timer = 0.05

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var owner_2d: Node2D = get_parent() as Node2D
	if owner_2d == null or not is_instance_valid(owner_2d):
		return
	_ensure_config_fresh()
	_timer -= delta
	if _timer > 0.0:
		return
	var target: Node2D = _find_nearest_attackable_target(owner_2d.global_position)
	if target == null:
		_timer = min(_interval, 0.15)
		return
	_timer = _interval
	_perform_auto_attack(owner_2d, target)

func _ensure_config_fresh() -> void:
	var hero_id: String = str(RunManager.current_hero_id)
	if hero_id.is_empty():
		hero_id = "HERO_KAEL"
	var stat_revision: int = _get_stat_revision()
	if hero_id != _configured_hero_id or stat_revision != _configured_stat_revision:
		_configure()

func _configure() -> void:
	var hero_id: String = str(RunManager.current_hero_id)
	if hero_id.is_empty():
		hero_id = "HERO_KAEL"
	_configured_hero_id = hero_id
	var ability: Dictionary = DataRegistry.get_hero_ability(hero_id, "auto_attack")
	# Keep the data-driven values, but use safe floors so the MVP auto-attack is visibly functional.
	_configured_stat_revision = _get_stat_revision()
	_range_px = max(105.0, float(ability.get("range_px", 105.0))) * _get_range_multiplier()
	_interval = max(0.15, float(ability.get("attack_interval_seconds", ability.get("cooldown_seconds", 0.8))))
	_damage = max(1.0, float(ability.get("base_damage", 8.0))) * _get_damage_multiplier()
	_ability_id = str(ability.get("id", "ABILITY_KAEL_AUTO"))
	_damage_type = _normalize_damage_type(str(ability.get("damage_type", "physical")))

func _find_nearest_attackable_target(origin: Vector2) -> Node2D:
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group("enemies"):
		candidates.append(node)
	# Defensive fallback: in case a scene was instantiated but group registration has not run yet.
	if candidates.is_empty():
		var current_scene: Node = get_tree().current_scene
		if current_scene != null:
			var enemy_container: Node = current_scene.find_child("EnemyContainer", true, false)
			if enemy_container != null:
				for child in enemy_container.get_children():
					candidates.append(child)
	var best: Node2D = null
	var best_dist_sq: float = _range_px * _range_px
	for node in candidates:
		var node2d: Node2D = node as Node2D
		if node2d == null or not is_instance_valid(node2d):
			continue
		if not _is_attackable(node2d):
			continue
		var dist_sq: float = origin.distance_squared_to(node2d.global_position)
		if dist_sq <= best_dist_sq:
			best = node2d
			best_dist_sq = dist_sq
	return best

func _is_attackable(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.has_method("apply_damage"):
		return true
	return node.get_node_or_null("HealthComponent") != null

func _perform_auto_attack(owner_2d: Node2D, target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var payload: DamagePayload = CombatSystem.build_payload(_damage, _damage_type, _ability_id, "", _ability_id, DamagePayload.SOURCE_AUTO_ATTACK_PRIMARY)
	payload.is_auto_attack = true
	# v0.18: auto-attacks must not receive BossAbilitySystem or ReactionSystem effects.
	payload.can_trigger_secondary_effects = false
	payload.can_trigger_boss_abilities = false
	payload.can_trigger_reactions = false
	payload.can_apply_reaction_prerequisites = false
	payload.normalize_source_type()
	CombatSystem.apply_damage(target, payload)
	if owner_2d.has_method("play_visual_action"):
		owner_2d.call("play_visual_action", "attack", 0.18)
	var context: EffectTriggerContext = EffectTriggerContext.new()
	context.caster = owner_2d
	context.target = target
	context.ability_id = _ability_id
	context.hit_position = target.global_position
	context.damage_payload = payload
	# v0.13: Boss abilities are active-ability only; auto-attack secondary effect hooks are disabled.
	_spawn_auto_attack_effect(owner_2d.global_position, target.global_position)
	_spawn_hit_feedback(target.global_position)

func _spawn_auto_attack_effect(from_position: Vector2, to_position: Vector2) -> void:
	var scene: PackedScene = _effect_scene
	if scene == null:
		scene = load(AUTO_ATTACK_EFFECT_SCENE) as PackedScene
		_effect_scene = scene
	if scene == null:
		return
	var effect: Node = scene.instantiate()
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return
	current_scene.add_child(effect)
	if effect.has_method("setup"):
		effect.call("setup", from_position, to_position)
	elif effect is Node2D:
		(effect as Node2D).global_position = to_position

func _spawn_hit_feedback(position: Vector2) -> void:
	var scene: PackedScene = load("res://scenes/effects/hit_effect.tscn") as PackedScene
	if scene == null:
		return
	var effect: Node2D = scene.instantiate() as Node2D
	if effect == null:
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return
	current_scene.add_child(effect)
	effect.global_position = position

func force_reconfigure() -> void:
	_configured_hero_id = ""
	_configured_stat_revision = -1
	_configure()

func _get_stat_revision() -> int:
	var stat_upgrades: Node = get_node_or_null("/root/StatUpgradeSystem")
	if stat_upgrades != null and stat_upgrades.has_method("get_revision"):
		return int(stat_upgrades.call("get_revision"))
	return 0

func _get_damage_multiplier() -> float:
	var multiplier: float = 1.0
	var stat_upgrades: Node = get_node_or_null("/root/StatUpgradeSystem")
	if stat_upgrades != null and stat_upgrades.has_method("get_attack_multiplier"):
		multiplier *= float(stat_upgrades.call("get_attack_multiplier"))
	var essence_scaling: Node = get_node_or_null("/root/EssenceAutoScaling")
	if essence_scaling != null and essence_scaling.has_method("get_damage_multiplier"):
		multiplier *= float(essence_scaling.call("get_damage_multiplier"))
	return multiplier

func _get_range_multiplier() -> float:
	var stat_upgrades: Node = get_node_or_null("/root/StatUpgradeSystem")
	if stat_upgrades != null and stat_upgrades.has_method("get_auto_attack_range_multiplier"):
		return float(stat_upgrades.call("get_auto_attack_range_multiplier"))
	if stat_upgrades != null and stat_upgrades.has_method("get_range_multiplier"):
		return float(stat_upgrades.call("get_range_multiplier"))
	return 1.0

func _normalize_damage_type(raw: String) -> String:
	var lower: String = raw.to_lower()
	if lower.contains("маг") or lower.contains("magic"):
		return "magical"
	return "physical"
