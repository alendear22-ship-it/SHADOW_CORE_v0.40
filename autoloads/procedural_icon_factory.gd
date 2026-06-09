extends Node

const VISUAL_GENERIC_UNKNOWN_ICON: String = "VISUAL_GENERIC_UNKNOWN_ICON"

var _icon_cache: Dictionary = {}
var _missing_icon_warnings: Dictionary = {}

const FACTION_BASE_COLORS: Dictionary = {
	"FACTION_KRUSHERS": "#3A0B10",
	"FACTION_NATURE": "#0C2F24",
	"FACTION_ETHERS": "#140B32",
	"FACTION_ETHER": "#140B32",
	"FACTION_NONE": "#1E182A"
}

const FACTION_ACCENT_COLORS: Dictionary = {
	"FACTION_KRUSHERS": "#FF6E54",
	"FACTION_NATURE": "#58D68D",
	"FACTION_ETHERS": "#8B7CFF",
	"FACTION_ETHER": "#8B7CFF",
	"FACTION_NONE": "#B88CFF"
}

const REACTION_ICON_PROFILES: Dictionary = {
	"rotten_wound": {"id":"REACTION_ROTTEN_WOUND","name_ru":"Гнилая Рана","glyph":"cracked_wound_with_green_rot","base_color":"#4A0F16","accent_color":"#86F050","background":"radial_gradient","frame":"reaction_ring","shape_language":"blood_rot"},
	"blood_bloom": {"id":"REACTION_BLOOD_BLOOM","name_ru":"Кровавое Цветение","glyph":"blood_flower_burst","base_color":"#5B1019","accent_color":"#65D96B","background":"radial_gradient","frame":"reaction_ring","shape_language":"blood_nature"},
	"blood_discharge": {"id":"REACTION_BLOOD_DISCHARGE","name_ru":"Кровавый Разряд","glyph":"blood_lightning","base_color":"#5B1019","accent_color":"#FFF16B","background":"radial_gradient","frame":"reaction_ring","shape_language":"blood_lightning"},
	"execution_seal": {"id":"REACTION_EXECUTION_SEAL","name_ru":"Печать Казни","glyph":"execution_seal","base_color":"#451021","accent_color":"#9A66FF","background":"radial_gradient","frame":"reaction_ring","shape_language":"execution_void"},
	"swamp_rift": {"id":"REACTION_SWAMP_RIFT","name_ru":"Топкий Разлом","glyph":"swamp_rift","base_color":"#0F3A31","accent_color":"#8B7CFF","background":"radial_gradient","frame":"reaction_ring","shape_language":"swamp_void"},
	"spore_storm": {"id":"REACTION_SPORE_STORM","name_ru":"Буря Спор","glyph":"spore_storm","base_color":"#123D20","accent_color":"#73E7FF","background":"radial_gradient","frame":"reaction_ring","shape_language":"spore_storm"}
}

const STATUS_ICON_PROFILES: Dictionary = {
	"bleed": {"id":"STATUS_BLEED","name_ru":"Кровотечение","glyph":"blood_drop","base_color":"#3F0C12","accent_color":"#E53D4F","frame":"status_ring"},
	"burn": {"id":"STATUS_BURN","name_ru":"Горение","glyph":"flame","base_color":"#3B1308","accent_color":"#FF8A2F","frame":"status_ring"},
	"poison": {"id":"STATUS_POISON","name_ru":"Яд","glyph":"toxic_drop","base_color":"#10381F","accent_color":"#95F04B","frame":"status_ring"},
	"slow": {"id":"STATUS_SLOW","name_ru":"Замедление","glyph":"ice_chain","base_color":"#0E2C3A","accent_color":"#7CD7FF","frame":"status_ring"},
	"shock": {"id":"STATUS_SHOCK","name_ru":"Шок","glyph":"lightning_mark","base_color":"#332508","accent_color":"#FFF16B","frame":"status_ring"},
	"void": {"id":"STATUS_VOID","name_ru":"Пустота","glyph":"void_eye","base_color":"#170B32","accent_color":"#9A66FF","frame":"status_ring"},
	"mark": {"id":"STATUS_MARK","name_ru":"Метка","glyph":"target_rune","base_color":"#24162F","accent_color":"#D8D8FF","frame":"status_ring"},
	"vulnerability": {"id":"STATUS_VULNERABILITY","name_ru":"Уязвимость","glyph":"cracked_armor","base_color":"#2E2530","accent_color":"#FFD1A3","frame":"status_ring"},
	"armor_break": {"id":"STATUS_ARMOR_BREAK","name_ru":"Пробитие брони","glyph":"broken_shield","base_color":"#2A2528","accent_color":"#C4C4C4","frame":"status_ring"},
	"stun": {"id":"STATUS_STUN","name_ru":"Оглушение","glyph":"star_ring","base_color":"#252033","accent_color":"#FFE680","frame":"status_ring"},
	"pull": {"id":"STATUS_PULL","name_ru":"Притяжение","glyph":"inward_arrows","base_color":"#142B32","accent_color":"#9A66FF","frame":"status_ring"},
	"knockback": {"id":"STATUS_KNOCKBACK","name_ru":"Отталкивание","glyph":"outward_arrows","base_color":"#2A1B20","accent_color":"#FF9E62","frame":"status_ring"}
}

func reset_run() -> void:
	# Icons are process-wide derived textures and are safe to keep between runs.
	pass

func get_state() -> Dictionary:
	return {"cache_size": _icon_cache.size(), "warned_missing_icons": _missing_icon_warnings.keys()}

func set_state(_state: Variant = {}) -> void:
	# Runtime cache is derived; no restore needed.
	pass

func clear_cache() -> void:
	_icon_cache.clear()
	_missing_icon_warnings.clear()

func get_cache_size() -> int:
	return _icon_cache.size()

func get_icon_for_boss_ability(ability_data: Dictionary, size: int = 64) -> Texture2D:
	return _resolve_icon("boss_ability", ability_data, str(ability_data.get("boss_ability_id", ability_data.get("id", "unknown"))), size, "default")

func get_icon_for_hero_ability(ability_data: Dictionary, size: int = 64) -> Texture2D:
	return _resolve_icon("hero_ability", ability_data, str(ability_data.get("id", ability_data.get("slot", "unknown"))), size, str(ability_data.get("hero_id", "default")))

func get_icon_for_altar_card(card_data: Dictionary, size: int = 64) -> Texture2D:
	return _resolve_icon("altar_card", card_data, str(card_data.get("id", card_data.get("card_type", "unknown"))), size, str(card_data.get("rarity", card_data.get("strength", "default"))))

func get_icon_for_reaction(reaction_id: String, reaction_data: Dictionary = {}, size: int = 64) -> Texture2D:
	var profile: Dictionary = _reaction_profile(reaction_id)
	profile.merge(reaction_data, true)
	return _resolve_icon("reaction", profile, reaction_id, size, str(profile.get("variant", "default")))

func get_icon_for_status(status_id: String, status_data: Dictionary = {}, size: int = 64) -> Texture2D:
	var profile: Dictionary = _status_profile(status_id)
	profile.merge(status_data, true)
	return _resolve_icon("status", profile, status_id, size, str(profile.get("variant", "default")))

func get_fallback_icon(icon_key: String, profile: Dictionary = {}, size: int = 64) -> Texture2D:
	var fallback_profile: Dictionary = profile.duplicate(true)
	fallback_profile["id"] = icon_key if not icon_key.is_empty() else VISUAL_GENERIC_UNKNOWN_ICON
	if not fallback_profile.has("icon_profile"):
		fallback_profile["icon_profile"] = {
			"glyph": str(fallback_profile.get("glyph", "unknown_rune")),
			"base_color": str(fallback_profile.get("base_color", "#1E182A")),
			"accent_color": str(fallback_profile.get("accent_color", "#B88CFF")),
			"background": "radial_gradient",
			"frame": "unknown_ring",
			"shape_language": "unknown",
			"rarity_ring": false
		}
	return _resolve_icon("fallback", fallback_profile, str(fallback_profile.get("id", icon_key)), size, str(fallback_profile.get("variant", "default")))

func audit_missing_icons() -> Array:
	var missing: Array = []
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry == null or not registry.has_method("get_items"):
		return missing
	for ability in registry.call("get_items", "boss_abilities"):
		if ability is Dictionary:
			_check_icon_coverage(missing, "boss_ability", ability, str(ability.get("boss_ability_id", ability.get("id", ""))))
	for ability in registry.call("get_items", "abilities"):
		if ability is Dictionary:
			_check_icon_coverage(missing, "hero_ability", ability, str(ability.get("id", "")))
	for card in registry.call("get_items", "altar_cards"):
		if card is Dictionary:
			_check_icon_coverage(missing, "altar_card", card, str(card.get("id", "")))
	for reaction_id in REACTION_ICON_PROFILES.keys():
		_check_icon_coverage(missing, "reaction", {"id": reaction_id, "icon_profile": REACTION_ICON_PROFILES[reaction_id]}, str(reaction_id))
	for status_id in STATUS_ICON_PROFILES.keys():
		_check_icon_coverage(missing, "status", {"id": status_id, "icon_profile": STATUS_ICON_PROFILES[status_id]}, str(status_id))
	return missing

func _resolve_icon(icon_type: String, source_data: Dictionary, source_id: String, size: int, variant: String) -> Texture2D:
	var safe_size: int = clampi(size, 24, 192)
	var icon_path: String = str(source_data.get("icon_path", ""))
	if not icon_path.is_empty():
		if ResourceLoader.exists(icon_path):
			var loaded: Texture2D = load(icon_path) as Texture2D
			if loaded != null:
				return loaded
		else:
			_warn_missing_once(icon_type + ":" + source_id + ":" + icon_path, "ProceduralIconFactory: missing icon_path, using procedural fallback: " + icon_path)
	var profile: Dictionary = _extract_icon_profile(source_data, icon_type, source_id)
	var cache_key: String = icon_type + ":" + source_id + ":" + str(safe_size) + ":" + variant + ":" + str(profile.get("glyph", "unknown"))
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key]
	var texture: Texture2D = _build_icon(profile, safe_size)
	_icon_cache[cache_key] = texture
	return texture

func _extract_icon_profile(source_data: Dictionary, icon_type: String, source_id: String) -> Dictionary:
	var raw: Variant = source_data.get("icon_profile", {})
	var profile: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	if profile.is_empty() and source_data.has("glyph"):
		profile = source_data.duplicate(true)
	if profile.is_empty():
		_warn_missing_once(icon_type + ":" + source_id + ":icon_profile", "ProceduralIconFactory: missing icon_profile for " + icon_type + " " + source_id + "; using generic unknown icon.")
		profile = {"glyph":"unknown_rune", "base_color":"#1E182A", "accent_color":"#B88CFF", "background":"radial_gradient", "frame":"unknown_ring", "shape_language":"unknown", "rarity_ring":false}
	if not profile.has("glyph"):
		profile["glyph"] = "unknown_rune"
	if not profile.has("base_color"):
		profile["base_color"] = _faction_base_color(str(source_data.get("faction_id", "FACTION_NONE")))
	if not profile.has("accent_color"):
		profile["accent_color"] = _faction_accent_color(str(source_data.get("faction_id", "FACTION_NONE")))
	if not profile.has("frame"):
		profile["frame"] = "faction_ring"
	if not profile.has("background"):
		profile["background"] = "radial_gradient"
	profile["source_id"] = source_id
	profile["icon_type"] = icon_type
	return profile

func _check_icon_coverage(result: Array, category: String, data: Dictionary, item_id: String) -> void:
	var icon_path: String = str(data.get("icon_path", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		return
	var profile: Variant = data.get("icon_profile", {})
	if not (profile is Dictionary) or profile.is_empty():
		result.append({"category": category, "id": item_id, "reason": "missing icon_path and icon_profile"})
		return
	var profile_dict: Dictionary = profile
	for required in ["glyph", "base_color", "accent_color"]:
		if str(profile_dict.get(required, "")).is_empty():
			result.append({"category": category, "id": item_id, "reason": "icon_profile missing " + str(required)})

func _build_icon(profile: Dictionary, size: int) -> Texture2D:
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var base_color: Color = Color(str(profile.get("base_color", "#1E182A")))
	var accent_color: Color = Color(str(profile.get("accent_color", "#B88CFF")))
	var center: Vector2 = Vector2(size * 0.5, size * 0.5)
	_draw_disc(image, center, size * 0.49, Color(0.025, 0.025, 0.04, 0.98))
	_draw_disc(image, center, size * 0.44, Color(base_color.r, base_color.g, base_color.b, 0.78))
	_draw_inner_gradient(image, center, size, base_color, accent_color)
	_draw_ring(image, center, size * 0.47, size * 0.035, Color(accent_color.r, accent_color.g, accent_color.b, 0.92))
	_draw_ring(image, center, size * 0.39, size * 0.010, Color(1, 1, 1, 0.20))
	_draw_glyph(image, str(profile.get("glyph", "unknown_rune")), base_color, accent_color, size)
	_draw_profile_accents(image, profile, accent_color, size)
	return ImageTexture.create_from_image(image)

func _draw_inner_gradient(image: Image, center: Vector2, size: int, base_color: Color, accent_color: Color) -> void:
	var radius: float = size * 0.42
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var d: float = Vector2(x, y).distance_to(center)
			if d <= radius:
				var t: float = clampf(1.0 - d / radius, 0.0, 1.0)
				_blend_pixel(image, x, y, Color(lerpf(base_color.r, accent_color.r, t) * 0.8, lerpf(base_color.g, accent_color.g, t) * 0.8, lerpf(base_color.b, accent_color.b, t) * 0.8, 0.18 + t * 0.20))

func _draw_glyph(image: Image, glyph: String, base_color: Color, accent_color: Color, size: int) -> void:
	var g: String = _canonical_glyph(glyph)
	var c: Vector2 = Vector2(size * 0.5, size * 0.5)
	match g:
		"shuriken":
			for i in range(4):
				var angle: float = TAU * float(i) / 4.0 + PI * 0.25
				_draw_line(image, c, c + Vector2.RIGHT.rotated(angle) * size * 0.28, size * 0.065, accent_color)
			_draw_disc(image, c, size * 0.055, Color(0.9, 0.9, 0.95, 0.90))
		"dagger":
			_draw_line(image, Vector2(size * 0.30, size * 0.74), Vector2(size * 0.70, size * 0.26), size * 0.070, accent_color)
			_draw_line(image, Vector2(size * 0.40, size * 0.72), Vector2(size * 0.75, size * 0.32), size * 0.024, Color(1,1,1,0.80))
		"crescent":
			_draw_arc_shape(image, c, size * 0.24, -PI * 0.8, PI * 0.45, size * 0.055, accent_color)
			_draw_arc_shape(image, c + Vector2(size * 0.05, 0), size * 0.19, -PI * 0.8, PI * 0.45, size * 0.035, Color(1,1,1,0.45))
		"slash":
			_draw_line(image, Vector2(size * 0.24, size * 0.72), Vector2(size * 0.76, size * 0.28), size * 0.075, accent_color)
			_draw_drop_cluster(image, accent_color, size, 3)
		"dash":
			_draw_line(image, Vector2(size * 0.20, size * 0.60), Vector2(size * 0.76, size * 0.36), size * 0.065, accent_color)
			_draw_line(image, Vector2(size * 0.18, size * 0.72), Vector2(size * 0.60, size * 0.58), size * 0.030, Color(1.0, 0.55, 0.25, 0.80))
		"rift":
			_draw_crack(image, accent_color, size, true)
		"impact":
			_draw_disc(image, c, size * 0.14, Color(accent_color.r, accent_color.g, accent_color.b, 0.88))
			for i in range(8):
				var a: float = TAU * float(i) / 8.0
				_draw_line(image, c + Vector2.RIGHT.rotated(a) * size * 0.12, c + Vector2.RIGHT.rotated(a) * size * 0.31, size * 0.028, Color(1,1,1,0.70))
		"shield":
			_draw_shield(image, c, accent_color, size, true)
		"bone":
			_draw_line(image, Vector2(size * 0.33, size * 0.70), Vector2(size * 0.66, size * 0.30), size * 0.070, Color(0.92, 0.84, 0.68, 0.95))
			_draw_crack(image, accent_color, size, false)
		"sound":
			for r in [0.16, 0.25, 0.34]:
				_draw_arc_shape(image, Vector2(size * 0.34, size * 0.52), size * r, -PI * 0.35, PI * 0.35, size * 0.020, accent_color)
		"banner":
			_draw_line(image, Vector2(size * 0.36, size * 0.22), Vector2(size * 0.36, size * 0.78), size * 0.035, Color(0.92,0.82,0.68,0.92))
			_draw_rect(image, Rect2(size * 0.38, size * 0.24, size * 0.28, size * 0.30), accent_color)
		"target":
			_draw_ring(image, c, size * 0.22, size * 0.025, accent_color)
			_draw_line(image, Vector2(size*0.5,size*0.20), Vector2(size*0.5,size*0.80), size*0.022, accent_color)
			_draw_line(image, Vector2(size*0.20,size*0.5), Vector2(size*0.80,size*0.5), size*0.022, accent_color)
		"puddle":
			_draw_disc(image, Vector2(size*0.42,size*0.57), size*0.15, accent_color)
			_draw_disc(image, Vector2(size*0.60,size*0.52), size*0.12, Color(accent_color.r,accent_color.g,accent_color.b,0.65))
			_draw_arc_shape(image, c, size*0.20, PI*0.2, PI*1.55, size*0.025, Color(1,1,1,0.72))
		"wave":
			_draw_arc_shape(image, Vector2(size*0.48,size*0.58), size*0.28, -PI*0.15, PI*0.95, size*0.060, accent_color)
			_draw_line(image, Vector2(size*0.28,size*0.64), Vector2(size*0.75,size*0.64), size*0.025, Color(1,1,1,0.70))
		"water_burst":
			_draw_disc(image, c, size*0.12, accent_color)
			for i in range(10):
				var a: float = TAU * float(i) / 10.0
				_draw_disc(image, c + Vector2.RIGHT.rotated(a) * size*0.25, size*0.035, Color(0.80,0.95,1.0,0.80))
		"fire":
			_draw_disc(image, Vector2(size*0.50,size*0.59), size*0.17, Color(1.0,0.28,0.08,0.88))
			_draw_disc(image, Vector2(size*0.50,size*0.43), size*0.12, Color(1.0,0.78,0.18,0.82))
			_draw_line(image, Vector2(size*0.39,size*0.70), Vector2(size*0.60,size*0.25), size*0.030, accent_color)
		"poison":
			_draw_drop(image, c, size*0.22, accent_color)
			_draw_bubbles(image, Color(0.82,1.0,0.40,0.88), size)
		"dome":
			_draw_arc_shape(image, Vector2(size*0.5,size*0.63), size*0.27, PI, TAU, size*0.055, accent_color)
			_draw_bubbles(image, accent_color, size)
		"wind":
			_draw_line(image, Vector2(size*0.22,size*0.38), Vector2(size*0.78,size*0.34), size*0.032, accent_color)
			_draw_line(image, Vector2(size*0.30,size*0.53), Vector2(size*0.72,size*0.51), size*0.027, Color(1,1,1,0.78))
			_draw_line(image, Vector2(size*0.24,size*0.66), Vector2(size*0.62,size*0.67), size*0.020, accent_color)
		"vortex":
			for r in [0.11,0.18,0.25]:
				_draw_arc_shape(image, c, size*r, -PI*0.1, PI*1.35, size*0.025, accent_color)
		"storm":
			_draw_disc(image, c, size*0.19, Color(accent_color.r,accent_color.g,accent_color.b,0.58))
			_draw_lightning(image, Color(1.0,0.92,0.25,0.95), size)
		"lightning":
			_draw_lightning(image, accent_color, size)
		"void_eye":
			_draw_ring(image, c, size*0.20, size*0.035, accent_color)
			_draw_disc(image, c, size*0.08, Color(0.05,0.02,0.10,0.95))
		"void_collapse":
			_draw_ring(image, c, size*0.25, size*0.035, accent_color)
			for i in range(6):
				var a: float = TAU*float(i)/6.0
				_draw_line(image, c + Vector2.RIGHT.rotated(a)*size*0.34, c + Vector2.RIGHT.rotated(a)*size*0.20, size*0.022, accent_color)
		"heart":
			_draw_disc(image, Vector2(size*0.42,size*0.43), size*0.10, accent_color)
			_draw_disc(image, Vector2(size*0.58,size*0.43), size*0.10, accent_color)
			_draw_line(image, Vector2(size*0.35,size*0.50), Vector2(size*0.50,size*0.72), size*0.080, accent_color)
			_draw_line(image, Vector2(size*0.65,size*0.50), Vector2(size*0.50,size*0.72), size*0.080, accent_color)
		"arrows":
			for i in range(4):
				var a: float = TAU*float(i)/4.0
				_draw_line(image, c - Vector2.RIGHT.rotated(a)*size*0.30, c - Vector2.RIGHT.rotated(a)*size*0.11, size*0.030, accent_color)
		_:
			for i in range(8):
				var a: float = TAU*float(i)/8.0
				_draw_line(image, c, c + Vector2.RIGHT.rotated(a)*size*0.24, size*0.023, accent_color)

func _canonical_glyph(glyph: String) -> String:
	var g: String = glyph.to_lower()
	if g.contains("shuriken"):
		return "shuriken"
	if g.contains("dagger"):
		return "dagger"
	if g.contains("crescent") or g.contains("arc") or g.contains("slash"):
		return "crescent" if g.contains("crescent") else "slash"
	if g.contains("dash"):
		return "dash"
	if g.contains("rift") or g.contains("crack"):
		return "rift"
	if g.contains("hammer") or g.contains("impact") or g.contains("burst") or g.contains("eruption"):
		return "impact" if not g.contains("water") and not g.contains("flower") else "water_burst"
	if g.contains("shield") or g.contains("armor"):
		return "shield"
	if g.contains("bone"):
		return "bone"
	if g.contains("cry") or g.contains("wave") and g.contains("shout"):
		return "sound"
	if g.contains("banner"):
		return "banner"
	if g.contains("execution") or g.contains("target") or g.contains("mark"):
		return "target"
	if g.contains("puddle") or g.contains("spiral"):
		return "puddle"
	if g.contains("wave"):
		return "wave"
	if g.contains("water_burst") or g.contains("droplet"):
		return "water_burst"
	if g.contains("fire") or g.contains("flame") or g.contains("volcanic"):
		return "fire"
	if g.contains("poison") or g.contains("spore") or g.contains("toxic") or g.contains("drop"):
		return "poison" if not g.contains("dome") and not g.contains("storm") else ("dome" if g.contains("dome") else "poison")
	if g.contains("dome"):
		return "dome"
	if g.contains("wind") or g.contains("air"):
		return "wind"
	if g.contains("vortex"):
		return "vortex"
	if g.contains("storm"):
		return "storm"
	if g.contains("lightning") or g.contains("spark") or g.contains("thunder"):
		return "lightning"
	if g.contains("void_eye") or g.contains("eye"):
		return "void_eye"
	if g.contains("collapse"):
		return "void_collapse"
	if g.contains("heart") or g.contains("heal"):
		return "heart"
	if g.contains("arrow") or g.contains("reroll") or g.contains("circular") or g.contains("inward") or g.contains("outward"):
		return "arrows"
	return g

func _draw_profile_accents(image: Image, profile: Dictionary, color: Color, size: int) -> void:
	var frame: String = str(profile.get("frame", ""))
	if frame.contains("gold") or frame.contains("rune"):
		_draw_ring(image, Vector2(size*0.5,size*0.5), size*0.50, size*0.025, Color(1.0,0.78,0.28,0.95))
	elif frame.contains("status"):
		_draw_ring(image, Vector2(size*0.5,size*0.5), size*0.50, size*0.018, Color(color.r,color.g,color.b,0.70))
	elif frame.contains("reaction"):
		for i in range(6):
			var a: float = TAU*float(i)/6.0
			_draw_disc(image, Vector2(size*0.5,size*0.5)+Vector2.RIGHT.rotated(a)*size*0.43, size*0.025, Color(color.r,color.g,color.b,0.92))
	if bool(profile.get("rarity_ring", false)):
		_draw_ring(image, Vector2(size*0.5,size*0.5), size*0.49, size*0.018, Color(1.0,0.85,0.35,0.85))

func _reaction_profile(reaction_id: String) -> Dictionary:
	var key: String = reaction_id.to_lower()
	if REACTION_ICON_PROFILES.has(key):
		return REACTION_ICON_PROFILES[key].duplicate(true)
	return {"id": reaction_id, "icon_profile": {"glyph":"unknown_rune", "base_color":"#25182E", "accent_color":"#B88CFF"}}

func _status_profile(status_id: String) -> Dictionary:
	var key: String = status_id.to_lower()
	if STATUS_ICON_PROFILES.has(key):
		return STATUS_ICON_PROFILES[key].duplicate(true)
	return {"id": status_id, "icon_profile": {"glyph":"unknown_rune", "base_color":"#1E182A", "accent_color":"#B88CFF"}}

func _faction_base_color(faction_id: String) -> String:
	return str(FACTION_BASE_COLORS.get(faction_id, FACTION_BASE_COLORS["FACTION_NONE"]))

func _faction_accent_color(faction_id: String) -> String:
	return str(FACTION_ACCENT_COLORS.get(faction_id, FACTION_ACCENT_COLORS["FACTION_NONE"]))

func _warn_missing_once(key: String, message: String) -> void:
	if _missing_icon_warnings.has(key):
		return
	_missing_icon_warnings[key] = true
	push_warning(message)

func _draw_drop_cluster(image: Image, color: Color, size: int, count: int) -> void:
	for i in range(count):
		_draw_disc(image, Vector2(size*(0.32+0.13*float(i)), size*(0.25+0.08*float(i))), size*0.030, color)

func _draw_bubbles(image: Image, color: Color, size: int) -> void:
	for p in [Vector2(0.35,0.40), Vector2(0.62,0.37), Vector2(0.68,0.60), Vector2(0.42,0.68)]:
		_draw_disc(image, Vector2(size*p.x, size*p.y), size*0.038, color)

func _draw_drop(image: Image, center: Vector2, radius: float, color: Color) -> void:
	_draw_disc(image, center + Vector2(0, radius*0.20), radius*0.72, color)
	_draw_line(image, center + Vector2(0, -radius), center + Vector2(-radius*0.45, radius*0.10), radius*0.16, color)
	_draw_line(image, center + Vector2(0, -radius), center + Vector2(radius*0.45, radius*0.10), radius*0.16, color)

func _draw_lightning(image: Image, color: Color, size: int) -> void:
	_draw_line(image, Vector2(size*0.56,size*0.18), Vector2(size*0.40,size*0.49), size*0.060, color)
	_draw_line(image, Vector2(size*0.40,size*0.49), Vector2(size*0.63,size*0.46), size*0.060, color)
	_draw_line(image, Vector2(size*0.63,size*0.46), Vector2(size*0.43,size*0.83), size*0.060, color)

func _draw_shield(image: Image, center: Vector2, color: Color, size: int, cracked: bool) -> void:
	_draw_line(image, Vector2(size*0.36,size*0.24), Vector2(size*0.66,size*0.30), size*0.060, color)
	_draw_line(image, Vector2(size*0.36,size*0.24), Vector2(size*0.34,size*0.58), size*0.060, color)
	_draw_line(image, Vector2(size*0.66,size*0.30), Vector2(size*0.62,size*0.61), size*0.060, color)
	_draw_line(image, Vector2(size*0.34,size*0.58), Vector2(size*0.50,size*0.76), size*0.060, color)
	_draw_line(image, Vector2(size*0.62,size*0.61), Vector2(size*0.50,size*0.76), size*0.060, color)
	if cracked:
		_draw_line(image, Vector2(size*0.52,size*0.30), Vector2(size*0.45,size*0.52), size*0.020, Color(0.05,0.04,0.04,0.95))
		_draw_line(image, Vector2(size*0.45,size*0.52), Vector2(size*0.55,size*0.62), size*0.020, Color(0.05,0.04,0.04,0.95))

func _draw_crack(image: Image, color: Color, size: int, vertical: bool) -> void:
	if vertical:
		_draw_line(image, Vector2(size*0.50,size*0.19), Vector2(size*0.39,size*0.47), size*0.050, color)
		_draw_line(image, Vector2(size*0.39,size*0.47), Vector2(size*0.59,size*0.53), size*0.050, color)
		_draw_line(image, Vector2(size*0.59,size*0.53), Vector2(size*0.45,size*0.82), size*0.050, color)
	else:
		_draw_line(image, Vector2(size*0.24,size*0.56), Vector2(size*0.47,size*0.48), size*0.045, color)
		_draw_line(image, Vector2(size*0.47,size*0.48), Vector2(size*0.72,size*0.58), size*0.045, color)

func _draw_arc_shape(image: Image, center: Vector2, radius: float, start_angle: float, end_angle: float, width: float, color: Color) -> void:
	var steps: int = 24
	var previous: Vector2 = center + Vector2.RIGHT.rotated(start_angle) * radius
	for i in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		var angle: float = lerpf(start_angle, end_angle, t)
		var current: Vector2 = center + Vector2.RIGHT.rotated(angle) * radius
		_draw_line(image, previous, current, width, color)
		previous = current

func _draw_disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var min_x: int = clampi(int(floor(center.x - radius - 1.0)), 0, image.get_width() - 1)
	var max_x: int = clampi(int(ceil(center.x + radius + 1.0)), 0, image.get_width() - 1)
	var min_y: int = clampi(int(floor(center.y - radius - 1.0)), 0, image.get_height() - 1)
	var max_y: int = clampi(int(ceil(center.y + radius + 1.0)), 0, image.get_height() - 1)
	var r2: float = radius * radius
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if Vector2(x, y).distance_squared_to(center) <= r2:
				_blend_pixel(image, x, y, color)

func _draw_ring(image: Image, center: Vector2, radius: float, width: float, color: Color) -> void:
	var outer: float = radius + width * 0.5
	var inner: float = max(0.0, radius - width * 0.5)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var d: float = Vector2(x, y).distance_to(center)
			if d >= inner and d <= outer:
				_blend_pixel(image, x, y, color)

func _draw_rect(image: Image, rect: Rect2, color: Color) -> void:
	for y in range(clampi(int(rect.position.y), 0, image.get_height() - 1), clampi(int(rect.end.y), 0, image.get_height() - 1)):
		for x in range(clampi(int(rect.position.x), 0, image.get_width() - 1), clampi(int(rect.end.x), 0, image.get_width() - 1)):
			_blend_pixel(image, x, y, color)

func _draw_line(image: Image, start: Vector2, end: Vector2, width: float, color: Color) -> void:
	var steps: int = max(1, int(start.distance_to(end) * 1.5))
	for i in range(steps + 1):
		var p: Vector2 = start.lerp(end, float(i) / float(steps))
		_draw_disc(image, p, max(1.0, width * 0.5), color)

func _blend_pixel(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height() or color.a <= 0.0:
		return
	var dst: Color = image.get_pixel(x, y)
	var a: float = clampf(color.a, 0.0, 1.0)
	var out: Color = dst.lerp(Color(color.r, color.g, color.b, 1.0), a)
	out.a = clampf(dst.a + a * (1.0 - dst.a), 0.0, 1.0)
	image.set_pixel(x, y, out)
