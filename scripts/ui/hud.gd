extends CanvasLayer
class_name Hud

var _hp_label: Label
var _resource_row: HBoxContainer
var _run_label: Label
var _debug_label: Label
var _dev_button: Button
var _boss_panel: Panel
var _boss_name_label: Label
var _boss_health_bar: ProgressBar
var _boss_ability_row: HBoxContainer
var _boss_ability_labels: Array = []
var _cooldown_labels: Dictionary = {}
var _dodge_button: Button
var _last_debug: Dictionary = {}

func _ready() -> void:
	_build_ui()
	EventBus.player_health_changed.connect(_on_player_health_changed)
	EventBus.run_resource_changed.connect(_refresh_resources)
	EventBus.ability_cooldown_changed.connect(_on_cooldown_changed)
	if EventBus.has_signal("dodge_cooldown_changed"):
		EventBus.dodge_cooldown_changed.connect(_on_dodge_cooldown_changed)
	EventBus.run_debug_changed.connect(_on_run_debug_changed)
	if EventBus.has_signal("boss_health_changed"):
		EventBus.boss_health_changed.connect(_on_boss_health_changed)
	if EventBus.has_signal("boss_ability_cooldowns_changed"):
		EventBus.boss_ability_cooldowns_changed.connect(_on_boss_ability_cooldowns_changed)
	if EventBus.has_signal("boss_hud_hidden"):
		EventBus.boss_hud_hidden.connect(_hide_boss_hud)
	var dev: Node = get_node_or_null("/root/DeveloperTools")
	if dev != null and dev.has_signal("developer_mode_changed"):
		dev.connect("developer_mode_changed", Callable(self, "_on_developer_mode_changed"))
	_refresh_dev_button()
	_refresh_resources()
	call_deferred("_sync_player_health_deferred")

func bind_player(player: PlayerController) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.health_component == null:
		return
	_on_player_health_changed(player.health_component.current_health, player.health_component.max_health)

func _sync_player_health_deferred() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: PlayerController = players[0] as PlayerController
	bind_player(player)

func _build_ui() -> void:
	var top: HBoxContainer = HBoxContainer.new()
	top.anchor_right = 1.0
	top.offset_left = 16
	top.offset_top = 12
	top.offset_right = -116
	top.offset_bottom = 48
	top.add_theme_constant_override("separation", 18)
	add_child(top)

	_hp_label = Label.new()
	_hp_label.text = "Здоровье: --"
	top.add_child(_hp_label)

	_resource_row = HBoxContainer.new()
	_resource_row.add_theme_constant_override("separation", 6)
	top.add_child(_resource_row)

	_run_label = Label.new()
	_run_label.text = "Комната 1 / Волна 0"
	top.add_child(_run_label)

	_dev_button = Button.new()
	_dev_button.anchor_left = 1.0
	_dev_button.anchor_top = 0.0
	_dev_button.anchor_right = 1.0
	_dev_button.anchor_bottom = 0.0
	_dev_button.offset_left = -104.0
	_dev_button.offset_top = 10.0
	_dev_button.offset_right = -12.0
	_dev_button.offset_bottom = 42.0
	_dev_button.text = "Разработка: ВЫКЛ"
	_dev_button.toggle_mode = true
	_dev_button.tooltip_text = "Кнопка разработчика: 0 перезарядки способностей и 10000 здоровья."
	_dev_button.pressed.connect(_on_dev_button_pressed)
	add_child(_dev_button)

	_build_boss_hud()

	_debug_label = Label.new()
	_debug_label.anchor_left = 0.0
	_debug_label.anchor_top = 0.0
	_debug_label.offset_left = 16.0
	_debug_label.offset_top = 56.0
	_debug_label.offset_right = 660.0
	_debug_label.offset_bottom = 150.0
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_debug_label)

	var joystick_scene: PackedScene = load("res://scenes/ui/virtual_joystick.tscn") as PackedScene
	var joystick: Control = joystick_scene.instantiate() as Control
	add_child(joystick)

	_build_dodge_and_ability_arc()

func _build_dodge_and_ability_arc() -> void:
	_dodge_button = Button.new()
	_dodge_button.anchor_left = 1.0
	_dodge_button.anchor_top = 1.0
	_dodge_button.anchor_right = 1.0
	_dodge_button.anchor_bottom = 1.0
	_dodge_button.offset_left = -194.0
	_dodge_button.offset_top = -194.0
	_dodge_button.offset_right = -86.0
	_dodge_button.offset_bottom = -86.0
	_dodge_button.text = "⤴"
	_dodge_button.tooltip_text = "Уворот: 2 заряда, Space на ПК. Быстрое перемещение на 2 м, неуязвимость 0.4 сек."
	_dodge_button.clip_contents = true
	_apply_round_button_style(_dodge_button, 54.0, Color(0.12, 0.15, 0.20, 0.92), Color(0.65, 0.78, 1.0, 0.90))
	_dodge_button.pressed.connect(func(): EventBus.dodge_button_pressed.emit())
	add_child(_dodge_button)

	var scene: PackedScene = load("res://scenes/ui/ability_button.tscn") as PackedScene
	var layout: Array = [
		{"slot": "active_1", "text": "Q", "rect": Rect2(-327, -182, 94, 94)},
		{"slot": "active_2", "text": "E", "rect": Rect2(-297, -292, 94, 94)},
		{"slot": "ultimate", "text": "R", "rect": Rect2(-187, -332, 94, 94)}
	]
	for entry in layout:
		var button: AbilityButton = scene.instantiate() as AbilityButton
		button.slot = str(entry.get("slot", ""))
		button.text = str(entry.get("text", ""))
		button.anchor_left = 1.0
		button.anchor_top = 1.0
		button.anchor_right = 1.0
		button.anchor_bottom = 1.0
		var rect: Rect2 = entry.get("rect")
		button.offset_left = rect.position.x
		button.offset_top = rect.position.y
		button.offset_right = rect.position.x + rect.size.x
		button.offset_bottom = rect.position.y + rect.size.y
		add_child(button)
		_cooldown_labels[button.slot] = button

func _apply_round_button_style(button: Button, radius: float, bg: Color, border: Color) -> void:
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = border
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(int(radius))
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(bg.r + 0.05, bg.g + 0.05, bg.b + 0.06, bg.a)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)

func _build_boss_hud() -> void:
	_boss_panel = Panel.new()
	_boss_panel.anchor_left = 0.5
	_boss_panel.anchor_top = 0.0
	_boss_panel.anchor_right = 0.5
	_boss_panel.anchor_bottom = 0.0
	_boss_panel.offset_left = -220.0
	_boss_panel.offset_top = 10.0
	_boss_panel.offset_right = 220.0
	_boss_panel.offset_bottom = 82.0
	_boss_panel.visible = false
	add_child(_boss_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 12.0
	root.offset_top = 6.0
	root.offset_right = -12.0
	root.offset_bottom = -6.0
	root.add_theme_constant_override("separation", 4)
	_boss_panel.add_child(root)

	_boss_name_label = Label.new()
	_boss_name_label.text = "Босс"
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_boss_name_label)

	_boss_health_bar = ProgressBar.new()
	_boss_health_bar.min_value = 0.0
	_boss_health_bar.max_value = 100.0
	_boss_health_bar.value = 100.0
	_boss_health_bar.show_percentage = false
	_boss_health_bar.custom_minimum_size = Vector2(0, 12)
	root.add_child(_boss_health_bar)

	_boss_ability_row = HBoxContainer.new()
	_boss_ability_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_boss_ability_row.add_theme_constant_override("separation", 6)
	root.add_child(_boss_ability_row)
	for i in range(3):
		var label: Label = Label.new()
		label.custom_minimum_size = Vector2(96, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = str(i + 1) + ": --"
		_boss_ability_row.add_child(label)
		_boss_ability_labels.append(label)

func _on_player_health_changed(current: float, maximum: float) -> void:
	_hp_label.text = "Здоровье: " + str(int(ceil(current))) + "/" + str(int(maximum))

func _refresh_resources() -> void:
	if _resource_row != null:
		_clear_children(_resource_row)
		var any_resource: bool = false
		var faction_totals: Dictionary = {
			"FACTION_KRUSHERS": 0,
			"FACTION_NATURE": 0,
			"FACTION_ETHERS": 0
		}
		for creature in DataRegistry.get_items("creature_types"):
			var creature_id: String = str(creature.get("id", ""))
			var amount: int = EssenceBank.get_amount(creature_id)
			if amount <= 0:
				continue
			var faction_id: String = str(creature.get("faction_id", ""))
			faction_totals[faction_id] = int(faction_totals.get(faction_id, 0)) + amount
		for faction_id in ["FACTION_KRUSHERS", "FACTION_NATURE", "FACTION_ETHERS"]:
			var total: int = int(faction_totals.get(faction_id, 0))
			if total <= 0:
				continue
			any_resource = true
			_resource_row.add_child(_make_hud_icon(ShadowCoreAssetPaths.essence_texture_path(faction_id), Vector2(22, 22)))
			var amount_label: Label = Label.new()
			amount_label.text = str(total)
			_resource_row.add_child(amount_label)
		if not any_resource:
			var none_label: Label = Label.new()
			none_label.text = "—"
			_resource_row.add_child(none_label)
		var soul_ash_label: Label = Label.new()
		soul_ash_label.text = "Пепел Душ " + str(RunManager.get_soul_ash() if RunManager.has_method("get_soul_ash") else 0)
		soul_ash_label.tooltip_text = "Валюта текущего забега для Алтаря и отказа от наград."
		_resource_row.add_child(soul_ash_label)
	var room_part: String = "Финал" if RunManager.final_boss_unlocked else ("Подготовка" if RunManager.final_preparation_active else "Комната " + str(RunManager.current_room_index))
	_run_label.text = "Этаж " + str(RunManager.current_floor_index) + " | " + room_part + " | Боссов " + str(RunManager.current_boss_number) + "/3 | Волна " + str(WaveDirector.get_wave_index())

func _make_hud_icon(texture_path: String, min_size: Vector2) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = min_size
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture != null:
			icon.texture = texture
	return icon

func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()

func _on_run_debug_changed(debug_data: Dictionary) -> void:
	_last_debug = debug_data.duplicate(true)
	var wave_status: Dictionary = WaveDirector.get_status() if WaveDirector.has_method("get_status") else {}
	_debug_label.text = "Состояние: %s | Босс: %s | Продолжение: %s | Режим разработки: %s\nЭтаж: %d | Комната этажа: %d/%d | Волна: %d/%d | Осталось: %d с\nАктивные враги: %d | Сложность: %.2f | Выпадения: %d" % [
		debug_data.get("state_name", "?"),
		debug_data.get("current_boss", ""),
		str(debug_data.get("continue_used", false)),
		"ВКЛ" if bool(debug_data.get("dev_mode", false)) else "ВЫКЛ",
		int(debug_data.get("floor", RunManager.current_floor_index)),
		int(debug_data.get("rooms_completed_in_floor", RunManager.rooms_completed_in_floor)),
		3,
		int(wave_status.get("wave_index", WaveDirector.get_wave_index())),
		int(wave_status.get("wave_total", 0)),
		int(wave_status.get("remaining_seconds", 0)),
		int(wave_status.get("active_enemies", debug_data.get("active_enemies", 0))),
		float(debug_data.get("difficulty", 1.0)),
		int(debug_data.get("essence_total", 0))
	]

func _on_cooldown_changed(slot: String, remaining: float, duration: float) -> void:
	var button: AbilityButton = _cooldown_labels.get(slot, null) as AbilityButton
	if button != null:
		button.set_cooldown(remaining, duration)

func _on_dodge_cooldown_changed(charges: int, max_charges: int, next_charge_remaining: float, _next_charge_duration: float, global_cooldown_remaining: float) -> void:
	if _dodge_button == null:
		return
	_dodge_button.disabled = charges <= 0 or global_cooldown_remaining > 0.05
	var suffix: String = ""
	if global_cooldown_remaining > 0.05:
		suffix = "\n%.1f" % global_cooldown_remaining
	elif charges < max_charges and next_charge_remaining > 0.05:
		suffix = "\n%d/%d %.0f" % [charges, max_charges, ceil(next_charge_remaining)]
	else:
		suffix = "\n%d/%d" % [charges, max_charges]
	_dodge_button.text = "⤴" + suffix

func _on_dev_button_pressed() -> void:
	var dev: Node = get_node_or_null("/root/DeveloperTools")
	if dev != null and dev.has_method("toggle"):
		dev.call("toggle")
	_refresh_dev_button()

func _on_developer_mode_changed(_enabled: bool) -> void:
	_refresh_dev_button()

func _refresh_dev_button() -> void:
	if _dev_button == null:
		return
	var dev: Node = get_node_or_null("/root/DeveloperTools")
	var enabled: bool = dev != null and bool(dev.get("enabled"))
	_dev_button.button_pressed = enabled
	_dev_button.text = "Разработка: ВКЛ" if enabled else "Разработка: ВЫКЛ"

func _on_boss_health_changed(_boss_id: String, boss_name: String, current: float, maximum: float, is_final_boss: bool) -> void:
	if _boss_panel == null:
		return
	_boss_panel.visible = true
	_boss_name_label.text = ("ФИНАЛ: " if is_final_boss else "") + boss_name
	_boss_health_bar.max_value = max(1.0, maximum)
	_boss_health_bar.value = clampf(current, 0.0, max(1.0, maximum))

func _on_boss_ability_cooldowns_changed(_boss_id: String, abilities: Array) -> void:
	if _boss_panel == null:
		return
	_boss_panel.visible = true
	for i in range(_boss_ability_labels.size()):
		var label: Label = _boss_ability_labels[i] as Label
		if label == null:
			continue
		if i >= abilities.size():
			label.visible = false
			continue
		label.visible = true
		var ability: Dictionary = abilities[i]
		var name: String = str(ability.get("name", "Атака"))
		var remaining: float = float(ability.get("remaining", 0.0))
		label.text = "%s: %.1fs" % [name.substr(0, min(10, name.length())), remaining]
		label.tooltip_text = "%s\n%s\nТелеграф: %.1f сек." % [name, str(ability.get("shape", "")), float(ability.get("telegraph", 0.0))]

func _hide_boss_hud() -> void:
	if _boss_panel != null:
		_boss_panel.visible = false
