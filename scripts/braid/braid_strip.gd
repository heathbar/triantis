@tool
extends Node2D
## A lane strip: one hand-built piece of a Braid lane, one band tall
## (BraidTuning.BAND_HEIGHT) and `length` long. Levels are strips placed end
## to end (scripts/braid/braid_level.gd).
##
## Build one as a scene with this script on its root, then add:
##   BraidBlock nodes (scripts/braid/braid_block.gd): walls, top-left at the
##     node position, `size` in the inspector
##   BraidSpawn nodes (scripts/braid/braid_spawn.gd): enemy spawn vents
## The level adds the solid top and bottom walls itself (drawn here as a
## guide), so don't build those.
##
## In the editor it draws the band, one-screen guides and the door slots at
## both ends (green), and the scene dock shows a warning when something
## breaks the rules: a length that isn't whole screens, a block in a door
## slot or outside the band, or no open path from one end to the other.

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")
const BraidBlock := preload("res://scripts/braid/braid_block.gd")
const BraidSpawn := preload("res://scripts/braid/braid_spawn.gd")
const BraidGrid := preload("res://scripts/braid/braid_grid.gd")

const GUIDE := Color(1, 1, 1, 0.25)
const OUTER := Color(0.3, 0.28, 0.33, 0.6)
const DOOR := Color(0.3, 1.0, 0.4, 0.8)

## Pixels long: whole screens (BraidTuning.SCREEN_WIDTH), usually two.
@export var length := BraidTuning.STRIP_LENGTH:
	set(value):
		length = value
		queue_redraw()
		update_configuration_warnings()
## Tide speed while the tide crosses this strip (px/s); 0 = the usual.
@export var tide_speed := 0.0
## 1 (easy) to 5 (hard): the generator (scripts/braid/braid_generator.gd)
## uses easy strips early in an act and hard ones late.
@export_range(1, 5, 1) var difficulty := 1
## How the generator uses it: "normal" anywhere, "calm" (a breather) only to
## open a segment, "start" only to open an act (where the squads spawn).
@export_enum("normal", "calm", "start") var zone: String = "normal"
## The art set it belongs to; an act uses one theme's strips.
@export var art_theme := "greybox"

var _warn_timer := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
	else:
		set_process(false)


func _process(delta: float) -> void:
	# Editor only: keep the guides and warnings current while blocks move.
	_warn_timer -= delta
	if _warn_timer <= 0.0:
		_warn_timer = 0.5
		queue_redraw()
		update_configuration_warnings()


func blocks() -> Array[Node]:
	return find_children("*", "", true, false).filter(func(n: Node) -> bool:
		return n.get_script() == BraidBlock)


func spawns() -> Array[Node]:
	return find_children("*", "", true, false).filter(func(n: Node) -> bool:
		return n.get_script() == BraidSpawn)


## This strip's wall rectangles, relative to the strip.
func local_wall_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for b in blocks():
		rects.append(Rect2(b.position, b.size))
	return rects


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var band := Rect2(0, 0, length, BraidTuning.BAND_HEIGHT)
	draw_rect(Rect2(0, 0, length, BraidTuning.OUTER_WALL), OUTER)
	draw_rect(Rect2(0, BraidTuning.BAND_HEIGHT - BraidTuning.OUTER_WALL, length, BraidTuning.OUTER_WALL), OUTER)
	draw_rect(band, GUIDE, false, 1.0)
	var x := BraidTuning.SCREEN_WIDTH
	while x < length:
		draw_dashed_line(Vector2(x, 0), Vector2(x, BraidTuning.BAND_HEIGHT), GUIDE, 1.0, 6.0)
		x += BraidTuning.SCREEN_WIDTH
	for door_x in [0.0, length - BraidTuning.DOOR_DEPTH]:
		draw_rect(Rect2(door_x, BraidTuning.DOOR_SLOT.x, BraidTuning.DOOR_DEPTH,
			BraidTuning.DOOR_SLOT.y - BraidTuning.DOOR_SLOT.x), DOOR, false, 1.0)


func _get_configuration_warnings() -> PackedStringArray:
	var out := problems()
	if spawns().is_empty():
		out.append("No BraidSpawn vents: enemies will only come out of the tide here (fine for a start strip).")
	return out


## What's wrong with this strip (empty = nothing). Also used to check strips
## when a level is built.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if length <= 0.0 or fmod(length, BraidTuning.SCREEN_WIDTH) != 0.0:
		out.append("Length should be whole screens (multiples of %d px)." % BraidTuning.SCREEN_WIDTH)
	var inner := Rect2(0, BraidTuning.OUTER_WALL, length,
		BraidTuning.BAND_HEIGHT - 2.0 * BraidTuning.OUTER_WALL)
	var doors := [
		Rect2(0, BraidTuning.DOOR_SLOT.x, BraidTuning.DOOR_DEPTH, BraidTuning.DOOR_SLOT.y - BraidTuning.DOOR_SLOT.x),
		Rect2(length - BraidTuning.DOOR_DEPTH, BraidTuning.DOOR_SLOT.x, BraidTuning.DOOR_DEPTH,
			BraidTuning.DOOR_SLOT.y - BraidTuning.DOOR_SLOT.x),
	]
	var walls := local_wall_rects()
	for b in blocks():
		var r := Rect2(b.position, b.size)
		if not Rect2(0, 0, length, BraidTuning.BAND_HEIGHT).encloses(r):
			out.append("%s sticks out of the band." % b.name)
		for door: Rect2 in doors:
			if r.intersects(door):
				out.append("%s blocks a door slot (the green boxes)." % b.name)
	for s in spawns():
		if not inner.has_point(s.position):
			out.append("%s is outside the walkable band." % s.name)
		for r: Rect2 in walls:
			if r.grow(4.0).has_point(s.position):
				out.append("%s is inside a wall." % s.name)
	# A way through from the left door to the right door, MIN_CORRIDOR wide.
	var all := walls.duplicate()
	all.append(Rect2(0, 0, length, BraidTuning.OUTER_WALL))
	all.append(Rect2(0, BraidTuning.BAND_HEIGHT - BraidTuning.OUTER_WALL, length, BraidTuning.OUTER_WALL))
	var mid_y := (BraidTuning.DOOR_SLOT.x + BraidTuning.DOOR_SLOT.y) / 2.0
	if length > 0.0 and not BraidGrid.new().has_way_through(Rect2(0, 0, length, BraidTuning.BAND_HEIGHT),
			all, Vector2(8, mid_y), Vector2(length - 8, mid_y)):
		out.append("No way through from the left door to the right door at least %d px wide." \
			% BraidTuning.MIN_CORRIDOR)
	return out
