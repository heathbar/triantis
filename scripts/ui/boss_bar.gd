extends Control
## The boss's health at the top middle of the HUD (scripts/ui/health_hud.gd),
## under the wave timer: its name, then one bar, or a row of bars for a boss
## in several pieces (the Fruit Bowl once it bursts), and a line of news under
## them (enraged, venting, the Fruit Bowl's fruit left). Everything comes from
## the boss (scripts/bosses/boss.gd: bar_segments, bar_note) every frame.

const WIDTH := 1300.0
const BAR_HEIGHT := 46.0
const GAP := 24.0
const TITLE_SIZE := 52
const LABEL_SIZE := 34
const NOTE_SIZE := 42
const BACK := Color(0.12, 0.05, 0.05, 0.85)

## The boss fight being shown (scripts/bosses/boss.gd).
var boss: Node


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, TITLE_SIZE + BAR_HEIGHT + NOTE_SIZE + 40.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(boss):
		return
	var font := get_theme_default_font()
	var left := (size.x - WIDTH) / 2.0
	var color: Color = boss.info.get("color", Color.WHITE)
	_text(font, Vector2(left, TITLE_SIZE * 0.85), WIDTH, String(boss.info.get("name", "")).to_upper(),
		TITLE_SIZE, color)

	var top := TITLE_SIZE + 10.0
	var segments: Array = boss.bar_segments()
	var count := maxi(segments.size(), 1)
	var width := (WIDTH - GAP * (count - 1)) / count
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var rect := Rect2(left + i * (width + GAP), top, width, BAR_HEIGHT)
		draw_rect(rect.grow(5.0), Color.BLACK)
		draw_rect(rect, BACK)
		var fill: Color = seg["color"]
		if seg.get("dim", false):
			fill = fill.darkened(0.65)
		var frac := clampf(float(seg["frac"]), 0.0, 1.0)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y)), fill)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y * 0.3)),
			Color(1, 1, 1, 0.25))
		if count > 1:
			# A part that's out (a smashed fruit): its name greyed, its bar empty.
			var label_color := Color(0.55, 0.55, 0.55) if seg.get("dim", false) else Color.WHITE
			_text(font, Vector2(rect.position.x, rect.position.y + BAR_HEIGHT * 0.78), rect.size.x,
				seg["label"], LABEL_SIZE, label_color)

	var note: String = boss.bar_note()
	if not note.is_empty():
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 120.0)
		_text(font, Vector2(left, top + BAR_HEIGHT + 12.0 + NOTE_SIZE * 0.85), WIDTH, note, NOTE_SIZE,
			Color(1.0, 0.45, 0.35, pulse))


func _text(font: Font, at: Vector2, width: float, text: String, font_size: int, color: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 12, Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)
