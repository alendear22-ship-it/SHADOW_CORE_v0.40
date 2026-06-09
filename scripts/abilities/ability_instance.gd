extends RefCounted
class_name AbilityInstance

var data: Dictionary = {}
var cooldown_remaining: float = 0.0

func setup(ability_data: Dictionary) -> void:
    data = ability_data.duplicate(true)
    cooldown_remaining = 0.0
