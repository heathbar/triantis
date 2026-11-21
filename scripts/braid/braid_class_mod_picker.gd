extends CanvasLayer
## After a Braid boss fight: every player picks one Class Mod from
## their cards (scripts/braid/braid_class_mod.gd), each with their own
## controller (or the keyboard, or a click), side by side like the shop.
## Emits `all_ready` once everyone has picked, then removes itself.
##
## A player whose class has no trees, or no Class Mods left to pick, has nothing
## to pick and counts as ready. So does one whose controller is unplugged
## (they get their first card).

signal all_ready

const BraidClassMod := preload("res://scripts/braid/braid_class_mod.gd")
const MenuInput := preload("res://scripts/ui/menu_input.gd")

const COLUMN_WIDTH := 620.0
const CARD_BG := Color(0.1, 0.12, 0.16)
const CARD_SELECTED := Color(0.18, 0.24, 0.32)
const MUTED := Color(0.65, 0.65, 0.7)

## [{"player", "cards", "cursor", "picked" (-1 = not yet), "panels", "status"}]
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
	vbox.add_child(_label("Up / Down: choose     A / Enter: pick", MUTED, 40, 6))

	var ordered := players.duplicate()
	ordered.sort_custom(func(a: Node, b: Node) -> bool: return a.player_index < b.player_index)
	for player in ordered:
		var rng := RandomNumberGenerator.new()
		rng.seed = rng_seed * 31 + player.player_index
		var seat := {"player": player, "cards": BraidClassMod.offer(player, rng), "cursor": 0,
			"picked": -1, "panels": [], "status": null}
		_build_column(seat, columns)
		_seats.append(seat)
	for seat in _seats:
		if seat["cards"].is_empty():
			seat["picked"] = -2  # nothing to pick
	_pick_for_unplugged()
	_refresh()
	_check_done.call_deferred()


func _build_column(seat: Dictionary, parent: Control) -> void:
	var player: Node = seat["player"]
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	col.add_theme_constant_override("separation", 18)
	parent.add_child(col)
	var class_name_text: String = player.class_id.capitalize()
	col.add_child(_label("%s  %s" % [player.display_name(), class_name_text], player.color, 64, 10))
	if seat["cards"].is_empty():
		var why := "No Class Mods left to pick." if BraidClassMod.has_trees(player.class_id) \
			else "No Class Mods for the %s yet." % class_name_text
		col.add_child(_label(why, MUTED, 44, 6))
		return
	for i in seat["cards"].size():
		var card: Dictionary = seat["cards"][i]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(COLUMN_WIDTH, 300)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 6)
		panel.add_child(inner)
		var gun: bool = card["slot"] == "gun"
		var weapon: Dictionary = player.gun if gun else player.melee
		var kind := "%s: %s" % ["GUN" if gun else "MELEE", str(weapon.get("name", "")).to_upper()]
		inner.add_child(_label(kind, BraidClassMod.GUN_COLOR if gun else BraidClassMod.MELEE_COLOR, 36, 6, false))
		inner.add_child(_label(BraidClassMod.card_title(card), Color.WHITE, 60, 10, false))
		var text := _label(BraidClassMod.card_text(card), Color(0.88, 0.88, 0.9), 38, 0, false)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(COLUMN_WIDTH - 40, 0)
		inner.add_child(text)
		panel.gui_input.connect(_on_card_mouse.bind(seat, i))
		col.add_child(panel)
		seat["panels"].append(panel)
	var status := _label("", MUTED, 40, 6)
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
	if seat["picked"] != -1:
		return  # A pick is final.
	var n: int = seat["cards"].size()
	match intent:
		"up", "left":
			seat["cursor"] = posmod(seat["cursor"] - 1, n)
		"down", "right":
			seat["cursor"] = posmod(seat["cursor"] + 1, n)
		"accept", "start":
			_pick(seat, seat["cursor"])
	_refresh()


func _on_card_mouse(event: InputEvent, seat: Dictionary, i: int) -> void:
	if _done or seat["picked"] != -1:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		seat["cursor"] = i
		_pick(seat, i)
		_refresh()


func _pick(seat: Dictionary, i: int) -> void:
	seat["picked"] = i
	BraidClassMod.pick(seat["player"], seat["cards"][i])
	# Deferred: picks made while opening (unplugged controllers) mustn't
	# finish the screen before anyone's waiting for all_ready.
	_check_done.call_deferred()


## A player whose controller is unplugged can't pick: they get their first card.
func _pick_for_unplugged() -> void:
	var connected := Input.get_connected_joypads()
	for seat in _seats:
		var device: int = seat["player"].device
		if seat["picked"] == -1 and device != Global.KEYBOARD and device not in connected:
			_pick(seat, 0)


func _refresh() -> void:
	for seat in _seats:
		var panels: Array = seat["panels"]
		for i in panels.size():
			var style := StyleBoxFlat.new()
			var chosen: bool = seat["picked"] == i
			var hovered: bool = seat["picked"] == -1 and seat["cursor"] == i
			style.bg_color = CARD_SELECTED if (chosen or hovered) else CARD_BG
			style.set_border_width_all(6 if (chosen or hovered) else 2)
			style.border_color = seat["player"].color if (chosen or hovered) else Color(0.3, 0.32, 0.38)
			style.set_corner_radius_all(14)
			style.content_margin_left = 20
			style.content_margin_right = 20
			style.content_margin_top = 16
			style.content_margin_bottom = 16
			panels[i].add_theme_stylebox_override("panel", style)
			panels[i].modulate.a = 0.45 if seat["picked"] >= 0 and not chosen else 1.0
		var status: Label = seat["status"]
		if status:
			status.text = "Picked! Waiting for the others..." if seat["picked"] >= 0 else ""


func _check_done() -> void:
	if _done:
		return
	for seat in _seats:
		if seat["picked"] == -1:
			return
	_done = true
	all_ready.emit()
	queue_free()


func _label(text: String, color: Color, font_size: int, outline: int, center := true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", outline)
	if center:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
