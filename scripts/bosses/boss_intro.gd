extends CanvasLayer
## The boss's entrance, played before a boss wave starts (game.gd waits for
## `finished`): the world freezes, the camera swings over to where the boss
## will stand, a slash of its colour cuts across the screen and its name
## slams down with its epithet underneath. Then the camera hands back to the
## players. Any confirm press skips the rest once it's had a moment.
##
## The game is paused throughout: this, its preview of the boss and the
## camera keep running anyway (PROCESS_MODE_ALWAYS).

signal finished


const PAN_TIME := 0.7
const SLAM_AT := 0.55
const HOLD := 2.7
const OUT_TIME := 0.45
## The camera's zoom on the boss.
const ZOOM := 0.8
const NAME_SIZE := 190
const EPITHET_SIZE := 68
const TAG_SIZE := 54
## Skipping is allowed this long in.
const SKIP_AFTER := 0.8
## The colour band starts off-screen and comes in this long after the start,
## sweeps most of the way in (most of it within BAND_SNAP * 3 seconds), then
## keeps creeping along at BAND_CRAWL pixels a second until the intro is gone.
const BAND_AT := 0.25
const BAND_SNAP := 0.08
const BAND_CRAWL := 45.0
## Where the creep starts, back along the band from where it's centred.
const BAND_CRAWL_FROM := 70.0

var _camera: Camera2D
var _camera_mode := Node.PROCESS_MODE_INHERIT
var _preview: Node2D
var _root: Control
var _band: Control
## How far the band travels from off-screen to the start of its creep.
var _band_travel := 0.0
var _age := 0.0
var _done := false


## Plays boss `boss_id`'s intro, with its preview at `at` (world position)
## in `world`. `subtitle` goes above its name ("WAVE 5").
func play(world: Node2D, camera: Camera2D, boss_id: String, at: Vector2, subtitle: String) -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var info := Boss.boss_info(boss_id)
	var color: Color = info.get("color", Color.WHITE)

	_preview = Preview.new()
	_preview.boss_id = boss_id
	_preview.process_mode = Node.PROCESS_MODE_ALWAYS
	_preview.z_index = 50
	_preview.position = at
	world.add_child(_preview)

	_camera = camera
	_camera_mode = camera.process_mode
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	var pan := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	pan.tween_property(camera, "global_position", at, PAN_TIME)
	# The game camera may be zoomed in to draw the pixel art at full size.
	var render_scale: float = world.get("render_scale") if world.get("render_scale") != null else 1.0
	pan.tween_property(camera, "zoom", Vector2(ZOOM, ZOOM) * render_scale, PAN_TIME)

	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var view := _root.get_viewport_rect().size

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	var band := Band.new()
	band.color = color
	band.size = view
	# The band is drawn twice the screen's width (half a screen hangs off each
	# side), so it's fully off-screen a screen and a half to the left.
	_band = band
	_band_travel = view.x * 1.5 + Band.HEIGHT
	_place_band()
	_root.add_child(band)

	var tag := _label(subtitle.to_upper() + "  -  BOSS", Color(1, 1, 1, 0.9), TAG_SIZE, 10)
	var title := _label(String(info.get("name", "")).to_upper(), Color.WHITE, NAME_SIZE, 30)
	title.add_theme_color_override("font_shadow_color", color.darkened(0.5))
	title.add_theme_constant_override("shadow_offset_x", 12)
	title.add_theme_constant_override("shadow_offset_y", 12)
	var epithet := _label(String(info.get("epithet", "")), color.lightened(0.35), EPITHET_SIZE, 14)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.add_child(tag)
	box.add_child(title)
	box.add_child(epithet)
	_root.add_child(box)
	box.size = Vector2(view.x, 0)
	box.position = Vector2(0, view.y * Band.CENTRE - box.get_combined_minimum_size().y / 2.0)
	box.pivot_offset = Vector2(view.x / 2.0, box.get_combined_minimum_size().y / 2.0)
	box.rotation = deg_to_rad(Band.TILT)
	box.modulate.a = 0.0
	tag.modulate.a = 0.0
	epithet.modulate.a = 0.0

	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(flash)

	var intro := create_tween()
	intro.tween_property(shade, "color:a", 0.45, PAN_TIME * 0.6)
	# The name slams down from big to its size.
	intro.tween_callback(func() -> void:
		box.modulate.a = 1.0
		box.scale = Vector2(2.6, 2.6))
	intro.tween_property(box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.parallel().tween_property(flash, "color:a", 0.0, 0.35).from(0.7)
	intro.tween_property(tag, "modulate:a", 1.0, 0.2)
	intro.tween_property(epithet, "modulate:a", 1.0, 0.35)
	intro.tween_interval(HOLD - 0.8)
	intro.tween_callback(_finish)


func _label(text: String, color: Color, font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _process(delta: float) -> void:
	_age += delta
	_place_band()


## One smooth motion: a fast slide that decays into a slow, steady creep (no
## stop between them), along the band's own tilt.
func _place_band() -> void:
	if not is_instance_valid(_band):
		return
	var t := maxf(_age - BAND_AT, 0.0)
	var along := -_band_travel * exp(-t / BAND_SNAP) - BAND_CRAWL_FROM + BAND_CRAWL * t
	_band.position = Vector2.from_angle(deg_to_rad(Band.TILT)) * along


func _input(event: InputEvent) -> void:
	if _done or _age < SKIP_AFTER:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") \
			or (event is InputEventJoypadButton and event.pressed):
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var out := create_tween()
	out.tween_property(_root, "modulate:a", 0.0, OUT_TIME)
	out.tween_callback(func() -> void:
		_camera.process_mode = _camera_mode
		if is_instance_valid(_preview):
			_preview.queue_free()
		finished.emit()
		queue_free())


## The boss itself, drawn where it'll appear (it isn't in the world yet).
class Preview extends Node2D:
	var boss_id := ""
	var age := 0.0

	func _process(delta: float) -> void:
		age += delta
		queue_redraw()

	func _draw() -> void:
		Boss.paint_preview_of(boss_id, self, age)


## A slash of the boss's colour across the screen, behind its name.
class Band extends Control:
	## Middle of the band, as a fraction of the screen height, and its tilt.
	const CENTRE := 0.62
	const TILT := -4.0
	const HEIGHT := 420.0
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var mid := Vector2(size.x / 2.0, size.y * CENTRE)
		var along := Vector2.from_angle(deg_to_rad(TILT)) * size.x
		var across := Vector2.from_angle(deg_to_rad(TILT) + PI / 2.0) * HEIGHT / 2.0
		var pts := PackedVector2Array([mid - along - across, mid + along - across * 1.2,
			mid + along + across * 0.8, mid - along + across])
		draw_colored_polygon(pts, Color(color.darkened(0.35), 0.92))
		# Rough streaks along its edges.
		for i in 7:
			var t := float(i) / 6.0
			var off := across * (1.05 + 0.12 * (i % 3))
			var a := mid - along * (1.0 - 2.0 * t) - off
			draw_line(a, a + along * 0.25, Color(color, 0.8), 10.0 + 6.0 * (i % 2))
			var b := mid + along * (1.0 - 2.0 * t) + off
			draw_line(b, b - along * 0.2, Color(color, 0.8), 8.0 + 6.0 * (i % 2))
