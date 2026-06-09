extends CanvasLayer
class_name RouteChoicePanel

signal route_option_selected(card_index: int)

var _panel: Panel
var _list: VBoxContainer
var _route_context: Dictionary = {}
var _cards: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_base()

func show_route_choices(cards: Array, route_context: Dictionary = {}) -> void:
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
		var card: Dictionary = _cards[i]
		var button: Button = _build_route_button(card, i)
		if bool(card.get("disabled", false)):
			button.disabled = true
		else:
			button.pressed.connect(_on_route_button_pressed.bind(i))
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
	_panel.offset_left = -500.0
	_panel.offset_top = -250.0
	_panel.offset_right = 500.0
	_panel.offset_bottom = 250.0
	add_child(_panel)
	_list = VBoxContainer.new()
	_list.anchor_right = 1.0
	_list.anchor_bottom = 1.0
	_list.offset_left = 18.0
	_list.offset_top = 18.0
	_list.offset_right = -18.0
	_list.offset_bottom = -18.0
	_list.add_theme_constant_override("separation", 14)
	_panel.add_child(_list)

func _build_title() -> String:
	var floor_index: int = int(_route_context.get("floor_index", _route_context.get("current_floor", 1)))
	var room_index: int = int(_route_context.get("room_index_on_floor", _route_context.get("current_room_on_floor", 1)))
	var rooms_on_floor: int = int(_route_context.get("rooms_on_floor", 1))
	return "Выберите путь: этаж %d, комната %d/%d" % [floor_index, min(room_index, rooms_on_floor), rooms_on_floor]

func _build_route_button(card: Dictionary, index: int) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(285, 290)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.text = ""
	var root: VBoxContainer = VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 12.0
	root.offset_top = 12.0
	root.offset_right = -12.0
	root.offset_bottom = -12.0
	root.add_theme_constant_override("separation", 10)
	button.add_child(root)

	var label: Label = Label.new()
	label.text = str(card.get("route_label", _fallback_label(index)))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	root.add_child(label)

	var name_label: Label = Label.new()
	name_label.text = str(card.get("room_type_name", card.get("name", "Маршрут")))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 16)
	root.add_child(name_label)

	var desc: Label = Label.new()
	desc.text = _description_for_card(card)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(desc)

	var footer: Label = Label.new()
	footer.text = str(card.get("reward_preview", ""))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size", 12)
	root.add_child(footer)
	_ignore_mouse_recursive(root)
	return button

func _description_for_card(card: Dictionary) -> String:
	if bool(card.get("disabled", false)):
		return str(card.get("description", "Отключено до CORE Progression Rework."))
	if str(card.get("route_option_type", "")) == "optional_boss":
		return "%s\nЗаменяет обычную комнату. Победа закрывает окно пары; отказ открывает второй шанс." % _difficulty_ru(str(card.get("difficulty_band", "optional")))
	if str(card.get("route_option_type", "")) == "altar":
		return str(card.get("description", "Алтарь: жертва эссенции в обмен на Пепел Душ и 3 карточки."))
	var primary: String = str(card.get("primary_enemy_name", "противники"))
	var secondary: String = str(card.get("secondary_enemy_name", "поддержка"))
	var difficulty: String = str(card.get("difficulty_label", card.get("difficulty", "")))
	return "%s / %s\nСложность: %s" % [primary, secondary, difficulty]

func _difficulty_ru(value: String) -> String:
	match value.to_lower():
		"weak", "easy":
			return "Слабая"
		"medium", "normal":
			return "Средняя"
		"strong", "hard", "elite":
			return "Мощная"
		"optional":
			return "Дополнительный босс"
		_:
			return value

func _fallback_label(index: int) -> String:
	if index == 0:
		return "Комната A"
	if index == 1:
		return "Комната B"
	return "Алтарь"

func _on_route_button_pressed(card_index: int) -> void:
	hide_panel()
	route_option_selected.emit(card_index)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursive(child)
