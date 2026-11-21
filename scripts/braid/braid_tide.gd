extends Node2D
## The tide: a wall of murk that rolls along a Braid lane from left to right
## and is what moves a squad on (scripts/braid/braid_game.gd).
##
## It covers every lane, at the same progress along each (BraidLevel.progress),
## so it follows the lanes round their corners. Each physics frame braid_game.gd moves its front to
## where the segment's clock says (BraidLevel.tide_after: the host's clock in
## a squads game, so it's in the same place for everyone), never past `stop_x`
## (just short of the next checkpoint gate), and calls update(), which:
##   - our players it reaches are pushed along (they can't be more than
##     TIDE_PUSH_DEPTH into it) and lose TIDE_DAMAGE every
##     TIDE_DAMAGE_INTERVAL while it touches them; a player pinned against a
##     wall until it covers them is knocked out,
##   - our enemies and pickups TIDE_SWALLOW_DEPTH inside it are swallowed
##     (no kill, no drops; the pickup is lost).

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")
const BossBody := preload("res://scripts/bosses/boss_body.gd")

const BODY := Color(0.16, 0.06, 0.22, 0.92)
const FRONT := Color(0.55, 0.25, 0.75, 0.95)
const FOAM := Color(0.85, 0.6, 1.0, 0.9)
## Players count as this wide when it reaches them (their square is 26 px).
const PLAYER_HALF_WIDTH := 13.0
## A touch shorter than this does no damage.
const FIRST_TOUCH_GRACE := 0.5

## Progress of the front (along every lane).
var front := 0.0
## It stops here.
var stop_x := INF
## The lane (scripts/braid/braid_level.gd), for its speed along the way.
var level: Node2D
## Half hearts lost to it per player this segment (for the summary).
var damage_dealt := {}
var _touch_timers := {}
var _time := 0.0


func _ready() -> void:
	z_index = 50


## Puts the front at `x` with the stop at `stop`.
func reset(x: float, stop: float) -> void:
	front = x
	stop_x = stop
	_touch_timers.clear()
	damage_dealt.clear()
	queue_redraw()


func reached_stop() -> bool:
	return front >= stop_x


## Seconds until it reaches the stop.
func time_left() -> float:
	return level.tide_time(front, stop_x) if level else 0.0


## Moves the front to `x` (capped at stop_x) and does what it does to
## `players` (ours) and to our enemies and pickups.
func update(x: float, delta: float, players: Array[Node]) -> void:
	_time += delta
	front = minf(x, stop_x)
	_push_players(delta, players)
	_swallow()
	queue_redraw()


func _push_players(delta: float, players: Array[Node]) -> void:
	for player: Node2D in players:
		if player.is_dead():
			_touch_timers.erase(player)
			continue
		var at := _progress(player.global_position)
		if at - PLAYER_HALF_WIDTH >= front:
			_touch_timers.erase(player)
			continue
		# Shove them out to TIDE_PUSH_DEPTH inside it; walls can stop that.
		var min_x := front - BraidTuning.TIDE_PUSH_DEPTH + PLAYER_HALF_WIDTH
		if at < min_x:
			var along: Vector2 = level.dir_at_point(player.global_position) if level else Vector2.RIGHT
			player.move_and_collide(along * (min_x - at))
			at = _progress(player.global_position)
		if at + PLAYER_HALF_WIDTH < front:
			# Pinned and swallowed whole.
			_hurt(player, player.health)
			continue
		# Seconds to the next hit: the grace first, then every interval.
		var t: float = _touch_timers.get(player, FIRST_TOUCH_GRACE) - delta
		if t <= 0.0:
			_hurt(player, BraidTuning.TIDE_DAMAGE)
			t += BraidTuning.TIDE_DAMAGE_INTERVAL
		_touch_timers[player] = t


func _hurt(player: Node, amount: int) -> void:
	damage_dealt[player] = damage_dealt.get(player, 0) + amount
	player.take_hit(amount, player.global_position)


func _swallow() -> void:
	var line := front - BraidTuning.TIDE_SWALLOW_DEPTH
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		if _progress(enemy.global_position) < line and not enemy.is_queued_for_deletion() \
				and not enemy.get("is_mirror") and not enemy is BossBody:
			enemy.remove_from_group("enemies")
			enemy.queue_free()
	for pickup: Node2D in get_tree().get_nodes_in_group("pickups"):
		if _progress(pickup.global_position) < line:
			pickup.remove_from_group("pickups")
			pickup.queue_free()


func _progress(at: Vector2) -> float:
	return level.progress(at) if level else at.x


func _draw() -> void:
	if level == null:
		return
	for p: Dictionary in level.pieces:
		var behind := true
		var ahead := true
		for k in level.lanes:
			behind = behind and p["s0"][k] + p["len"][k] <= front
			ahead = ahead and p["s0"][k] >= front
		if ahead:
			continue
		if behind:
			draw_rect(p["rect"], BODY)
			continue
		for k in level.lanes:
			var d: float = front - p["s0"][k]
			if d <= 0.0:
				continue
			if p["kind"] == "straight":
				_draw_straight(p, k, d)
			else:
				_draw_corner(p, k, d)


## Lane `k` of straight piece `p`, `d` of it covered: up to a rolling front.
func _draw_straight(p: Dictionary, k: int, d: float) -> void:
	var band := BraidTuning.BAND_HEIGHT
	var s0: float = p["s0"][k]
	if d >= p["len"][k]:
		draw_colored_polygon(PackedVector2Array([level.point_in(p, k, s0, 0.0),
			level.point_in(p, k, s0 + d, 0.0), level.point_in(p, k, s0 + d, band),
			level.point_in(p, k, s0, band)]), BODY)
		return
	var edge := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var v := band * i / steps
		var y: float = (k * band + v) if p["dir"] == Vector2.RIGHT else v
		var bulge := sin(y * 0.045 + _time * 2.2) * 5.0 + sin(y * 0.11 - _time * 3.1) * 3.0
		# (Never behind the piece's start: the polygon would fold over.)
		edge.append(level.point_in(p, k, maxf(s0 + d + bulge - 4.0, s0 + 1.0), v))
	var poly := PackedVector2Array([level.point_in(p, k, s0, 0.0)])
	poly.append_array(edge)
	poly.append(level.point_in(p, k, s0, band))
	draw_colored_polygon(poly, BODY)
	var glow := edge.duplicate()
	var back: Vector2 = -p["dir"] * 10.0
	for i in range(edge.size() - 1, -1, -1):
		glow.append(edge[i] + back)
	draw_colored_polygon(glow, FRONT)
	draw_polyline(edge, FOAM, 2.0)


## Lane `k` of corner `p`, `d` of it covered: its arm in, the turning square,
## its arm out, each up to the front.
func _draw_corner(p: Dictionary, k: int, d: float) -> void:
	var band := BraidTuning.BAND_HEIGHT
	var lo: float = p["c_lo"][k]
	var cell: float = level.CORNER_CELL
	# The arm in: a along [lo, lo + band], b along [0, lo].
	if lo > 0.0:
		var b := minf(d, lo)
		_fill_ab(p, lo, lo + band, 0.0, b)
		if d < lo:
			_front_line(level._ab(p, lo, b), level._ab(p, lo + band, b))
			return
	# The turning square, swept round its inside corner.
	var t := clampf((d - lo) / cell, 0.0, 1.0) * PI / 2.0
	if t > 0.02:
		var hit := Vector2(band, band * tan(t)) if t <= PI / 4.0 else Vector2(band / tan(t), band)
		var poly := PackedVector2Array([level._ab(p, lo, lo), level._ab(p, lo + band, lo)])
		if t > PI / 4.0:
			poly.append(level._ab(p, lo + band, lo + band))
		poly.append(level._ab(p, lo + hit.x, lo + hit.y))
		draw_colored_polygon(poly, BODY)
		if d < lo + cell:
			_front_line(level._ab(p, lo, lo), level._ab(p, lo + hit.x, lo + hit.y))
			return
	# The arm out: b along [lo, lo + band], a from lo back to 0.
	if lo > 0.0:
		var a := maxf(lo - (d - lo - cell), 0.0)
		_fill_ab(p, a, lo, lo, lo + band)
		if a > 0.0:
			_front_line(level._ab(p, a, lo), level._ab(p, a, lo + band))


func _fill_ab(p: Dictionary, a0: float, a1: float, b0: float, b1: float) -> void:
	if a1 - a0 > 0.0 and b1 - b0 > 0.0:
		draw_rect(level._ab_rect(p, a0, a1, b0, b1), BODY)


func _front_line(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, FRONT, 8.0)
	draw_line(from, to, FOAM, 2.0)
