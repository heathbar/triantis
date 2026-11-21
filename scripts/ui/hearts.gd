extends Control
## Draws a row of hearts from `health` and `max_health`, both in half hearts:
## filled halves first, then grey "lost" ones (a heart can be half filled).
## With `max_width` set, the hearts shrink so the row never gets wider.
## While `healing`, the first lost half (the one coming back) flashes.

const HEART_COLOR := Color(1.0, 0.2, 0.3)
const LOST_HEART_COLOR := Color(0.25, 0.25, 0.25)
const HEALING_HEART_COLOR := Color(0.45, 1.0, 0.55)
## Flashes per second while healing.
const HEAL_FLASH_RATE := 2.5

const HALVES := 2

var health := 0:
	set(value):
		health = value
		queue_redraw()
var max_health := 6:
	set(value):
		max_health = value
		_update_size()
		queue_redraw()
var heart_size := 44.0:
	set(value):
		heart_size = value
		_update_size()
		queue_redraw()
## 0 = no limit.
var max_width := 0.0:
	set(value):
		max_width = value
		_update_size()
		queue_redraw()
var healing := false:
	set(value):
		healing = value
		_flash_time = 0.0
		set_process(value)
		queue_redraw()

var _flash_time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_size()
	set_process(false)


func _process(delta: float) -> void:
	_flash_time += delta
	queue_redraw()


## Heart size and gap actually used, after shrinking to fit max_width.
func _metrics() -> Vector2:
	var s := heart_size
	var gap := s * 0.23
	var n := maxi(_heart_count(), 1)
	if max_width > 0.0 and n * s + (n - 1) * gap > max_width:
		s = max_width / (n + (n - 1) * 0.23)
		gap = s * 0.23
	return Vector2(s, gap)


func _update_size() -> void:
	var m := _metrics()
	var count := _heart_count()
	var width := count * m.x + maxi(count - 1, 0) * m.y
	custom_minimum_size = Vector2(maxf(width, max_width), heart_size)


func _draw() -> void:
	var m := _metrics()
	var top := (heart_size - m.x) / 2.0
	for i in _heart_count():
		var origin := Vector2(i * (m.x + m.y), top)
		# The whole heart in its right half's colour, then the left half over it.
		_draw_heart(origin, m.x, _half_color(i * HALVES + 1))
		_draw_heart(origin, m.x, _half_color(i * HALVES), true)


func _heart_count() -> int:
	return ceili(max_health / float(HALVES))


## Colour of half heart number `half` (0 = left half of the first heart).
func _half_color(half: int) -> Color:
	if half < health:
		return HEART_COLOR
	if healing and half == health:
		var t := 0.5 - 0.5 * cos(_flash_time * TAU * HEAL_FLASH_RATE)
		return LOST_HEART_COLOR.lerp(HEALING_HEART_COLOR, t)
	return LOST_HEART_COLOR


## Two circles for the lobes plus a triangle for the point. With `left_only`,
## just the part left of the middle.
func _draw_heart(origin: Vector2, s: float, color: Color, left_only := false) -> void:
	var r := s * 0.27
	var shapes: Array[PackedVector2Array] = [
		_circle(origin + Vector2(s * 0.29, s * 0.32), r),
		_circle(origin + Vector2(s * 0.71, s * 0.32), r),
		PackedVector2Array([
			origin + Vector2(s * 0.04, s * 0.42),
			origin + Vector2(s * 0.96, s * 0.42),
			origin + Vector2(s * 0.5, s * 0.95),
		]),
	]
	var clip := PackedVector2Array([origin, origin + Vector2(s * 0.5, 0),
			origin + Vector2(s * 0.5, s), origin + Vector2(0, s)])
	for shape in shapes:
		var pieces: Array[PackedVector2Array] = [shape]
		if left_only:
			pieces = Geometry2D.intersect_polygons(shape, clip)
		for piece in pieces:
			if piece.size() >= 3:
				draw_colored_polygon(piece, color)


static func _circle(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in 32:
		points.append(center + Vector2.from_angle(k * TAU / 32) * radius)
	return points
