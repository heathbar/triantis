@tool
extends StaticBody2D
## A solid wall block in a Braid level piece (tiled with the act's block texture). Its top-left corner is
## at the node's position and it is `size` big. Players, enemies and shots
## can't pass it (BraidTuning.WALL_LAYER).
##
## In the editor: drag it to move it, set `size` in the inspector.
##
## `style`: "wall" (solid), "glass" (a window pane: bodies can't pass, shots
## can, BraidTuning.WINDOW_LAYER) or "seal" (a junction exit closed to this
## squad only: like glass, drawn as a force field in `tint`).

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")

## Wall blocks are this tile, repeated on a world-aligned grid so the
## bricks line up across blocks that touch.
const TEXTURE := preload("res://assets/meadow/environment/block-1.png")
## The act's own block texture replaces TEXTURE, when it has one.
const ActTheme := preload("res://scripts/act_theme.gd")
const OUTLINE := Color(0.14, 0.13, 0.16)
const GLASS := Color(0.55, 0.8, 1.0, 0.28)
const GLASS_SHINE := Color(0.85, 0.95, 1.0, 0.6)

@export var size := Vector2(64, 64):
	set(value):
		size = value.max(Vector2(4, 4)).round()
		_update_shape()
		queue_redraw()

@export_enum("wall", "glass", "seal") var style: String = "wall":
	set(value):
		style = value
		_update_layer()
		queue_redraw()
## Which of the act's block textures a wall uses: 1 = block-1.png,
## 2 = block-2.png, 3 = block-3.png (assets/<theme>/environment). Only the
## look changes; a missing file falls back to the meadow's, then block-1.
## Variants 1 and 3 tile on the world grid (bricks line up across blocks);
## variant 2 starts at the block's own top-left corner (a picture, tiling
## right and down if the block is bigger than it). Only variant 1 gets the
## dark outline.
@export_range(1, 3) var variant := 1:
	set(value):
		variant = value
		queue_redraw()
## A seal's colour.
@export var tint := Color(1, 1, 1)

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
	if style == "glass":
		draw_rect(Rect2(Vector2.ZERO, size), GLASS)
		draw_line(Vector2(2, size.y - 3), Vector2(minf(10.0, size.x), 3), GLASS_SHINE, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), GLASS_SHINE, false, 1.0)
		return
	if style == "seal":
		draw_rect(Rect2(Vector2.ZERO, size), Color(tint, 0.25))
		var y := 2.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(tint, 0.6), 1.0)
			y += 6.0
		draw_rect(Rect2(Vector2.ZERO, size), Color(tint, 0.9), false, 1.0)
		return
	var texture := ActTheme.environment("block", TEXTURE, variant)
	var from := global_position
	if variant == 2:
		from = Vector2.ZERO
	draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), Rect2(from, size))
	if variant == 1:  # Variants 2 and 3 have no outline (their art may be see-through).
		draw_rect(Rect2(Vector2.ZERO, size), OUTLINE, false, 1.0)
