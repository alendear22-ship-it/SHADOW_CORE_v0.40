extends CanvasLayer
class_name RunSummaryPanel

signal menu_requested()
signal new_run_requested()

var _panel: Panel
var _list: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_base()

func show_summary(summary: Dictionary) -> void:
	_clear_children(_list)
	var title: Label = Label.new()
	title.text = "Итоги забега"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	_list.add_child(title)

	var result_label: Label = Label.new()
	result_label.text = "Победа над Моргратом" if bool(summary.get("morgath_defeated", false)) else str(summary.get("result_text", "Забег завершён"))
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 20)
	_list.add_child(result_label)

	var body: Label = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = _build_body(summary)
	_list.add_child(body)

	_build_opened_ability_icons(summary)
	_build_unlock_preview(summary)
	_build_buttons()
	visible = true
	get_tree().paused = true

func hide_panel() -> void:
	visible = false
	get_tree().paused = false

func _build_body(summary: Dictionary) -> String:
	var bosses: Array = summary.get("bosses_defeated", []) if summary.get("bosses_defeated", []) is Array else []
	var unlocked: Array = summary.get("opened_boss_abilities", []) if summary.get("opened_boss_abilities", []) is Array else []
	var altar_rewards: Array = summary.get("used_altar_rewards", []) if summary.get("used_altar_rewards", []) is Array else []
	var resources: Dictionary = summary.get("final_resources", {}) if summary.get("final_resources", {}) is Dictionary else {}
	var lines: Array[String] = []
	lines.append("Побеждённые боссы: " + _join_values(bosses))
	lines.append("Открытые/улучшенные способности: " + _join_values(unlocked))
	lines.append("Использованные награды Алтаря: " + _summarize_altar_rewards(altar_rewards))
	lines.append("Итоговые ресурсы: Пепел Душ " + str(int(resources.get("soul_ash", summary.get("soul_ash", 0)))) + ", эссенция " + str(int(resources.get("essence_total", summary.get("essence_total", 0)))))
	lines.append("Получено Ядро эссенции: +" + str(int(summary.get("core_essence_earned", 0))))
	lines.append("Всего Ядра эссенции: " + str(int(summary.get("core_essence_total", 0))))
	lines.append("Финальная подготовка: " + str(summary.get("final_preparation_choice", "—")))
	lines.append("Прямой постоянный рост базовых статов: нет")
	return "\n".join(lines)

func _join_values(values: Array) -> String:
	if values.is_empty():
		return "—"
	var parts: Array[String] = []
	for value in values:
		parts.append(str(value))
	return ", ".join(parts)

func _summarize_altar_rewards(values: Array) -> String:
	if values.is_empty():
		return "—"
	var parts: Array[String] = []
	for value in values:
		if value is Dictionary:
			var entry: Dictionary = value
			var card: Dictionary = entry.get("card", {}) if entry.get("card", {}) is Dictionary else {}
			parts.append(str(card.get("card_type", card.get("id", "altar_card"))))
		else:
			parts.append(str(value))
	return ", ".join(parts)


func _build_opened_ability_icons(summary: Dictionary) -> void:
	var opened: Array = summary.get("opened_boss_abilities", []) if summary.get("opened_boss_abilities", []) is Array else []
	if opened.is_empty():
		return
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_list.add_child(row)
	for value in opened.slice(0, min(8, opened.size())):
		var ability_id: String = str(value.get("boss_ability_id", value.get("id", ""))) if value is Dictionary else str(value)
		var ability_data: Dictionary = _get_boss_ability_data(ability_id)
		if ability_data.is_empty():
			ability_data = {"id": ability_id, "boss_ability_id": ability_id}
		var icon: TextureRect = TextureRect.new()
		icon.custom_minimum_size = Vector2(38, 38)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = str(ability_data.get("name_ru", ability_id))
		icon.texture = _get_boss_ability_icon(ability_data, 36)
		row.add_child(icon)

func _get_boss_ability_data(ability_id: String) -> Dictionary:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_ability"):
		var data: Variant = registry.call("get_boss_ability", ability_id)
		if data is Dictionary:
			return data
	return {}

func _get_boss_ability_icon(ability_data: Dictionary, size: int = 64) -> Texture2D:
	var factory: Node = get_node_or_null("/root/ProceduralIconFactory")
	if factory != null and factory.has_method("get_icon_for_boss_ability"):
		var generated: Variant = factory.call("get_icon_for_boss_ability", ability_data, size)
		if generated is Texture2D:
			return generated
	return null

func _build_unlock_preview(summary: Dictionary) -> void:
	var unlocks: Array = summary.get("possible_meta_unlocks", []) if summary.get("possible_meta_unlocks", []) is Array else []
	var label: Label = Label.new()
	label.text = "Возможные мета-открытия:"
	label.add_theme_font_size_override("font_size", 18)
	_list.add_child(label)
	if unlocks.is_empty():
		var empty: Label = Label.new()
		empty.text = "— нет доступных записей мета-открытий"
		_list.add_child(empty)
		return
	for unlock_value in unlocks.slice(0, min(5, unlocks.size())):
		if not (unlock_value is Dictionary):
			continue
		var unlock: Dictionary = unlock_value
		var row: Label = Label.new()
		row.text = "• %s · стоимость %d · %s" % [str(unlock.get("name_ru", unlock.get("id", "открытие"))), int(unlock.get("cost", 0)), "доступно" if bool(unlock.get("enabled", false)) else "запланировано"]
		_list.add_child(row)

func _build_buttons() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_list.add_child(row)
	var menu_button: Button = Button.new()
	menu_button.text = "В меню"
	menu_button.custom_minimum_size = Vector2(180, 48)
	menu_button.pressed.connect(func() -> void:
		hide_panel()
		menu_requested.emit()
	)
	row.add_child(menu_button)
	var new_run_button: Button = Button.new()
	new_run_button.text = "Новый забег"
	new_run_button.custom_minimum_size = Vector2(180, 48)
	new_run_button.pressed.connect(func() -> void:
		hide_panel()
		new_run_requested.emit()
	)
	row.add_child(new_run_button)

func _build_base() -> void:
	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -430.0
	_panel.offset_top = -310.0
	_panel.offset_right = 430.0
	_panel.offset_bottom = 310.0
	add_child(_panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	margin.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
