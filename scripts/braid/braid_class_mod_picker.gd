extends CanvasLayer
## After a Braid boss fight: every player picks one Class Mod from
## their cards (scripts/braid/braid_class_mod.gd), each with their own
## controller (or the keyboard, or a click), side by side like the shop.
## Emits `all_ready` once everyone is ready, then removes itself.
##
## A / Enter (or a click) selects a card; the player can change it freely.
## READY UP under the cards (or Start) locks it in once a card is selected,
## and B / Escape un-readies. Picks are applied only when everyone is ready.
##
## A player whose class has no trees, or no Class Mods left to pick, has nothing
## to pick and counts as ready. So does one whose controller is unplugged
## (they get their first card).
##
## X (keyboard X) inspects the highlighted card: that player's column swaps to
## all three stages of the mod, stage 1 -> 2 -> 3, until B / Escape (or X
## again) goes back to the cards. Right-clicking a card inspects it too.

signal all_ready

const BraidClassMod := preload("res://scripts/braid/braid_class_mod.gd")
const MenuInput := preload("res://scripts/ui/menu_input.gd")
const ButtonPrompts := preload("res://scripts/ui/button_prompts.gd")

## Every player's column is exactly this wide (all text wraps inside it), and
## every card is as tall as the tallest card on the screen, so all players'
## boxes are the same size whatever their mods say.
const COLUMN_WIDTH := 620.0
## A card's text width: COLUMN_WIDTH minus the 20 px side margins.
const INNER_WIDTH := COLUMN_WIDTH - 40.0
const CARD_MIN_HEIGHT := 300.0
# Colours match the shop (scripts/ui/shop.gd): each player's column is a
# panel framed in their colour (the class colour they picked), faint until
# they're ready, solid once they are.
const COLUMN_BG := Color(0.08, 0.08, 0.08, 0.95)
const COLUMN_BORDER_IDLE := Color(0.35, 0.4, 0.35)
# Grey, so the only colour on a card is the player's own.
const CARD_BG := Color(0.13, 0.13, 0.13)
## How far a highlighted or selected card's background leans to the player's colour.
const CARD_TINT := 0.3
const MUTED := Color(0.55, 0.55, 0.55)
const STAGE_NAMES := ["STAGE 1", "STAGE 2", "STAGE 3"]

## [{"player", "cards", "cursor" (cards.size() = the READY UP button),
##   "selected" (-1 = none yet), "ready", "panels", "badges", "ready_button", "frame",
##   "status", "cards_box", "inspect_box", "inspecting"}]
var _seats: Array[Dictionary] = []
var _menu_input := MenuInput.new()
var _done := false


func _init() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS


## Builds the screen for `players`; `rng_seed` makes the cards repeatable.
func open(players: Array[Node], rng_seed: int, title := "CLASS MODS") -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	vbox.add_child(_label(title, Color(0.6, 1.0, 0.7), 140, 22))
	vbox.add_child(_label("Pick one Class Mod each: it changes how that weapon works for the rest of the run.",
		Color(0.85, 0.85, 0.85), 48, 8))
	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 40)
	vbox.add_child(columns)
	# Controller icons only (ButtonPrompts): no keyboard text.
	vbox.add_child(ButtonPrompts.label("{UP}{DOWN} choose      {A} select      {X} inspect      {B} back",
		MUTED, 40, 6))

	var ordered := players.duplicate()
	ordered.sort_custom(func(a: Node, b: Node) -> bool: return a.player_index < b.player_index)
	for player in ordered:
		var rng := RandomNumberGenerator.new()
		rng.seed = rng_seed * 31 + player.player_index
		var seat := {"player": player, "cards": BraidClassMod.offer(player, rng), "cursor": 0,
			"selected": -1, "ready": false, "panels": [], "badges": [], "ready_button": null, "frame": null, "status": null,
			"cards_box": null, "inspect_box": null, "inspecting": false}
		_build_column(seat, columns)
		_seats.append(seat)
	for seat in _seats:
		if seat["cards"].is_empty():
			seat["ready"] = true  # nothing to pick
	_equalize_cards(center)
	_pick_for_unplugged()
	_refresh()
	_check_done.call_deferred()


## Makes every card on the screen as tall as the tallest one. Wrapped text
## only knows its height after a layout pass, so this waits a frame, with
## `content` invisible meanwhile so the uneven first layout never shows.
func _equalize_cards(content: Control) -> void:
	content.modulate.a = 0.0
	await (Engine.get_main_loop() as SceneTree).process_frame
	if not is_inside_tree():
		return
	var tallest := CARD_MIN_HEIGHT
	for seat in _seats:
		for panel: Control in seat["panels"]:
			panel.custom_minimum_size.y = 0.0
			tallest = maxf(tallest, panel.get_combined_minimum_size().y)
	for seat in _seats:
		for panel: Control in seat["panels"]:
			panel.custom_minimum_size.y = tallest
	_fit_to_screen(content)
	content.modulate.a = 1.0


## Shrinks the whole screen evenly (never grows it) when the cards don't fit,
## e.g. four players with long mod texts, so nothing runs off the edges.
func _fit_to_screen(content: Control) -> void:
	var box := content.get_child(0) as Control
	var needed := box.get_combined_minimum_size()
	var room := content.get_viewport_rect().size * 0.96
	var fit := minf(1.0, minf(room.x / maxf(needed.x, 1.0), room.y / maxf(needed.y, 1.0)))
	# `content` grows past the screen to hold everything, so scale from its
	# corner and re-centre the scaled result by hand.
	content.scale = Vector2(fit, fit)
	# (Its size hasn't caught up with the new card heights yet, so work it out.)
	var screen := content.get_viewport_rect().size
	var full := Vector2(maxf(screen.x, needed.x), maxf(screen.y, needed.y))
	content.position = (screen - full * fit) / 2.0


func _build_column(seat: Dictionary, parent: Control) -> void:
	var player: Node = seat["player"]
	var frame := StyleBoxFlat.new()
	frame.bg_color = COLUMN_BG
	frame.set_border_width_all(8)
	frame.border_color = COLUMN_BORDER_IDLE.lerp(player.color, 0.4)
	frame.set_corner_radius_all(24)
	frame.set_content_margin_all(32)
	seat["frame"] = frame
	var framed := PanelContainer.new()
	framed.add_theme_stylebox_override("panel", frame)
	parent.add_child(framed)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	col.add_theme_constant_override("separation", 18)
	framed.add_child(col)
	var class_name_text: String = player.class_id.capitalize()
	col.add_child(_label("%s  %s" % [player.display_name(), class_name_text], player.color, 64, 10, true, COLUMN_WIDTH))
	if seat["cards"].is_empty():
		var why := "No Class Mods left to pick." if BraidClassMod.has_trees(player.class_id) \
			else "No Class Mods for the %s yet." % class_name_text
		col.add_child(_label(why, MUTED, 44, 6, true, COLUMN_WIDTH))
		return
	var cards_box := VBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 18)
	col.add_child(cards_box)
	seat["cards_box"] = cards_box
	var inspect_box := VBoxContainer.new()
	inspect_box.add_theme_constant_override("separation", 4)
	inspect_box.visible = false
	col.add_child(inspect_box)
	seat["inspect_box"] = inspect_box
	for i in seat["cards"].size():
		var card: Dictionary = seat["cards"][i]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(COLUMN_WIDTH, CARD_MIN_HEIGHT)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 6)
		panel.add_child(inner)
		var gun: bool = card["slot"] == "gun"
		var weapon: Dictionary = player.gun if gun else player.melee
		var kind := "%s: %s" % ["GUN" if gun else "MELEE", str(weapon.get("name", "")).to_upper()]
		inner.add_child(_label(kind, BraidClassMod.GUN_COLOR if gun else BraidClassMod.MELEE_COLOR, 36, 6, false, INNER_WIDTH))
		inner.add_child(_label(BraidClassMod.card_title(card), Color.WHITE, 60, 10, false, INNER_WIDTH))
		var text := _label(BraidClassMod.card_text(card), Color(0.88, 0.88, 0.9), 38, 0, false, INNER_WIDTH)
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL  # pushes the badge to the bottom
		inner.add_child(text)
		# Always laid out (hidden by alpha), so selecting doesn't change the card's height.
		var badge := _label("SELECTED", player.color, 36, 6, false, INNER_WIDTH)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		inner.add_child(badge)
		seat["badges"].append(badge)
		panel.gui_input.connect(_on_card_mouse.bind(seat, i))
		cards_box.add_child(panel)
		seat["panels"].append(panel)
	var ready_button := PanelContainer.new()
	ready_button.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	ready_button.add_child(_label("READY UP", Color.WHITE, 56, 10, true, INNER_WIDTH))
	ready_button.gui_input.connect(_on_ready_mouse.bind(seat))
	cards_box.add_child(ready_button)
	seat["ready_button"] = ready_button
	# Shown only while inspecting (nothing under READY UP).
	var status := ButtonPrompts.label("{B} back to the cards", MUTED, 40, 6)
	status.visible = false
	col.add_child(status)
	seat["status"] = status


func _input(event: InputEvent) -> void:
	if _done:
		return
	var press := _menu_input.read(event)
	if press.is_empty():
		return
	for seat in _seats:
		if seat["player"].device == press["device"]:
			get_viewport().set_input_as_handled()
			_handle(seat, press["intent"])
			return


func _handle(seat: Dictionary, intent: String) -> void:
	if seat["cards"].is_empty():
		return  # Nothing to pick.
	if seat["ready"]:
		if intent == "back":
			seat["ready"] = false
			_refresh()
		return
	if seat["inspecting"]:
		if intent in ["back", "bank"]:
			_set_inspecting(seat, false)
		return
	var n: int = seat["cards"].size() + 1  # the cards, then READY UP
	match intent:
		"up", "left":
			seat["cursor"] = posmod(seat["cursor"] - 1, n)
		"down", "right":
			seat["cursor"] = posmod(seat["cursor"] + 1, n)
		"accept":
			if _on_ready_button(seat):
				_ready_up(seat)
			else:
				_select(seat, seat["cursor"])
		"start":
			_ready_up(seat)
		"bank":
			if not _on_ready_button(seat):
				_set_inspecting(seat, true)
	_refresh()


func _on_ready_button(seat: Dictionary) -> bool:
	return seat["cursor"] >= seat["cards"].size()


## Selects card `i` (replacing any earlier choice) and moves the cursor
## to READY UP.
func _select(seat: Dictionary, i: int) -> void:
	seat["selected"] = i
	seat["cursor"] = seat["cards"].size()


## Locks in the selected card, if there is one.
func _ready_up(seat: Dictionary) -> void:
	if seat["selected"] < 0:
		return
	seat["ready"] = true
	# Deferred: ready-ups made while opening (unplugged controllers) mustn't
	# finish the screen before anyone's waiting for all_ready.
	_check_done.call_deferred()


## Swaps `seat`'s column between its cards and all stages of the highlighted card's mod.
func _set_inspecting(seat: Dictionary, on: bool) -> void:
	seat["inspecting"] = on
	seat["cards_box"].visible = not on
	seat["inspect_box"].visible = on
	if on:
		_build_inspect(seat)
	_refresh()


## Fills the inspect view: the mod's three stages, top to bottom, joined by
## arrows. The stage this card offers is outlined; earlier ones are owned.
func _build_inspect(seat: Dictionary) -> void:
	var box: VBoxContainer = seat["inspect_box"]
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var card: Dictionary = seat["cards"][seat["cursor"]]
	var branch: Dictionary = card["branch"]
	var offered := int(card["level"])
	var gun: bool = card["slot"] == "gun"
	var accent: Color = BraidClassMod.GUN_COLOR if gun else BraidClassMod.MELEE_COLOR
	box.add_child(_label("%s  %s" % ["GUN" if gun else "MELEE", str(branch["name"]).to_upper()], accent, 44, 8, true, COLUMN_WIDTH))
	var stages: Array = branch["stages"]
	for i in stages.size():
		if i > 0:
			box.add_child(_label("▼", accent, 52, 6))
		var level := i + 1
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
		var style := StyleBoxFlat.new()
		style.bg_color = CARD_BG.lerp(seat["player"].color, CARD_TINT) if level == offered else CARD_BG
		style.set_border_width_all(6 if level == offered else 2)
		style.border_color = seat["player"].color if level == offered else CARD_BG
		style.set_corner_radius_all(14)
		style.content_margin_left = 20
		style.content_margin_right = 20
		style.content_margin_top = 10
		style.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", style)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 4)
		panel.add_child(inner)
		var tag := ""
		if level < offered:
			tag = "  (owned)"
		elif level == offered:
			tag = "  (this pick)"
		var head := _label("%s: %s%s" % [STAGE_NAMES[mini(i, 2)],
			BraidClassMod.card_title({"branch": branch, "level": level}), tag],
			Color.WHITE if level >= offered else MUTED, 44, 8, false, INNER_WIDTH)
		inner.add_child(head)
		var text := _label(str(stages[i]["text"]), Color(0.88, 0.88, 0.9) if level >= offered else MUTED, 34, 0, false,
			INNER_WIDTH)
		inner.add_child(text)
		box.add_child(panel)


func _on_card_mouse(event: InputEvent, seat: Dictionary, i: int) -> void:
	if _done or seat["ready"] or seat["inspecting"]:
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_select(seat, i)
		_refresh()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		seat["cursor"] = i
		_set_inspecting(seat, true)


## Clicking READY UP readies up, or un-readies if already ready.
func _on_ready_mouse(event: InputEvent, seat: Dictionary) -> void:
	if _done or seat["inspecting"]:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		seat["cursor"] = seat["cards"].size()
		if seat["ready"]:
			seat["ready"] = false
		else:
			_ready_up(seat)
		_refresh()


## A player whose controller is unplugged can't pick: they get their first card.
func _pick_for_unplugged() -> void:
	var connected := Input.get_connected_joypads()
	for seat in _seats:
		var device: int = seat["player"].device
		if not seat["ready"] and device != Global.KEYBOARD and device not in connected:
			_select(seat, 0)
			_ready_up(seat)


func _refresh() -> void:
	for seat in _seats:
		var panels: Array = seat["panels"]
		var color: Color = seat["player"].color
		var ready: bool = seat["ready"]
		seat["frame"].border_color = color if ready else COLUMN_BORDER_IDLE.lerp(color, 0.4)
		for i in panels.size():
			var chosen: bool = seat["selected"] == i
			var hovered: bool = not ready and seat["cursor"] == i
			var style := _box(CARD_BG.lerp(color, CARD_TINT) if (chosen or hovered) else CARD_BG,
				color if hovered else (color.darkened(0.35) if chosen else CARD_BG),
				6 if hovered else (4 if chosen else 2))
			panels[i].add_theme_stylebox_override("panel", style)
			panels[i].modulate.a = 0.45 if ready and not chosen else 1.0
			seat["badges"][i].modulate.a = 1.0 if chosen else 0.0
		var button: PanelContainer = seat["ready_button"]
		if button:
			var can_ready: bool = seat["selected"] >= 0
			var on_button: bool = not ready and _on_ready_button(seat)
			var bg := color.darkened(0.55) if (ready or (on_button and can_ready)) else CARD_BG
			button.add_theme_stylebox_override("panel", _box(bg,
				color if (on_button or ready) else CARD_BG, 6 if on_button or ready else 2))
			button.modulate.a = 1.0 if can_ready else 0.45
			var ready_label := button.get_child(0) as Label
			ready_label.text = "READY!" if ready else "READY UP"
			ready_label.add_theme_color_override("font_color", color.lightened(0.3) if ready else Color.WHITE)
		var status: Control = seat["status"]
		if status:
			status.visible = seat["inspecting"]


func _check_done() -> void:
	if _done:
		return
	for seat in _seats:
		if not seat["ready"]:
			return
	_done = true
	for seat in _seats:
		if seat["selected"] >= 0:
			BraidClassMod.pick(seat["player"], seat["cards"][seat["selected"]])
	all_ready.emit()
	queue_free()


func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(width)
	style.border_color = border
	style.set_corner_radius_all(14)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style


## `width` > 0: the label is exactly that wide and wraps its text.
func _label(text: String, color: Color, font_size: int, outline: int, center := true, width := 0.0) -> Label:
	var label := Label.new()
	if width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(width, 0)
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", outline)
	if center:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
