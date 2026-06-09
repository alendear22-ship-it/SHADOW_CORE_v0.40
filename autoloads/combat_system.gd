extends Node

signal damage_applied(payload: DamagePayload)

func apply_damage(target: Node, payload: DamagePayload) -> void:
	if target == null or not is_instance_valid(target):
		return
	if payload == null or payload.amount <= 0.0:
		return
	_validate_and_prepare_payload(target, payload)
	var applied: bool = false
	if target.has_method("apply_damage"):
		target.apply_damage(payload)
		applied = true
	else:
		var health: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			health.damage(payload.amount, payload)
			applied = true
	if applied:
		damage_applied.emit(payload)

func build_payload(amount: float, damage_type: String, source_id: String, faction_id: String, ability_id: String, source_type: String = "") -> DamagePayload:
	var payload: DamagePayload = DamagePayload.new()
	payload.amount = amount
	payload.damage_type = damage_type
	payload.source_id = source_id
	payload.faction_id = faction_id
	payload.ability_id = ability_id
	payload.source_type = source_type if not source_type.is_empty() else DamagePayload.SOURCE_DIRECT_ACTIVE_HIT
	payload.normalize_source_type()
	return payload

func reset_run() -> void:
	# transient combat event dispatcher. No run-local reset required.
	pass

func get_state() -> Dictionary:
	return {"stateless": true, "note": "transient combat event dispatcher"}

func set_state(state: Variant = {}) -> void:
	# transient combat event dispatcher. Incoming state intentionally ignored.
	pass

func _validate_and_prepare_payload(target: Node, payload: DamagePayload) -> void:
	if payload.source_type.is_empty() or not DamagePayload.KNOWN_SOURCE_TYPES.has(payload.source_type):
		push_warning("CombatSystem.apply_damage: invalid or missing source_type. Fallback to DIRECT_ACTIVE_HIT for debug safety.")
		payload.source_type = DamagePayload.SOURCE_DIRECT_ACTIVE_HIT
	payload.target = target
	if payload.caster == null:
		payload.caster = payload.source_owner
	payload.normalize_source_type()

func is_source_type_known(source_type: String) -> bool:
	return DamagePayload.KNOWN_SOURCE_TYPES.has(source_type)
