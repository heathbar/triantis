@tool
extends StaticBody2D
## A solid wall block in a Braid level piece (tiled with the act's block texture). Its top-left corner is
## at the node's position and it is `size` big. Players, enemies and shots
## can't pass it (BraidTuning.WALL_LAYER).
##
## In the editor: drag it to move it, set `size` in the inspector.
##
## `style`: "wall" (solid), "glass" (a pane, e.g. a gun port: bodies can't
## pass, shots can, BraidTuning.WINDOW_LAYER), "window" (a pane in a window
## between lanes: like glass, drawn with the act's window-1.png tiled from the
## block's top-left, or as plain glass if the act has none) or "seal" (a
## junction exit closed to this squad only: like glass, drawn with the act's
## window art turned 90 degrees clockwise, or as a force field in `tint` if
## the act has none).

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")

## The last-resort wall tile (the meadow's own lettered tiles are normally
## used: see ActTheme.environment_options), repeated on a world-aligned grid
## so the bricks line up across blocks that touch.
const TEXTURE := preload("res://assets/meadow/environment/block-1a.png")
## Lettered block art is mixed per cell of this size (TEXTURE's size).
const TILE := 24.0
## The act's own block texture replaces TEXTURE, when it has one.
const ActTheme := preload("res://scripts/act_theme.gd")
const OUTLINE := Color(0.14, 0.13, 0.16)
## Variant 1's outline in the robot act (#262854).
const ROBOT_OUTLINE := Color8(0x26, 0x28, 0x54)
const GLASS := Color(0.55, 0.8, 1.0, 0.28)
const GLASS_SHINE := Color(0.85, 0.95, 1.0, 0.6)

@export var size := Vector2(64, 64):
	set(value):
		size = value.max(Vector2(4, 4)).round()
		_update_shape()
		queue_redraw()

@export_enum("wall", "glass", "window", "seal") var style: String = "wall":
	set(value):
		style = value
		_update_layer()
		queue_redraw()
## Which of the act's block textures a wall uses: 1 = block-1.png,
## 2 = block-2.png, 3 = block-3.png (assets/<theme>/environment; if lettered
## ones like block-1a.png .. block-1d.png exist, a random mix of those: one
## per 24px cell for variants 1 and 3, one per picture for variant 2). Only the
## look changes; a missing file falls back to the meadow's, then block-1.
## Variants 1 and 3 tile on the world grid (bricks line up across blocks);
## variant 2 starts at the block's own top-left corner (a picture, tiling
## right and down if the block is bigger than it). Only variant 1 gets the
## outline (dark; light grey in the robot act).
## A `lane_wall` uses the act's wall art instead (wall-1.png, or lettered
## wall-1a.png ..., 64x16) when it has some: see _draw_wall_tiles.
@export_range(1, 3) var variant := 1:
	set(value):
		variant = value
		queue_redraw()
## A seal's colour.
@export var tint := Color(1, 1, 1)
## True for the walls the level builds round and between the lanes (set by
## braid_level.gd), not the blocks inside a strip or junction: these draw
## with the act's wall art when it has some.
var lane_wall := false

var _shape: CollisionShape2D


func _ready() -> void:
	collision_mask = 0
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# The tiling follows the world position, so redraw when the block moves.
	set_notify_transform(true)
	_update_layer()
	_update_shape()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and style == "wall":
		queue_redraw()


func _update_layer() -> void:
	collision_layer = BraidTuning.WALL_LAYER if style == "wall" else BraidTuning.WINDOW_LAYER


func _update_shape() -> void:
	if not is_inside_tree():
		return
	if _shape == null:
		_shape = CollisionShape2D.new()
		_shape.shape = RectangleShape2D.new()
		# Built at run time (and in the editor), never saved into the scene.
		add_child(_shape, false, Node.INTERNAL_MODE_BACK)
	(_shape.shape as RectangleShape2D).size = size
	_shape.position = size / 2.0


## The block's rectangle in world space.
func world_rect() -> Rect2:
	return Rect2(global_position, size)


func _draw() -> void:
	if style == "window":
		var pane := ActTheme.optional_environment("window")
		if pane:
			draw_texture_rect_region(pane, Rect2(Vector2.ZERO, size), Rect2(Vector2.ZERO, size))
			return
	if style == "glass" or style == "window":
		draw_rect(Rect2(Vector2.ZERO, size), GLASS)
		draw_line(Vector2(2, size.y - 3), Vector2(minf(10.0, size.x), 3), GLASS_SHINE, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), GLASS_SHINE, false, 1.0)
		return
	if style == "seal":
		var art := ActTheme.optional_environment("window")
		if art:
			# The act's window art turned 90 degrees clockwise (its top edge on
			# the right), tiling down from the top, centred across the seal
			# (it may be wider than the seal: it overhangs both sides).
			var art_h := art.get_size().y
			draw_set_transform(Vector2((size.x + art_h) / 2.0, 0.0), PI / 2.0)
			var turned := Rect2(0.0, 0.0, size.y, art_h)
			draw_texture_rect_region(art, turned, turned)
			draw_set_transform(Vector2.ZERO)
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(tint, 0.25))
		var y := 2.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(tint, 0.6), 1.0)
			y += 6.0
		draw_rect(Rect2(Vector2.ZERO, size), Color(tint, 0.9), false, 1.0)
		return
	var walls := ActTheme.optional_environment_options("wall", 1) if lane_wall and variant == 1 else []
	var options := ActTheme.environment_options("block", TEXTURE, variant)
	if not walls.is_empty():
		_draw_wall_tiles(walls)
	elif variant == 2 and options.size() > 1:
		_draw_pictures(options)
	elif variant == 2:
		draw_texture_rect_region(options[0], Rect2(Vector2.ZERO, size), Rect2(Vector2.ZERO, size))
	elif options.size() == 1:
		draw_texture_rect_region(options[0], Rect2(Vector2.ZERO, size), Rect2(global_position, size))
	else:
		_draw_tiles(options)
	if variant == 1:  # Variants 2 and 3 have no outline (their art may be see-through).
		var outline := ROBOT_OUTLINE if ActTheme.current == "robot" else OUTLINE
		draw_rect(Rect2(Vector2.ZERO, size), outline, false, 1.0)


## Lettered block art (block-1a.png, ...): each TILE-sized cell of the world
## grid the block covers gets its own pick, from the cell's coordinates, so
## the mix is stable across redraws and the same for every player. Each cell
## shows its texture's world-aligned part, so the art lines up as before.
## Only drawn when the block appears or moves, not every frame.
func _draw_tiles(options: Array) -> void:
	var origin := global_position.round()
	var rect := Rect2(origin, size)
	var first := Vector2i((origin / TILE).floor())
	var last := Vector2i(((origin + size) / TILE).ceil())
	for cy in range(first.y, last.y):
		for cx in range(first.x, last.x):
			var cell := Rect2(Vector2(cx, cy) * TILE, Vector2(TILE, TILE)).intersection(rect)
			if cell.has_area():
				var texture: Texture2D = options[posmod(hash(Vector2i(cx, cy)), options.size())]
				draw_texture_rect_region(texture, Rect2(cell.position - origin, cell.size), cell)


## Wall art (wall-1a.png, ... 64x16): laid in rows as tall as the art from
## the block's top edge, so a 16px lane wall is exactly one row, with the
## columns on the world grid so the tiles carry on across blocks side by
## side. A block taller than it is wide (a wall running up and down) turns
## the art 90 degrees clockwise: columns from its left edge, rows on the
## world grid. Each tile is its own pick (from its world cell, so stable and
## the same for every player); the block's edges crop the last ones.
func _draw_wall_tiles(options: Array) -> void:
	var art: Vector2 = options[0].get_size()
	var turned := size.y > size.x
	var origin := global_position.round()
	# Work in the art's own frame: `along` runs with the art's width.
	var length := size.y if turned else size.x
	var across := size.x if turned else size.y
	var start := origin.y if turned else origin.x  # world grid along the wall
	var first := floori(start / art.x)
	var last := ceili((start + length) / art.x)
	var rows := ceili(across / art.y)
	for row in rows:
		for col in range(first, last):
			var from := maxf(col * art.x, start)
			var to := minf((col + 1) * art.x, start + length)
			var thick := minf(art.y, across - row * art.y)
			if to <= from or thick <= 0.0:
				continue
			var texture: Texture2D = options[posmod(hash([col, row, origin.x if turned else origin.y]), options.size())]
			var src := Rect2(from - col * art.x, 0.0, to - from, thick)
			if turned:
				# Clockwise: the art's top edge on the right, its left end at the top.
				draw_set_transform(Vector2((row + 1) * art.y - (art.y - thick), from - start) , PI / 2.0)
				draw_texture_rect_region(texture, Rect2(Vector2.ZERO, src.size), src)
				draw_set_transform(Vector2.ZERO)
			else:
				draw_texture_rect_region(texture,
					Rect2(from - start, row * art.y, to - from, thick), src)


## Lettered pictures (block-2a.png, ...): laid out from the block's top-left
## in cells as big as the largest of them, each cell its own pick (from the
## block's position and the cell's, so stable and the same for every player).
## A picture smaller than the cell sits centred in it; the block's edges
## crop the last row and column.
func _draw_pictures(options: Array) -> void:
	var cell_size := Vector2.ZERO
	for texture: Texture2D in options:
		cell_size = cell_size.max(texture.get_size())
	var origin := Vector2i(global_position.round())
	var block := Rect2(Vector2.ZERO, size)
	var cells := Vector2i((size / cell_size).ceil())
	for cy in cells.y:
		for cx in cells.x:
			var texture: Texture2D = options[posmod(hash([origin, cx, cy]), options.size())]
			var at := (Vector2(cx, cy) * cell_size + ((cell_size - texture.get_size()) / 2.0).floor())
			var shown := Rect2(at, texture.get_size()).intersection(block)
			if shown.has_area():
				draw_texture_rect_region(texture, shown, Rect2(shown.position - at, shown.size))
