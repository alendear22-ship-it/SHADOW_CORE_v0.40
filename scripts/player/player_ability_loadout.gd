extends Node
class_name PlayerAbilityLoadout

var slot_to_ability_id: Dictionary = {}

func configure(hero_id: String) -> void:
    slot_to_ability_id.clear()
    for slot in ["active_1", "active_2", "ultimate", "passive", "auto_attack"]:
        var ability: Dictionary = DataRegistry.get_hero_ability(hero_id, slot)
        if not ability.is_empty():
            slot_to_ability_id[slot] = ability.get("id", "")

func get_ability_id(slot: String) -> String:
    return slot_to_ability_id.get(slot, "")
