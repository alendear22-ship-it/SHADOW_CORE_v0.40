extends Control

func _ready() -> void:
    _build_ui()
    _show_pending_meta_summary_if_needed()

func _build_ui() -> void:
    var root: VBoxContainer = VBoxContainer.new()
    root.anchor_left = 0.5
    root.anchor_top = 0.5
    root.anchor_right = 0.5
    root.anchor_bottom = 0.5
    root.offset_left = -260
    root.offset_top = -170
    root.offset_right = 260
    root.offset_bottom = 170
    root.add_theme_constant_override("separation", 18)
    add_child(root)

    var title: Label = Label.new()
    title.text = "SHADOW CORE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 44)
    root.add_child(title)

    var subtitle: Label = Label.new()
    subtitle.text = "Godot 4 technical MVP / full run loop patch A"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    root.add_child(subtitle)

    var new_run: Button = Button.new()
    new_run.text = "Новый забег"
    new_run.pressed.connect(func() -> void:
        get_tree().change_scene_to_file("res://scenes/ui/hero_select_screen.tscn")
    )
    root.add_child(new_run)

    var continue_button: Button = Button.new()
    continue_button.text = "Продолжить забег"
    continue_button.disabled = not SaveManager.has_suspend_save()
    continue_button.pressed.connect(func() -> void:
        RunManager.restore_suspend(SaveManager.consume_run_state() if SaveManager.has_method("consume_run_state") else SaveManager.load_suspend_and_consume())
        get_tree().change_scene_to_file("res://scenes/main/run_scene.tscn")
    )
    root.add_child(continue_button)

    var quit: Button = Button.new()
    quit.text = "Выход"
    quit.pressed.connect(func() -> void: get_tree().quit())
    root.add_child(quit)

func _show_pending_meta_summary_if_needed() -> void:
    var run_flow: Node = get_node_or_null("/root/RunFlow")
    if run_flow == null:
        return
    if not run_flow.has_method("has_pending_meta_summary") or not bool(run_flow.call("has_pending_meta_summary")):
        return
    var panel: MetaProgressionSummaryPanel = MetaProgressionSummaryPanel.new()
    add_child(panel)
    panel.show_summary(run_flow.call("consume_pending_meta_summary"))
