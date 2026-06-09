extends Node

signal soul_ash_changed(amount: int, reason: String)

var _amount: int = 0
var _history: Array[Dictionary] = []

func reset_run() -> void:
	_amount = 0
	_history.clear()
	_emit_changed("reset_run")

func get_amount() -> int:
	return _amount

func add(amount: int, reason: String = "") -> void:
	var value: int = max(0, amount)
	if value <= 0:
		return
	_amount += value
	_history.append({
		"type": "add",
		"amount": value,
		"reason": reason,
		"total": _amount
	})
	_emit_changed(reason)

func spend(amount: int, reason: String = "") -> bool:
	var value: int = max(0, amount)
	if value <= 0:
		return true
	if _amount < value:
		return false
	_amount -= value
	_history.append({
		"type": "spend",
		"amount": value,
		"reason": reason,
		"total": _amount
	})
	_emit_changed(reason)
	return true

func can_afford(amount: int) -> bool:
	return _amount >= max(0, amount)

func get_state() -> Dictionary:
	return {
		"amount": _amount,
		"history": _history.duplicate(true)
	}

func set_state(state: Variant) -> void:
	if not (state is Dictionary):
		_amount = 0
		_history.clear()
		_emit_changed("set_state_invalid")
		return
	var data: Dictionary = state
	_amount = max(0, int(data.get("amount", data.get("soul_ash", 0))))
	_history.clear()
	var source_history: Variant = data.get("history", [])
	if source_history is Array:
		for entry in source_history:
			if entry is Dictionary:
				_history.append(entry.duplicate(true))
	_emit_changed("set_state")

func _emit_changed(reason: String = "") -> void:
	soul_ash_changed.emit(_amount, reason)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("run_resource_changed"):
		bus.emit_signal("run_resource_changed")
