extends CanvasLayer
class_name BossChoicePanel

signal boss_card_selected(card_index: int)

var _panel: Panel
var _list: VBoxContainer
var _detail_label: RichTextLabel
var _cards: Array = []
var _route_context: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_base()


func show_boss_choices(cards: Array, route_context: Dictionary = {}) -> void:
	_cards = cards.duplicate(true)
	_route_context = route_context.duplicate(true)
	_clear_children(_list)

	var title: Label = Label.new()
	title.text = _build_title()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	_list.add_child(title)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_child(row)

	for i in range(_cards.size()):
		row.add_child(_build_boss_card(_cards[i], i))

	_detail_label = RichTextLabel.new()
	_detail_label.custom_minimum_size = Vector2(0, 96)
	_detail_label.fit_content = true
	_detail_label.scroll_active = false
	_detail_label.bbcode_enabled = true
	_detail_label.text = "[center]Наведите курсор или нажмите на иконку способности, чтобы увидеть описание.[/center]"
	_list.add_child(_detail_label)

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
	_panel.offset_left = -540.0
	_panel.offset_top = -320.0
	_panel.offset_right = 540.0
	_panel.offset_bottom = 320.0
	add_child(_panel)

	_list = VBoxContainer.new()
	_list.anchor_right = 1.0
	_list.anchor_bottom = 1.0
	_list.offset_left = 18.0
	_list.offset_top = 18.0
	_list.offset_right = -18.0
	_list.offset_bottom = -18.0
	_list.add_theme_constant_override("separation", 12)
	_panel.add_child(_list)


func _build_title() -> String:
	var floor_index: int = int(_route_context.get("floor_index", 1))
	return "Выбор босса: этаж %d" % floor_index


func _build_boss_card(card: Dictionary, index: int) -> PanelContainer:
	var container: PanelContainer = PanelContainer.new()
	container.custom_minimum_size = Vector2(480, 420)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_boss_card_style(container, card)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(root)

	var marker: Label = Label.new()
	marker.text = _marker_ru(str(card.get("boss_choice_marker", "Отголосок" if bool(card.get("is_echo", false)) else "Новый")))
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", 16)
	root.add_child(marker)

	var portrait: TextureRect = TextureRect.new()
	portrait.custom_minimum_size = Vector2(0, 118)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path: String = str(card.get("portrait_path", ""))
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path) as Texture2D
	root.add_child(portrait)

	if portrait.texture == null:
		var placeholder: Label = Label.new()
		placeholder.text = "Портрет недоступен"
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.add_theme_font_size_override("font_size", 13)
		root.add_child(placeholder)

	var name_label: Label = Label.new()
	name_label.text = str(card.get("name_ru", card.get("name", "Босс")))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 20)
	root.add_child(name_label)

	var faction_label: Label = Label.new()
	faction_label.text = "%s · %s" % [str(card.get("faction_name", card.get("faction_id", "Фракция"))), str(card.get("difficulty_band", card.get("difficulty", "")))]
	faction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	faction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	faction_label.add_theme_font_size_override("font_size", 13)
	root.add_child(faction_label)

	var icon_row: HBoxContainer = HBoxContainer.new()
	icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_row.add_theme_constant_override("separation", 8)
	root.add_child(icon_row)
	var previews: Array = card.get("ability_previews", []) if card.get("ability_previews", []) is Array else []
	for ability in previews:
		if ability is Dictionary:
			icon_row.add_child(_build_ability_icon(ability))

	var select_button: Button = Button.new()
	select_button.text = "Выбрать босса"
	select_button.custom_minimum_size = Vector2(0, 42)
	select_button.pressed.connect(_on_select_pressed.bind(index))
	root.add_child(select_button)

	return container



func _apply_boss_card_style(container: PanelContainer, card: Dictionary) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.045, 0.070, 0.94)
	var faction_id: String = str(card.get("faction_id", ""))
	var border: Color = Color(0.54, 0.48, 0.86, 0.88)
	if faction_id == "FACTION_KRUSHERS":
		border = Color(0.95, 0.28, 0.24, 0.88)
	elif faction_id == "FACTION_NATURE":
		border = Color(0.30, 0.85, 0.50, 0.88)
	elif faction_id == "FACTION_ETHERS" or faction_id == "FACTION_ETHER":
		border = Color(0.56, 0.48, 1.00, 0.90)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	container.add_theme_stylebox_override("panel", style)

func _marker_ru(value: String) -> String:
	match value.to_lower():
		"boss echo", "echo", "отголосок":
			return "Отголосок босса"
		"optional", "optional boss":
			return "Дополнительный босс"
		"new", "новый":
			return "Новый босс"
		_:
			return value

func _build_ability_icon(ability: Dictionary) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(96, 64)
	button.text = _short_ability_name(str(ability.get("name_ru", ability.get("ability_id", "?"))))
	button.tooltip_text = _plain_ability_text(ability)
	button.icon = _get_boss_ability_icon(ability, 42)
	button.expand_icon = true
	button.mouse_entered.connect(_show_ability_details.bind(ability))
	button.focus_entered.connect(_show_ability_details.bind(ability))
	button.pressed.connect(_show_ability_details.bind(ability))
	return button

func _get_boss_ability_icon(ability: Dictionary, size: int = 64) -> Texture2D:
	var icon_path: String = str(ability.get("icon_path", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var loaded: Texture2D = load(icon_path) as Texture2D
		if loaded != null:
			return loaded
	var factory: Node = get_node_or_null("/root/ProceduralIconFactory")
	if factory != null and factory.has_method("get_icon_for_boss_ability"):
		var generated: Variant = factory.call("get_icon_for_boss_ability", ability, size)
		if generated is Texture2D:
			return generated
	return null


func _show_ability_details(ability: Dictionary) -> void:
	if _detail_label == null:
		return
	var current_level: int = int(ability.get("current_level", 0))
	var next_level: int = int(ability.get("next_level", 0))
	var next_text: String = str(ability.get("next_description_ru", ""))
	var tags: Array = ability.get("tags", []) if ability.get("tags", []) is Array else []
	_detail_label.text = "[b]%s[/b]\nТекущий уровень: %d · Следующий: %s\n%s\n[i]%s[/i]" % [
		str(ability.get("name_ru", ability.get("ability_id", "Способность"))),
		current_level,
		str(next_level) if next_level > 0 else "макс.",
		next_text,
		", ".join(_stringify_array(tags))
	]


func _plain_ability_text(ability: Dictionary) -> String:
	return "%s\nТекущий уровень: %d\nСледующий уровень: %s\n%s" % [
		str(ability.get("name_ru", ability.get("ability_id", "Способность"))),
		int(ability.get("current_level", 0)),
		str(int(ability.get("next_level", 0))) if int(ability.get("next_level", 0)) > 0 else "макс.",
		str(ability.get("next_description_ru", ""))
	]


func _short_ability_name(value: String) -> String:
	if value.length() <= 14:
		return value
	return value.substr(0, 12) + "…"


func _stringify_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result


func _on_select_pressed(card_index: int) -> void:
	hide_panel()
	boss_card_selected.emit(card_index)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
