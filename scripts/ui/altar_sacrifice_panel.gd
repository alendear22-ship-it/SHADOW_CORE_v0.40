extends CanvasLayer
class_name AltarSacrificePanel

signal sacrifice_confirmed(faction_or_mix, amount: int)
signal cancel_requested()

var _panel: Panel
var _list: VBoxContainer
var _amount_options: Array[int] = []
var _selected_amount: int = 0
var _floor_index: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_base()

func show_altar(floor_index: int, route_context: Dictionary = {}) -> void:
	_floor_index = floor_index
	_selected_amount = 0
	_rebuild(route_context)
	visible = true
	get_tree().paused = true

func hide_panel() -> void:
	visible = false
	get_tree().paused = false

func _build_base() -> void:
	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -430.0
	_panel.offset_top = -280.0
	_panel.offset_right = 430.0
	_panel.offset_bottom = 280.0
	add_child(_panel)
	_list = VBoxContainer.new()
	_list.anchor_right = 1.0
	_list.anchor_bottom = 1.0
	_list.offset_left = 24.0
	_list.offset_top = 24.0
	_list.offset_right = -24.0
	_list.offset_bottom = -24.0
	_list.add_theme_constant_override("separation", 12)
	_panel.add_child(_list)

func _rebuild(_route_context: Dictionary = {}) -> void:
	_clear_children(_list)
	var title: Label = Label.new()
	title.text = "Алтарь — этаж %d" % _floor_index
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	_list.add_child(title)

	var essence_label: Label = Label.new()
	essence_label.text = _build_essence_text()
	essence_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(essence_label)

	var warning: Label = Label.new()
	warning.text = "Жертва уменьшает текущую эссенцию и может снизить силу текущего билда. Алтарь доступен максимум 1 раз за этаж."
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(warning)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	_list.add_child(buttons)
	_build_amount_buttons(buttons)

	var preview: Label = Label.new()
	preview.name = "PreviewLabel"
	preview.text = _build_preview_text()
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(preview)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_list.add_child(row)
	var confirm_button: Button = Button.new()
	confirm_button.text = "Принести жертву"
	confirm_button.custom_minimum_size = Vector2(220, 48)
	confirm_button.disabled = _selected_amount <= 0
	confirm_button.pressed.connect(_on_confirm_pressed)
	row.add_child(confirm_button)
	var cancel_button: Button = Button.new()
	cancel_button.text = "Назад"
	cancel_button.custom_minimum_size = Vector2(160, 48)
	cancel_button.pressed.connect(_on_cancel_pressed)
	row.add_child(cancel_button)

func _build_amount_buttons(container: HBoxContainer) -> void:
	_amount_options.clear()
	var total: int = _get_total_essence()
	for amount in [20, 40, 80, 150]:
		if total >= amount:
			_amount_options.append(amount)
	if total >= 20 and not _amount_options.has(total):
		_amount_options.append(total)
	_amount_options.sort()
	if _selected_amount <= 0 and not _amount_options.is_empty():
		_selected_amount = _amount_options[0]
	for amount in _amount_options:
		var button: Button = Button.new()
		button.text = str(amount)
		button.toggle_mode = true
		button.button_pressed = amount == _selected_amount
		button.custom_minimum_size = Vector2(95, 42)
		button.pressed.connect(_on_amount_pressed.bind(amount))
		container.add_child(button)
	if _amount_options.is_empty():
		var label: Label = Label.new()
		label.text = "Нужно минимум 20 эссенции."
		container.add_child(label)

func _build_essence_text() -> String:
	var essence_bank: Node = get_node_or_null("/root/EssenceBank")
	if essence_bank == null:
		return "Банк эссенции недоступен."
	var total: int = int(essence_bank.call("get_total_amount")) if essence_bank.has_method("get_total_amount") else 0
	var by_faction = essence_bank.call("get_amounts_by_faction") if essence_bank.has_method("get_amounts_by_faction") else {}
	return "Текущая эссенция: %d\nПо фракциям: %s" % [total, JSON.stringify(by_faction)]

func _build_preview_text() -> String:
	if _selected_amount <= 0:
		return "Выберите размер жертвы."
	var altar_manager: Node = get_node_or_null("/root/AltarManager")
	var preview: Dictionary = altar_manager.call("get_sacrifice_preview", _selected_amount) if altar_manager != null and altar_manager.has_method("get_sacrifice_preview") else {}
	var chances: Dictionary = preview.get("chances", {}) if preview.get("chances", {}) is Dictionary else {}
	return "Жертва: %d эссенции → +%d Пепла Душ\nШансы: Слабая %d%% / Средняя %d%% / Мощная %d%%\nПотеря авто-усиления: %s" % [
		_selected_amount,
		int(preview.get("soul_ash_gain", int(floor(float(_selected_amount) / 5.0)))),
		int(chances.get("weak", 0)),
		int(chances.get("medium", 0)),
		int(chances.get("strong", 0)),
		_format_scaling_loss(preview.get("scaling_loss", {}))
	]

func _format_scaling_loss(raw_loss) -> String:
	if not (raw_loss is Dictionary):
		return "нет данных"
	var loss: Dictionary = raw_loss
	var parts: Array[String] = []
	for key in ["damage_multiplier", "move_speed_multiplier", "hp_multiplier", "dot_duration_multiplier", "ability_damage_multiplier", "ability_range_multiplier"]:
		var value: float = float(loss.get(key, 0.0))
		if value > 0.0001:
			parts.append("%s -%.2f%%" % [_short_scaling_key(key), value * 100.0])
	if parts.is_empty():
		return "нет"
	return "; ".join(parts)

func _short_scaling_key(key: String) -> String:
	match key:
		"damage_multiplier":
			return "урон"
		"move_speed_multiplier":
			return "скорость"
		"hp_multiplier":
			return "здоровье"
		"dot_duration_multiplier":
			return "длительность эффектов"
		"ability_damage_multiplier":
			return "урон способн."
		"ability_range_multiplier":
			return "радиус способн."
		_:
			return key

func _get_total_essence() -> int:
	var essence_bank: Node = get_node_or_null("/root/EssenceBank")
	if essence_bank != null and essence_bank.has_method("get_total_amount"):
		return int(essence_bank.call("get_total_amount"))
	return 0

func _on_amount_pressed(amount: int) -> void:
	_selected_amount = amount
	_rebuild({})

func _on_confirm_pressed() -> void:
	if _selected_amount <= 0:
		return
	hide_panel()
	sacrifice_confirmed.emit("mix", _selected_amount)

func _on_cancel_pressed() -> void:
	hide_panel()
	cancel_requested.emit()

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
