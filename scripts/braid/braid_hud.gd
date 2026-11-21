extends CanvasLayer
## Braid mode's own bits of HUD, on top of the usual one
## (scripts/ui/health_hud.gd): a big banner as each segment starts, and the
## braid bar along the bottom of the screen: the whole act from start to the
## last checkpoint, with the tide, the checkpoint gates (tall posts), junctions
## (diamonds), windows (short bars) and vertical slices (a pale stretch with
## an arrow up or down), our players as dots in their colours
## and every other squad as one dot in its squad colour (dim while wiped out).

const BAR_SIZE := Vector2(1600, 44)
const BAR_BOTTOM_MARGIN := 64.0
const TRACK := Color(0, 0, 0, 0.55)
const TRACK_BORDER := Color(1, 1, 1, 0.35)
const TIDE_COLOR := Color(0.55, 0.25, 0.75, 0.95)
const GATE_COLOR := Color(1.0, 0.72, 0.35)
const JUNCTION_COLOR := Color(0.6, 0.95, 1.0)
const WINDOW_COLOR := Color(0.55, 0.8, 1.0, 0.8)
const SLICE_COLOR := Color(1, 1, 1, 0.16)
const SLICE_ARROW := Color(1, 1, 1, 0.7)
const DOT_RADIUS := 12.0
const SQUAD_DOT_RADIUS := 16.0


## The bar: draws itself from what BraidHud.update_bar gives it.
class ProgressBarView extends Control:
	var start_x := 0.0
	var end_x := 1.0
	var tide_x := 0.0
	var gates: Array[float] = []
	var junctions: Array[float] = []
	var windows: Array[Vector2] = []
	## [Vector3(from, to, 1 up / -1 down)]
	var slices: Array[Vector3] = []
	## [{"x": world x, "color": Color, "dead": bool, "squad": bool}]
	var dots: Array[Dictionary] = []

	func _frac(x: float) -> float:
		return clampf((x - start_x) / maxf(end_x - start_x, 1.0), 0.0, 1.0)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var track := StyleBoxFlat.new()
		track.bg_color = TRACK
		track.border_color = TRACK_BORDER
		track.set_border_width_all(3)
		track.set_corner_radius_all(int(size.y / 2.0))
		draw_style_box(track, r)
		for sl in slices:
			var a := size.x * _frac(sl.x)
			var b := size.x * _frac(sl.y)
			draw_rect(Rect2(a, 4, b - a, size.y - 8), SLICE_COLOR)
			var c := Vector2((a + b) / 2.0, size.y / 2.0)
			var d := 9.0 * sl.z
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, d * 0.6),
				c + Vector2(-d, d * 0.6)]), SLICE_ARROW)
		for w in windows:
			var a := size.x * _frac(w.x)
			var b := size.x * _frac(w.y)
			draw_rect(Rect2(a, size.y * 0.35, b - a, size.y * 0.3), WINDOW_COLOR)
		var tide_w := size.x * _frac(tide_x)
		if tide_w > 2.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = TIDE_COLOR
			fill.set_corner_radius_all(int(size.y / 2.0))
			draw_style_box(fill, Rect2(0, 0, maxf(tide_w, size.y), size.y))
		for g in gates:
			draw_rect(Rect2(size.x * _frac(g) - 4, -14, 8, size.y + 28), GATE_COLOR)
		for j in junctions:
			var c := Vector2(size.x * _frac(j), size.y / 2.0)
			var d := 12.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0),
				c + Vector2(0, d), c + Vector2(-d, 0)]), JUNCTION_COLOR)
		for d in dots:
			var at := Vector2(size.x * _frac(d["x"]), size.y / 2.0)
			var c: Color = d["color"]
			if d["dead"]:
				c = c.darkened(0.6)
			var radius := SQUAD_DOT_RADIUS if d.get("squad", false) else DOT_RADIUS
			draw_circle(at, radius + 3.0, Color.BLACK)
			draw_circle(at, radius, c)


var _bar: ProgressBarView
var _banner: VBoxContainer
var _banner_tween: Tween


func _ready() -> void:
	layer = 2
	_bar = ProgressBarView.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_left = -BAR_SIZE.x / 2.0
	_bar.offset_right = BAR_SIZE.x / 2.0
	_bar.offset_top = -BAR_BOTTOM_MARGIN - BAR_SIZE.y
	_bar.offset_bottom = -BAR_BOTTOM_MARGIN
	add_child(_bar)


func set_bar_visible(on: bool) -> void:
	_bar.visible = on


## The act: from `start_x` to `end_x`, `level` (BraidLevel) for its gates,
## junctions and windows.
func set_act(start_x: float, end_x: float, level: Node) -> void:
	_bar.start_x = start_x
	_bar.end_x = end_x
	_bar.gates.clear()
	for i in level.segment_count():
		_bar.gates.append(level.gate_x(i))
	_bar.junctions.clear()
	for j in level.junctions:
		if not _bar.junctions.has((j["x0"] + j["x1"]) / 2.0):
			_bar.junctions.append((j["x0"] + j["x1"]) / 2.0)
	_bar.windows.clear()
	for w in level.windows:
		_bar.windows.append(Vector2(w["x0"], w["x1"]))
	_bar.slices.clear()
	for sl in level.slices:
		_bar.slices.append(Vector3(sl["from"], sl["to"], 1.0 if sl["up"] else -1.0))


## `players`: ours. `squads`: the others, [{"x", "color", "alive"}].
## `progress` (world position -> place along the lane) if not x.
func update_bar(tide_x: float, players: Array[Node], squads: Array, progress := Callable()) -> void:
	_bar.tide_x = tide_x
	_bar.dots.clear()
	for s in squads:
		_bar.dots.append({"x": s["x"], "color": s["color"], "dead": not s["alive"], "squad": true})
	for p: Node2D in players:
		var x: float = progress.call(p.global_position) if progress.is_valid() else p.global_position.x
		_bar.dots.append({"x": x, "color": p.color, "dead": p.is_dead()})
	_bar.queue_redraw()


## A big title (and a line under it) mid-screen that fades after a moment.
func show_banner(title: String, subtitle: String, color := Color(1, 0.85, 0.3)) -> void:
	hide_banner()
	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.add_child(_label(title, color, 180, 28))
	if subtitle != "":
		_banner.add_child(_label(subtitle, Color.WHITE, 72, 14))
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.8)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
	_banner_tween.tween_callback(hide_banner)


func hide_banner() -> void:
	if _banner_tween:
		_banner_tween.kill()
		_banner_tween = null
	if _banner:
		_banner.queue_free()
		_banner = null


func _label(text: String, color: Color, font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
