extends Node2D

const PICKUP_SCENE: String = "res://scenes/effects/pickup_essence.tscn"
const REACTION_EFFECT_SCENE: String = "res://scenes/effects/hit_effect.tscn" # Fallback only; primary path is EffectVisualSystem.

@onready var player: PlayerController = $Player as PlayerController
@onready var enemy_container: Node2D = $EnemyContainer as Node2D
@onready var pickups: Node2D = $Pickups as Node2D
@onready var hud: Hud = $HUD as Hud
@onready var pause_menu: PauseMenu = $PauseMenu as PauseMenu

var _route_choice_panel: RouteChoicePanel
var _boss_choice_panel: BossChoicePanel
var _boss_reward_panel: BossRewardPanel
var _altar_sacrifice_panel: AltarSacrificePanel
var _altar_reward_cards_panel: AltarRewardCardsPanel
var _ability_slot_install_panel: AbilitySlotInstallPanel
var _final_preparation_panel: FinalPreparationPanel
var _run_summary_panel: RunSummaryPanel
var _continue_panel: ContinueRunPanel
var _result_panel: RunResultPanel
var _run_flow: Node = null

func _safe_connect_signal(source: Object, signal_name: StringName, target: Callable) -> void:
	if source == null:
		return
	if not source.has_signal(signal_name):
		return
	if not target.is_valid():
		return
	if source.is_connected(signal_name, target):
		return
	source.connect(signal_name, target)

func _safe_call(target: Object, method_name: StringName, args: Array = []) -> void:
	if target == null:
		return
	if not target.has_method(method_name):
		return
	target.callv(method_name, args)

func _ready() -> void:
	# На всякий случай снимаем паузу: если игрок вернулся из результата/continue,
	# новый забег не должен наследовать paused=true.
	get_tree().paused = false
	_run_flow = get_node_or_null("/root/RunFlow")
	_build_runtime_panels()
	if hud != null and hud.has_method("bind_player"):
		hud.bind_player(player)
	if _run_flow == null:
		push_error("RunScene: RunFlow is missing. CORE progression cannot start.")
		set_process(false)
		set_physics_process(false)
		return
	_connect_signals()
	_run_flow.call("bind_runtime", self, enemy_container, player, pickups)
	_run_flow.call("start_or_resume_current_run")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9 and _run_flow != null and _run_flow.has_method("get_debug_state"):
			print("RunFlow debug: ", JSON.stringify(_run_flow.call("get_debug_state")))

func _build_runtime_panels() -> void:
	_route_choice_panel = RouteChoicePanel.new()
	add_child(_route_choice_panel)
	_boss_choice_panel = BossChoicePanel.new()
	add_child(_boss_choice_panel)
	_boss_reward_panel = BossRewardPanel.new()
	add_child(_boss_reward_panel)
	_altar_sacrifice_panel = AltarSacrificePanel.new()
	add_child(_altar_sacrifice_panel)
	_altar_reward_cards_panel = AltarRewardCardsPanel.new()
	add_child(_altar_reward_cards_panel)
	_ability_slot_install_panel = AbilitySlotInstallPanel.new()
	add_child(_ability_slot_install_panel)
	_final_preparation_panel = FinalPreparationPanel.new()
	add_child(_final_preparation_panel)
	_run_summary_panel = RunSummaryPanel.new()
	add_child(_run_summary_panel)
	_continue_panel = ContinueRunPanel.new()
	add_child(_continue_panel)
	_result_panel = RunResultPanel.new()
	add_child(_result_panel)

func _connect_signals() -> void:
	_safe_connect_signal(EventBus, &"enemy_died_with_position", Callable(self, "_on_enemy_died_with_position"))
	_safe_connect_signal(EventBus, &"reaction_visual_requested", Callable(self, "_on_reaction_visual_requested"))
	if _run_flow == null:
		return

	# Active flow: RouteChoice/Altar/BossChoice/BossReward/AbilitySlotInstall/FinalPreparation/RunSummary.
	_safe_connect_signal(_run_flow, &"route_choices_ready", Callable(self, "_show_route_choices"))
	_safe_connect_signal(_run_flow, &"boss_choice_cards_ready", Callable(self, "_show_boss_choices"))
	_safe_connect_signal(_run_flow, &"boss_reward_ready", Callable(self, "_show_boss_reward"))
	_safe_connect_signal(_run_flow, &"ability_slot_install_requested", Callable(self, "_show_ability_slot_install"))
	_safe_connect_signal(_run_flow, &"altar_sacrifice_requested", Callable(self, "_show_altar_sacrifice"))
	_safe_connect_signal(_run_flow, &"altar_reward_cards_ready", Callable(self, "_show_altar_reward_cards"))
	_safe_connect_signal(_run_flow, &"continue_choice_requested", Callable(_continue_panel, "show_continue_options"))
	_safe_connect_signal(_run_flow, &"final_preparation_choices_ready", Callable(self, "_show_final_preparation_choices"))
	_safe_connect_signal(_run_flow, &"run_summary_ready", Callable(self, "_show_run_summary"))
	_safe_connect_signal(_run_flow, &"run_result_ready", Callable(_result_panel, "show_result"))

	_safe_connect_signal(_route_choice_panel, &"route_option_selected", Callable(_run_flow, "choose_room_card"))
	_safe_connect_signal(_boss_choice_panel, &"boss_card_selected", Callable(_run_flow, "choose_boss_card"))
	_safe_connect_signal(_boss_reward_panel, &"continue_requested", Callable(_run_flow, "continue_after_boss_reward"))
	_safe_connect_signal(_boss_reward_panel, &"reward_declined", Callable(_run_flow, "decline_boss_reward_for_soul_ash"))
	_safe_connect_signal(_boss_reward_panel, &"boss_ability_reward_selected", Callable(_run_flow, "choose_boss_reward_ability"))
	_safe_connect_signal(_altar_sacrifice_panel, &"sacrifice_confirmed", Callable(_run_flow, "confirm_altar_sacrifice"))
	_safe_connect_signal(_altar_sacrifice_panel, &"cancel_requested", Callable(_run_flow, "cancel_altar"))
	_safe_connect_signal(_altar_reward_cards_panel, &"altar_card_selected", Callable(_run_flow, "choose_altar_reward_card"))
	_safe_connect_signal(_ability_slot_install_panel, &"install_confirmed", Callable(_run_flow, "confirm_boss_ability_install"))
	_safe_connect_signal(_ability_slot_install_panel, &"install_refused", Callable(_run_flow, "refuse_boss_ability_install"))
	_safe_connect_signal(_final_preparation_panel, &"preparation_selected", Callable(_run_flow, "choose_final_preparation"))
	_safe_connect_signal(_run_summary_panel, &"menu_requested", Callable(self, "_go_to_main_menu"))
	_safe_connect_signal(_run_summary_panel, &"new_run_requested", Callable(self, "_start_new_run_from_result"))
	_safe_connect_signal(_continue_panel, &"continue_selected", Callable(_run_flow, "accept_continue_option"))
	_safe_connect_signal(_result_panel, &"menu_requested", Callable(self, "_go_to_main_menu"))
	_safe_connect_signal(_result_panel, &"new_run_requested", Callable(self, "_start_new_run_from_result"))

func _on_enemy_died_with_position(_enemy_id: String, faction_id: String, creature_type_id: String, essence_amount: int, position: Vector2) -> void:
	var scene: PackedScene = load(PICKUP_SCENE) as PackedScene
	if scene == null:
		return
	var pickup: EssencePickup = scene.instantiate() as EssencePickup
	pickup.global_position = position
	pickup.setup(creature_type_id, faction_id, essence_amount)
	pickups.add_child(pickup)



func _on_reaction_visual_requested(reaction_data: Dictionary) -> void:
	var visual_system: Node = get_node_or_null("/root/EffectVisualSystem")
	if visual_system != null:
		# EffectVisualSystem is the primary EventBus receiver in v0.37.
		# RunScene keeps this handler only as a missing-autoload fallback to avoid double VFX.
		return
	# Safe fallback only if visual autoload is missing. This keeps old hit_effect from being the primary visual path.
	var scene: PackedScene = load(REACTION_EFFECT_SCENE) as PackedScene
	if scene == null:
		return
	var effect: Node2D = scene.instantiate() as Node2D
	if effect == null:
		return
	add_child(effect)
	var position_value: Variant = reaction_data.get("position", Vector2.ZERO)
	if position_value is Vector2:
		effect.global_position = position_value
	elif player != null and is_instance_valid(player):
		effect.global_position = player.global_position


func _show_final_preparation_choices(choices: Array) -> void:
	_hide_reward_panels()
	if _route_choice_panel != null:
		_route_choice_panel.hide_panel()
	if _boss_choice_panel != null:
		_boss_choice_panel.hide_panel()
	if _final_preparation_panel != null:
		_final_preparation_panel.show_choices(choices)

func _show_run_summary(summary: Dictionary) -> void:
	_hide_reward_panels()
	if _result_panel != null:
		_result_panel.visible = false
	if _run_summary_panel != null:
		_run_summary_panel.show_summary(summary)

func _show_altar_sacrifice(floor_index: int, route_context: Dictionary = {}) -> void:
	_hide_reward_panels()
	if _route_choice_panel != null:
		_route_choice_panel.hide_panel()
	if _boss_choice_panel != null:
		_boss_choice_panel.hide_panel()
	if _altar_sacrifice_panel != null:
		_altar_sacrifice_panel.show_altar(floor_index, route_context)

func _show_altar_reward_cards(cards: Array, sacrifice_result: Dictionary = {}) -> void:
	_hide_reward_panels()
	if _altar_reward_cards_panel != null:
		_altar_reward_cards_panel.show_cards(cards, sacrifice_result)

func _show_ability_slot_install(boss_ability_id: String, reward_data: Dictionary = {}) -> void:
	_hide_reward_panels()
	if _ability_slot_install_panel != null:
		_ability_slot_install_panel.show_install(boss_ability_id, reward_data)

func _show_boss_reward(reward_data: Dictionary = {}) -> void:
	_hide_reward_panels()
	if _route_choice_panel != null:
		_route_choice_panel.hide_panel()
	if _boss_choice_panel != null:
		_boss_choice_panel.hide_panel()
	if _boss_reward_panel != null:
		_boss_reward_panel.show_reward(reward_data)

func _show_route_choices(cards: Array, route_context: Dictionary = {}) -> void:
	_hide_reward_panels()
	if _boss_choice_panel != null:
		_boss_choice_panel.hide_panel()
	_route_choice_panel.show_route_choices(cards, route_context)

func _show_boss_choices(cards: Array, route_context: Dictionary = {}) -> void:
	_hide_reward_panels()
	if _route_choice_panel != null:
		_route_choice_panel.hide_panel()
	_boss_choice_panel.show_boss_choices(cards, route_context)

func _hide_reward_panels() -> void:
	if _route_choice_panel != null:
		_route_choice_panel.hide_panel()
	if _boss_choice_panel != null:
		_boss_choice_panel.hide_panel()
	if _boss_reward_panel != null:
		_boss_reward_panel.hide_panel()
	if _altar_sacrifice_panel != null:
		_altar_sacrifice_panel.hide_panel()
	if _altar_reward_cards_panel != null:
		_altar_reward_cards_panel.hide_panel()
	if _ability_slot_install_panel != null:
		_ability_slot_install_panel.hide_panel()
	if _final_preparation_panel != null:
		_final_preparation_panel.hide_panel()

func _go_to_main_menu() -> void:
	if _run_flow != null and _run_flow.has_method("mark_run_result_closed"):
		_run_flow.call("mark_run_result_closed")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

func _start_new_run_from_result() -> void:
	if _run_flow != null and _run_flow.has_method("mark_run_result_closed"):
		_run_flow.call("mark_run_result_closed")
	get_tree().paused = false
	if _run_flow != null and _run_flow.has_method("start_new_run_in_current_scene"):
		_run_flow.call("start_new_run_in_current_scene", RunManager.current_hero_id)
