@tool
extends RefCounted
## A coarse grid over a Braid level: which cells are wall, and a flow field
## (steps to the nearest player) that enemies follow around walls.
##
## Built once from the level's wall rectangles (rasterize), then the flow
## field is rebuilt a few times a second (update_flow) over a window around
## the squad. Enemies outside the window, or with nothing in the way, just
## walk straight (steer() returns the straight-line direction).

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")

## Within this many steps of a player, enemies walk straight at them.
const DIRECT_STEPS := 2
## clearance() looks this many cells out at most.
const CLEAR_MAX := 4
## waypoint_ahead looks this many cells down the flow field.
const LOOKAHEAD := 12

var cell := BraidTuning.FLOW_CELL
## World position of cell (0, 0)'s top-left corner.
var origin := Vector2.ZERO
var cols := 0
var rows := 0
## 1 = wall (cols * rows, row-major).
var blocked := PackedByteArray()
## Steps to the nearest player, -1 = not reached. Only cells in
## [_win_lo, _win_hi) columns are valid.
var dist := PackedInt32Array()
var _win_lo := 0
var _win_hi := 0
## Per cell, the way steer() sends enemies (worked out when first asked after
## each update_flow: _way_gen[i] == _gen means it's current).
var _way := PackedVector2Array()
var _way_kind := PackedByteArray()
var _way_gen := PackedInt32Array()
var _gen := 0
## Per cell, clearance() once worked out (255 = not yet). Wiped whenever a
## cell's wall changes (_clear_dirty).
var _clear := PackedByteArray()
var _clear_dirty := true
const _WAY_STRAIGHT := 0  # straight at the target
const _WAY_DOWNHILL := 1  # along _way, pulled toward the cell's middle
const _WAY_OUT := 2  # along _way, out of a wall's padding

const _NEIGHBOURS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const _DIAGONALS := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


## Sets up a grid covering `area` with every cell overlapping `walls`
## (Rect2s, grown by `pad`) blocked.
func rasterize(area: Rect2, walls: Array, pad := BraidTuning.FLOW_WALL_PAD) -> void:
	origin = area.position
	cols = ceili(area.size.x / cell)
	rows = ceili(area.size.y / cell)
	blocked = PackedByteArray()
	blocked.resize(cols * rows)
	blocked.fill(0)
	dist = PackedInt32Array()
	dist.resize(cols * rows)
	dist.fill(-1)
	_way.resize(cols * rows)
	_way_kind.resize(cols * rows)
	_way_gen = PackedInt32Array()
	_way_gen.resize(cols * rows)
	_way_gen.fill(-1)
	_gen = 0
	_clear = PackedByteArray()
	_clear.resize(cols * rows)
	_clear_dirty = true
	for wall: Rect2 in walls:
		set_blocked(wall.grow(pad), true)


## Marks every cell that doesn't overlap any of `rects` as wall: the void
## around the level's lanes isn't floor (enemies must never be put there).
func block_outside(rects: Array) -> void:
	var inside := PackedByteArray()
	inside.resize(cols * rows)
	inside.fill(0)
	for rect: Rect2 in rects:
		var lo := cell_of(rect.position)
		var hi := cell_of(rect.end - Vector2(0.01, 0.01))
		for cy in range(maxi(lo.y, 0), mini(hi.y, rows - 1) + 1):
			for cx in range(maxi(lo.x, 0), mini(hi.x, cols - 1) + 1):
				inside[cy * cols + cx] = 1
	for i in cols * rows:
		if inside[i] == 0:
			blocked[i] = 1
	_clear_dirty = true


## Marks every cell overlapping `rect` as wall (or clears them).
func set_blocked(rect: Rect2, value: bool) -> void:
	_clear_dirty = true
	var lo := cell_of(rect.position)
	# A rect ending exactly on a cell edge doesn't reach into the next cell.
	var hi := cell_of(rect.end - Vector2(0.01, 0.01))
	for cy in range(maxi(lo.y, 0), mini(hi.y, rows - 1) + 1):
		for cx in range(maxi(lo.x, 0), mini(hi.x, cols - 1) + 1):
			blocked[cy * cols + cx] = 1 if value else 0


func cell_of(world: Vector2) -> Vector2i:
	return Vector2i(floori((world.x - origin.x) / cell), floori((world.y - origin.y) / cell))


func cell_center(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell


func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


func is_free(c: Vector2i) -> bool:
	return in_grid(c) and blocked[c.y * cols + c.x] == 0


func is_free_at(world: Vector2) -> bool:
	return is_free(cell_of(world))


## How many cells (square rings) out from cell `c` the nearest wall cell is:
## 0 for a wall, 1 next to one, up to CLEAR_MAX for open floor. Worked out
## once per cell and cached.
func clearance(c: Vector2i) -> int:
	if not is_free(c):
		return 0
	if _clear_dirty:
		_clear.fill(255)
		_clear_dirty = false
	var i := c.y * cols + c.x
	if _clear[i] != 255:
		return _clear[i]
	var r := 1
	while r < CLEAR_MAX and not _ring_blocked(c, r):
		r += 1
	_clear[i] = r
	return r


## True if any cell on the square ring `r` out from `c` is wall (or off the
## grid).
func _ring_blocked(c: Vector2i, r: int) -> bool:
	for d in range(-r, r + 1):
		if not is_free(Vector2i(c.x + d, c.y - r)) or not is_free(Vector2i(c.x + d, c.y + r)) \
				or not is_free(Vector2i(c.x - r, c.y + d)) or not is_free(Vector2i(c.x + r, c.y + d)):
			return true
	return false


## Breadth-first steps from `sources` (world positions) over the columns
## covering world x `from_x` .. `to_x`.
func update_flow(sources: Array, from_x: float, to_x: float) -> void:
	_gen += 1
	# Forget the old window.
	for cx in range(_win_lo, _win_hi):
		for cy in rows:
			dist[cy * cols + cx] = -1
	_win_lo = clampi(floori((from_x - origin.x) / cell), 0, cols)
	_win_hi = clampi(ceili((to_x - origin.x) / cell), _win_lo, cols)
	var queue := PackedInt32Array()
	for p: Vector2 in sources:
		var c := cell_of(p)
		if c.x < _win_lo or c.x >= _win_hi or c.y < 0 or c.y >= rows:
			continue
		var i := c.y * cols + c.x
		if dist[i] != 0:
			dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var cx := i % cols
		var cy := i / cols
		var d := dist[i] + 1
		# Unrolled 4-neighbour step (this loop is the hot path).
		if cx + 1 < _win_hi:
			var n := i + 1
			if dist[n] == -1 and blocked[n] == 0:
				dist[n] = d
				queue.append(n)
		if cx - 1 >= _win_lo:
			var n := i - 1
			if dist[n] == -1 and blocked[n] == 0:
				dist[n] = d
				queue.append(n)
		if cy + 1 < rows:
			var n := i + cols
			if dist[n] == -1 and blocked[n] == 0:
				dist[n] = d
				queue.append(n)
		if cy - 1 >= 0:
			var n := i - cols
			if dist[n] == -1 and blocked[n] == 0:
				dist[n] = d
				queue.append(n)


func _dist(c: Vector2i) -> int:
	if c.x < _win_lo or c.x >= _win_hi or c.y < 0 or c.y >= rows:
		return -1
	return dist[c.y * cols + c.x]


## Which way an enemy at `from` should walk to reach `target` (a world
## position): downhill along the flow field, or straight when it's close, off
## the field, or the field doesn't reach it. Each cell's way is worked out
## once per update_flow and shared by every enemy in it.
func steer(from: Vector2, target: Vector2) -> Vector2:
	var cx := floori((from.x - origin.x) / cell)
	var cy := floori((from.y - origin.y) / cell)
	if cx < _win_lo or cx >= _win_hi or cy < 0 or cy >= rows:
		return from.direction_to(target)
	var i := cy * cols + cx
	if _way_gen[i] != _gen:
		_work_out_way(i, Vector2i(cx, cy))
	match _way_kind[i]:
		_WAY_DOWNHILL:
			# Pull a little toward the cell's middle so enemies don't grind along walls.
			var centre := origin + Vector2(cx + 0.5, cy + 0.5) * cell
			return (_way[i] + (centre - from) / cell * 0.35).normalized()
		_WAY_OUT:
			return _way[i]
	return from.direction_to(target)


func _work_out_way(i: int, c: Vector2i) -> void:
	_way_gen[i] = _gen
	_way_kind[i] = _WAY_STRAIGHT
	var here := dist[i]
	if here < 0:
		# Pushed up against a wall (its padding) or the field doesn't reach:
		# head for the best cell next to us, if there is one.
		var best := -1
		var best_o := Vector2i.ZERO
		for o: Vector2i in _NEIGHBOURS + _DIAGONALS:
			var d := _dist(c + o)
			if d >= 0 and (best < 0 or d < best):
				best = d
				best_o = o
		if best >= 0:
			_way_kind[i] = _WAY_OUT
			_way[i] = Vector2(best_o).normalized()
		return
	if here <= DIRECT_STEPS:
		return
	# Downhill neighbours, leaning toward the ones further from walls, so
	# enemies (much wider than a wall's padding) give corners a wider berth.
	var sum := Vector2.ZERO
	for o: Vector2i in _NEIGHBOURS:
		var d := _dist(c + o)
		if d >= 0 and d < here:
			sum += Vector2(o) * float(here - d) * _lean(c + o)
	for o: Vector2i in _DIAGONALS:
		# No cutting a wall's corner.
		if _dist(Vector2i(c.x + o.x, c.y)) < 0 or _dist(Vector2i(c.x, c.y + o.y)) < 0:
			continue
		var d := _dist(c + o)
		if d >= 0 and d < here:
			sum += Vector2(o).normalized() * float(here - d) * _lean(c + o)
	if sum != Vector2.ZERO:
		_way_kind[i] = _WAY_DOWNHILL
		_way[i] = sum.normalized()


func _lean(c: Vector2i) -> float:
	return 1.0 + 0.5 * clearance(c)


## The careful way, for an enemy that's been stuck (chasesplayer.gd's
## unstick_left): follows the flow field up to LOOKAHEAD cells ahead and
## returns the farthest point on it that a body `radius` px across can walk
## to in a straight line without touching a wall (else the next cell on it;
## Vector2.INF off the field). A few hundred cell checks (~0.2 ms), so only
## stuck enemies use it, and not every frame.
func waypoint_ahead(from: Vector2, target: Vector2, radius: float) -> Vector2:
	var c := cell_of(from)
	if _dist(c) < 0:
		# In a wall's padding (or off the field): start from the best cell next to us.
		var best := -1
		for o: Vector2i in _NEIGHBOURS + _DIAGONALS:
			var d := _dist(c + o)
			if d >= 0 and (best < 0 or d < best):
				best = d
				c = cell_of(from) + o
		if best < 0:
			return Vector2.INF
	# Down the field, steepest first (ties: away from walls).
	var path: Array[Vector2] = [cell_center(c)]
	var here := _dist(c)
	while path.size() <= LOOKAHEAD and here > 0:
		var next := c
		var next_d := here
		var next_clear := -1
		for o: Vector2i in _NEIGHBOURS + _DIAGONALS:
			if o.x != 0 and o.y != 0 and (_dist(Vector2i(c.x + o.x, c.y)) < 0 or _dist(Vector2i(c.x, c.y + o.y)) < 0):
				continue
			var d := _dist(c + o)
			if d < 0 or d > next_d:
				continue
			var cl := clearance(c + o)
			if d < next_d or cl > next_clear:
				next = c + o
				next_d = d
				next_clear = cl
		if next == c or next_d == here:
			break
		c = next
		here = next_d
		path.append(cell_center(c))
	if here == 0:
		path.append(target)
	# How far from walls the body's middle must stay, in cells (see clearance).
	var need := 1 + ceili(maxf(radius - BraidTuning.FLOW_WALL_PAD, 0.0) / cell)
	for k in range(path.size() - 1, 0, -1):
		if _walkable(from, path[k], radius, need):
			return path[k]
	return path[1] if path.size() > 1 else target


## True if a body `radius` px across can walk straight from `a` to `b`: every
## half cell along the way has at least `need` clearance (just open floor
## within `radius` of `a`, where it already stands).
func _walkable(a: Vector2, b: Vector2, radius: float, need: int) -> bool:
	var length := a.distance_to(b)
	var steps := maxi(ceili(length / (cell * 0.5)), 1)
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var c := cell_of(a.lerp(b, t))
		if t * length < radius:
			if not is_free(c):
				return false
		elif clearance(c) < need:
			return false
	return true


## Free rows (as world y, cell centres) in the column at world x.
func free_ys_at(x: float) -> Array[float]:
	var cx := floori((x - origin.x) / cell)
	var ys: Array[float] = []
	if cx < 0 or cx >= cols:
		return ys
	for cy in rows:
		if blocked[cy * cols + cx] == 0:
			ys.append(origin.y + (cy + 0.5) * cell)
	return ys


## Cell size has_way_through uses by default: fine enough that the answer
## doesn't depend on where a gap sits against the grid.
const WAY_CELL := 4.0


## True if a way at least BraidTuning.MIN_CORRIDOR wide leads from `a` to
## `b` (world points) through `area` around `walls` (Rect2s). Rasterizes
## this grid for that (use a fresh one), in `cell_size` cells.
##
## Every gap of MIN_CORRIDOR or more passes wherever it sits; a gap up to two
## cells narrower may pass too, depending on where it falls against the grid
## (so with WAY_CELL, only gaps under MIN_CORRIDOR - 8 px surely fail). Coarser
## cells are quicker on big areas but let narrower gaps through.
func has_way_through(area: Rect2, walls: Array, a: Vector2, b: Vector2,
		cell_size := WAY_CELL) -> bool:
	cell = cell_size
	# Walls grow by MIN_CORRIDOR/2 less a cell, so a MIN_CORRIDOR gap leaves
	# two cells' width open, which always holds a whole grid cell (cells
	# round the grown walls outwards).
	rasterize(area, walls, BraidTuning.MIN_CORRIDOR / 2.0 - cell_size)
	return connected(a, b)


## True if open floor connects world points `a` and `b` (ignores the flow
## window). For checking level pieces.
func connected(a: Vector2, b: Vector2) -> bool:
	var start := cell_of(a)
	var goal := cell_of(b)
	if not is_free(start) or not is_free(goal):
		return false
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	seen.fill(0)
	var queue := PackedInt32Array([start.y * cols + start.x])
	seen[queue[0]] = 1
	var head := 0
	var goal_i := goal.y * cols + goal.x
	# Walls count as seen, so each step is one byte check.
	for k in cols * rows:
		if blocked[k] != 0:
			seen[k] = 1
	while head < queue.size():
		var i := queue[head]
		head += 1
		if i == goal_i:
			return true
		var cx := i % cols
		# Unrolled 4-neighbour step (as in update_flow).
		if cx + 1 < cols and seen[i + 1] == 0:
			seen[i + 1] = 1
			queue.append(i + 1)
		if cx > 0 and seen[i - 1] == 0:
			seen[i - 1] = 1
			queue.append(i - 1)
		if i + cols < seen.size() and seen[i + cols] == 0:
			seen[i + cols] = 1
			queue.append(i + cols)
		if i >= cols and seen[i - cols] == 0:
			seen[i - cols] = 1
			queue.append(i - cols)
	return false
