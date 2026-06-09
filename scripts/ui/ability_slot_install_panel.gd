extends CanvasLayer
class_name AbilitySlotInstallPanel

signal install_confirmed(active_ability_id: String, slot_index: int, boss_ability_id: String)
signal install_refused(boss_ability_id: String)

var _panel: Panel
var _list: VBoxContainer
var _boss_ability_id: String = ""
var _reward_data: Dictionary = {}
var _pending_replace: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_base()

func show_install(boss_ability_id: String, reward_data: Dictionary = {}) -> void:
	_boss_ability_id = boss_ability_id
	_reward_data = reward_data.duplicate(true)
	_pending_replace.clear()
	_clear_children(_list)
	var title: Label = Label.new()
	title.text = "Установить способность босса"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	_list.add_child(title)

	var ability_data: Dictionary = _get_boss_ability_data(boss_ability_id)
	var ability_title: Label = Label.new()
	ability_title.text = str(ability_data.get("name_ru", boss_ability_id))
	ability_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ability_title.add_theme_font_size_override("font_size", 19)
	_list.add_child(ability_title)

	var ability_icon: TextureRect = TextureRect.new()
	ability_icon.custom_minimum_size = Vector2(72, 60)
	ability_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ability_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ability_icon.texture = _get_boss_ability_icon(ability_data, 64)
	_list.add_child(ability_icon)

	var desc: Label = Label.new()
	desc.text = _build_ability_description(boss_ability_id, ability_data)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(desc)

	var hint: Label = Label.new()
	hint.text = "Выберите активную способность. Эффект будет работать только в выбранной способности. Свободное переставление запрещено."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(hint)

	_build_active_ability_rows()
	var refuse_button: Button = Button.new()
	refuse_button.text = "Отказаться: +5 Пепла Душ"
	refuse_button.custom_minimum_size = Vector2(240, 44)
	refuse_button.pressed.connect(_on_refuse_pressed)
	_list.add_child(refuse_button)
	visible = true
	get_tree().paused = true

func hide_panel() -> void:
	visible = false
	get_tree().paused = false

func _build_active_ability_rows() -> void:
	var slot_manager: Node = get_node_or_null("/root/AbilitySlotManager")
	var active_ids: Array = []
	if slot_manager != null and slot_manager.has_method("get_active_ability_ids"):
		var raw_ids: Variant = slot_manager.call("get_active_ability_ids")
		if raw_ids is Array:
			active_ids = raw_ids
	if active_ids.is_empty():
		active_ids = ["ABILITY_KAEL_ACTIVE_1", "ABILITY_KAEL_ACTIVE_2", "ABILITY_KAEL_ULTIMATE"]
	for active_id_value in active_ids:
		var active_id: String = str(active_id_value)
		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		_list.add_child(box)
		var label: Label = Label.new()
		label.text = _get_active_label(active_id)
		label.add_theme_font_size_override("font_size", 16)
		box.add_child(label)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var slots: Array = _get_slots(active_id)
		var has_free: bool = _has_free_slot(slots)
		for i in range(3):
			var slot_entry: Dictionary = {}
			if i < slots.size() and slots[i] is Dictionary:
				slot_entry = slots[i]
			var installed_id: String = str(slot_entry.get("boss_ability_id", ""))
			var installed_level: int = int(slot_entry.get("level", 0))
			var button: Button = Button.new()
			button.custom_minimum_size = Vector2(185, 52)
			if installed_id.is_empty():
				button.text = "Слот " + str(i + 1) + ": свободен"
				button.disabled = false
				_apply_slot_button_style(button, false)
				button.pressed.connect(_make_install_callable(active_id, -1))
			else:
				button.text = "Слот " + str(i + 1) + ": " + _get_boss_ability_name(installed_id) + "\nур. " + str(installed_level)
				var installed_data: Dictionary = _get_boss_ability_data(installed_id)
				button.icon = _get_boss_ability_icon(installed_data, 36)
				button.expand_icon = true
				_apply_slot_button_style(button, true)
				if has_free:
					button.disabled = true
				else:
					button.text += " · заменить"
					button.disabled = false
					button.pressed.connect(_make_install_callable(active_id, i))
			row.add_child(button)


func _apply_slot_button_style(button: Button, occupied: bool) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.040, 0.040, 0.060, 0.92)
	style.border_color = Color(0.52, 0.48, 0.82, 0.90) if occupied else Color(0.32, 0.34, 0.42, 0.62)
	style.set_border_width_all(2 if occupied else 1)
	style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.070, 0.065, 0.100, 0.98)
	hover.set_border_width_all(3)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)

func _make_install_callable(active_ability_id: String, slot_index: int) -> Callable:
	return Callable(self, "_on_install_pressed").bind(active_ability_id, slot_index)

func _on_install_pressed(active_ability_id: String, slot_index: int) -> void:
	if slot_index >= 0:
		_show_replace_confirmation(active_ability_id, slot_index)
		return
	hide_panel()
	install_confirmed.emit(active_ability_id, slot_index, _boss_ability_id)

func _show_replace_confirmation(active_ability_id: String, slot_index: int) -> void:
	_pending_replace = {"active_ability_id": active_ability_id, "slot_index": slot_index}
	var slots: Array = _get_slots(active_ability_id)
	var old_id: String = ""
	if slot_index >= 0 and slot_index < slots.size() and slots[slot_index] is Dictionary:
		var old_entry: Dictionary = slots[slot_index]
		old_id = str(old_entry.get("boss_ability_id", ""))
	var label: Label = Label.new()
	label.text = "Заменить " + _get_boss_ability_name(old_id) + " на " + _get_boss_ability_name(_boss_ability_id) + "?"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(label)
	var confirm_button: Button = Button.new()
	confirm_button.text = "Заменить"
	confirm_button.custom_minimum_size = Vector2(240, 44)
	confirm_button.pressed.connect(_confirm_replace_pressed)
	_list.add_child(confirm_button)

func _confirm_replace_pressed() -> void:
	if _pending_replace.is_empty():
		return
	var active_ability_id: String = str(_pending_replace.get("active_ability_id", ""))
	var slot_index: int = int(_pending_replace.get("slot_index", -1))
	_pending_replace.clear()
	hide_panel()
	install_confirmed.emit(active_ability_id, slot_index, _boss_ability_id)

func _on_refuse_pressed() -> void:
	hide_panel()
	install_refused.emit(_boss_ability_id)

func _get_slots(active_ability_id: String) -> Array:
	var slot_manager: Node = get_node_or_null("/root/AbilitySlotManager")
	if slot_manager != null and slot_manager.has_method("get_slots"):
		var slots: Variant = slot_manager.call("get_slots", active_ability_id)
		if slots is Array:
			return slots
	return ["", "", ""]

func _has_free_slot(slots: Array) -> bool:
	for value in slots:
		if not (value is Dictionary):
			return true
		if str(value.get("boss_ability_id", "")).is_empty():
			return true
	return false

func _get_active_label(active_ability_id: String) -> String:
	var slot_manager: Node = get_node_or_null("/root/AbilitySlotManager")
	if slot_manager != null and slot_manager.has_method("get_active_ability_label"):
		return str(slot_manager.call("get_active_ability_label", active_ability_id))
	return active_ability_id

func _get_boss_ability_name(boss_ability_id: String) -> String:
	var data: Dictionary = _get_boss_ability_data(boss_ability_id)
	return str(data.get("name_ru", boss_ability_id))

func _get_boss_ability_data(boss_ability_id: String) -> Dictionary:
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	if system != null and system.has_method("get_ability_data"):
		var data: Variant = system.call("get_ability_data", boss_ability_id)
		if data is Dictionary:
			return data
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_ability"):
		var fallback: Variant = registry.call("get_boss_ability", boss_ability_id)
		if fallback is Dictionary:
			return fallback
	return {}

func _get_boss_ability_icon(ability_data: Dictionary, size: int = 64) -> Texture2D:
	var icon_path: String = str(ability_data.get("icon_path", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var loaded: Texture2D = load(icon_path) as Texture2D
		if loaded != null:
			return loaded
	var factory: Node = get_node_or_null("/root/ProceduralIconFactory")
	if factory != null and factory.has_method("get_icon_for_boss_ability"):
		var generated: Variant = factory.call("get_icon_for_boss_ability", ability_data, size)
		if generated is Texture2D:
			return generated
	return null

func _build_ability_description(boss_ability_id: String, ability_data: Dictionary) -> String:
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	var current_level: int = 0
	var next_description: String = ""
	if system != null:
		if system.has_method("get_level"):
			current_level = int(system.call("get_level", boss_ability_id))
		if system.has_method("get_player_version"):
			var next_level: int = clampi(current_level + 1, 1, 3)
			var next_data: Variant = system.call("get_player_version", boss_ability_id, next_level)
			if next_data is Dictionary:
				next_description = str(next_data.get("description_ru", ""))
		elif system.has_method("get_next_description"):
			next_description = str(system.call("get_next_description", boss_ability_id))
	var base: String = "Текущий уровень: " + str(current_level) + " / 3"
	var visual_text: String = _build_visual_summary_ru(ability_data)
	if not visual_text.is_empty():
		base += "\n" + visual_text
	if not next_description.is_empty():
		base += "\nСледующий уровень: " + next_description
	else:
		base += "\n" + str(ability_data.get("description_ru", ""))
	return base


func _build_visual_summary_ru(ability_data: Dictionary) -> String:
	var visual_profile_raw: Variant = ability_data.get("visual_profile", {})
	if not (visual_profile_raw is Dictionary):
		return "Визуал: базовый эффект"
	var visual_profile: Dictionary = visual_profile_raw
	var player_raw: Variant = visual_profile.get("player_version", {})
	if not (player_raw is Dictionary):
		return "Визуал: базовый эффект"
	var player_profile: Dictionary = player_raw
	var parts: Array[String] = []
	if not str(player_profile.get("zone_visual_id", "")).is_empty():
		parts.append("зона")
	if not str(player_profile.get("delayed_visual_id", "")).is_empty():
		parts.append("задержка")
	if not str(player_profile.get("travel_visual_id", "")).is_empty():
		parts.append("след/волна")
	if not str(player_profile.get("status_visual_id", "")).is_empty():
		parts.append("статус/метка")
	if not str(player_profile.get("impact_visual_id", "")).is_empty():
		parts.append("попадание")
	return "Визуал: " + (", ".join(parts) if not parts.is_empty() else "применение")

func _build_base() -> void:
	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -520.0
	_panel.offset_top = -315.0
	_panel.offset_right = 520.0
	_panel.offset_bottom = 315.0
	add_child(_panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
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

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
