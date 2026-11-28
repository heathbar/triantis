@tool
extends RefCounted
## Per-act art for the Braid campaign. braid_game.gd calls set_act() as it
## builds each act's level; enemies (when they spawn) and level pieces (when
## they draw) ask here for their textures. The arena game (game.gd) goes
## through the same themes in the same order, one every 5 waves (each ending
## on its boss), or uses the theme a custom game picked (set_theme).
##
## Art lives in assets/<theme>/enemies and assets/<theme>/environment, named
## after what it's for, numbered per variation (grunt-1.png, grunt-2.png;
## animation frames get a letter: swarmling-1a.png, swarmling-1b.png).
##
## Act themes:
##   act 1: "meadow", the default art (each script preloads it itself)
##   act 2: "ocean"
##   act 3: "junkyard"
##   act 4: "robot"
## (Junkyard and meadow swapped places 2026-11-24, their bosses with them:
## see data/waves/wave_05.tres and wave_15.tres.)
##
## Environment textures are optional: environment() looks for the theme's
## file for a role and falls back to the meadow art when there isn't one,
## so new tiles can just be dropped in. Roles: "block" (wall blocks),
## "roof" and "store-mat" (checkpoint shop), "background" (the ground, also
## behind the shop), "window" (32x32 tile for the panes of windows between
## lanes; see optional_environment: plain drawn glass when there's none),
## "wall" (64x16 tiles for the lane walls the level builds; see
## optional_environment_options: block-1 art when there's none).
## A role's file is assets/<theme>/environment/<role>-1.png; "block" also
## has variations block-2.png and block-3.png (picked per block with its
## `variant`). Any variation can instead come as lettered alternatives
## (block-1a.png, block-1b.png, ...; any role, gaps in the letters are
## fine): environment_options() lists them, and environment() picks one with
## its `pick`. Blocks mix them (braid_block.gd: per 24px cell, or per
## picture for block-2). The plain file is only used when there are no
## lettered ones.

## Theme name per act (0-based); "" = default art.
const ACT_THEMES: Array[String] = ["", "ocean", "junkyard", "robot"]

## Enemy looks per theme: kind -> the textures one is picked from at random
## (each one still image). Kinds missing here keep their default (meadow)
## art, which each enemy script preloads itself, animation frames and all
## (the sprayer outside junkyard and robot, for one).
const ENEMY_LOOKS := {
	"junkyard": {
		"grunt": [
			preload("res://assets/junkyard/enemies/grunt-1.png"),
			preload("res://assets/junkyard/enemies/grunt-2.png"),
			preload("res://assets/junkyard/enemies/grunt-3.png"),
		],
		"swarmling": [
			preload("res://assets/junkyard/enemies/swarmling-1.png"),
			preload("res://assets/junkyard/enemies/swarmling-2.png"),
			preload("res://assets/junkyard/enemies/swarmling-3.png"),
		],
		"runner": [preload("res://assets/junkyard/enemies/runner-1.png")],
		"brute": [preload("res://assets/junkyard/enemies/brute-1.png")],
		"charger": [preload("res://assets/junkyard/enemies/charger-1.png")],
		"bomber": [preload("res://assets/junkyard/enemies/bomber-1.png")],
		"splitter": [preload("res://assets/junkyard/enemies/splitter-1.png")],
		"shooter": [preload("res://assets/junkyard/enemies/shooter-1.png")],
		"sprayer": [preload("res://assets/junkyard/enemies/sprayer-1.png")],
	},
	"ocean": {
		"grunt": [
			preload("res://assets/ocean/enemies/grunt-1.png"),
			preload("res://assets/ocean/enemies/grunt-2.png"),
		],
		"runner": [preload("res://assets/ocean/enemies/runner-1.png")],
		"swarmling": [
			preload("res://assets/ocean/enemies/swarmling-1.png"),
			preload("res://assets/ocean/enemies/swarmling-2.png"),
		],
		"brute": [preload("res://assets/ocean/enemies/brute-1.png")],
		"charger": [preload("res://assets/ocean/enemies/charger-1.png")],
		"bomber": [preload("res://assets/ocean/enemies/bomber-1.png")],
		"splitter": [preload("res://assets/ocean/enemies/splitter-1.png")],
		"shooter": [preload("res://assets/ocean/enemies/shooter-1.png")],
	},
	"robot": {
		"grunt": [
			preload("res://assets/robot/enemies/grunt-1.png"),
			preload("res://assets/robot/enemies/grunt-2.png"),
			preload("res://assets/robot/enemies/grunt-3.png"),
		],
		"runner": [preload("res://assets/robot/enemies/runner-1.png")],
		"swarmling": [
			preload("res://assets/robot/enemies/swarmling-1.png"),
			preload("res://assets/robot/enemies/swarmling-2.png"),
			preload("res://assets/robot/enemies/swarmling-3.png"),
		],
		"brute": [preload("res://assets/robot/enemies/brute-1.png")],
		"charger": [preload("res://assets/robot/enemies/charger-1.png")],
		"bomber": [
			preload("res://assets/robot/enemies/bomber-1.png"),
			preload("res://assets/robot/enemies/bomber-2.png"),
			preload("res://assets/robot/enemies/bomber-3.png"),
			preload("res://assets/robot/enemies/bomber-4.png"),
		],
		"splitter": [preload("res://assets/robot/enemies/splitter-1.png")],
		"shooter": [preload("res://assets/robot/enemies/shooter-1.png")],
		"sprayer": [preload("res://assets/robot/enemies/sprayer-1.png")],
	},
}

## Every theme, in menu order (the custom game's theme picker). "meadow" is
## the default art (current "").
const THEMES := [
	{"id": "meadow", "name": "Meadow"},
	{"id": "junkyard", "name": "Junkyard"},
	{"id": "ocean", "name": "Ocean"},
	{"id": "robot", "name": "Robot"},
]

## The current theme ("" = default art).
static var current := ""
## "theme/role-variant" (and ".../lettered") -> Array of Texture2Ds (see
## _env_textures and _lettered_textures; empty when there's no file).
static var _env_cache := {}
## Texture -> its opaque Rect2i (see used_rect), worked out once per image:
## reading an image back is far too slow to do for every enemy that spawns.
static var _used_rects := {}


static func set_act(act: int) -> void:
	current = ACT_THEMES[act] if act >= 0 and act < ACT_THEMES.size() else ""


## The THEMES id act `act` (0-based) uses; past the last act, the last one's.
static func act_theme(act: int) -> String:
	var name: String = ACT_THEMES[clampi(act, 0, ACT_THEMES.size() - 1)]
	return name if name != "" else "meadow"


## Uses theme `id` (a THEMES id; "meadow" or unknown = the default art).
static func set_theme(id: String) -> void:
	current = id if id != "meadow" and THEMES.any(func(t: Dictionary) -> bool: return t["id"] == id) else ""


static func reset() -> void:
	current = ""


## Frame `t` seconds into a looping animation of `frames`, `frame_time`
## seconds each (one frame = a still image).
static func frame_at(frames: Array, t: float, frame_time: float) -> Texture2D:
	return frames[int(t / frame_time) % frames.size()]


## The current theme's looks for enemy `kind`, or [] for its default art.
static func enemy_looks(kind: String) -> Array:
	return ENEMY_LOOKS.get(current, {}).get(kind, [])


## A random current-theme look for `kind`, or null for its default art.
static func enemy_look(kind: String) -> Texture2D:
	var looks := enemy_looks(kind)
	return looks.pick_random() if not looks.is_empty() else null


## The current theme's environment texture for `role` (e.g. "block"),
## variation `variant` (its <role>-<variant>.png, or one of its lettered
## alternatives chosen by `pick`). Falls back to the meadow art's file for
## that variation, then to `fallback` (the meadow's <role>-1).
static func environment(role: String, fallback: Texture2D, variant := 1, pick := 0) -> Texture2D:
	var options := environment_options(role, fallback, variant)
	return options[posmod(pick, options.size())]


## Every texture environment() can pick from for `role`/`variant` (never
## empty): the lettered alternatives when there are any, else one texture.
static func environment_options(role: String, fallback: Texture2D, variant := 1) -> Array:
	var options := _env_textures(current, role, variant) if current != "" else []
	if options.is_empty() and variant != 1:
		options = _env_textures("meadow", role, variant)
	if options.is_empty() and current == "" and variant == 1:
		# No theme: `fallback` is the default art, unless the meadow has
		# lettered alternatives for it.
		options = _lettered_textures("meadow", role, 1)
	return options if not options.is_empty() else [fallback]


## The current theme's <role>-1.png (the meadow's when no act theme is set),
## or null if there's none: for roles with no default art.
static func optional_environment(role: String) -> Texture2D:
	return _env_texture(current if current != "" else "meadow", role, 1)


## Every texture of the current theme's <role>-<variant> (lettered
## alternatives, or the plain file; the meadow's when no act theme is set),
## or [] if it has none: for roles with no default art.
static func optional_environment_options(role: String, variant := 1) -> Array:
	return _env_textures(current if current != "" else "meadow", role, variant)


## assets/<theme>/environment/<role>-<variant>.png, or null if there's none.
## When lettered alternatives exist (<role>-<variant>a.png, b, c, ...), one
## of them instead: number `pick` of them (wrapping round).
static func _env_texture(theme: String, role: String, variant: int, pick := 0) -> Texture2D:
	var options := _env_textures(theme, role, variant)
	return options[posmod(pick, options.size())] if not options.is_empty() else null


## Every texture for <role>-<variant> in `theme`: its lettered alternatives
## if it has any, else just the plain file (or none).
static func _env_textures(theme: String, role: String, variant: int) -> Array:
	var key := "%s/%s-%d" % [theme, role, variant]
	if not _env_cache.has(key):
		var options := _lettered_textures(theme, role, variant)
		var plain := "res://assets/%s/environment/%s-%d.png" % [theme, role, variant]
		if options.is_empty() and ResourceLoader.exists(plain):
			options = [load(plain)]
		_env_cache[key] = options
	return _env_cache[key]


## <role>-<variant>a.png, b, c, ... z in `theme` (gaps allowed), or [].
static func _lettered_textures(theme: String, role: String, variant: int) -> Array:
	var key := "%s/%s-%d/lettered" % [theme, role, variant]
	if not _env_cache.has(key):
		var options := []
		for code in range("a".unicode_at(0), "z".unicode_at(0) + 1):
			var path := "res://assets/%s/environment/%s-%d%s.png" % [theme, role, variant, String.chr(code)]
			if ResourceLoader.exists(path):
				options.append(load(path))
		_env_cache[key] = options
	return _env_cache[key]


## The part of `texture` that has opaque pixels (all of it if none do).
static func used_rect(texture: Texture2D) -> Rect2i:
	if not _used_rects.has(texture):
		var image := texture.get_image()
		var used := image.get_used_rect() if image else Rect2i()
		if used.size == Vector2i.ZERO:
			used = Rect2i(Vector2i.ZERO, Vector2i(texture.get_size()))
		_used_rects[texture] = used
	return _used_rects[texture]


## Puts `texture` on `enemy`'s Sprite2D (pixel-snapped, centred, unscaled)
## and sizes its collision rectangle to the texture's opaque pixels.
static func apply_look(enemy: Node2D, texture: Texture2D) -> void:
	var sprite := enemy.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var used := used_rect(texture)
	var size := Vector2(used.size)
	var offset := -Vector2(used.position) - (size / 2.0).floor()
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = offset
	sprite.scale = Vector2.ONE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	var shape_node := enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node:
		var rect := RectangleShape2D.new()  # Own copy: the scene's is shared.
		rect.size = size
		shape_node.shape = rect
		shape_node.position = offset + Vector2(used.position) + size / 2.0
