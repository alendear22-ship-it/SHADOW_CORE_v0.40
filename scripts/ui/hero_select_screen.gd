extends Control

var _selected_hero_id: String = "HERO_KAEL"
var _info_label: Label = null
var _start_button: Button = null
var _selected_is_playable: bool = true

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.anchor_left = 0.5
	root.anchor_top = 0.5
	root.anchor_right = 0.5
	root.anchor_bottom = 0.5
	root.offset_left = -420
	root.offset_top = -260
	root.offset_right = 420
	root.offset_bottom = 260
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var title: Label = Label.new()
	title.text = "Выбор героя"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)

	var heroes: Array = DataRegistry.get_items("heroes")
	for hero in heroes:
		var hero_id: String = str(hero.get("id", ""))
		var is_playable: bool = bool(hero.get("is_playable_in_mvp", false))
		var button: Button = Button.new()
		button.text = str(hero.get("name", hero_id)) + ("  [MVP]" if is_playable else "  [закрыт до подключения gameplay]")
		button.disabled = not is_playable
		button.pressed.connect(_select_hero.bind(hero_id))
		root.add_child(button)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_info_label)
	_select_hero(_selected_hero_id)

	_start_button = Button.new()
	_start_button.text = "Старт забега"
	_start_button.pressed.connect(func() -> void:
		if not _selected_is_playable:
			return
		RunManager.start_new_run(_selected_hero_id)
		get_tree().change_scene_to_file("res://scenes/main/run_scene.tscn")
	)
	root.add_child(_start_button)

	var back: Button = Button.new()
	back.text = "Назад"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))
	root.add_child(back)

func _select_hero(hero_id: String) -> void:
	var hero: Dictionary = DataRegistry.get_hero(hero_id)
	_selected_is_playable = bool(hero.get("is_playable_in_mvp", false))
	if not _selected_is_playable:
		return
	_selected_hero_id = hero_id
	if _info_label != null:
		_info_label.text = "%s\n%s\n%s" % [
			hero.get("name", hero_id),
			hero.get("role", ""),
			"Каэл полностью подключён в этом MVP. Бранн и Эйра оставлены в data как следующий production milestone, но заблокированы в UI, чтобы не создавать ложный playable scope."
		]
	if _start_button != null:
		_start_button.disabled = not _selected_is_playable
