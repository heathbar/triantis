@tool
extends Node2D
## A Braid level: one lane per squad, side by side, built from the
## generator's layout (scripts/braid/braid_generator.gd): lane strips
## (levels/braid/strips/) and junctions (levels/braid/junctions/) in slots
## that line up across every lane.
##
## The lanes run together, like a ribbon. Mostly the ribbon runs right, lane
## 1 on top. At a vertical slice it turns up or down through a corner, runs
## that way for a while, and turns back to running right through a second
## corner: turns always come in pairs. Lanes keep their order across the way
## they run (running up, lane 1 is on the left; running down, on the right).
## In a corner each lane follows its own L, the lanes nested round the inside
## corner, so a lane on the inside of the turn has a short way round and one
## on the outside a long way; the second corner turns the other way, so over
## a whole slice every lane is exactly as long. The corners' long arms get a
## few pillars and spawn vents of their own.
##
## Places along a lane are "progress": pixels along that lane from the
## level's start (progress(), point_at(); every function here that takes or
## returns a place along a lane means progress). Outside slices progress is
## the same in every lane straight across the ribbon; inside a slice each
## lane has its own. So everything that has to line up across lanes
## (checkpoints, junctions, windows, the convergence room) is where the ribbon
## runs right, outside slices, and the tide (at one progress in every lane)
## runs at one speed across a whole slice.
##
## Each segment ends at a checkpoint across every lane: a shop building
## (scripts/braid/braid_shop_building.gd) over a solid gate block, with a
## metal plate before its door. Squads stand on the plates to go into the
## shop, and come out past the building (it stays solid behind them). The
## level adds the walls along both edges of each lane (between two lanes
## that's a separator, 2 x OUTER_WALL), windows where the layout says (glass
## panes between pillars: shots pass, bodies don't), doors in the lane walls
## (scripts/braid/braid_door.gd), a wall closing the start, the floor, and
## the pathing grid (scripts/braid/braid_grid.gd) enemies use.
##
## After the last gate comes the convergence room (unless built without it):
## one open room every lane opens into, where the act's boss is fought. The
## first MOUTH_DEPTH of it (the lane mouths) is kept clear of the boss.
##
## Squads swap lanes at junctions. lane_at(start_lane, s) says which lane a
## squad that started in `start_lane` is in at progress s. In a squad's own
## game, add_seals closes each junction's exit back into the lane that squad
## came in by (so it has to cross).
##
## World layout: the level starts at the origin, running right, lane k's band
## from y k*BAND_HEIGHT to (k+1)*BAND_HEIGHT (until it first turns). Positions
## here are relative to the level (it sits at the origin in a game), so it can
## also be built outside the scene tree: the Braid preview dock
## (addons/braid_tools/) builds one in the editor.

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")
const BraidBlock := preload("res://scripts/braid/braid_block.gd")
const BraidGrid := preload("res://scripts/braid/braid_grid.gd")
const BraidFavour := preload("res://scripts/braid/braid_favour.gd")
const BraidTurret := preload("res://scripts/braid/braid_turret.gd")
const BraidShopBuilding := preload("res://scripts/braid/braid_shop_building.gd")
const BraidDoor := preload("res://scripts/braid/braid_door.gd")
const FLOOR_TEXTURE := preload("res://assets/meadow/environment/background-1.png")
## The act's own floor texture replaces FLOOR_TEXTURE, when it has one.
const ActTheme := preload("res://scripts/act_theme.gd")

const STRIP_DIR := "res://levels/braid/strips/%s.tscn"
const JUNCTION_DIR := "res://levels/braid/junctions/%s.tscn"
## Checkpoint gates (the shop buildings) are this wide.
const GATE_WIDTH := 128.0
## The ways the ribbon can run (a layout's corner slots name the way out).
const DIRECTIONS := {"right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}
## Along a lane, the square where it turns in a corner counts as a quarter
## circle through its middle.
const CORNER_CELL := BraidTuning.BAND_HEIGHT * PI / 4.0
## Corner arms: a pillar this big every band's length, this far in from the
## lane's wall on alternate sides, and a spawn vent this far in on the other.
const ARM_PILLAR := 64.0
const ARM_PILLAR_INSET := 80.0
const ARM_VENT_INSET := 64.0
const VOID_COLOR := Color(0.06, 0.05, 0.07)
## Where along a slot a gun port may go (fractions of its length, tried in
## order): first spots clear of the door spots (BraidTuning.DOOR_SPOTS_*),
## then anywhere (a door there is left out instead).
const TURRET_SPOTS: Array[float] = [0.58, 0.33, 0.83, 0.1]
const TURRET_FALLBACK_SPOTS: Array[float] = [0.5, 0.65, 0.4, 0.75, 0.25, 0.9, 0.15, 0.05, 0.95]

## How many lanes.
var lanes := 1
## The whole level (walls included).
var bounds := Rect2()
## Pathing for enemies: walls and the flow field toward the players.
var grid: BraidGrid
## Per segment: {"start": progress where it begins, "gate_x": progress at the
## gates' near edge, "gates": [BraidBlock per lane], "shops":
## [BraidShopBuilding per lane], "slice": true if it has a vertical slice}.
var segments: Array[Dictionary] = []
## Progress where the act's start strip ends (its opener slot in the first
## segment; -1 if it has none). No doors there, and braid_game.gd holds the
## first chapter's spawns until the squad walks past it.
var start_end := -1.0
## Every spawn vent: {"pos": Vector2, "lanes": [lanes it serves], "s":
## progress}, by progress.
var vents: Array[Dictionary] = []
## Doors in the lanes' walls (scripts/braid/braid_door.gd), by progress
## (their `s`).
var doors: Array[Node] = []
## Every junction: {"x0", "x1" (progress at its ends), "pair" (lanes pair,
## pair+1), "node", "rect" (where it is)}, by progress.
var junctions: Array[Dictionary] = []
## Every window: {"x0", "x1" (progress), "pair"}, by progress.
var windows: Array[Dictionary] = []
## Every vertical slice: {"from", "to" (progress, the same in every lane at
## both ends), "up": true going up}, by progress.
var slices: Array[Dictionary] = []
## Favour plates (scripts/braid/braid_favour.gd), by progress.
var favours: Array[Node] = []
## Mounted turrets (scripts/braid/braid_turret.gd), in build order.
var turrets: Array[Node] = []
## World points of the gun ports' slits (doors keep away from them).
var _ports: Array[Vector2] = []
## The convergence room, walls excluded (Rect2() if there isn't one), the part
## of it past the lane mouths (where the boss fights), and the progress where
## it starts.
var room := Rect2()
var arena := Rect2()
var room_start := 0.0
## The level's pieces from its start, each {"kind", "s0" (per lane: progress
## at its start), "len" (per lane: its length along that lane), "rect" (its
## part of the world, walls included), "width" (across the ribbon)} and
##   "straight": "origin" (where it starts, on the ribbon's left-hand edge),
##     "dir" (the way it runs), "normal" (dir turned right: across the
##     ribbon, lane 0 first);
##   "corner": "pivot" (the inside corner), "d_in", "d_out" (the way the
##     ribbon runs in and out), "left" (a left turn: the pivot is on lane 0's
##     side), "c_lo" (per lane: how far from the pivot its inner wall is).
var pieces: Array[Dictionary] = []
## Tide speed, from the start: {"from": progress, "to": progress,
## "tide_speed": px/s}.
var _spans: Array[Dictionary] = []
## Where progress() found something last (it's asked about nearby points in a
## row).
var _last_piece := 0
## Top of lane 0's band where the level ends (band_rect).
var _end_y := 0.0
## Wall runs being built, by name: each new wall that lines up with the last
## one of its name joins it.
var _runs := {}
## Per piece file: [modified time, its problems()] (see _piece_problems).
static var _problems_seen := {}


## Builds the level from `layout` (BraidGenerator's format). Returns the
## problems found in its pieces and the level as a whole (empty = none: see
## check()); the level is built either way.
func build(layout: Dictionary, with_room := true) -> PackedStringArray:
	var problems := PackedStringArray()
	lanes = clampi(int(layout.get("lanes", 1)), 1, BraidTuning.MAX_LANES)
	var band := BraidTuning.BAND_HEIGHT
	var wall := BraidTuning.OUTER_WALL
	var width := band * lanes
	var origin := Vector2.ZERO
	var dir := Vector2.RIGHT
	# Progress per lane at the cursor (all the same outside slices).
	var at_s: Array[float] = []
	at_s.resize(lanes)
	at_s.fill(0.0)
	# The slice we're in: {"from", "speed", "up"}.
	var slice := {}
	var door_spots := []
	_wall_run("Start", _frame_rect(origin, dir, Rect2(-wall, 0, wall, width)))
	var seg_index := -1
	for seg: Dictionary in layout.get("segments", []):
		seg_index += 1
		var start := at_s[0]
		var has_slice := false
		for slot: Dictionary in seg["slots"]:
			if slot.has("corner"):
				var d_out: Vector2 = DIRECTIONS.get(slot["corner"], Vector2.RIGHT)
				if d_out == dir or d_out == -dir:
					problems.append("A corner can't turn %s from running that way or back." % slot["corner"])
					continue
				if dir == Vector2.RIGHT:
					slice = {"from": at_s[0], "speed": BraidTuning.TIDE_SPEED, "up": d_out == Vector2.UP}
					has_slice = true
				origin = _add_corner(origin, dir, d_out, at_s)
				dir = d_out
				if dir == Vector2.RIGHT and not slice.is_empty():
					for k in lanes:
						if not is_equal_approx(at_s[k], at_s[0]):
							problems.append("Slice lanes differ in length (lane %d: %d, lane 1: %d)." % [
								k + 1, at_s[k], at_s[0]])
						at_s[k] = at_s[0]
					_spans.append({"from": slice["from"], "to": at_s[0],
						"tide_speed": slice["speed"] * BraidTuning.VERTICAL_TIDE_FACTOR})
					slices.append({"from": slice["from"], "to": at_s[0], "up": slice["up"]})
					slice = {}
				continue
			var length: float = slot["length"]
			var in_slice := not slice.is_empty()
			var s0 := at_s.duplicate()
			var p := _add_straight(origin, dir, s0, length, width)
			var slowest := INF
			var junction_lanes := []
			if not slot["junctions"].is_empty() and (in_slice or dir != Vector2.RIGHT):
				problems.append("A junction in a vertical slice (left out).")
			elif not slot["junctions"].is_empty():
				for pair in slot["junctions"]:
					var piece_name: String = slot["junctions"][pair]
					var jat: Vector2 = origin + p["normal"] * int(pair) * band
					var piece := _place(JUNCTION_DIR % piece_name, jat, piece_name, problems)
					junction_lanes.append_array([int(pair), int(pair) + 1])
					if piece:
						slowest = minf(slowest, _speed(piece))
						_add_vents(piece, [int(pair), int(pair) + 1])
						junctions.append({"x0": s0[0], "x1": s0[0] + length, "pair": int(pair),
							"node": piece, "rect": Rect2(jat, Vector2(length, band * 2.0))})
			var placed := {}  # lane -> its strip in this slot
			for lane in lanes:
				var strip_name: String = slot["strips"][lane]
				if strip_name.is_empty() or lane in junction_lanes:
					continue
				var strip := _place_turned(STRIP_DIR % strip_name, origin + p["normal"] * lane * band,
					dir, strip_name, problems)
				if strip:
					placed[lane] = strip
					slowest = minf(slowest, _speed(strip))
					_add_vents(strip, [lane])
			var seams: Array = slot["seams"].duplicate()
			for k in lanes - 1:
				var seam: String = seams[k]
				if seam == "junction" and (k in junction_lanes):
					continue
				if seam == "window" and (in_slice or dir != Vector2.RIGHT):
					problems.append("A window in a vertical slice (left solid).")
					seam = "solid"
				if seam == "window":
					_add_window(origin, s0[0], length, k)
					continue
				seams[k] = "solid"
				var ports := []
				for t: Dictionary in slot.get("turrets", []):
					if mini(int(t["lane"]), int(t["target"])) != k:
						continue
					var at := _turret_spot(p, length, k, int(t["lane"]), placed, ports)
					if at < 0.0:
						problems.append("No clear spot for a turret (lane %d, segment %d)." % [
							int(t["lane"]) + 1, segments.size() + 1])
						continue
					ports.append([at, int(t["lane"]), int(t["target"])])
				ports.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
				var from := 0.0
				for port in ports:
					var x0: float = port[0] - BraidTuning.TURRET_PORT / 2.0
					_wall_run("Separator%d" % (k + 1), _frame_rect(origin, dir,
						Rect2(from, (k + 1) * band - wall, x0 - from, BraidTuning.SEPARATOR)))
					_add_turret(p, k, port[0], port[1], port[2])
					from = x0 + BraidTuning.TURRET_PORT
				_wall_run("Separator%d" % (k + 1), _frame_rect(origin, dir,
					Rect2(from, (k + 1) * band - wall, length - from, BraidTuning.SEPARATOR)))
			if seg_index == 0 and slot.get("opener", false):
				start_end = s0[0] + length  # The start strip: no doors in it.
			else:
				door_spots.append_array(_door_spots(p, slot["strips"], seams, junction_lanes))
			var speed := slowest if slowest < INF else BraidTuning.TIDE_SPEED
			if in_slice:
				slice["speed"] = minf(slice["speed"], speed)
			else:
				_spans.append({"from": s0[0], "to": s0[0] + length, "tide_speed": speed})
			origin += dir * length
			for k in lanes:
				at_s[k] += length
		# The checkpoint, across every lane: a solid gate under a shop.
		if not slice.is_empty() or dir != Vector2.RIGHT:
			problems.append("Segment %d ends inside a vertical slice: checkpoints need the lanes running right."
				% (segments.size() + 1))
		var gates: Array = []
		var shops: Array = []
		var gp := _add_straight(origin, dir, at_s.duplicate(), GATE_WIDTH, width)
		for lane in lanes:
			var at: Vector2 = origin + gp["normal"] * (lane * band + wall)
			var gate_size := Vector2(GATE_WIDTH, band - 2.0 * wall)
			var gate := _block(at, gate_size, "Gate%d_%d" % [segments.size() + 1, lane + 1])
			gate.visible = false  # the shop draws it (still solid)
			gates.append(gate)
			var shop := BraidShopBuilding.new()
			shop.name = "Shop%d_%d" % [segments.size() + 1, lane + 1]
			shop.position = at
			shop.size = gate_size
			add_child(shop)
			shops.append(shop)
		for k in lanes - 1:
			_wall_run("Separator%d" % (k + 1), _frame_rect(origin, dir,
				Rect2(0, (k + 1) * band - wall, GATE_WIDTH, BraidTuning.SEPARATOR)))
		segments.append({"start": start, "gate_x": at_s[0], "gates": gates, "shops": shops,
			"slice": has_slice})
		_spans.append({"from": at_s[0], "to": at_s[0] + GATE_WIDTH, "tide_speed": BraidTuning.TIDE_SPEED})
		origin += dir * GATE_WIDTH
		for k in lanes:
			at_s[k] += GATE_WIDTH
	vents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["s"] < b["s"])

	_end_y = origin.y
	if with_room and dir == Vector2.RIGHT:
		var room_lanes := maxi(lanes, BraidTuning.ROOM_MIN_LANES)
		room_start = at_s[0]
		_add_straight(origin, dir, at_s.duplicate(), BraidTuning.ROOM_LENGTH, band * room_lanes)
		_add_room(origin, room_lanes)
		_spans.append({"from": room_start, "to": room_start + BraidTuning.ROOM_LENGTH,
			"tide_speed": BraidTuning.TIDE_SPEED})
	else:
		_wall_run("End", _frame_rect(origin, dir, Rect2(0, 0, wall, width)))
	_flush_runs()

	bounds = Rect2()
	for p in pieces:
		bounds = p["rect"] if bounds.size == Vector2.ZERO else bounds.merge(p["rect"])
	bounds = bounds.grow(wall)
	var void_fill := ColorRect.new()
	void_fill.name = "Void"
	void_fill.color = VOID_COLOR
	void_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	void_fill.position = bounds.position
	void_fill.size = bounds.size
	void_fill.z_index = -1112
	add_child(void_fill)
	move_child(void_fill, 0)
	for p in pieces:
		var ground := Sprite2D.new()
		ground.name = "Floor"
		ground.texture = ActTheme.environment("background", FLOOR_TEXTURE)
		ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		ground.centered = false
		ground.region_enabled = true
		ground.region_rect = p["rect"]  # world-aligned, so it tiles on across pieces
		ground.position = p["rect"].position
		ground.z_index = -1111
		add_child(ground)
		move_child(ground, 1)

	rebuild_grid()
	_add_doors(door_spots)
	problems.append_array(check())
	return problems


# --- Building --------------------------------------------------------------------

## Rectangle `local` of the ribbon running `dir` from `origin` (x along the
## ribbon, y across it from its left-hand edge), in the world.
func _frame_rect(origin: Vector2, dir: Vector2, local: Rect2) -> Rect2:
	var n := _normal(dir)
	var a := origin + dir * local.position.x + n * local.position.y
	var b := origin + dir * local.end.x + n * local.end.y
	return Rect2(a.min(b), (a - b).abs())


## Across the ribbon (lane 0 first) when it runs `dir`.
static func _normal(dir: Vector2) -> Vector2:
	return Vector2(-dir.y, dir.x)


## A straight piece `length` long from `origin` running `dir`, `width`
## across, starting at progress `s0` (per lane), with walls along both edges.
func _add_straight(origin: Vector2, dir: Vector2, s0: Array, length: float, width: float) -> Dictionary:
	var wall := BraidTuning.OUTER_WALL
	var lens := []
	lens.resize(lanes)
	lens.fill(length)
	var p := {"kind": "straight", "s0": s0, "len": lens,
		"rect": _frame_rect(origin, dir, Rect2(0, 0, length, width)), "width": width,
		"origin": origin, "dir": dir, "normal": _normal(dir)}
	pieces.append(p)
	_wall_run("Left", _frame_rect(origin, dir, Rect2(0, 0, length, wall)))
	_wall_run("Right", _frame_rect(origin, dir, Rect2(0, width - wall, length, wall)))
	return p


## A corner from running `d_in` to `d_out`, entered at `origin` (the ribbon's
## left-hand edge), with progress per lane `at_s` (moved on to its far end).
## Each lane turns along its own L round the pivot: walls at every lane
## boundary, and pillars and vents along the long arms. Returns where the
## ribbon carries on (its new left-hand edge).
func _add_corner(origin: Vector2, d_in: Vector2, d_out: Vector2, at_s: Array[float]) -> Vector2:
	var band := BraidTuning.BAND_HEIGHT
	var wall := BraidTuning.OUTER_WALL
	var width := band * lanes
	var half := width / 2.0
	var center := origin + _normal(d_in) * half + d_in * half
	var pivot := center - d_in * half + d_out * half
	var left := d_in.x * d_out.y - d_in.y * d_out.x < 0.0
	var s0 := []
	var lens := []
	var c_lo := []
	for k in lanes:
		var lo := k * band if left else width - (k + 1) * band
		c_lo.append(lo)
		s0.append(at_s[k])
		lens.append(2.0 * lo + CORNER_CELL)
		at_s[k] += 2.0 * lo + CORNER_CELL
	var p := {"kind": "corner", "s0": s0, "len": lens, "c_lo": c_lo, "width": width,
		"rect": Rect2(center - Vector2(half, half), Vector2(width, width)),
		"pivot": pivot, "d_in": d_in, "d_out": d_out, "left": left}
	pieces.append(p)
	# An L-shaped wall at every lane boundary (the first is a post in the
	# inside corner, the last the outside walls).
	for j in lanes + 1:
		var c_from := maxf(j * band - wall, 0.0)
		var c_to := minf(j * band + wall, width)
		_block_at(_ab_rect(p, c_from, c_to, 0.0, c_to), "CornerWall")
		_block_at(_ab_rect(p, 0.0, c_to, c_from, c_to), "CornerWall")
	# The long arms: a pillar and a vent every band's length.
	for k in lanes:
		var lo: float = c_lo[k]
		for i in floori(lo / band + 0.01):
			var along := i * band + band / 2.0
			var side := (i + k) % 2 == 0
			var pillar := lo + wall + ARM_PILLAR_INSET if side else lo + band - wall - ARM_PILLAR_INSET - ARM_PILLAR
			var vent := lo + band - wall - ARM_VENT_INSET if side else lo + wall + ARM_VENT_INSET
			var h := ARM_PILLAR / 2.0
			# The arm in (a across, b along), then the one out (a along, b across).
			_block_at(_ab_rect(p, pillar, pillar + ARM_PILLAR, along - h, along + h), "ArmPillar")
			_block_at(_ab_rect(p, along - h, along + h, pillar, pillar + ARM_PILLAR), "ArmPillar")
			for pos in [_ab(p, vent, along), _ab(p, along, vent)]:
				vents.append({"pos": pos, "lanes": [k], "s": progress(pos)})
	return center + d_out * half - _normal(d_out) * half


## Corner `p`'s point `a` from the pivot back along the way in, `b` along it.
func _ab(p: Dictionary, a: float, b: float) -> Vector2:
	return p["pivot"] - p["d_out"] * a + p["d_in"] * b


func _ab_rect(p: Dictionary, a0: float, a1: float, b0: float, b1: float) -> Rect2:
	var x := _ab(p, a0, b0)
	var y := _ab(p, a1, b1)
	return Rect2(x.min(y), (x - y).abs())


## Adds wall `r` to the run `run_name`: joined to its last wall if they line
## up end to end, else that one is built and `r` starts a new run.
func _wall_run(run_name: String, r: Rect2) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	if _runs.has(run_name):
		var last: Rect2 = _runs[run_name]
		var joined := last.merge(r)
		if is_equal_approx(joined.get_area(), last.get_area() + r.get_area()) and not last.intersects(r):
			_runs[run_name] = joined
			return
		_block_at(last, run_name)
	_runs[run_name] = r


func _flush_runs() -> void:
	for run_name in _runs:
		_block_at(_runs[run_name], run_name)
	_runs.clear()


func _block_at(r: Rect2, block_name: String) -> BraidBlock:
	return _block(r.position, r.size, block_name)


## Instances the piece at `path` at `at`; null (and a problem) if it's missing.
func _place(path: String, at: Vector2, piece_name: String, problems: PackedStringArray) -> Node2D:
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if scene == null:
		problems.append("%s: no such piece (%s)" % [piece_name, path])
		return null
	var piece: Node2D = scene.instantiate()
	piece.position = at
	add_child(piece)
	for p in _piece_problems(path, piece):
		problems.append("%s: %s" % [piece_name, p])
	return piece


## piece.problems() (`piece` freshly placed from `path`), remembered per file
## until it changes: the way-through checks take tens of ms a strip and over
## a second a junction, too slow to redo on every build.
static func _piece_problems(path: String, piece: Node) -> PackedStringArray:
	var stamp := FileAccess.get_modified_time(path)
	var known: Array = _problems_seen.get(path, [])
	if known.is_empty() or known[0] != stamp:
		known = [stamp, piece.problems()]
		_problems_seen[path] = known
	return known[1]


## Places a strip as _place does, laid along `dir` from `origin` (its band's
## left-hand edge): a strip that runs up or down has its blocks and vents
## moved and turned into place (the strip node itself isn't rotated, so
## blocks stay axis-aligned and drawn the right way up).
func _place_turned(path: String, origin: Vector2, dir: Vector2, piece_name: String,
		problems: PackedStringArray) -> Node2D:
	var piece := _place(path, origin, piece_name, problems)
	if piece == null or dir == Vector2.RIGHT:
		return piece
	for child in piece.get_children():
		if child.get_script() == BraidBlock:
			var r := _frame_rect(Vector2.ZERO, dir, Rect2(child.position, child.size))
			child.position = r.position
			child.size = r.size
		elif child is Node2D:
			child.position = dir * child.position.x + _normal(dir) * child.position.y
			if child.get_child_count() > 0:
				problems.append("%s: only direct children are turned (%s has its own)." % [piece_name, child.name])
	return piece


func _speed(piece: Node) -> float:
	return piece.tide_speed if piece.tide_speed > 0.0 else BraidTuning.TIDE_SPEED


func _add_vents(piece: Node2D, serves: Array) -> void:
	for v: Node2D in piece.spawns():
		var pos := piece.position + v.get_relative_transform_to_parent(piece).origin
		vents.append({"pos": pos, "lanes": serves, "s": progress(pos)})


func _block(at: Vector2, size: Vector2, block_name: String, style := "wall") -> BraidBlock:
	var block := BraidBlock.new()
	block.name = block_name
	block.position = at
	block.size = size
	block.style = style
	add_child(block)
	return block


## Door spots along straight piece `p` (one slot, `strips` per lane): in each
## lane's walls where they're plain wall (not a window, not in a junction).
## [pos, inward, lane, s].
func _door_spots(p: Dictionary, strips: Array, seams: Array, junction_lanes: Array) -> Array:
	var out := []
	var origin: Vector2 = p["origin"]
	var dir: Vector2 = p["dir"]
	var n: Vector2 = p["normal"]
	var length: float = p["len"][0]
	var band := BraidTuning.BAND_HEIGHT
	var wall := BraidTuning.OUTER_WALL
	for lane in lanes:
		if lane in junction_lanes or String(strips[lane]).is_empty():
			continue
		var s0: float = p["s0"][lane]
		if lane == 0 or seams[lane - 1] == "solid":
			for f in BraidTuning.DOOR_SPOTS_TOP:
				out.append([origin + dir * length * f + n * (lane * band + wall), n, lane, s0 + length * f])
		if lane == lanes - 1 or seams[lane] == "solid":
			for f in BraidTuning.DOOR_SPOTS_BOTTOM:
				out.append([origin + dir * length * f + n * ((lane + 1) * band - wall), -n, lane,
					s0 + length * f])
	return out


## Puts a door at each spot whose way into the lane is open floor, turned to
## face into it.
func _add_doors(spots: Array) -> void:
	var half := BraidTuning.DOOR_WIDTH / 2.0
	for spot in spots:
		var at: Vector2 = spot[0]
		var inward: Vector2 = spot[1]
		var along := Vector2(inward.y, -inward.x)
		var exit := at + inward * BraidTuning.DOOR_EXIT_DEPTH
		var clear := true
		for port in _ports:
			if port.distance_to(at) < BraidTuning.TURRET_PORT / 2.0 + BraidTuning.DOOR_WIDTH:
				clear = false
		for q in [exit - along * half, exit + along * half, exit, exit + inward * BraidTuning.FLOW_CELL * 2.0]:
			if not grid.is_free_at(q):
				clear = false
				break
		if not clear:
			continue
		var door := BraidDoor.new()
		door.name = "Door"
		door.lane = spot[2]
		door.face = 1
		door.rotation = inward.angle() - PI / 2.0
		door.position = at
		door.s = spot[3]
		add_child(door)
		doors.append(door)
	doors.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.s < b.s)


## The convergence room from `origin` (running right; its straight piece is
## already in): the wall closing the bands below the lanes (when the room is
## taller than them), and the wall closing its far end. Nothing stands inside.
func _add_room(origin: Vector2, room_lanes: int) -> void:
	var band := BraidTuning.BAND_HEIGHT
	var wall := BraidTuning.OUTER_WALL
	var height := band * room_lanes
	if room_lanes > lanes:
		_block(origin + Vector2(-wall, lanes * band), Vector2(wall, (room_lanes - lanes) * band), "Filler")
	_block(origin + Vector2(BraidTuning.ROOM_LENGTH, 0), Vector2(wall, height), "RoomEnd")
	room = Rect2(origin + Vector2(0, wall), Vector2(BraidTuning.ROOM_LENGTH, height - 2.0 * wall))
	arena = Rect2(origin + Vector2(BraidTuning.MOUTH_DEPTH, wall),
		Vector2(BraidTuning.ROOM_LENGTH - BraidTuning.MOUTH_DEPTH, height - 2.0 * wall))


## A window in the wall between lanes `pair` and `pair` + 1 over the slot
## from `origin` (running right; progress `s`, `length` long): glass panes
## between pillars, and a favour plate on each side.
func _add_window(origin: Vector2, s: float, length: float, pair: int) -> void:
	var y := origin.y + (pair + 1) * BraidTuning.BAND_HEIGHT - BraidTuning.OUTER_WALL
	var h := BraidTuning.SEPARATOR
	var x := origin.x
	var end := x + length
	var at := x
	_block(Vector2(at, y), Vector2(BraidTuning.WINDOW_INSET, h), "WindowPillar")
	at += BraidTuning.WINDOW_INSET
	while at + BraidTuning.WINDOW_PANE + BraidTuning.WINDOW_PILLAR + BraidTuning.WINDOW_INSET <= end:
		_block(Vector2(at, y), Vector2(BraidTuning.WINDOW_PANE, h), "WindowGlass", "window")
		at += BraidTuning.WINDOW_PANE
		_block(Vector2(at, y), Vector2(BraidTuning.WINDOW_PILLAR, h), "WindowPillar")
		at += BraidTuning.WINDOW_PILLAR
	if end - at > 0.0:
		_block(Vector2(at, y), Vector2(end - at, h), "WindowPillar")
	windows.append({"x0": s, "x1": s + length, "pair": pair})
	# A favour plate on each side, a third of the way along.
	for side in 2:
		var plate := BraidFavour.new()
		plate.name = "Favour"
		plate.lane = pair + side
		plate.target_lane = pair + 1 - side
		var f := (1.0 if side == 0 else 2.0) / 3.0
		var fy := y - 28.0 if side == 0 else y + h + 28.0
		plate.position = Vector2(x + length * f, fy)
		plate.s = s + length * f
		plate.crush_y = origin.y + (plate.target_lane + 0.5) * BraidTuning.BAND_HEIGHT
		add_child(plate)
		favours.append(plate)


## Where along straight piece `p` (one slot, `length` long) the wall between
## lanes `pair` and `pair` + 1 can take a gun port whose turret sits in lane
## `lane`: clear of the strips' blocks on both sides (room for the gunner on
## the seat side), of the door spots and of the other `ports` ([along, ...])
## on that wall. Distance along the piece, or -1 if nowhere.
func _turret_spot(p: Dictionary, length: float, pair: int, lane: int, placed: Dictionary,
		ports: Array) -> float:
	var band := BraidTuning.BAND_HEIGHT
	# Across the piece (lane 0's edge = 0): the wall's two faces.
	var top := (pair + 1) * band - BraidTuning.OUTER_WALL
	var bottom := top + BraidTuning.SEPARATOR
	var port := BraidTuning.TURRET_PORT
	var seat_depth := BraidTurret.SEAT_DEPTH + 24.0
	var seat_width := port + 20.0
	var door_fs: Array[float] = []
	door_fs.append_array(BraidTuning.DOOR_SPOTS_TOP)
	door_fs.append_array(BraidTuning.DOOR_SPOTS_BOTTOM)
	var tries: Array[float] = []
	tries.append_array(TURRET_SPOTS)
	tries.append_array(TURRET_FALLBACK_SPOTS)
	for n in tries.size():
		var x := length * tries[n]
		var crowded := x < seat_width / 2.0 or x > length - seat_width / 2.0
		if n < TURRET_SPOTS.size():
			for df in door_fs:
				if absf(length * df - x) < port / 2.0 + BraidTuning.DOOR_WIDTH:
					crowded = true
		for other in ports:
			if absf(float(other[0]) - x) < port + seat_width:
				crowded = true
		if crowded:
			continue
		var seat_first := lane == pair  # the seat on the lane-0 side of the wall
		var seat_local := Rect2(x - seat_width / 2.0, top - seat_depth, seat_width, seat_depth) if seat_first \
			else Rect2(x - seat_width / 2.0, bottom, seat_width, seat_depth)
		var fire_local := Rect2(x - port / 2.0, bottom, port, 24.0) if seat_first \
			else Rect2(x - port / 2.0, top - 24.0, port, 24.0)
		var seat_rect := _frame_rect(p["origin"], p["dir"], seat_local)
		var fire_rect := _frame_rect(p["origin"], p["dir"], fire_local)
		var clear := true
		for strip: Node2D in placed.values():
			for child in strip.get_children():
				if child.get_script() != BraidBlock:
					continue
				var r := Rect2(strip.position + child.position, child.size)
				if r.intersects(seat_rect) or r.intersects(fire_rect):
					clear = false
		if clear:
			return x
	return -1.0


## A gun port `x` along straight piece `p` in the wall between lanes `pair`
## and `pair` + 1: a slit of glass with a turret seated in `lane` firing into
## `target`.
func _add_turret(p: Dictionary, pair: int, x: float, lane: int, target: int) -> void:
	var top := (pair + 1) * BraidTuning.BAND_HEIGHT - BraidTuning.OUTER_WALL
	var port := BraidTuning.TURRET_PORT
	var r := _frame_rect(p["origin"], p["dir"], Rect2(x - port / 2.0, top, port, BraidTuning.SEPARATOR))
	_block(r.position, r.size, "PortGlass", "glass")
	var turret := BraidTurret.new()
	turret.name = "Turret"
	turret.lane = lane
	turret.target_lane = target
	var normal: Vector2 = p["normal"]
	turret.facing = normal if target > lane else -normal
	turret.position = p["origin"] + p["dir"] * x + normal * (top + BraidTuning.SEPARATOR / 2.0)
	turret.s = float(p["s0"][lane]) + x
	add_child(turret)
	turrets.append(turret)
	_ports.append(turret.position)


# --- Junctions and lanes ----------------------------------------------------------

## Closes, for a squad that started in lane `start_lane`, each junction's exit
## into the lane it entered by (seals drawn in `tint`). Call once, in that
## squad's game.
func add_seals(start_lane: int, tint: Color) -> void:
	for j in junctions:
		var lane := lane_at(start_lane, j["x0"])
		if lane != j["pair"] and lane != j["pair"] + 1:
			continue
		var r: Rect2 = j["node"].seal_rect(lane - j["pair"])
		var seal := _block(j["node"].position + r.position, r.size, "Seal", "seal")
		seal.tint = tint
	rebuild_grid()


## The lane a squad that started in `start_lane` is in at progress `x`: it
## swaps at the end of each junction its lane is part of.
func lane_at(start_lane: int, x: float) -> int:
	var lane := start_lane
	for j in junctions:
		if j["x1"] > x:
			break
		if lane == j["pair"]:
			lane += 1
		elif lane == j["pair"] + 1:
			lane -= 1
	return lane


## The junction lane `lane` is in at progress x ({} if none).
func junction_at(lane: int, x: float) -> Dictionary:
	for j in junctions:
		if x >= j["x0"] and x < j["x1"] and (lane == j["pair"] or lane == j["pair"] + 1):
			return j
	return {}


## The window beside lane `lane` at progress x ({} if none).
func window_at(lane: int, x: float) -> Dictionary:
	for w in windows:
		if x >= w["x0"] - BraidTuning.SCREEN_WIDTH / 4.0 and x < w["x1"] + BraidTuning.SCREEN_WIDTH / 4.0 \
				and (lane == w["pair"] or lane == w["pair"] + 1):
			return w
	return {}


## The vertical slice at progress x ({} if none).
func slice_at(x: float) -> Dictionary:
	for sl in slices:
		if x >= sl["from"] and x < sl["to"]:
			return sl
	return {}


## Lane `lane`'s band (its whole height, walls included) where the level
## ends, running right (the convergence room's end of the level).
func band_rect(lane: int) -> Rect2:
	return Rect2(bounds.position.x, _end_y + lane * BraidTuning.BAND_HEIGHT, bounds.size.x,
		BraidTuning.BAND_HEIGHT)


# --- Progress -----------------------------------------------------------------------

## Progress (pixels along its lane from the level's start) at world point
## `at`.
func progress(at: Vector2) -> float:
	var p := _piece_containing(at)
	return _progress_in(p, _lane_in(p, at), at)


## The lane world point `at` is in (by where it is across the ribbon; in the
## room, the band it's in).
func lane_of(at: Vector2) -> int:
	return _lane_in(_piece_containing(at), at)


## The world point at progress `s` in lane `lane`, `v` across the lane from
## its left-hand edge (its top edge while it runs right).
func point_at(lane: int, s: float, v: float) -> Vector2:
	return point_in(_piece_at(lane, s), lane, s, v)


## The middle of lane `lane` at progress `s`.
func lane_point(lane: int, s: float) -> Vector2:
	return point_at(lane, s, BraidTuning.BAND_HEIGHT / 2.0)


## The way lane `lane` runs at progress `s` (round a corner, along its curve).
func dir_at(lane: int, s: float) -> Vector2:
	var p := _piece_at(lane, s)
	if p["kind"] == "straight":
		return p["dir"]
	var lo: float = p["c_lo"][lane]
	var d: float = s - p["s0"][lane]
	if d < lo:
		return p["d_in"]
	if d > lo + CORNER_CELL:
		return p["d_out"]
	var t := (d - lo) / CORNER_CELL * PI / 2.0
	return (sin(t) * p["d_out"] + cos(t) * p["d_in"] as Vector2).normalized()


## The way the lane runs at world point `at`.
func dir_at_point(at: Vector2) -> Vector2:
	var p := _piece_containing(at)
	var lane := _lane_in(p, at)
	return dir_at(lane, _progress_in(p, lane, at))


## True if world points `a` and `b` are in the same lane.
func same_lane(a: Vector2, b: Vector2) -> bool:
	return lane_of(a) == lane_of(b)


## `at` if it's in lane `lane`, else the nearest edge of that lane to it.
func clamp_to_lane(at: Vector2, lane: int) -> Vector2:
	var p := _piece_containing(at)
	var other := _lane_in(p, at)
	if other == lane:
		return at
	var margin := BraidTuning.OUTER_WALL + 8.0
	var v := margin if other < lane else BraidTuning.BAND_HEIGHT - margin
	return point_at(lane, _progress_in(p, other, at), v)


## The world x span (as Vector2(from, to)) the flow field needs to cover every
## lane from progress `from_s` to `to_s`.
func flow_range(from_s: float, to_s: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in pieces:
		var touches := false
		for k in lanes:
			if p["s0"][k] <= to_s and p["s0"][k] + p["len"][k] >= from_s:
				touches = true
				break
		if not touches:
			continue
		var r: Rect2 = p["rect"]
		if p["kind"] == "straight" and p["dir"].x != 0.0:
			var x0: float = p["origin"].x
			var len: float = p["len"][0]
			lo = minf(lo, x0 + clampf(from_s - p["s0"][0], 0.0, len))
			hi = maxf(hi, x0 + clampf(to_s - p["s0"][0], 0.0, len))
		else:
			lo = minf(lo, r.position.x)
			hi = maxf(hi, r.end.x)
	if lo > hi:
		return Vector2(bounds.position.x, bounds.end.x)
	return Vector2(lo, hi)


## Piece `p`'s point in lane `lane` at progress `s` (past a straight piece's
## ends it carries on straight), `v` across from the lane's left-hand edge.
func point_in(p: Dictionary, lane: int, s: float, v: float) -> Vector2:
	var band := BraidTuning.BAND_HEIGHT
	if p["kind"] == "straight":
		return p["origin"] + p["dir"] * (s - p["s0"][lane]) + p["normal"] * (lane * band + v)
	var lo: float = p["c_lo"][lane]
	var d: float = s - p["s0"][lane]
	# How far out from the lane's inside wall.
	var r := v if p["left"] else band - v
	if d < lo:
		return _ab(p, lo + r, d)
	if d > lo + CORNER_CELL:
		return _ab(p, lo - (d - lo - CORNER_CELL), lo + r)
	var t := clampf((d - lo) / CORNER_CELL, 0.0, 1.0) * PI / 2.0
	return _ab(p, lo + r * cos(t), lo + r * sin(t))


func _lane_in(p: Dictionary, at: Vector2) -> int:
	var band := BraidTuning.BAND_HEIGHT
	var k := 0
	if p["kind"] == "straight":
		k = floori((at - p["origin"]).dot(p["normal"]) / band)
	else:
		var rel: Vector2 = at - p["pivot"]
		var c := maxf(rel.dot(-p["d_out"]), rel.dot(p["d_in"]))
		k = floori(c / band) if p["left"] else floori((p["width"] - c) / band)
	return clampi(k, 0, lanes - 1)


func _progress_in(p: Dictionary, lane: int, at: Vector2) -> float:
	var s0: float = p["s0"][lane]
	if p["kind"] == "straight":
		return s0 + (at - p["origin"]).dot(p["dir"])
	var rel: Vector2 = at - p["pivot"]
	var a := rel.dot(-p["d_out"])
	var b := rel.dot(p["d_in"])
	var lo: float = p["c_lo"][lane]
	if b <= lo:
		return s0 + b
	if a <= lo:
		return s0 + lo + CORNER_CELL + (lo - a)
	var t := clampf(atan2(b - lo, a - lo), 0.0, PI / 2.0)
	return s0 + lo + t / (PI / 2.0) * CORNER_CELL


## The piece lane `lane` is in at progress `s` (the first or last past the
## ends).
func _piece_at(lane: int, s: float) -> Dictionary:
	for p in pieces:
		if s < p["s0"][lane] + p["len"][lane]:
			return p
	return pieces[-1]


## The piece world point `at` is in (the nearest, if none).
func _piece_containing(at: Vector2) -> Dictionary:
	var n := pieces.size()
	for k in n:
		for i in ([_last_piece] if k == 0 else [_last_piece + k, _last_piece - k]):
			if i < 0 or i >= n:
				continue
			if pieces[i]["rect"].grow(0.5).has_point(at):
				_last_piece = i
				return pieces[i]
	var best := 0
	var best_d := INF
	for i in n:
		var r: Rect2 = pieces[i]["rect"]
		var d := at.distance_squared_to(at.clamp(r.position, r.end))
		if d < best_d:
			best_d = d
			best = i
	return pieces[best]


# --- Checks and the grid -------------------------------------------------------------

## What's wrong with the level as a whole (empty = nothing): with every gate
## open (and no squad's seals), a way at least BraidTuning.MIN_CORRIDOR wide
## must lead from the start of every lane to the far end, and every segment
## without a slice must be whole screens long.
func check() -> PackedStringArray:
	var out := PackedStringArray()
	if pieces.is_empty():
		return out
	var walls: Array[Rect2] = []
	for block in _blocks():
		var n := String(block.name)
		if not n.begins_with("Gate") and not n.begins_with("Seal"):
			walls.append(_rect_of(block))
	var end_s: float = room_start + BraidTuning.ROOM_LENGTH - BraidTuning.MIN_CORRIDOR if room.has_area() \
		else (gate_x(segments.size() - 1) - 8.0 if not segments.is_empty() else pieces[-1]["s0"][0])
	# Coarse cells (a whole level at the fine default takes seconds): this
	# lets gaps a bit under MIN_CORRIDOR through, but each strip and junction
	# has already had the exact check in its own problems().
	for lane in lanes:
		if not BraidGrid.new().has_way_through(bounds, walls, lane_point(lane, BraidTuning.MIN_CORRIDOR),
				lane_point(lane, end_s), BraidTuning.FLOW_CELL):
			out.append("No way through lane %d at least %d px wide." % [lane + 1, BraidTuning.MIN_CORRIDOR])
	for i in segments.size():
		if segments[i]["slice"]:
			continue
		var seg_len: float = segments[i]["gate_x"] - segments[i]["start"]
		# (Progress after a slice isn't a whole number: corners are part circles.)
		var over := fposmod(seg_len, BraidTuning.SCREEN_WIDTH)
		if over > 0.01 and over < BraidTuning.SCREEN_WIDTH - 0.01:
			out.append("Segment %d is %d px, not whole screens." % [i + 1, seg_len])
	return out


func _blocks() -> Array[Node]:
	return find_children("*", "StaticBody2D", true, false).filter(func(n: Node) -> bool:
		return n.get_script() == BraidBlock and not n.is_queued_for_deletion())


## A block's rectangle relative to the level.
func _rect_of(block: Node2D) -> Rect2:
	return Rect2(block.get_relative_transform_to_parent(self).origin, block.size)


## Every wall rectangle (blocks, glass, closed gates, seals).
func wall_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for block in _blocks():
		rects.append(_rect_of(block))
	return rects


func rebuild_grid() -> void:
	grid = BraidGrid.new()
	grid.rasterize(bounds, wall_rects())
	var floor_rects: Array[Rect2] = []
	for p in pieces:
		floor_rects.append(p["rect"])
	grid.block_outside(floor_rects)


# --- Segments and checkpoints --------------------------------------------------------

func segment_count() -> int:
	return segments.size()


## Progress at segment `i`'s checkpoint gates (their near edge).
func gate_x(i: int) -> float:
	return segments[i]["gate_x"]


func segment_start(i: int) -> float:
	return segments[i]["start"]


## Segment `i`'s checkpoint is done with: its shops' doors stand open. The
## buildings stay solid (squads come out past them).
func open_gate(i: int) -> void:
	for shop: Node in segments[i]["shops"]:
		shop.open()


## Every checkpoint gets a light for each of `squads` (in `colors`).
func set_shop_squads(squads: Array, colors: Array) -> void:
	for seg in segments:
		for shop: Node in seg["shops"]:
			shop.set_squads(squads, colors)


## Segment `i`'s checkpoint lights, in every lane: {squad: BraidShopBuilding.Light}.
func set_shop_lights(i: int, states: Dictionary) -> void:
	for shop: Node in segments[i]["shops"]:
		shop.set_lights(states)


## Segment `i`'s checkpoint plate in lane `lane` (relative to the level).
func plate_rect(i: int, lane: int) -> Rect2:
	return segments[i]["shops"][lane].plate_rect()


# --- The tide ---------------------------------------------------------------------

## Every tide speed in the level is multiplied by this (the Riptide
## modifier: scripts/braid/braid_modifiers.gd). The layout isn't: the same
## level, crossed faster.
var tide_speed_scale := 1.0


## The tide's speed (px/s) with its front at progress `x`.
func tide_speed_at(x: float) -> float:
	for span in _spans:
		if x < span["to"]:
			return span["tide_speed"] * tide_speed_scale
	return BraidTuning.TIDE_SPEED * tide_speed_scale


## Seconds the tide takes from progress `from_x` to `to_x`.
func tide_time(from_x: float, to_x: float) -> float:
	var t := 0.0
	var x := from_x
	if x < 0.0:
		t += minf(-x, to_x - x) / (BraidTuning.TIDE_SPEED * tide_speed_scale)  # before the first slot
		x = 0.0
	for span in _spans:
		if x >= to_x:
			break
		if span["to"] <= x:
			continue
		var end := minf(span["to"], to_x)
		t += (end - x) / (span["tide_speed"] * tide_speed_scale)
		x = end
	return t


## Where the tide is `seconds` after it left `from_x` (never past `stop_x`).
func tide_after(from_x: float, seconds: float, stop_x: float) -> float:
	var x := from_x
	var left := seconds
	while left > 0.0 and x < stop_x:
		var speed := tide_speed_at(x)
		# To the end of this span (or the first slot, before it).
		var span_end := 0.0 if x < 0.0 else stop_x
		if x >= 0.0:
			for span in _spans:
				if x < span["to"]:
					span_end = span["to"]
					break
		var step := minf(span_end, stop_x) - x
		if step <= 0.0:
			break
		if step / speed >= left:
			return x + left * speed
		x += step
		left -= step / speed
	return minf(x, stop_x)


# --- Spawning -------------------------------------------------------------------------

## Spawn vents with progress in [from_x, to_x] serving lane `lane`.
func vents_between(lane: int, from_x: float, to_x: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for v in vents:
		if v["s"] > to_x:
			break
		if v["s"] >= from_x and lane in v["lanes"]:
			out.append(v["pos"])
	return out


## Doors with progress in [from_x, to_x] opening into lane `lane`.
func doors_between(lane: int, from_x: float, to_x: float) -> Array[Node]:
	var out: Array[Node] = []
	for d: Node2D in doors:
		if d.s > to_x:
			break
		if d.s >= from_x and d.lane == lane:
			out.append(d)
	return out


## A random open spot (a cell centre) across lane `lane` at progress `x`, or
## Vector2.INF if it's all wall. Spots a cell clear of walls first (bigger
## enemies spawned right against a wall start out overlapping it).
func random_open_point_at(lane: int, x: float) -> Vector2:
	var spots: Array[Vector2] = []
	var roomy: Array[Vector2] = []
	var v := BraidTuning.OUTER_WALL + BraidTuning.FLOW_CELL / 2.0
	while v < BraidTuning.BAND_HEIGHT - BraidTuning.OUTER_WALL:
		var c := grid.cell_of(point_at(lane, x, v))
		if grid.is_free(c):
			var centre := grid.cell_center(c)
			if not spots.has(centre):
				spots.append(centre)
				if grid.clearance(c) >= 2:
					roomy.append(centre)
		v += BraidTuning.FLOW_CELL
	if not roomy.is_empty():
		return roomy.pick_random()
	return spots.pick_random() if not spots.is_empty() else Vector2.INF


## `at` if it's open floor, else the nearest open cell centre (searching a
## few cells out), else `at`.
func nearest_open(at: Vector2) -> Vector2:
	var c := grid.cell_of(at)
	if grid.is_free(c):
		return at
	for r in range(1, 6):
		var best := Vector2.INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if grid.is_free(n):
					var p := grid.cell_center(n)
					if best == Vector2.INF or p.distance_squared_to(at) < best.distance_squared_to(at):
						best = p
		if best != Vector2.INF:
			return best
	return at
