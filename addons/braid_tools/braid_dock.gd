@tool
extends EditorDock
## The Braid dock:
##   Preview: build the lane a seed makes (scripts/braid/braid_generator.gd)
##     into PREVIEW_SCENE and open it, with each segment's strips, length and
##     tide time listed, and any problems the checks find.
##   Check seeds: build many seeds in a row and list the ones with problems.
##   Play seed / Play strip: run the Braid game on that seed, or on a lane
##     that's one strip over and over (scripts/braid/braid_game.gd DEBUG_FILE).
##     "Act" picks the act: Play seed starts the run there (in that act's
##     art and boss, at act 1's difficulty), Play strip draws the strip in
##     that act's art (scripts/act_theme.gd), to look at it. Either plays
##     with every connected controller, or the keyboard if there are none.

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")
const BraidGenerator := preload("res://scripts/braid/braid_generator.gd")
const BraidLevel := preload("res://scripts/braid/braid_level.gd")
const BraidStrip := preload("res://scripts/braid/braid_strip.gd")

const PREVIEW_SCENE := "res://levels/braid/_preview.tscn"
const GAME_SCENE := "res://scenenodethings/braid/braid_game.tscn"
## Same file and keys as braid_game.gd DEBUG_FILE.
const DEBUG_FILE := "user://braid_test.cfg"
const SEEDS_TO_CHECK := 20
const OPEN_SCENE_ITEM := "(the strip open in the editor)"

var _seed: SpinBox
var _segments: SpinBox
var _lanes: SpinBox
var _strips: OptionButton
var _act: SpinBox
var _out: RichTextLabel


func _init() -> void:
	title = "Braid"
	layout_key = "braid_tools"
	default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_build_ui()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	add_child(box)

	box.add_child(_heading("Lane preview"))
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_text("Seed"))
	_seed = SpinBox.new()
	_seed.min_value = 0
	_seed.max_value = 2147483647
	_seed.rounded = true
	_seed.value = 1
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_seed)
	row.add_child(_button("Random", func() -> void: _seed.value = randi() % 2147483647))
	row = HBoxContainer.new()
	box.add_child(row)
	row.add_child(_text("Segments"))
	_segments = SpinBox.new()
	_segments.min_value = 1
	_segments.max_value = 8
	_segments.value = BraidTuning.SEGMENTS_PER_ACT
	row.add_child(_segments)
	row.add_child(_text("Lanes"))
	_lanes = SpinBox.new()
	_lanes.min_value = 1
	_lanes.max_value = BraidTuning.MAX_LANES
	_lanes.value = 1
	row.add_child(_lanes)
	row = HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("Build preview", _build_preview))
	row.add_child(_button("Check %d seeds" % SEEDS_TO_CHECK, _check_seeds))
	row.add_child(_button("Play seed", _play_seed))

	box.add_child(HSeparator.new())
	box.add_child(_heading("Play-testing"))
	row = HBoxContainer.new()
	box.add_child(row)
	row.add_child(_text("Act"))
	_act = SpinBox.new()
	_act.min_value = 1
	_act.max_value = BraidTuning.ACTS
	_act.value = 1
	_act.tooltip_text = "Play seed starts the run at this act (act 1 difficulty); Play strip draws the strip in this act's art."
	row.add_child(_act)
	row.add_child(_text("(Play seed / Play strip)"))

	box.add_child(HSeparator.new())
	box.add_child(_heading("Strip test"))
	row = HBoxContainer.new()
	box.add_child(row)
	_strips = OptionButton.new()
	_strips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_strips)
	row.add_child(_button("Refresh", _refresh_strips))
	row.add_child(_button("Play strip", _play_strip))
	_refresh_strips()

	box.add_child(HSeparator.new())
	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.selection_enabled = true
	_out.fit_content = false
	_out.custom_minimum_size = Vector2(0, 260)
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_out)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1, 0.86, 0.5))
	return label


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


# --- Preview ------------------------------------------------------------------------

func _build_preview() -> void:
	BraidGenerator.catalog(true)
	BraidGenerator.junction_catalog(true)
	var run_seed := int(_seed.value)
	var layout := BraidGenerator.act_layout(run_seed, 0, int(_segments.value), int(_lanes.value))
	var level := BraidLevel.new()
	level.name = "BraidPreview"
	var problems := level.build(layout)
	# Each segment's number and tide time above its first strip.
	for i in level.segment_count():
		var label := Label.new()
		label.text = "Segment %d  -  %d s of tide" % [i + 1, roundi(_segment_seconds(level, i))]
		label.position = level.point_at(0, level.segment_start(i), 0.0) + Vector2(24.0, -40.0)
		label.add_theme_font_size_override("font_size", 24)
		level.add_child(label)
	for child in level.get_children():
		child.owner = level
	var packed := PackedScene.new()
	var err := packed.pack(level)
	level.free()
	if err != OK or ResourceSaver.save(packed, PREVIEW_SCENE) != OK:
		_say("[color=red]Couldn't save %s[/color]" % PREVIEW_SCENE)
		return
	EditorInterface.get_resource_filesystem().update_file(PREVIEW_SCENE)
	if PREVIEW_SCENE in EditorInterface.get_open_scenes():
		EditorInterface.reload_scene_from_path(PREVIEW_SCENE)
	else:
		EditorInterface.open_scene_from_path(PREVIEW_SCENE)
	_say(_describe(run_seed, layout, problems))


## How long the tide takes over segment `i` of `level`.
func _segment_seconds(level: BraidLevel, i: int) -> float:
	var start: float = level.segment_start(i) - BraidTuning.TIDE_START_GAP
	return level.tide_time(start, level.gate_x(i) - BraidTuning.TIDE_GATE_STOP)


func _describe(run_seed: int, layout: Dictionary, problems: PackedStringArray) -> String:
	var lines := ["[b]Seed %d, %d lane(s)[/b]" % [run_seed, layout["lanes"]]]
	for i in layout["segments"].size():
		var length := 0.0
		var seams := []
		for slot in layout["segments"][i]["slots"]:
			if slot.has("corner"):
				seams.append("turn " + str(slot["corner"]))
				continue
			length += slot["length"]
			for k in slot["seams"].size():
				if slot["seams"][k] != "solid":
					seams.append("%s %d-%d" % [slot["seams"][k], k + 1, k + 2])
		lines.append("Segment %d (%d px%s):" % [i + 1, length,
			"; " + ", ".join(seams) if not seams.is_empty() else ""])
		var lane := 0
		for names in BraidGenerator.strip_names(layout, i):
			lane += 1
			lines.append("   lane %d: %s" % [lane, ", ".join(names)])
	if problems.is_empty():
		lines.append("[color=green]No problems found.[/color]")
	else:
		for p in problems:
			lines.append("[color=red]%s[/color]" % p)
	return "\n".join(lines)


func _check_seeds() -> void:
	BraidGenerator.catalog(true)
	BraidGenerator.junction_catalog(true)
	var first := int(_seed.value)
	var bad := []
	var used := {}
	for k in SEEDS_TO_CHECK:
		var run_seed := first + k
		var layout := BraidGenerator.act_layout(run_seed, 0, int(_segments.value), int(_lanes.value))
		var level := BraidLevel.new()
		var problems := level.build(layout)
		level.free()
		for seg in layout["segments"].size():
			for names in BraidGenerator.strip_names(layout, seg):
				for n in names:
					used[n] = used.get(n, 0) + 1
		if not problems.is_empty():
			bad.append("Seed %d: %s" % [run_seed, "; ".join(problems)])
	var lines := ["[b]Seeds %d to %d[/b]" % [first, first + SEEDS_TO_CHECK - 1]]
	if bad.is_empty():
		lines.append("[color=green]All %d built without problems.[/color]" % SEEDS_TO_CHECK)
	else:
		for b in bad:
			lines.append("[color=red]%s[/color]" % b)
	var counts := []
	var names := used.keys()
	names.sort()
	for n in names:
		counts.append("%s %d" % [n, used[n]])
	lines.append("Strips used: " + ", ".join(counts))
	_say("\n".join(lines))


# --- Play-testing ---------------------------------------------------------------------

func _play_seed() -> void:
	_play({"seed": int(_seed.value), "act": int(_act.value)})
	_say("Playing seed [b]%d[/b] from act %d." % [int(_seed.value), int(_act.value)])


func _play_strip() -> void:
	var strip_name := _strips.get_item_text(_strips.selected) if _strips.selected >= 0 else ""
	if strip_name == OPEN_SCENE_ITEM:
		var root := EditorInterface.get_edited_scene_root()
		if root == null or root.get_script() != BraidStrip:
			_say("[color=red]The scene open in the editor isn't a Braid strip.[/color]")
			return
		strip_name = root.scene_file_path.get_file().get_basename()
		EditorInterface.save_scene()  # The game loads the strip from disk.
	if strip_name.is_empty():
		return
	_play({"strip": strip_name, "act": int(_act.value)})
	_say("Playing [b]%s[/b] over and over, in act %d's art. Stop the game to end it."
		% [strip_name, int(_act.value)])


func _play(test: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key in test:
		cfg.set_value("test", key, test[key])
	cfg.set_value("test", "written", Time.get_unix_time_from_system())
	cfg.save(DEBUG_FILE)
	EditorInterface.play_custom_scene(GAME_SCENE)


func _refresh_strips() -> void:
	var keep := _strips.get_item_text(_strips.selected) if _strips.selected >= 0 else ""
	_strips.clear()
	_strips.add_item(OPEN_SCENE_ITEM)
	for s in BraidGenerator.catalog(true):
		_strips.add_item(s["name"])
	for i in _strips.item_count:
		if _strips.get_item_text(i) == keep:
			_strips.select(i)


func _say(text: String) -> void:
	_out.text = text
