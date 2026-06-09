extends CanvasLayer
class_name FinalPreparationPanel

signal preparation_selected(choice_id: String)

var _panel: Panel
var _list: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_base()

func show_choices(choices: Array) -> void:
	_clear_children(_list)
	var title: Label = Label.new()
	title.text = "Финальная подготовка"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	_list.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Выберите одну короткую подготовку перед Моргратом."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(subtitle)

	for choice_value in choices:
		if not (choice_value is Dictionary):
			continue
		var choice: Dictionary = choice_value
		var button: Button = Button.new()
		button.text = "%s\n%s" % [str(choice.get("name_ru", choice.get("id", "Подготовка"))), str(choice.get("description_ru", ""))]
		button.custom_minimum_size = Vector2(520, 72)
		button.disabled = bool(choice.get("disabled", false))
		button.pressed.connect(_on_choice_pressed.bind(str(choice.get("id", ""))))
		_list.add_child(button)

	visible = true
	get_tree().paused = true

func hide_panel() -> void:
	visible = false
	get_tree().paused = false

func _on_choice_pressed(choice_id: String) -> void:
	if choice_id.is_empty():
		return
	hide_panel()
	preparation_selected.emit(choice_id)

func _build_base() -> void:
	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -360.0
	_panel.offset_top = -240.0
	_panel.offset_right = 360.0
	_panel.offset_bottom = 240.0
	add_child(_panel)
	_list = VBoxContainer.new()
	_list.anchor_right = 1.0
	_list.anchor_bottom = 1.0
	_list.offset_left = 24.0
	_list.offset_top = 24.0
	_list.offset_right = -24.0
	_list.offset_bottom = -24.0
	_list.add_theme_constant_override("separation", 14)
	_panel.add_child(_list)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
