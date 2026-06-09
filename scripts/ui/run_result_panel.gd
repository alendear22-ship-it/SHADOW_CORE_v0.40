extends CanvasLayer
class_name RunResultPanel

signal menu_requested()
signal new_run_requested()

var _panel: Panel
var _list: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_base()

func show_result(result: Dictionary) -> void:
	for child in _list.get_children():
		child.queue_free()
	var title: Label = Label.new()
	title.text = "ПОБЕДА" if bool(result.get("victory", false)) else "ПОРАЖЕНИЕ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	_list.add_child(title)

	var stats: Label = Label.new()
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.text = "Время: %s\nУбито врагов: %d\nПолучено эссенции: %d\nПобеждённые боссы: %s\nПепел Душ: %d" % [
		_format_time(int(result.get("time_seconds", 0))),
		int(result.get("enemies_killed", 0)),
		int(result.get("essence_total", 0)),
		", ".join(result.get("bosses_defeated", [])),
		int(result.get("soul_ash", 0))
	]
	_list.add_child(stats)

	var menu_button: Button = Button.new()
	menu_button.text = "В меню"
	menu_button.pressed.connect(func() -> void:
		visible = false
		get_tree().paused = false
		menu_requested.emit()
	)
	_list.add_child(menu_button)

	var new_run_button: Button = Button.new()
	new_run_button.text = "Новый забег"
	new_run_button.pressed.connect(func() -> void:
		visible = false
		get_tree().paused = false
		new_run_requested.emit()
	)
	_list.add_child(new_run_button)

	visible = true
	get_tree().paused = true

func _build_base() -> void:
	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -360.0
	_panel.offset_top = -230.0
	_panel.offset_right = 360.0
	_panel.offset_bottom = 230.0
	add_child(_panel)
	_list = VBoxContainer.new()
	_list.anchor_right = 1.0
	_list.anchor_bottom = 1.0
	_list.offset_left = 20.0
	_list.offset_top = 20.0
	_list.offset_right = -20.0
	_list.offset_bottom = -20.0
	_list.add_theme_constant_override("separation", 14)
	_panel.add_child(_list)

func _format_time(total_seconds: int) -> String:
	var minutes: int = int(total_seconds / 60)
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
