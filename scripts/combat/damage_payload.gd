extends RefCounted
class_name DamagePayload

const SOURCE_DIRECT_ACTIVE_HIT: String = "DIRECT_ACTIVE_HIT"
const SOURCE_ZONE_INITIAL_HIT: String = "ZONE_INITIAL_HIT"
const SOURCE_ZONE_TICK: String = "ZONE_TICK"
const SOURCE_DOT_TICK: String = "DOT_TICK"
const SOURCE_PHANTOM_ECHO: String = "PHANTOM_ECHO"
const SOURCE_BOSS_ABILITY_DAMAGE: String = "BOSS_ABILITY_DAMAGE"
const SOURCE_REACTION_DAMAGE: String = "REACTION_DAMAGE"
const SOURCE_FRIENDLY_FIRE: String = "FRIENDLY_FIRE"
const SOURCE_AUTO_ATTACK_PRIMARY: String = "AUTO_ATTACK_PRIMARY"
const SOURCE_AUTO_ATTACK_EXTRA_SHURIKEN: String = "AUTO_ATTACK_EXTRA_SHURIKEN"
const SOURCE_AUTO_ATTACK_BOUNCE: String = "AUTO_ATTACK_BOUNCE"
const SOURCE_AUTO_ATTACK_PROC_BONUS: String = "AUTO_ATTACK_PROC_BONUS"
const SOURCE_WEAK_MOB_ABILITY_DAMAGE: String = "WEAK_MOB_ABILITY_DAMAGE"
const SOURCE_BOSS_AI_ABILITY_DAMAGE: String = "BOSS_AI_ABILITY_DAMAGE"
const SOURCE_ALTAR_CARD_DAMAGE: String = "ALTAR_CARD_DAMAGE"

const KNOWN_SOURCE_TYPES: Array[String] = [
	SOURCE_DIRECT_ACTIVE_HIT,
	SOURCE_ZONE_INITIAL_HIT,
	SOURCE_ZONE_TICK,
	SOURCE_DOT_TICK,
	SOURCE_PHANTOM_ECHO,
	SOURCE_BOSS_ABILITY_DAMAGE,
	SOURCE_REACTION_DAMAGE,
	SOURCE_FRIENDLY_FIRE,
	SOURCE_AUTO_ATTACK_PRIMARY,
	SOURCE_AUTO_ATTACK_EXTRA_SHURIKEN,
	SOURCE_AUTO_ATTACK_BOUNCE,
	SOURCE_AUTO_ATTACK_PROC_BONUS,
	SOURCE_WEAK_MOB_ABILITY_DAMAGE,
	SOURCE_BOSS_AI_ABILITY_DAMAGE,
	SOURCE_ALTAR_CARD_DAMAGE
]

var amount: float = 0.0
var damage_type: String = "physical"
var source_id: String = ""
var source_owner: Node = null
var caster: Node = null
var target: Node = null
var faction_id: String = ""
var ability_id: String = ""
var source_type: String = SOURCE_DIRECT_ACTIVE_HIT
var source_event_id: String = ""
var effect_tags: Array[String] = []
var reaction_tags: Array[String] = []
var can_trigger_secondary_effects: bool = true
var can_trigger_boss_abilities: bool = true
var can_trigger_reactions: bool = true
var can_trigger_weapon_upgrades: bool = false
var can_apply_reaction_prerequisites: bool = true
var reaction_consumed: bool = false
var chain_depth: int = 0
var event_id: String = ""
var is_periodic: bool = false
var is_auto_attack: bool = false
var is_ultimate: bool = false

func normalize_source_type() -> void:
	if source_type.is_empty() or not KNOWN_SOURCE_TYPES.has(source_type):
		source_type = SOURCE_DIRECT_ACTIVE_HIT
	if event_id.is_empty() and not source_event_id.is_empty():
		event_id = source_event_id
	if source_event_id.is_empty():
		source_event_id = source_type + ":" + source_id + ":" + ability_id + ":" + str(Time.get_ticks_usec())
	if event_id.is_empty():
		event_id = source_event_id
	_apply_source_type_gates()

func set_source_type(value: String) -> void:
	source_type = value
	normalize_source_type()

func add_effect_tag(tag: String) -> void:
	if tag.is_empty() or effect_tags.has(tag):
		return
	effect_tags.append(tag)

func add_reaction_tag(tag: String) -> void:
	if tag.is_empty() or reaction_tags.has(tag):
		return
	reaction_tags.append(tag)

func get_all_reaction_tags() -> Array[String]:
	var result: Array[String] = []
	for tag in effect_tags:
		if not result.has(tag):
			result.append(tag)
	for tag in reaction_tags:
		if not result.has(tag):
			result.append(tag)
	return result

func duplicate_payload() -> DamagePayload:
	var copy: DamagePayload = DamagePayload.new()
	copy.amount = amount
	copy.damage_type = damage_type
	copy.source_id = source_id
	copy.source_owner = source_owner
	copy.caster = caster
	copy.target = target
	copy.faction_id = faction_id
	copy.ability_id = ability_id
	copy.source_type = source_type
	copy.source_event_id = source_event_id
	for tag in effect_tags:
		copy.effect_tags.append(tag)
	for tag in reaction_tags:
		copy.reaction_tags.append(tag)
	copy.can_trigger_secondary_effects = can_trigger_secondary_effects
	copy.can_trigger_boss_abilities = can_trigger_boss_abilities
	copy.can_trigger_reactions = can_trigger_reactions
	copy.can_trigger_weapon_upgrades = can_trigger_weapon_upgrades
	copy.can_apply_reaction_prerequisites = can_apply_reaction_prerequisites
	copy.reaction_consumed = reaction_consumed
	copy.chain_depth = chain_depth
	copy.event_id = event_id
	copy.is_periodic = is_periodic
	copy.is_auto_attack = is_auto_attack
	copy.is_ultimate = is_ultimate
	return copy

func _apply_source_type_gates() -> void:
	match source_type:
		SOURCE_DIRECT_ACTIVE_HIT:
			can_trigger_boss_abilities = true
			can_trigger_reactions = true
			can_trigger_weapon_upgrades = false
			can_apply_reaction_prerequisites = true
		SOURCE_ZONE_INITIAL_HIT:
			can_trigger_boss_abilities = true
			can_trigger_reactions = true
			can_trigger_weapon_upgrades = false
			can_apply_reaction_prerequisites = true
		SOURCE_ZONE_TICK:
			can_trigger_boss_abilities = false
			can_trigger_reactions = false
			can_trigger_weapon_upgrades = false
			can_apply_reaction_prerequisites = false
		SOURCE_DOT_TICK:
			can_trigger_boss_abilities = false
			can_trigger_reactions = false
			can_trigger_weapon_upgrades = false
			can_apply_reaction_prerequisites = false
		SOURCE_PHANTOM_ECHO:
			can_trigger_boss_abilities = false
			can_trigger_reactions = false
			can_trigger_weapon_upgrades = false
			can_apply_reaction_prerequisites = false
		SOURCE_BOSS_ABILITY_DAMAGE, SOURCE_WEAK_MOB_ABILITY_DAMAGE, SOURCE_BOSS_AI_ABILITY_DAMAGE, SOURCE_ALTAR_CARD_DAMAGE:
			can_trigger_boss_abilities = false
			can_trigger_reactions = false
			can_trigger_weapon_upgrades = false
			can_apply_reaction_prerequisites = false
		SOURCE_REACTION_DAMAGE:
			can_trigger_boss_abilities = false
			can_trigger_reactions = false
			can_trigger_weapon_upgrades = false
			can_apply_reaction_prerequisites = false
		SOURCE_FRIENDLY_FIRE:
			can_trigger_boss_abilities = false
			can_trigger_reactions = false
			can_trigger_weapon_upgrades = false
			can_apply_reaction_prerequisites = false
		SOURCE_AUTO_ATTACK_PRIMARY:
			can_trigger_boss_abilities = false
			can_trigger_reactions = false
			can_trigger_weapon_upgrades = true
			can_apply_reaction_prerequisites = false
			is_auto_attack = true
		SOURCE_AUTO_ATTACK_EXTRA_SHURIKEN, SOURCE_AUTO_ATTACK_BOUNCE:
			can_trigger_boss_abilities = false
			can_trigger_reactions = false
			can_trigger_weapon_upgrades = false
			can_apply_reaction_prerequisites = false
			is_auto_attack = true
		SOURCE_AUTO_ATTACK_PROC_BONUS:
			can_trigger_boss_abilities = false
			can_trigger_reactions = false
			can_trigger_weapon_upgrades = chain_depth <= 0
			can_apply_reaction_prerequisites = false
			is_auto_attack = true
		_:
			can_trigger_boss_abilities = false
			can_trigger_reactions = false
			can_trigger_weapon_upgrades = false
			can_apply_reaction_prerequisites = false
