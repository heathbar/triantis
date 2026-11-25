extends CanvasLayer
## End-of-wave summary: what each player did during the wave (show_summary).
## Also the end-of-run screen, victory or game over (show_final), flipped with
## Left / Right or LB / RB between a scoreboard page (one row per player, their
## unspent resources counting down into their score) and a player stats page.
## In a squads game every squad gets both pages, ours first. Runs while the
## game is paused.
##
## Emits `continued` when any player presses A / Enter / Space / Start or
## B / Escape (only B / Escape if `back_only`), after a short delay so nobody
## skips it by accident, then removes itself.
##
## The prompt shows controller buttons as icons ({A} / {B}, see
## scripts/ui/button_prompts.gd).
##
## Mouse: click the prompt to continue (only the prompt, so a held fire button
## can't skip the screen); click the < / > arrows to flip end-of-run pages.

signal continued

const MenuInput := preload("res://scripts/ui/menu_input.gd")
const ButtonPrompts := preload("res://scripts/ui/button_prompts.gd")
const PlayerStats := preload("res://scripts/ui/player_stats.gd")
const CharacterClasses := preload("res://scripts/character_classes.gd")

## Seconds before input is accepted.
const INPUT_DELAY := 1.0
## Resource cash-in animation (end of the run): pause before it starts, and
## seconds per resource counted, capped at CASH_IN_MAX_TIME.
const CASH_IN_PAUSE := 0.6
const CASH_IN_TIME_PER_RESOURCE := 0.04
const CASH_IN_MAX_TIME := 2.5
const ResourceIcon := preload("res://scripts/ui/resource_icon.gd")
const RESOURCE_COLOR := ResourceIcon.COLOR
const POINTS_COLOR := Color(1, 0.85, 0.3)
const HEADING_COLOR := Color(0.7, 0.7, 0.7)
const TEXT_COLOR := Color(0.85, 0.85, 0.85)
const COLUMNS := ["", "Kills", "Points", "Resources", "Hearts"]
const FINAL_COLUMNS := ["Player", "Kills", "Resources", "Score"]
## Fixed column widths on the end-of-run table, so the numbers don't shift
## while they count and every squad's page lines up.
## The Player column fits a full-length name (Global.MAX_NAME_LENGTH).
const FINAL_COLUMN_WIDTHS := [640, 220, 320, 320]
## End-of-run page area height (fits the stats cards), so flipping between
## pages never moves the title.
const FINAL_PAGE_HEIGHT := 1000

## True: only B / Escape continues. Set before show_summary() / show_final().
var back_only := false

var _prompt: RichTextLabel
var _accepting := false

# End-of-run screen (show_final).
enum Page { SCOREBOARD, STATS }
## One per squad (just one outside a squads game), ours first:
## {"squad": int, "name": String, "color": Color, "results": Dictionary}.
## `results` is {} until that squad's arrive (see game.gd _cash_in_resources).
var _squads: Array[Dictionary] = []
## Every page in order: [squad index into _squads, Page], two per squad.
var _pages: Array = []
var _page := 0
## Index into _squads -> how far its scoreboard's cash-in count got (0..1).
var _progress := {}
var _points_per_resource := 0.0
var _bonus := 0
var _page_header: Label
var _prev_arrow: Label
var _next_arrow: Label
var _table_holder: VBoxContainer
var _tween: Tween
var _menu := MenuInput.new()
## False for the first INPUT_DELAY of the end-of-run screen: movement still
## held from the game (stick, D-pad, keys) mustn't flip it off page 1.
var _can_flip := false


func _init() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS


## Between waves. `rows`: one per player, {"player": Node, "kills": int,
## "points": int, "resources": int, "health": int (half hearts)}. `bonus` resources were given
## to everyone on top, and `bonus_hearts` extra max hearts.
func show_summary(title: String, title_color: Color, subtitle: String,
		rows: Array[Dictionary], bonus: int, prompt: String, bonus_hearts := 0) -> void:
	var vbox := _build_frame(title, title_color, subtitle, 40)

	var grid := GridContainer.new()
	grid.columns = COLUMNS.size()
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 100)
	grid.add_theme_constant_override("v_separation", 20)
	vbox.add_child(grid)

	for heading in COLUMNS:
		grid.add_child(_label(heading, HEADING_COLOR, 56, 10))
	# Most points this wave first (then most points overall, then slot).
	var sorted_rows := rows.duplicate()
	sorted_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		if a["player"].points != b["player"].points:
			return a["player"].points > b["player"].points
		return a["player"].player_index < b["player"].player_index)
	for row in sorted_rows:
		var player: Node = row["player"]
		var name_label := _label(player.display_name(), player.color, 88, 16)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(name_label)
		grid.add_child(_label(str(row["kills"]), Color.WHITE, 88, 16))
		grid.add_child(_label("+%d" % row["points"], Color.WHITE, 88, 16))
		grid.add_child(_label("+%d" % row["resources"], RESOURCE_COLOR, 88, 16))
		grid.add_child(_label("%s / %s" % [CharacterClasses.hearts_text(row["health"]),
				CharacterClasses.hearts_text(player.max_health)], Color(1.0, 0.4, 0.45), 88, 16))

	if bonus > 0:
		vbox.add_child(_label("Wave bonus: +%d resources each" % bonus, RESOURCE_COLOR, 64, 12))
	if bonus_hearts > 0:
		vbox.add_child(_label("Wave bonus: +%d max heart%s each" % [bonus_hearts,
				"" if bonus_hearts == 1 else "s"], Color(1.0, 0.4, 0.45), 64, 12))

	_add_prompt(vbox, prompt)
	await get_tree().create_timer(INPUT_DELAY, true).timeout
	_accept_input()
	# A dummy squad (scripts/net/dummy_squad.gd) has nobody to press on.
	if Global.dummy_squad:
		_continue()


## End of the run (won or lost). `squads`: one per squad, ours first, as
## described at _squads (one with squad -1 outside a squads game). Each
## player's unspent resources count down to 0 while their score counts up by
## `points_per_resource` each. Other squads' results can arrive later
## (add_results); their pages say they're waiting until then.
func show_final(title: String, title_color: Color, subtitle: String, bonus: int,
		prompt: String, points_per_resource: float, squads: Array[Dictionary]) -> void:
	_points_per_resource = points_per_resource
	_squads = squads
	for squad in _squads:
		_sort_results(squad["results"])
	for i in _squads.size():
		_pages.append([i, Page.SCOREBOARD])
		_pages.append([i, Page.STATS])
	_bonus = bonus
	var vbox := _build_frame(title, title_color, subtitle, 24)

	# <    page name    >   (the arrows are clickable)
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	header_row.add_theme_constant_override("separation", 80)
	vbox.add_child(header_row)
	_prev_arrow = _clickable(_label("<", Color.WHITE, 72, 12), _flip.bind(-1))
	header_row.add_child(_prev_arrow)
	_page_header = _label("", Color.WHITE, 72, 12)
	header_row.add_child(_page_header)
	_next_arrow = _clickable(_label(">", Color.WHITE, 72, 12), _flip.bind(1))
	header_row.add_child(_next_arrow)

	# Top-aligned (not centred) so short pages sit just under the header.
	_table_holder = VBoxContainer.new()
	_table_holder.alignment = BoxContainer.ALIGNMENT_BEGIN
	_table_holder.custom_minimum_size.y = FINAL_PAGE_HEIGHT
	vbox.add_child(_table_holder)

	var hint := "scoreboard / stats" if _squads.size() == 1 else "more pages"
	vbox.add_child(ButtonPrompts.label("{LB}{RB}  " + hint, HEADING_COLOR, 44, 10))

	_add_prompt(vbox, prompt)
	_show_page(0)
	get_tree().create_timer(INPUT_DELAY, true).timeout.connect(_allow_flip)

	# Let our scoreboard's count finish before anyone can skip it.
	var wait := maxf(INPUT_DELAY, CASH_IN_PAUSE + _cash_in_duration(_squads[0]["results"]))
	await get_tree().create_timer(wait, true).timeout
	_accept_input()


## Squads game: `squad`'s end-of-run results arrived.
func add_results(squad: int, results: Dictionary) -> void:
	for i in _squads.size():
		if _squads[i]["squad"] == squad and _squads[i]["results"].is_empty():
			_sort_results(results)
			_squads[i]["results"] = results
			if _pages[_page][0] == i and is_inside_tree():
				_show_page(_page)


func _input(event: InputEvent) -> void:
	if not _pages.is_empty():
		var intent: String = _menu.read(event).get("intent", "")
		if intent in ["left", "prev_tab", "right", "next_tab"]:
			get_viewport().set_input_as_handled()
			# Still read while blocked, so a stick held from the game has to
			# be let go and pushed again to count.
			if _can_flip:
				_flip(-1 if intent in ["left", "prev_tab"] else 1)
			return
	if not _accepting:
		return
	var pressed: bool = event.is_action_pressed("escape") or (not back_only and (
		event.is_action_pressed("ui_accept") or event.is_action_pressed("menu_start")))
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	_continue()


func _continue() -> void:
	if not _accepting:
		return
	_accepting = false
	continued.emit()
	queue_free()


func _allow_flip() -> void:
	_can_flip = true


func _flip(step: int) -> void:
	_show_page(posmod(_page + step, _pages.size()))


## Makes `label` respond to a left click by calling `on_click`.
func _clickable(label: Control, on_click: Callable):
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			label.accept_event()
			on_click.call())
	return label


## Dim backdrop and a centred column holding the title and subtitle.
func _build_frame(title: String, title_color: Color, subtitle: String, separation: int) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", separation)
	center.add_child(vbox)

	vbox.add_child(_label(title, title_color, 200, 28))
	if subtitle != "":
		vbox.add_child(_label(subtitle, TEXT_COLOR, 72, 14))
	return vbox


## Reserve the prompt's space now so the layout doesn't jump when it appears.
func _add_prompt(parent: Node, prompt: String) -> void:
	_prompt = _clickable(ButtonPrompts.label(prompt, TEXT_COLOR, 64, 12), _continue)
	_prompt.modulate.a = 0.0
	parent.add_child(_prompt)


func _accept_input() -> void:
	if not is_inside_tree():
		return
	_accepting = true
	create_tween().tween_property(_prompt, "modulate:a", 1.0, 0.3)


## Shows page `index` of the end-of-run screen. A scoreboard picks up its
## cash-in count where it left off (or starts it the first time it's seen).
func _show_page(index: int) -> void:
	_page = index
	if _tween:
		_tween.kill()
		_tween = null
	for child in _table_holder.get_children():
		_table_holder.remove_child(child)
		child.queue_free()

	var squad_i: int = _pages[index][0]
	var kind: Page = _pages[index][1]
	var squad: Dictionary = _squads[squad_i]
	var page_name := "Scoreboard" if kind == Page.SCOREBOARD else "Player Stats"
	if squad["squad"] >= 0:
		_page_header.text = "%s Squad  -  %s  (%d / %d)" % [
			squad["name"], page_name, index + 1, _pages.size()]
		_page_header.add_theme_color_override("font_color", squad["color"])
	else:
		_page_header.text = "%s  (%d / %d)" % [page_name, index + 1, _pages.size()]

	var results: Dictionary = squad["results"]
	if results.is_empty():
		_table_holder.add_child(_label("Waiting for %s's results..." % squad["name"], TEXT_COLOR, 56, 12))
		return
	if kind == Page.STATS:
		_build_stats_cards(results)
		return

	var views := _build_final_table(results)
	var from: float = _progress.get(squad_i, 0.0)
	_apply_cash_in(views, results, from)
	if from >= 1.0:
		return
	var duration := _cash_in_duration(results)
	if duration <= 0.0:
		_progress[squad_i] = 1.0
		return
	_tween = create_tween()
	if from == 0.0:
		_tween.tween_interval(CASH_IN_PAUSE)
	_tween.tween_method(func(t: float) -> void:
		_progress[squad_i] = t
		_apply_cash_in(views, results, t), from, 1.0, duration * (1.0 - from))
	_tween.tween_callback(_pop_scores.bind(views))


## One PlayerStats card per player, side by side.
func _build_stats_cards(results: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_table_holder.add_child(row)
	for data: Dictionary in results.get("stats", []):
		var card := PlayerStats.new()
		row.add_child(card)
		card.show_stats(data)


## The end-of-run table:
##   Player   Kills   Resources   Score
##   Heath    42      12          620
## (rows sorted by final score, see _sort_results)
## Returns one view per player: {"row" (the results row), "resources", "score" (Labels)}.
func _build_final_table(results: Dictionary) -> Array:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	_table_holder.add_child(vbox)
	if _bonus > 0:
		vbox.add_child(_label("Wave bonus: +%d resources each" % _bonus, RESOURCE_COLOR, 56, 12))

	var grid := GridContainer.new()
	grid.columns = FINAL_COLUMNS.size()
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 16)
	vbox.add_child(grid)
	for i in FINAL_COLUMNS.size():
		var heading := _label(FINAL_COLUMNS[i], HEADING_COLOR, 56, 10)
		heading.custom_minimum_size.x = FINAL_COLUMN_WIDTHS[i]
		if i == 0:
			heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(heading)

	var views := []
	for row: Dictionary in results["players"]:
		var name_label := _label(row["label"], row["color"], 88, 16)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(name_label)
		grid.add_child(_label(str(row["kills"]), Color.WHITE, 88, 16))
		var resources := _label("", RESOURCE_COLOR, 88, 16)
		grid.add_child(resources)
		var score := _label("", POINTS_COLOR, 88, 16)
		grid.add_child(score)
		views.append({"row": row, "resources": resources, "score": score})
	return views


## Orders `results`' scoreboard rows by final score, highest first (ties by
## slot), and its stats cards to match. In place.
func _sort_results(results: Dictionary) -> void:
	var players: Array = results.get("players", [])
	if players.is_empty():
		return
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := _final_score(a)
		var sb := _final_score(b)
		if sa != sb:
			return sa > sb
		return a.get("slot", 0) < b.get("slot", 0))
	# Stats cards follow the scoreboard order (results from an older build
	# without slots keep their own order).
	var stats: Array = results.get("stats", [])
	if stats.is_empty() or not players[0].has("slot") or not stats[0].has("slot"):
		return
	var order := {}
	for i in players.size():
		order[players[i]["slot"]] = i
	stats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return order.get(a["slot"], 99) < order.get(b["slot"], 99))


## A scoreboard row's score once its resources are cashed in.
func _final_score(row: Dictionary) -> int:
	return row["points_before"] + roundi(row["resources"] * _points_per_resource)


## Seconds the cash-in count takes for these results (0 if nothing to count).
func _cash_in_duration(results: Dictionary) -> float:
	return minf(_most_resources(results) * CASH_IN_TIME_PER_RESOURCE, CASH_IN_MAX_TIME)


func _most_resources(results: Dictionary) -> int:
	var most := 0
	for row: Dictionary in results.get("players", []):
		most = maxi(most, row["resources"])
	return most


## Shows the count `t` (0..1) of the way through: everyone counts at the same
## speed, so smaller piles just finish sooner.
func _apply_cash_in(views: Array, results: Dictionary, t: float) -> void:
	var most := _most_resources(results)
	for v in views:
		var total: int = v["row"]["resources"]
		var counted := mini(roundi(t * most), total)
		v["resources"].text = str(total - counted)
		v["score"].text = str(v["row"]["points_before"] + roundi(counted * _points_per_resource))


func _pop_scores(views: Array) -> void:
	for v in views:
		var score: Label = v["score"]
		score.pivot_offset = score.size / 2.0
		# Bound to the label, so flipping the page mid-pop just drops it.
		var pop := score.create_tween()
		pop.tween_property(score, "scale", Vector2(1.2, 1.2), 0.1)
		pop.tween_property(score, "scale", Vector2.ONE, 0.15)


func _label(text: String, color: Color, font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	return label
