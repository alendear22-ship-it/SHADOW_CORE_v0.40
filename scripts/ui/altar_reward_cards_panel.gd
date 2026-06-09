extends CanvasLayer
class_name AltarRewardCardsPanel

signal altar_card_selected(card_index: int)

var _panel: Panel
var _list: VBoxContainer
var _cards: Array = []
var _sacrifice_result: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_base()

func show_cards(cards: Array, sacrifice_result: Dictionary = {}) -> void:
	_cards = cards.duplicate(true)
	_sacrifice_result = sacrifice_result.duplicate(true)
	_clear_children(_list)
	var title: Label = Label.new()
	title.text = "Карты Алтаря"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	_list.add_child(title)

	var summary: Label = Label.new()
	summary.text = "Жертва: %d эссенции / +%d Пепла Душ" % [int(_sacrifice_result.get("spent_amount", 0)), int(_sacrifice_result.get("soul_ash_gain", 0))]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(summary)

	if _cards.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "Нет доступных карточек Алтаря для этой жертвы."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(empty_label)
		var close_button: Button = Button.new()
		close_button.text = "Закрыть"
		close_button.pressed.connect(hide_panel)
		_list.add_child(close_button)
		visible = true
		get_tree().paused = true
		return

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_child(row)
	for i in range(_cards.size()):
		var card: Dictionary = _cards[i]
		var button: Button = _build_card_button(card, i)
		button.pressed.connect(_on_card_pressed.bind(i))
		row.add_child(button)
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
	_panel.offset_left = -520.0
	_panel.offset_top = -280.0
	_panel.offset_right = 520.0
	_panel.offset_bottom = 280.0
	add_child(_panel)
	_list = VBoxContainer.new()
	_list.anchor_right = 1.0
	_list.anchor_bottom = 1.0
	_list.offset_left = 20.0
	_list.offset_top = 20.0
	_list.offset_right = -20.0
	_list.offset_bottom = -20.0
	_list.add_theme_constant_override("separation", 12)
	_panel.add_child(_list)

func _type_ru(card_type: String) -> String:
	match card_type:
		"weapon_upgrade":
			return "Усиление оружия"
		"stat_upgrade":
			return "Усиление характеристик"
		"boss_ability_upgrade":
			return "Усиление способности босса"
		"heal":
			return "Исцеление"
		_:
			return "Карточка Алтаря"

func _rarity_ru(card: Dictionary) -> String:
	var rarity: String = str(card.get("rarity", card.get("strength", "weak")))
	match rarity:
		"strong":
			return "Мощная"
		"medium":
			return "Средняя"
		_:
			return "Слабая"

func _safe_title(card: Dictionary) -> String:
	var title: String = str(card.get("title_ru", card.get("name_ru", "")))
	if title.is_empty():
		title = _type_ru(str(card.get("card_type", "")))
	return title

func _build_card_button(card: Dictionary, _index: int) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(300, 320)
	button.text = ""
	_apply_altar_card_style(button, card)
	var root: VBoxContainer = VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 12.0
	root.offset_top = 12.0
	root.offset_right = -12.0
	root.offset_bottom = -12.0
	root.add_theme_constant_override("separation", 9)
	button.add_child(root)
	var name_label: Label = Label.new()
	name_label.text = _safe_title(card)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	root.add_child(name_label)
	var type_label: Label = Label.new()
	type_label.text = "%s · %s" % [_type_ru(str(card.get("card_type", ""))), _rarity_ru(card)]
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(type_label)

	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(78, 62)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = _get_altar_card_icon(card, 64)
	root.add_child(icon_rect)
	var desc: Label = Label.new()
	desc.text = _build_description(card)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(desc)
	_ignore_mouse_recursive(root)
	return button

func _get_altar_card_icon(card: Dictionary, size: int = 64) -> Texture2D:
	var icon_path: String = str(card.get("icon_path", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var loaded: Texture2D = load(icon_path) as Texture2D
		if loaded != null:
			return loaded
	var factory: Node = get_node_or_null("/root/ProceduralIconFactory")
	if factory != null and factory.has_method("get_icon_for_altar_card"):
		var generated: Variant = factory.call("get_icon_for_altar_card", card, size)
		if generated is Texture2D:
			return generated
	return null


func _apply_altar_card_style(button: Button, card: Dictionary) -> void:
	var rarity: String = str(card.get("rarity", card.get("strength", "weak")))
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.045, 0.043, 0.060, 0.96)
	match rarity:
		"strong":
			normal.border_color = Color(0.95, 0.72, 0.22, 0.95)
		"medium":
			normal.border_color = Color(0.25, 0.70, 0.92, 0.90)
		_:
			normal.border_color = Color(0.38, 0.40, 0.46, 0.80)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.075, 0.070, 0.105, 0.98)
	hover.set_border_width_all(3)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)

func _payload_label(value: String) -> String:
	if value == "auto":
		return "автоматически"
	if value == "shadow_blade":
		return "Теневой клинок"
	return value

func _build_description(card: Dictionary) -> String:
	var base: String = str(card.get("description_ru", ""))
	var card_type: String = str(card.get("card_type", ""))
	match card_type:
		"stat_upgrade":
			return base + "\nЦель: " + _payload_label(str(card.get("upgrade_id", "auto")))
		"boss_ability_upgrade":
			return base + "\nСпособность босса: " + _payload_label(str(card.get("boss_ability_id", "auto")))
		"heal":
			return base + "\nИсцеление: %d%%" % int(card.get("heal_percent", 25))
		"weapon_upgrade":
			return base + "\nВетка оружия: %s\nУровень оружия: +1" % _payload_label(str(card.get("weapon_branch_id", "shadow_blade")))
		_:
			if base.is_empty():
				return "Эффект будет применён сразу после выбора."
			return base

func _on_card_pressed(card_index: int) -> void:
	hide_panel()
	altar_card_selected.emit(card_index)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursive(child)
