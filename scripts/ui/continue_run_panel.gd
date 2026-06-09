extends CanvasLayer
class_name ContinueRunPanel

signal continue_selected(health_ratio: float, essence_penalty_fraction: float)

var _panel: Panel
var _list: VBoxContainer

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    visible = false
    _build_base()

func show_continue_options() -> void:
    visible = true
    get_tree().paused = true

func hide_panel() -> void:
    visible = false

func _build_base() -> void:
    _panel = Panel.new()
    _panel.anchor_left = 0.5
    _panel.anchor_top = 0.5
    _panel.anchor_right = 0.5
    _panel.anchor_bottom = 0.5
    _panel.offset_left = -330.0
    _panel.offset_top = -190.0
    _panel.offset_right = 330.0
    _panel.offset_bottom = 190.0
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

    var title: Label = Label.new()
    title.text = "Последний шанс"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 28)
    _list.add_child(title)

    var note: Label = Label.new()
    note.text = "Игрок может продолжить забег только один раз. После второй смерти забег закончится поражением."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _list.add_child(note)

    var safe_button: Button = Button.new()
    safe_button.text = "Воскреснуть с 30% здоровья без потери ресурсов"
    safe_button.pressed.connect(func() -> void:
        hide_panel()
        continue_selected.emit(0.30, 0.0)
    )
    _list.add_child(safe_button)

    var costly_button: Button = Button.new()
    costly_button.text = "Воскреснуть с 70% здоровья, потеряв 50% текущей эссенции"
    costly_button.pressed.connect(func() -> void:
        hide_panel()
        continue_selected.emit(0.70, 0.50)
    )
    _list.add_child(costly_button)
