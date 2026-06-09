extends CanvasLayer
class_name BossRewardPanel

signal continue_requested()
signal reward_declined()
signal boss_ability_reward_selected(boss_ability_id: String)

var _panel: Panel
var _list: VBoxContainer
var _reward_data: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_base()

func show_reward(reward_data: Dictionary = {}) -> void:
	_reward_data = reward_data.duplicate(true)
	_clear_children(_list)
	var title: Label = Label.new()
	title.text = _ui_text(str(_reward_data.get("title", "Награда босса")))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 27)
	_list.add_child(title)

	var name_label: Label = Label.new()
	name_label.text = str(_reward_data.get("boss_name", _reward_data.get("boss_id", "Неизвестный босс")))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	_list.add_child(name_label)

	var marker: Label = Label.new()
	marker.text = _ui_text(str(_reward_data.get("marker", "Босс побеждён")))
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", 15)
	_list.add_child(marker)

	var body: Label = Label.new()
	body.text = _ui_text(str(_reward_data.get("description", "Выберите способность босса или откажитесь от награды.")))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(body)

	var options: Array = _reward_data.get("reward_options", []) if _reward_data.get("reward_options", []) is Array else []
	if not options.is_empty():
		_build_boss_ability_options(options)
	else:
		_build_default_continue_row()
	visible = true
	get_tree().paused = true

func hide_panel() -> void:
	visible = false
	get_tree().paused = false

func _ui_text(value: String) -> String:
	match value:
		"Награда босса":
			return "Награда босса"
		"Награда Отголоска":
			return "Награда Отголоска босса"
		"Награда дополнительного босса":
			return "Награда дополнительного босса"
		"Босс побеждён", "Обязательный босс побеждён":
			return "Босс побеждён"
		"Отголосок босса побеждён":
			return "Отголосок босса побеждён"
		"Дополнительный босс побеждён":
			return "Дополнительный босс побеждён"
		_:
			var normalized: String = value
			normalized = normalized.replace("MAX", "МАКС.")
			normalized = normalized.replace("LOCKED", "ЗАКРЫТО")
			normalized = normalized.replace("META-ЗАКРЫТО", "МЕТА-ЗАКРЫТО")
			return normalized

func _build_boss_ability_options(options: Array) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_list.add_child(row)
	for option_value in options:
		if not (option_value is Dictionary):
			continue
		var option: Dictionary = option_value
		row.add_child(_make_reward_card(option))
	_build_decline_row()

func _make_reward_card(option: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(275, 320)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_reward_card_style(panel, option)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(78, 62)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = _get_boss_ability_icon(option, 64)
	box.add_child(icon_rect)

	var name_label: Label = Label.new()
	name_label.text = str(option.get("name_ru", option.get("boss_ability_id", "Способность")))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 16)
	box.add_child(name_label)

	var level_label: Label = Label.new()
	level_label.text = _build_level_line(option)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(level_label)

	var state_label: Label = Label.new()
	state_label.text = _build_state_line(option)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(state_label)

	var current_label: Label = Label.new()
	current_label.text = "Сейчас: " + _short_text(str(option.get("current_description_ru", "Не открыта.")), 120)
	current_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(current_label)

	var next_label: Label = Label.new()
	next_label.text = "Дальше: " + _short_text(str(option.get("next_description_ru", "Максимальный уровень")), 120)
	next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(next_label)

	var button: Button = Button.new()
	button.text = _ui_text(str(option.get("button_label", _button_label(option))))
	button.custom_minimum_size = Vector2(220, 46)
	button.disabled = bool(option.get("disabled", false)) or str(option.get("state", "AVAILABLE")) in ["MAX", "LOCKED"]
	button.tooltip_text = _build_tooltip(option)
	if not button.disabled:
		button.pressed.connect(Callable(self, "_on_boss_ability_option_pressed").bind(str(option.get("boss_ability_id", option.get("id", "")))))
	box.add_child(button)
	return panel

func _apply_reward_card_style(panel: PanelContainer, option: Dictionary) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.043, 0.065, 0.96)
	var faction_id: String = str(option.get("faction_id", ""))
	var border: Color = Color(0.54, 0.48, 0.86, 0.88)
	if faction_id == "FACTION_KRUSHERS":
		border = Color(0.95, 0.28, 0.24, 0.88)
	elif faction_id == "FACTION_NATURE":
		border = Color(0.30, 0.85, 0.50, 0.88)
	elif faction_id == "FACTION_ETHERS" or faction_id == "FACTION_ETHER":
		border = Color(0.56, 0.48, 1.00, 0.90)
	if str(option.get("state", "")) == "MAX":
		border = Color(0.95, 0.72, 0.22, 0.95)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)

func _get_boss_ability_icon(option: Dictionary, size: int = 64) -> Texture2D:
	var icon_path: String = str(option.get("icon_path", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var loaded: Texture2D = load(icon_path) as Texture2D
		if loaded != null:
			return loaded
	var factory: Node = get_node_or_null("/root/ProceduralIconFactory")
	if factory != null and factory.has_method("get_icon_for_boss_ability"):
		var generated: Variant = factory.call("get_icon_for_boss_ability", option, size)
		if generated is Texture2D:
			return generated
	return null

func _build_level_line(option: Dictionary) -> String:
	var current_level: int = int(option.get("current_level", 0))
	var next_level: int = int(option.get("next_level", 0))
	if bool(option.get("is_max_level", false)) or str(option.get("state", "")) == "MAX":
		return "Уровень: 3 / 3"
	if next_level > 0:
		return "Уровень: " + str(current_level) + " → " + str(next_level)
	return "Уровень: " + str(current_level) + " / 3"

func _build_state_line(option: Dictionary) -> String:
	if bool(option.get("meta_locked", false)):
		return "МЕТА-ЗАКРЫТО"
	if bool(option.get("locked", false)):
		return "ЗАКРЫТО"
	var state: String = str(option.get("state", "AVAILABLE"))
	if state == "MAX":
		return "МАКС."
	var action: String = str(option.get("action", option.get("reward_action", "unlock")))
	if action == "upgrade":
		return "Открыта · улучшение"
	return "Закрыта · открытие"

func _button_label(option: Dictionary) -> String:
	var state: String = str(option.get("state", "AVAILABLE"))
	if state == "MAX":
		return "МАКС."
	if state == "LOCKED":
		return "Недоступно"
	var action: String = str(option.get("action", option.get("reward_action", "unlock")))
	return "Улучшить" if action == "upgrade" else "Открыть"

func _build_tooltip(option: Dictionary) -> String:
	return "%s\n%s\nТекущий: %s\nСледующий: %s" % [
		str(option.get("name_ru", option.get("boss_ability_id", "Способность"))),
		str(option.get("visual_summary_ru", "Визуал: базовый эффект")),
		str(option.get("current_description_ru", "Не открыта.")),
		str(option.get("next_description_ru", "Максимальный уровень"))
	]

func _build_default_continue_row() -> void:
	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)
	_list.add_child(button_row)
	var continue_button: Button = Button.new()
	continue_button.text = "Принять / продолжить"
	continue_button.custom_minimum_size = Vector2(220, 52)
	continue_button.pressed.connect(_on_continue_pressed)
	button_row.add_child(continue_button)
	if bool(_reward_data.get("can_decline_for_soul_ash", true)):
		var decline_button: Button = Button.new()
		decline_button.text = "Отказаться: +" + str(int(_reward_data.get("decline_reward_soul_ash", 5))) + " Пепла Душ"
		decline_button.custom_minimum_size = Vector2(250, 52)
		decline_button.pressed.connect(_on_decline_pressed)
		button_row.add_child(decline_button)

func _build_decline_row() -> void:
	if not bool(_reward_data.get("can_decline_for_soul_ash", true)):
		return
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_list.add_child(row)
	var decline_button: Button = Button.new()
	decline_button.text = "Отказаться: +" + str(int(_reward_data.get("decline_reward_soul_ash", 5))) + " Пепла Душ"
	decline_button.custom_minimum_size = Vector2(270, 50)
	decline_button.pressed.connect(_on_decline_pressed)
	row.add_child(decline_button)

func _build_base() -> void:
	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -520.0
	_panel.offset_top = -340.0
	_panel.offset_right = 520.0
	_panel.offset_bottom = 340.0
	add_child(_panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	margin.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

func _on_boss_ability_option_pressed(boss_ability_id: String) -> void:
	if boss_ability_id.is_empty():
		return
	hide_panel()
	boss_ability_reward_selected.emit(boss_ability_id)

func _on_continue_pressed() -> void:
	hide_panel()
	continue_requested.emit()

func _on_decline_pressed() -> void:
	hide_panel()
	reward_declined.emit()

func _short_text(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, max(0, limit - 3)) + "..."

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
