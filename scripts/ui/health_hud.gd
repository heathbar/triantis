extends CanvasLayer
## Compact player stats in the screen corners: P1 top-left, P2 top-right,
## P3 bottom-left, P4 bottom-right. Each panel is one row:
## player tag, lives (hearts), points, resources, and (if they have
## equipment) a wrench whose pie chart shows the time until it's ready.
## The half heart a Healing Bubble is bringing back flashes.
## Also shows the current wave and its time remaining at the top centre, and
## in objective mode the wave's objective and how it's going underneath, or
## on a boss wave the boss's health (scripts/ui/boss_bar.gd).


	
const MARGIN := 40.0
const FONT_SIZE := 48
const HEART_SIZE := 44.0
const Hearts := preload("res://scripts/ui/hearts.gd")
const ResourceIcon := preload("res://scripts/ui/resource_icon.gd")
## The wave timer turns this colour for the last few seconds.
const TIMER_WARN_COLOR := Color(1.0, 0.75, 0.2)
const TIMER_WARN_SECONDS := 5.0
const EquipmentIcon := preload("res://scripts/ui/equipment_icon.gd")
const BossBar := preload("res://scripts/ui/boss_bar.gd")

# Debug Menu
var debug_menu: PanelContainer
var fps_label: Label
var debug_visible := false
var player_speed_labels: Dictionary = {}

func _build_debug_menu() -> void:
	debug_menu = PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	style.set_border_width_all(2)
	style.border_color = Color(0.2, 0.8, 1.0)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 15
	style.content_margin_bottom = 15

	debug_menu.add_theme_stylebox_override("panel", style)

	add_child(debug_menu)

	# Position in top-left corner
	debug_menu.position = Vector2(40, 140)

	# Create vertical layout
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	debug_menu.add_child(container)

	# Title
	var title := Label.new()
	title.text = "DEBUG MENU"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	container.add_child(title)

	# FPS counter
	fps_label = Label.new()
	fps_label.add_theme_font_size_override("font_size", 20)
	fps_label.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(fps_label)

	debug_menu.hide()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_menu"):
		debug_visible = not debug_visible
		debug_menu.visible = debug_visible


func _process(_delta: float) -> void:
	if debug_visible:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

		for player in player_speed_labels:
			if is_instance_valid(player):
				var speed: float = player.velocity.length()
				player_speed_labels[player].text = "P%d Speed: %.1f" % [
					player.player_index + 1,
					speed
				]
		

func add_player(player: Node) -> void:
	var slot: int = player.player_index
	var color: Color = player.color

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_border_width_all(4)
	style.border_color = color
	style.set_corner_radius_all(16)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 12

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	panel.add_child(row)

	row.add_child(_label("P%d" % (slot + 1), color))

	var hearts := Hearts.new()
	hearts.heart_size = HEART_SIZE
	hearts.max_health = player.max_health
	hearts.health = player.health
	row.add_child(hearts)

	var points_label := _label("", Color.WHITE)
	row.add_child(points_label)

	var resource_box := HBoxContainer.new()
	resource_box.add_theme_constant_override("separation", 10)
	resource_box.add_child(ResourceIcon.new())
	var resources_label := _label("", ResourceIcon.COLOR)
	resource_box.add_child(resources_label)
	row.add_child(resource_box)

	var equipment_icon := EquipmentIcon.new(HEART_SIZE + 8.0)
	equipment_icon.player = player
	equipment_icon.visible = player.has_equipment()
	row.add_child(equipment_icon)

	_place_in_corner(panel, slot)

	player.health_changed.connect(func(health: int) -> void:
		hearts.max_health = player.max_health
		hearts.health = health)
	player.healing_changed.connect(func(healing: bool) -> void: hearts.healing = healing)

	var update_points := func(points: int) -> void:
		points_label.text = "%d pts" % points
	update_points.call(player.points)
	player.points_changed.connect(update_points)

	var update_resources := func(count: int) -> void:
		resources_label.text = str(count)
	update_resources.call(player.resources)
	player.resources_changed.connect(update_resources)

	player.died.connect(func(_at: Vector2) -> void: panel.modulate = Color(1, 1, 1, 0.45))
	player.revived.connect(func() -> void: panel.modulate = Color.WHITE)
	
	# Add player to debug menu for capturing their speed
	var speed_label := Label.new()
	speed_label.text = "P%d Speed: 0" % (slot + 1)
	speed_label.add_theme_font_size_override("font_size", 20)
	speed_label.add_theme_color_override("font_color", color)

	debug_menu.get_child(0).add_child(speed_label)

	player_speed_labels[player] = speed_label


var _wave_label: Label
var _timer_label: Label
## What the timer shows now (whole seconds, warning colour or not), so it's
## only updated when that changes, not every frame.
var _timer_secs := -1
var _timer_warn := false
var _banner: VBoxContainer
var _banner_tween: Tween
var _notice: Label
var _objective_name: Label
var _objective_status: Label
var _boss_bar: BossBar


func _ready() -> void:
	_build_wave_panel()
	_build_debug_menu()
	
	
## Top-centre "WAVE 2 / 5" with the time remaining underneath.
func _build_wave_panel() -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_top = MARGIN
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_wave_label = _outlined_label("", Color.WHITE, 56, 12)
	box.add_child(_wave_label)
	_timer_label = _outlined_label("", Color.WHITE, 88, 16)
	box.add_child(_timer_label)
	_objective_name = _outlined_label("", Color.WHITE, 52, 12)
	_objective_name.hide()
	box.add_child(_objective_name)
	_objective_status = _outlined_label("", Color.WHITE, 44, 10)
	_objective_status.hide()
	box.add_child(_objective_status)
	_boss_bar = BossBar.new()
	_boss_bar.hide()
	box.add_child(_boss_bar)
	_notice = _outlined_label("", Color(1, 0.85, 0.3), 64, 14)
	_notice.hide()
	box.add_child(_notice)


## A message under the wave timer that stays up until hide_notice().
func show_notice(text: String) -> void:
	_notice.text = text
	_notice.show()


func hide_notice() -> void:
	_notice.hide()


## Objective mode: the wave's objective, under the timer.
func show_objective(objective_name: String, color: Color) -> void:
	_objective_name.text = objective_name.to_upper()
	_objective_name.add_theme_color_override("font_color", color)
	_objective_name.show()
	_objective_status.text = ""
	_objective_status.show()


func hide_objective() -> void:
	_objective_name.hide()
	_objective_status.hide()


func set_objective_status(text: String) -> void:
	if _objective_status.text != text:
		_objective_status.text = text


## Boss wave: the boss's health bar (`boss`: scripts/bosses/boss.gd), under the timer.
func show_boss(boss: Node) -> void:
	_boss_bar.boss = boss
	_boss_bar.show()


func hide_boss() -> void:
	_boss_bar.boss = null
	_boss_bar.hide()


## Updates the wave counter and flashes a big "WAVE N" banner mid-screen.
func show_wave_start(index: int, total: int, wave_name: String) -> void:
	_wave_label.text = "WAVE %d / %d" % [index + 1, total]

	hide_wave_banner()
	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := "FINAL WAVE" if index == total - 1 else "WAVE %d" % (index + 1)
	_banner.add_child(_outlined_label(title, Color(1, 0.85, 0.3), 200, 28))
	if wave_name != "":
		_banner.add_child(_outlined_label(wave_name, Color.WHITE, 80, 16))

	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.4)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
	_banner_tween.tween_callback(hide_wave_banner)


func hide_wave_banner() -> void:
	if _banner_tween:
		_banner_tween.kill()
	if _banner:
		_banner.queue_free()
		_banner = null


## The line above the timer ("WAVE 2 / 5"), for modes that count something
## else (Braid mode's segments).
func set_wave_label(text: String) -> void:
	_wave_label.text = text


## `can_warn`: false for a clock counting up, which never turns the warning colour.
func set_wave_time(seconds_left: float, can_warn := true) -> void:
	var secs := ceili(seconds_left) if can_warn else floori(seconds_left)
	var warn := can_warn and seconds_left <= TIMER_WARN_SECONDS and seconds_left > 0.0
	if secs != _timer_secs:
		_timer_secs = secs
		_timer_label.text = "%d:%02d" % [floori(secs / 60.0), secs % 60]
	if warn != _timer_warn:  # (It starts out white, not warning.)
		_timer_warn = warn
		_timer_label.add_theme_color_override("font_color", TIMER_WARN_COLOR if warn else Color.WHITE)


func _outlined_label(text: String, color: Color, font_size: int, outline: int) -> Label:
	var label := _label(text, color)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _place_in_corner(panel: Control, slot: int) -> void:
	var right := slot % 2 == 1
	var bottom := slot >= 2
	var ax := 1.0 if right else 0.0
	var ay := 1.0 if bottom else 0.0
	var ox := -MARGIN if right else MARGIN
	var oy := -MARGIN if bottom else MARGIN
	panel.anchor_left = ax
	panel.anchor_right = ax
	panel.anchor_top = ay
	panel.anchor_bottom = ay
	panel.offset_left = ox
	panel.offset_right = ox
	panel.offset_top = oy
	panel.offset_bottom = oy
	# Grow away from the corner so the panel stays on screen.
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label
