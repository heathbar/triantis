@tool
extends "res://scripts/braid/braid_strip.gd"
## A junction: a room two lanes tall where the squads in those lanes cross
## over (the braid). Placed by the level in a slot across lanes k and k+1
## (scripts/braid/braid_level.gd), in place of their strips.
##
## Build it like a strip, but two bands tall (2 x BAND_HEIGHT) with doors at
## both ends of both bands. Keep the wall between the bands at the two ends
## (from the left end to the middle room, and from `seal_x` to the right end)
## so each band's exit is separate. The level adds the outer walls (top and
## bottom) itself, and in each squad's game closes off the exit of the band
## that squad came in by, at `seal_x` (a seal only that squad sees as solid):
## so whoever enters at the top leaves at the bottom, and the other way round.

## Where the exit seals go (x, from the junction's left end). Everything right
## of here must be split into the two bands' exits.
@export var seal_x := 920.0


func lanes() -> int:
	return 2


func height() -> float:
	return BraidTuning.BAND_HEIGHT * 2.0


## The seal closing band `band` (0 = top, 1 = bottom)'s exit, relative to the
## junction.
func seal_rect(band: int) -> Rect2:
	var top := BraidTuning.BAND_HEIGHT * band + BraidTuning.OUTER_WALL
	return Rect2(seal_x, top, BraidTuning.OUTER_WALL, BraidTuning.BAND_HEIGHT - 2.0 * BraidTuning.OUTER_WALL)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var h := height()
	var wall := BraidTuning.OUTER_WALL
	draw_rect(Rect2(0, 0, length, wall), OUTER)
	draw_rect(Rect2(0, h - wall, length, wall), OUTER)
	draw_rect(Rect2(0, 0, length, h), GUIDE, false, 1.0)
	draw_dashed_line(Vector2(0, h / 2.0), Vector2(length, h / 2.0), GUIDE, 1.0, 6.0)
	for door: Rect2 in _doors():
		draw_rect(door, DOOR, false, 1.0)
	for band in 2:
		draw_rect(seal_rect(band), Color(1, 0.4, 0.4, 0.6), false, 1.0)


func _doors() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var slot := BraidTuning.DOOR_SLOT
	for band in 2:
		var y := BraidTuning.BAND_HEIGHT * band + slot.x
		out.append(Rect2(0, y, BraidTuning.DOOR_DEPTH, slot.y - slot.x))
		out.append(Rect2(length - BraidTuning.DOOR_DEPTH, y, BraidTuning.DOOR_DEPTH, slot.y - slot.x))
	return out


func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if length <= 0.0 or fmod(length, BraidTuning.SCREEN_WIDTH) != 0.0:
		out.append("Length should be whole screens (multiples of %d px)." % BraidTuning.SCREEN_WIDTH)
	var h := height()
	var area := Rect2(0, 0, length, h)
	var walls := local_wall_rects()
	for b in blocks():
		var r := Rect2(b.position, b.size)
		if not area.encloses(r):
			out.append("%s sticks out of the two bands." % b.name)
		for door in _doors():
			if r.intersects(door):
				out.append("%s blocks a door slot (the green boxes)." % b.name)
	var inner := area.grow_individual(0, -BraidTuning.OUTER_WALL, 0, -BraidTuning.OUTER_WALL)
	for s in spawns():
		if not inner.has_point(s.position):
			out.append("%s is outside the walkable area." % s.name)
		elif s.position.x >= seal_x:
			out.append("%s is past seal_x, where one squad can't reach it." % s.name)
		for r: Rect2 in walls:
			if r.grow(4.0).has_point(s.position):
				out.append("%s is inside a wall." % s.name)
	walls.append(Rect2(0, 0, length, BraidTuning.OUTER_WALL))
	walls.append(Rect2(0, h - BraidTuning.OUTER_WALL, length, BraidTuning.OUTER_WALL))
	var mid := (BraidTuning.DOOR_SLOT.x + BraidTuning.DOOR_SLOT.y) / 2.0
	var band := BraidTuning.BAND_HEIGHT
	# In at the top, out at the bottom (top exit sealed), and the other way.
	for from_band in 2:
		var sealed := walls.duplicate()
		sealed.append(seal_rect(from_band))
		var a := Vector2(8, band * from_band + mid)
		var b := Vector2(length - 8, band * (1 - from_band) + mid)
		if length > 0.0 and not BraidGrid.new().has_way_through(area, sealed, a, b):
			out.append("No way from the %s entrance to the %s exit at least %d px wide." % [
				"top" if from_band == 0 else "bottom", "bottom" if from_band == 0 else "top",
				BraidTuning.MIN_CORRIDOR])
		# And none straight through to its own band's exit.
		if length > 0.0 and BraidGrid.new().has_way_through(area, sealed, a,
				Vector2(length - 8, band * from_band + mid)):
			out.append("The %s entrance has a way to its own exit: the wall between the bands must run from seal_x to the right end." % [
				"top" if from_band == 0 else "bottom"])
	return out
