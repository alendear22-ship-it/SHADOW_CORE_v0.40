extends CanvasLayer
class_name MetaProgressionSummaryPanel

var _panel: Panel
var _list: VBoxContainer

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    visible = false
    _build_base()

func show_summary(summary: Dictionary) -> void:
    for child in _list.get_children():
        child.queue_free()
    var title: Label = Label.new()
    title.text = "Мета-прогрессия"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 28)
    _list.add_child(title)

    var result: Dictionary = summary.get("result", {})
    var body: Label = Label.new()
    body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.text = "Результат: %s\nЯдра: %s\nОсколки: %s\nПепел Душ за забег: %d\nМета-счетчики: %s\nОпыт героев: %s\nОткрытые улучшения: %s" % [
        result.get("result", "?"),
        JSON.stringify(summary.get("cores", {})),
        JSON.stringify(summary.get("shards", {})),
        int(summary.get("soul_ash", 0)),
        JSON.stringify(summary.get("meta_progress", {})),
        JSON.stringify(summary.get("hero_experience", {})),
        JSON.stringify(summary.get("unlocked_upgrades", []))
    ]
    _list.add_child(body)

    var close: Button = Button.new()
    close.text = "Закрыть"
    close.pressed.connect(func() -> void:
        visible = false
        get_tree().paused = false
        queue_free()
    )
    _list.add_child(close)

    visible = true
    get_tree().paused = true

func _build_base() -> void:
    _panel = Panel.new()
    _panel.anchor_left = 0.5
    _panel.anchor_top = 0.5
    _panel.anchor_right = 0.5
    _panel.anchor_bottom = 0.5
    _panel.offset_left = -430.0
    _panel.offset_top = -250.0
    _panel.offset_right = 430.0
    _panel.offset_bottom = 250.0
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
