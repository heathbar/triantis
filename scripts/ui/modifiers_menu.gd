extends Control
## The Campaign modifiers page (scripts/braid/braid_modifiers.gd), shown over
## character select once everyone's ready for a Campaign run, when
## BraidModifiers.page_unlocked() (the Campaign has been won here). In a
## Squads game only the host sees it; their picks go to every squad.
##
## A grid of toggle tiles, one per modifier, each with its icon. The
## highlighted tile's description and score bonus show underneath, with the
## run's total score multiplier. None are on by default; picks are kept for
## the session (Global.campaign_modifiers).
##
## Controls (any player's controller, or the keyboard):
##   D-pad / stick / arrows - move (down from the bottom row: BEGIN)
##   A / Enter / Space      - toggle the highlighted modifier (on BEGIN: begin)
##   Start                  - begin
##   B / Escape             - back to character select (picks are kept)
## Mouse: hover highlights, click toggles, click BEGIN / < Back.
##
## Built in code, in the title screen's wooden style (data/ui/menu_theme.tres).

const MenuInput := preload("res://scripts/ui/menu_input.gd")
const ButtonPrompts := preload("res://scripts/ui/button_prompts.gd")
const BraidModifiers := preload("res://scripts/braid/braid_modifiers.gd")
const MENU_THEME := preload("res://data/ui/menu_theme.tres")

## true = begin the run with Global.campaign_modifiers; false = back.
signal finished(confirmed: bool)

const COLUMNS := 4
const TILE_WIDTH := 360.0
const ICON_SIZE := 160.0
const GRID_GAP := 28
## Wooden boards, as on character select.
const BOARD_COLOR := Color(0.37, 0.23, 0.12, 0.97)
const OFF_BOARD_COLOR := Color(0.24, 0.15, 0.08, 0.95)
const ON_BOARD_COLOR := Color(0.55, 0.36, 0.12, 0.98)
const BORDER_IDLE := Color(0.22, 0.12, 0.05)
const BORDER_ON := Color(1.0, 0.78, 0.3)
const BORDER_CURSOR := Color.WHITE
const OUTLINE_COLOR := Color(0.2, 0.11, 0.04)
const GOLD := Color(1, 0.86, 0.5)
const SCORE_COLOR := Color(0.55, 1.0, 0.5)
const OFF_ICON := Color(0.42, 0.42, 0.42)

## Modifier ids switched on.
var selected: Array = []
## The highlighted tile (LIST index), or LIST.size() for BEGIN (where the
## page opens, so A straight away starts the run with the kept picks).
var cursor := BraidModifiers.LIST.size()
## The column to return to when moving up off BEGIN.
var _column := 0
var _menu_input := MenuInput.new()
## Per tile: {"style", "icon", "name", "score"}.
var _tiles: Array[Dictionary] = []
var _begin_style: StyleBoxFlat
var _desc_name: Label
var _desc_blurb: Label
var _desc_score: Label
var _total: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = MENU_THEME
	selected = Global.campaign_modifiers.duplicate()
	_build()
	_refresh()


func _input(event: InputEvent) -> void:
	var press := _menu_input.read(event)
	if press.is_empty():
		return
	get_viewport().set_input_as_handled()
	var n := BraidModifiers.LIST.size()
	match press["intent"]:
		"left", "right", "prev_tab", "next_tab":
			if cursor < n:
				var step := -1 if press["intent"] in ["left", "prev_tab"] else 1
				var row_start := cursor - cursor % COLUMNS
				var row_size := mini(COLUMNS, n - row_start)
				cursor = row_start + posmod(cursor - row_start + step, row_size)
		"up":
			if cursor == n:
				var last_row := (n - 1) - (n - 1) % COLUMNS
				cursor = mini(last_row + _column, n - 1)
			elif cursor >= COLUMNS:
				cursor -= COLUMNS
		"down":
			if cursor < n:
				if cursor + COLUMNS < n:
					cursor += COLUMNS
				else:
					_column = cursor % COLUMNS
					cursor = n
		"accept":
			if cursor == n:
				_finish(true)
				return
			_toggle(cursor)
		"start":
			_finish(true)
			return
		"back":
			_finish(false)
			return
		_:
			return
	_refresh()


func _toggle(i: int) -> void:
	var id: String = BraidModifiers.LIST[i]["id"]
	if id in selected:
		selected.erase(id)
	else:
		selected.append(id)


func _finish(confirmed: bool) -> void:
	# Kept either way: backing out to change a character shouldn't lose them.
	Global.campaign_modifiers = selected.duplicate()
	finished.emit(confirmed)
	queue_free()


# --- Mouse ---------------------------------------------------------------------

func _on_tile_mouse(event: InputEvent, i: int) -> void:
	if event is InputEventMouseMotion and cursor != i:
		cursor = i
		_refresh()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cursor = i
		if i == BraidModifiers.LIST.size():
			_finish(true)
			return
		_toggle(i)
		_refresh()
		accept_event()


# --- UI -------------------------------------------------------------------------

func _build() -> void:
	# Its own backdrop (character select's grass, darkened), so nothing
	# underneath shows through.
	var grass := TextureRect.new()
	grass.texture = Global.MENU_GRASS
	grass.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	grass.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	grass.stretch_mode = TextureRect.STRETCH_TILE
	grass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grass.scale = Vector2.ONE * Global.MENU_GRASS_SCALE
	add_child(grass)
	var fit := func() -> void: grass.size = size / Global.MENU_GRASS_SCALE
	resized.connect(fit)
	fit.call()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.01, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)

	var heading := _label(vbox, "Modifiers", 96)
	heading.add_theme_color_override("font_color", GOLD)
	heading.add_theme_constant_override("outline_size", 24)
	var sub := _label(vbox, "Make the Campaign harder for a higher score" if not Squads.is_active()
		else "Make the Campaign harder for a higher score (every squad plays them)", 40)
	sub.modulate = Color(1, 1, 1, 0.75)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(grid)
	for i in BraidModifiers.LIST.size():
		_tiles.append(_build_tile(grid, i))

	# The highlighted modifier's description.
	var desc := PanelContainer.new()
	desc.add_theme_stylebox_override("panel", _board_style(28))
	desc.custom_minimum_size.x = COLUMNS * TILE_WIDTH + (COLUMNS - 1) * GRID_GAP
	desc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(desc)
	var desc_box := VBoxContainer.new()
	desc_box.add_theme_constant_override("separation", 8)
	desc.add_child(desc_box)
	_desc_name = _label(desc_box, "", 60)
	_desc_name.add_theme_color_override("font_color", GOLD)
	_desc_blurb = _label(desc_box, "", 40)
	_desc_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_blurb.custom_minimum_size.y = 110  # two lines, so the page doesn't jump
	_desc_score = _label(desc_box, "", 40)
	_desc_score.add_theme_color_override("font_color", SCORE_COLOR)

	_total = _label(vbox, "", 56)

	# BEGIN: one more stop for the cursor, below the grid.
	var begin_center := CenterContainer.new()
	vbox.add_child(begin_center)
	var begin := PanelContainer.new()
	_begin_style = _board_style(16)
	begin.add_theme_stylebox_override("panel", _begin_style)
	begin.custom_minimum_size = Vector2(560, 0)
	begin.mouse_filter = Control.MOUSE_FILTER_STOP
	begin.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	begin.gui_input.connect(_on_tile_mouse.bind(BraidModifiers.LIST.size()))
	begin_center.add_child(begin)
	var begin_label := _label(begin, "BEGIN", 64)
	begin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hint := ButtonPrompts.label("{A} toggle     Start: begin     {B} back", Color(1, 0.94, 0.8), 44, 10)
	hint.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	vbox.add_child(hint)

	var back := Button.new()
	back.text = "< Back"
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 48)
	back.custom_minimum_size = Vector2(300, 100)
	back.position = Vector2(40, 40)
	back.pressed.connect(_finish.bind(false))
	add_child(back)


func _build_tile(parent: Node, i: int) -> Dictionary:
	var m: Dictionary = BraidModifiers.LIST[i]
	var style := _board_style(20)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(TILE_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(_on_tile_mouse.bind(i))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon_center)
	var icon := TextureRect.new()
	icon.texture = BraidModifiers.icon(m["id"])
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel art
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(icon)
	var name_label := _label(box, m["name"], 44)
	var score := _label(box, _score_text(m), 32)
	for label: Label in [name_label, score]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return {"style": style, "icon": icon, "name": name_label, "score": score}


func _refresh() -> void:
	var n := BraidModifiers.LIST.size()
	for i in n:
		var m: Dictionary = BraidModifiers.LIST[i]
		var t := _tiles[i]
		var on: bool = m["id"] in selected
		var style: StyleBoxFlat = t["style"]
		style.bg_color = ON_BOARD_COLOR if on else OFF_BOARD_COLOR
		style.border_color = BORDER_CURSOR if i == cursor else (BORDER_ON if on else BORDER_IDLE)
		style.set_border_width_all(10 if i == cursor else 6)
		t["icon"].modulate = Color.WHITE if on else OFF_ICON
		t["name"].add_theme_color_override("font_color", GOLD if on else Color(0.75, 0.7, 0.62))
		t["score"].modulate = Color(SCORE_COLOR, 1.0) if on else Color(1, 1, 1, 0.45)
		t["score"].text = ("ON   " if on else "") + _score_text(m)
	_begin_style.border_color = BORDER_CURSOR if cursor == n else BORDER_IDLE
	_begin_style.set_border_width_all(10 if cursor == n else 6)
	_begin_style.bg_color = BOARD_COLOR.lerp(Color(0.3, 0.55, 0.2), 0.5) if cursor == n else BOARD_COLOR

	if cursor < n:
		var m: Dictionary = BraidModifiers.LIST[cursor]
		var on: bool = m["id"] in selected
		_desc_name.text = "%s%s" % [m["name"], "  (on)" if on else ""]
		_desc_blurb.text = m["blurb"]
		_desc_score.text = "Score " + _score_text(m)
	else:
		_desc_name.text = "Begin"
		_desc_blurb.text = "Start the run with these modifiers: %s." % BraidModifiers.names(selected) \
			if not selected.is_empty() else "Start the run with no modifiers."
		_desc_score.text = " "
	var mult := BraidModifiers.score_multiplier(selected)
	_total.text = "Score multiplier  %s     (%d of %d on)" % [
		BraidModifiers.multiplier_text(mult), selected.size(), n]
	_total.add_theme_color_override("font_color", GOLD if mult > 1.0 else Color(1, 1, 1, 0.8))


static func _score_text(m: Dictionary) -> String:
	return "+%d%%" % roundi(float(m["score"]) * 100.0)


## A wooden board for a tile or panel (its own copy, so its colours can change).
func _board_style(margin: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = get_theme_stylebox("panel", "PanelContainer").duplicate()
	style.bg_color = BOARD_COLOR
	style.border_color = BORDER_IDLE
	style.set_content_margin_all(margin)
	return style


func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	# The theme's outline is sized for big menu text.
	if size < 48:
		label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label
