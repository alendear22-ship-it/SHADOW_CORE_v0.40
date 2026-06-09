extends Node
class_name StatusEffectComponent

var _slows: Dictionary = {}
var _periodic: Dictionary = {}

func _process(delta: float) -> void:
    _update_slows(delta)
    _update_periodic(delta)

func apply_slow(status_id: String, slow_percent: float, duration: float) -> void:
    _slows[status_id] = {"percent": max(0.0, slow_percent), "time": max(0.0, duration)}

func get_speed_multiplier() -> float:
    var strongest: float = 0.0
    for key in _slows.keys():
        strongest = max(strongest, float(_slows[key].get("percent", 0.0)))
    return clamp(1.0 - strongest / 100.0, 0.15, 1.0)

func apply_periodic_damage(status_id: String, total_damage: float, duration: float, payload: DamagePayload, tick_interval: float = 0.5) -> void:
    if total_damage <= 0.0 or duration <= 0.0:
        return
    var ticks: int = max(1, int(ceil(duration / tick_interval)))
    _periodic[status_id] = {
        "remaining": duration,
        "tick_interval": tick_interval,
        "time_to_tick": tick_interval,
        "tick_damage": total_damage / float(ticks),
        "payload": payload
    }

func has_status(status_id: String) -> bool:
    return _slows.has(status_id) or _periodic.has(status_id)

func _update_slows(delta: float) -> void:
    var remove: Array = []
    for key in _slows.keys():
        _slows[key]["time"] = float(_slows[key].get("time", 0.0)) - delta
        if float(_slows[key]["time"]) <= 0.0:
            remove.append(key)
    for key in remove:
        _slows.erase(key)

func _update_periodic(delta: float) -> void:
    var remove: Array = []
    var host: Node = get_parent()
    for key in _periodic.keys():
        var data: Dictionary = _periodic[key]
        data["remaining"] = float(data.get("remaining", 0.0)) - delta
        data["time_to_tick"] = float(data.get("time_to_tick", 0.0)) - delta
        if float(data["time_to_tick"]) <= 0.0 and host != null and is_instance_valid(host):
            data["time_to_tick"] = float(data.get("tick_interval", 0.5))
            var payload: DamagePayload = data.get("payload", null) as DamagePayload
            if payload != null:
                var tick_payload: DamagePayload = payload.duplicate_payload()
                tick_payload.amount = float(data.get("tick_damage", 0.0))
                tick_payload.is_periodic = true
                tick_payload.source_type = DamagePayload.SOURCE_DOT_TICK
                tick_payload.source_event_id = ""
                tick_payload.event_id = ""
                tick_payload.chain_depth = payload.chain_depth + 1
                tick_payload.can_trigger_secondary_effects = false
                tick_payload.can_trigger_boss_abilities = false
                tick_payload.can_trigger_reactions = false
                tick_payload.can_apply_reaction_prerequisites = false
                tick_payload.normalize_source_type()
                CombatSystem.apply_damage(host, tick_payload)
        if float(data["remaining"]) <= 0.0:
            remove.append(key)
    for key in remove:
        _periodic.erase(key)
