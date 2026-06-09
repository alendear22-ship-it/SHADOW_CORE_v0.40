extends AnimatedSprite2D
class_name SpriteSheetAnimator

# Patch T: enemy/boss sprite sheets are not reliable enough to animate with one universal grid.
# This class now supports a safe static-frame path that finds one whole frame and prevents
# half-frame / duplicated-frame rendering when sheets have different layouts.

var _default_animation_name: String = "idle"

func _ready() -> void:
	centered = true
	z_index = 2
	if sprite_frames == null:
		sprite_frames = SpriteFrames.new()

func clear_all() -> void:
	sprite_frames = SpriteFrames.new()

func add_static_sheet_frame(anim_name: String, texture_path: String, fps: float = 1.0, loop: bool = true, columns: int = 0, rows: int = 0) -> bool:
	if anim_name.is_empty() or texture_path.is_empty():
		return false
	var atlas_texture: Texture2D = SpriteSheetAnimator.make_static_atlas(texture_path, columns, rows)
	if atlas_texture == null:
		return false
	if sprite_frames == null:
		sprite_frames = SpriteFrames.new()
	if sprite_frames.has_animation(anim_name):
		sprite_frames.remove_animation(anim_name)
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_speed(anim_name, max(1.0, fps))
	sprite_frames.set_animation_loop(anim_name, loop)
	sprite_frames.add_frame(anim_name, atlas_texture)
	if animation.is_empty() or animation == _default_animation_name:
		animation = anim_name
		_default_animation_name = anim_name
	return true

func add_sheet_animation(anim_name: String, texture_path: String, fps: float = 8.0, loop: bool = true, columns: int = 0, rows: int = 0, row_index: int = -1) -> bool:
	# Patch U: animation is enabled again. Mob sheets are sliced only by an explicit 8x4 grid
	# supplied by callers, using a single row. Attack sheets are still avoided in enemy code.
	if anim_name.is_empty() or texture_path.is_empty():
		return false
	if not ResourceLoader.exists(texture_path):
		return false
	var texture: Texture2D = load(texture_path) as Texture2D
	if texture == null:
		return false
	if sprite_frames == null:
		sprite_frames = SpriteFrames.new()
	if sprite_frames.has_animation(anim_name):
		sprite_frames.remove_animation(anim_name)
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_speed(anim_name, max(1.0, fps))
	sprite_frames.set_animation_loop(anim_name, loop)

	var grid: Vector2i = _infer_grid(texture, texture_path, columns, rows)
	var frame_width: float = float(texture.get_width()) / float(max(1, grid.x))
	var frame_height: float = float(texture.get_height()) / float(max(1, grid.y))

	if row_index >= 0 and grid.y > 1:
		var safe_row: int = clampi(row_index, 0, grid.y - 1)
		for c in range(grid.x):
			_add_atlas_frame(anim_name, texture, _safe_region(frame_width * float(c), frame_height * float(safe_row), frame_width, frame_height, texture))
	else:
		for r in range(grid.y):
			for c in range(grid.x):
				_add_atlas_frame(anim_name, texture, _safe_region(frame_width * float(c), frame_height * float(r), frame_width, frame_height, texture))

	if sprite_frames.get_frame_count(anim_name) <= 0:
		sprite_frames.remove_animation(anim_name)
		return false
	if animation.is_empty() or animation == _default_animation_name:
		animation = anim_name
		_default_animation_name = anim_name
	return true

func add_sequence_animation(anim_name: String, texture_paths: Array, fps: float = 12.0, loop: bool = false) -> bool:
	if anim_name.is_empty():
		return false
	if sprite_frames == null:
		sprite_frames = SpriteFrames.new()
	if sprite_frames.has_animation(anim_name):
		sprite_frames.remove_animation(anim_name)
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_speed(anim_name, max(1.0, fps))
	sprite_frames.set_animation_loop(anim_name, loop)
	var added: bool = false
	for path_value in texture_paths:
		var texture_path: String = str(path_value)
		if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
			continue
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture == null:
			continue
		sprite_frames.add_frame(anim_name, texture)
		added = true
	if not added:
		sprite_frames.remove_animation(anim_name)
		return false
	if animation.is_empty():
		animation = anim_name
	return true

func play_if_available(anim_name: String) -> bool:
	if sprite_frames == null or not sprite_frames.has_animation(anim_name):
		return false
	if animation != anim_name:
		play(anim_name)
	elif not is_playing():
		play()
	return true

func has_anim(anim_name: String) -> bool:
	return sprite_frames != null and sprite_frames.has_animation(anim_name)

func _add_atlas_frame(anim_name: String, texture: Texture2D, region: Rect2) -> void:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	atlas.set("filter_clip", true)
	sprite_frames.add_frame(anim_name, atlas)

static func make_static_atlas(texture_path: String, columns: int = 0, rows: int = 0) -> Texture2D:
	if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
		return null
	var texture: Texture2D = load(texture_path) as Texture2D
	if texture == null:
		return null
	var region: Rect2 = SpriteSheetAnimator._best_static_region(texture, texture_path, columns, rows)
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	atlas.set("filter_clip", true)
	return atlas

static func _best_static_region(texture: Texture2D, texture_path: String, requested_columns: int = 0, requested_rows: int = 0) -> Rect2:
	if texture == null:
		return Rect2(0, 0, 1, 1)
	var image: Image = texture.get_image()
	var texture_width: int = max(1, texture.get_width())
	var texture_height: int = max(1, texture.get_height())
	var candidates: Array[Vector2i] = SpriteSheetAnimator._candidate_grids(texture, texture_path, requested_columns, requested_rows)
	var best_region: Rect2 = Rect2(0, 0, texture_width, texture_height)
	var best_score: float = -999999.0

	for grid in candidates:
		var cols: int = max(1, grid.x)
		var rows: int = max(1, grid.y)
		var cell_w: float = float(texture_width) / float(cols)
		var cell_h: float = float(texture_height) / float(rows)
		var frames_to_scan: int = min(cols * rows, 16)
		for frame_index in range(frames_to_scan):
			var col: int = frame_index % cols
			var row: int = int(frame_index / cols)
			var region: Rect2 = SpriteSheetAnimator._safe_region_static(cell_w * float(col), cell_h * float(row), cell_w, cell_h, texture_width, texture_height)
			var score: float = SpriteSheetAnimator._score_region(image, region)
			if score > best_score:
				best_score = score
				best_region = region

	# If alpha analysis failed, prefer a known-safe top-left cell over the whole sheet.
	if best_score <= -900000.0:
		var fallback_grid: Vector2i = candidates[0] if not candidates.is_empty() else Vector2i.ONE
		best_region = SpriteSheetAnimator._safe_region_static(0.0, 0.0, float(texture_width) / float(max(1, fallback_grid.x)), float(texture_height) / float(max(1, fallback_grid.y)), texture_width, texture_height)
	return best_region


static func grid_for_texture_path(texture_path: String, requested_columns: int = 0, requested_rows: int = 0) -> Vector2i:
	if requested_columns > 0 and requested_rows > 0:
		return Vector2i(max(1, requested_columns), max(1, requested_rows))
	if texture_path.contains("/mobs-orc/"):
		var lower_path: String = texture_path.to_lower()
		if lower_path.contains("_attack"):
			return Vector2i(8, 4)
		if lower_path.contains("_death"):
			return Vector2i(6, 4)
		if lower_path.contains("_hurt"):
			return Vector2i(6, 4)
		if lower_path.contains("_idle"):
			return Vector2i(4, 4)
		if lower_path.contains("_run"):
			return Vector2i(8, 4)
		if lower_path.contains("_walk"):
			return Vector2i(6, 4)
		return Vector2i(4, 4)
	return Vector2i.ZERO

static func _candidate_grids(texture: Texture2D, texture_path: String, requested_columns: int = 0, requested_rows: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var explicit_grid: Vector2i = SpriteSheetAnimator.grid_for_texture_path(texture_path, requested_columns, requested_rows)
	SpriteSheetAnimator._push_unique_grid(result, explicit_grid)

	# Orc sheets have confirmed per-animation layouts. Keep these first so room cards and
	# boss previews no longer sample between two frames. Other enemy families keep the
	# previous broad fallbacks.
	if texture_path.contains("/mobs-orc/"):
		SpriteSheetAnimator._push_unique_grid(result, explicit_grid)
	elif texture_path.contains("/mobs-slime/"):
		SpriteSheetAnimator._push_unique_grid(result, Vector2i(8, 4))
		SpriteSheetAnimator._push_unique_grid(result, Vector2i(4, 8))
	elif texture_path.contains("/mobs-vampires/"):
		SpriteSheetAnimator._push_unique_grid(result, Vector2i(8, 4))
		SpriteSheetAnimator._push_unique_grid(result, Vector2i(4, 8))
	else:
		SpriteSheetAnimator._push_unique_grid(result, Vector2i(8, 4))
		SpriteSheetAnimator._push_unique_grid(result, Vector2i(4, 8))

	# Horizontal strip fallback for player/effects.
	var generic: Vector2i = SpriteSheetAnimator._infer_grid_static(texture, texture_path, 0, 0)
	SpriteSheetAnimator._push_unique_grid(result, generic)
	if result.is_empty():
		result.append(Vector2i.ONE)
	return result

static func _push_unique_grid(result: Array[Vector2i], grid: Vector2i) -> void:
	if grid.x <= 0 or grid.y <= 0:
		return
	for existing in result:
		if existing == grid:
			return
	result.append(grid)

static func _score_region(image: Image, region: Rect2) -> float:
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return -999999.0
	var x0: int = clampi(int(floor(region.position.x)), 0, image.get_width() - 1)
	var y0: int = clampi(int(floor(region.position.y)), 0, image.get_height() - 1)
	var x1: int = clampi(int(ceil(region.position.x + region.size.x)), x0 + 1, image.get_width())
	var y1: int = clampi(int(ceil(region.position.y + region.size.y)), y0 + 1, image.get_height())
	var step_x: int = max(1, int(float(x1 - x0) / 32.0))
	var step_y: int = max(1, int(float(y1 - y0) / 32.0))
	var min_x: int = 999999
	var min_y: int = 999999
	var max_x: int = -999999
	var max_y: int = -999999
	var opaque_count: int = 0
	var sample_count: int = 0
	for y in range(y0, y1, step_y):
		for x in range(x0, x1, step_x):
			sample_count += 1
			if image.get_pixel(x, y).a > 0.05:
				opaque_count += 1
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)
	if opaque_count <= 0 or sample_count <= 0:
		return -999999.0
	var margin: int = max(2, int(min(region.size.x, region.size.y) * 0.05))
	var edge_penalty: float = 0.0
	if min_x <= x0 + margin:
		edge_penalty += 1.0
	if max_x >= x1 - margin:
		edge_penalty += 1.0
	if min_y <= y0 + margin:
		edge_penalty += 0.4
	if max_y >= y1 - margin:
		edge_penalty += 0.4
	var used_w: float = float(max_x - min_x + 1)
	var used_h: float = float(max_y - min_y + 1)
	var used_ratio: float = clampf((used_w * used_h) / max(1.0, region.size.x * region.size.y), 0.0, 1.0)
	var opaque_ratio: float = float(opaque_count) / float(sample_count)
	var sprite_center: Vector2 = Vector2((float(min_x + max_x) * 0.5), (float(min_y + max_y) * 0.5))
	var cell_center: Vector2 = region.position + region.size * 0.5
	var center_penalty: float = sprite_center.distance_to(cell_center) / max(1.0, min(region.size.x, region.size.y))
	return used_ratio * 80.0 + opaque_ratio * 40.0 - edge_penalty * 35.0 - center_penalty * 15.0

static func _safe_region_static(x: float, y: float, w: float, h: float, texture_width: int, texture_height: int) -> Rect2:
	var margin: float = 1.0
	var rx: float = clampf(x + margin, 0.0, float(texture_width))
	var ry: float = clampf(y + margin, 0.0, float(texture_height))
	var rw: float = max(1.0, min(w - margin * 2.0, float(texture_width) - rx))
	var rh: float = max(1.0, min(h - margin * 2.0, float(texture_height) - ry))
	return Rect2(rx, ry, rw, rh)

func _safe_region(x: float, y: float, w: float, h: float, texture: Texture2D) -> Rect2:
	return SpriteSheetAnimator._safe_region_static(x, y, w, h, max(1, texture.get_width()), max(1, texture.get_height()))

func _infer_grid(texture: Texture2D, texture_path: String, requested_columns: int = 0, requested_rows: int = 0) -> Vector2i:
	return SpriteSheetAnimator._infer_grid_static(texture, texture_path, requested_columns, requested_rows)

static func _infer_grid_static(texture: Texture2D, texture_path: String, requested_columns: int = 0, requested_rows: int = 0) -> Vector2i:
	if texture == null:
		return Vector2i.ONE
	if requested_columns > 0 and requested_rows > 0:
		return Vector2i(max(1, requested_columns), max(1, requested_rows))
	var width: int = max(1, texture.get_width())
	var height: int = max(1, texture.get_height())
	var explicit_grid: Vector2i = SpriteSheetAnimator.grid_for_texture_path(texture_path, requested_columns, requested_rows)
	if explicit_grid.x > 0 and explicit_grid.y > 0:
		return explicit_grid
	if texture_path.contains("/assets/sprites/enemies/mob/"):
		return Vector2i(8, 4)
	if width <= height * 1.35:
		return Vector2i.ONE
	var guessed: int = int(round(float(width) / float(height)))
	guessed = clampi(guessed, 1, 16)
	while guessed > 1 and width % guessed != 0:
		guessed -= 1
	return Vector2i(max(1, guessed), 1)
