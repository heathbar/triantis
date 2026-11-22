extends CanvasLayer
## Between-wave shop. Every player gets their own column and browses it with
## their own controller (or the keyboard) at the same time, spending resources
## on this wave's random items (scripts/items.gd). Runs while the game is paused.
## Guns, melee weapons and equipment are sold among the items; buying one
## replaces the one the player holds. Under the items, two UPGRADE KIT rows always
## offer the player's gun (Items.tune_offer) and melee weapon
## (Items.melee_tune_offer) their next upgrade level, or a promotion to the
## next tier once fully tuned.
##
## Each column has two tabs: SHOP (the items for sale) and STATS (the player's
## attributes and current stats), plus a third, MODS (the Braid Class Mods
## they've picked, scripts/braid/braid_class_mod.gd), once they have one.
##
## Controls (per player):
##   LB / RB, Q / E     - switch between the SHOP, STATS (and MODS) tabs
##   Up / Down          - choose a row (D-pad, left stick, arrows / WS)
##   A / Enter / Space  - buy it (or an Upgrade Kit); on "READY" (or Start), ready up
##   Y / R              - re-roll: swap every unbanked item for new random
##                        ones (costs double each time this wave)
##   X                  - bank / un-bank the selected item (keeps it for next wave)
##   B / Escape         - un-ready
##
## The mouse drives the keyboard player's column: hover a row to select it,
## click to buy (or ready up / un-ready on the READY row), right-click to bank,
## click a tab to switch to it, click the re-roll line to re-roll.
##
## READY UP sits under the tabs, so it's there on every tab: on SHOP it's the
## last row; on STATS and MODS it's the only one, so A readies up.
##
## The shop closes after SHOP_TIME seconds even if not everyone is ready
## (a countdown in the top-right corner), so nobody holds the squad up.
##
## Emits `all_ready` once every player is ready (or time runs out), then
## removes itself.

signal all_ready

const Items := preload("res://scripts/items.gd")
const Guns := preload("res://scripts/guns.gd")
const Melee := preload("res://scripts/melee.gd")
const Equipment := preload("res://scripts/equipment.gd")
const AttributeBar := preload("res://scripts/ui/attribute_bar.gd")
const PlayerStats := preload("res://scripts/ui/player_stats.gd")
const MenuInput := preload("res://scripts/ui/menu_input.gd")
const ResourceIcon := preload("res://scripts/ui/resource_icon.gd")
const ButtonPrompts := preload("res://scripts/ui/button_prompts.gd")
const BraidClassMod := preload("res://scripts/braid/braid_class_mod.gd")
const ActTheme := preload("res://scripts/act_theme.gd")
## Darkens the act's floor behind the shop.
const BACKGROUND_DIM := Color(0, 0, 0, 0.75)

const RESOURCE_COLOR := ResourceIcon.COLOR
const ROW_BG := Color(0.12, 0.15, 0.12)
const ROW_SELECTED_BG := Color(0.22, 0.3, 0.22)
const BORDER_IDLE := Color(0.35, 0.4, 0.35)
const MUTED := Color(0.55, 0.55, 0.55)
const TOO_EXPENSIVE := Color(1.0, 0.4, 0.4)
const BANK_COLOR := Color(1.0, 0.8, 0.25)
const TUNE_COLOR := Color(0.55, 0.85, 1.0)
## Guns.LEVEL_BONUSES stat ids as shown in the Upgrade Kit description.
const UPGRADE_STAT_NAMES := {"fire_rate": "fire rate", "damage": "damage", "range": "range"}
## The same for Melee.LEVEL_BONUSES.
const MELEE_UPGRADE_STAT_NAMES := {"fire_rate": "swing speed", "damage": "damage", "range": "reach"}
const BUFF_COLOR := AttributeBar.POSITIVE_COLOR
const DEBUFF_COLOR := AttributeBar.NEGATIVE_COLOR
const HINT := "{LB}{RB} switch tab     Up / Down: choose     {A} buy" \
	+ "     {X} bank item     Start: ready     {B} un-ready"

## Seconds before the shop closes on its own; the countdown turns red for
## the last SHOP_WARN of them.
const SHOP_TIME := 30.0
const SHOP_WARN := 10.0
const TIMER_COLOR := Color(0.85, 0.85, 0.85)
const TIMER_WARN_COLOR := Color(1.0, 0.4, 0.3)

enum Tab { SHOP, STATS, MODS }
const TAB_NAMES := ["SHOP", "STATS", "MODS"]
## Every tab page is at least this tall (taller if any page needs it), and
## they all share one size (see _refresh_seat), so switching never resizes
## the column.
const PAGE_HEIGHT := 870

## One per player: {"player", "tab", "cursor", "ready", "offer" (item ids),
## "sold" / "banked" (bools, one per offer slot), "price_waves" (waves-done
## each slot is priced at; see _waves_done), "rerolls" (re-rolls bought
## this wave), and UI node references}.
## Cursor rows on the SHOP tab: the offered items, the gun's and the melee
## weapon's UPGRADE KIT, then READY.
var _seats: Array[Dictionary] = []
var _menu_input := MenuInput.new()
var _hint: RichTextLabel
var _timer_label: Label
var _time_left := SHOP_TIME
var bg: TextureRect  # the act floor behind the shop
var _done := false
## Waves played before this shop (1 for the first shop); sets item prices
## (Items.price). A banked item keeps the price from the shop it was banked
## in instead (seat "price_waves").
var _waves_done := 1
## The same for the last shop of the game, the priciest.
var _last_waves_done := 1


func _init() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS


## `price_waves`: waves done for pricing, if not next_wave_index (Boss Rush
## prices as if the skipped waves had been played). `next_label`: what's
## next, if not just the wave number (a boss). `next_heading`: replaces the
## whole "Next: Wave N / M" line if set.
func open(players: Array[Node], next_wave_index: int, total_waves: int, price_waves := -1,
		next_label := "", next_heading := "") -> void:
	_waves_done = price_waves if price_waves >= 1 else next_wave_index
	_last_waves_done = maxi(total_waves - 1, _waves_done)
	# The current act's floor (meadow grass outside the campaign), tiled at
	# its in-game pixel size, under a dark veil.
	bg = TextureRect.new()
	bg.texture = ActTheme.environment("background", Global.MENU_GRASS)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = BACKGROUND_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_fit_background)
	_fit_background()

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	vbox.add_child(_label("SHOP", Color(0.45, 0.95, 0.45), 120, 20))
	var next := "Next: FINAL WAVE" if next_wave_index == total_waves - 1 \
		else "Next: Wave %d / %d" % [next_wave_index + 1, total_waves]
	if not next_heading.is_empty():
		next = next_heading  # Braid mode: segments, not waves.
	if not next_label.is_empty():
		next = "%s  -  %s" % [next, next_label]
	vbox.add_child(_label(next, Color(0.85, 0.85, 0.85), 60, 10))
	# The countdown sits in the top-right corner, off the columns.
	_timer_label = _label("", TIMER_COLOR, 60, 10)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_timer_label)
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 48)
	_timer_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_show_time()

	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 40)
	vbox.add_child(columns)

	var ordered := players.duplicate()
	ordered.sort_custom(func(a: Node, b: Node) -> bool: return a.player_index < b.player_index)
	for player in ordered:
		var offer := Items.roll_offer(player)
		var sold: Array[bool] = []
		var banked: Array[bool] = []
		var slot_waves: Array[int] = []
		for id in offer:
			sold.append(false)
			var was_banked: bool = id in player.banked_items
			banked.append(was_banked)
			slot_waves.append(mini(int(player.banked_price_waves.get(id, _waves_done)), _waves_done)
				if was_banked else _waves_done)
		var seat := {
			"player": player, "tab": Tab.SHOP, "cursor": 0, "ready": false,
			"offer": offer, "sold": sold, "banked": banked, "price_waves": slot_waves,
			"rerolls": 0,
		}
		_build_column(seat, columns)
		_seats.append(seat)
		# New kit changes the item details (and how tall they can get), so
		# they're measured again (before the refresh these signals also cause).
		for kit_changed: Signal in [player.gun_changed, player.melee_changed,
				player.equipment_changed, player.attributes_changed]:
			kit_changed.connect(func(_x) -> void: seat["measured_width"] = -1.0)
		player.resources_changed.connect(_on_player_changed.unbind(1))
		player.attributes_changed.connect(_on_player_changed.unbind(1))
		player.gun_changed.connect(_on_player_changed.unbind(1))
		player.melee_changed.connect(_on_player_changed.unbind(1))
		player.equipment_changed.connect(_on_player_changed.unbind(1))

	_hint = ButtonPrompts.label(HINT, Color(0.75, 0.75, 0.75), 44, 8)
	vbox.add_child(_hint)

	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_ready_up_disconnected()
	_refresh()


## The countdown: when it runs out, everyone is readied up and the shop closes.
func _process(delta: float) -> void:
	if _done:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_show_time()
	if _time_left <= 0.0:
		for seat in _seats:
			seat["ready"] = true
		_check_all_ready()


func _show_time() -> void:
	var secs := ceili(_time_left)
	var text := "Moving on in %ds" % secs
	if _timer_label.text != text:
		_timer_label.text = text
		_timer_label.add_theme_color_override("font_color",
			TIMER_WARN_COLOR if _time_left <= SHOP_WARN else TIMER_COLOR)


## Tile the floor over the whole screen at its in-game pixel size.
func _fit_background() -> void:
	var view := bg.get_viewport_rect()
	bg.scale = Vector2.ONE * Global.MENU_GRASS_SCALE
	bg.position = view.position
	bg.size = view.size / Global.MENU_GRASS_SCALE


func _input(event: InputEvent) -> void:
	if _done:
		return
	var press := _menu_input.read(event)
	if press.is_empty():
		return
	var seat := _seat_for(press["device"])
	if seat.is_empty():
		return
	get_viewport().set_input_as_handled()
	_handle(seat, press["intent"])


func _handle(seat: Dictionary, intent: String) -> void:
	var cursor: int = seat["cursor"]
	var on_shop: bool = seat["tab"] == Tab.SHOP and not seat["ready"]
	match intent:
		"prev_tab", "next_tab":
			var step := -1 if intent == "prev_tab" else 1
			seat["tab"] = posmod(seat["tab"] + step, seat["tab_labels"].size())
		"up", "down":
			if on_shop:
				var step := -1 if intent == "up" else 1
				seat["cursor"] = posmod(cursor + step, _row_count(seat))
		"accept":
			if seat["ready"]:
				pass
			elif seat["tab"] != Tab.SHOP or cursor == _ready_row(seat):
				# Off the SHOP tab, READY UP is the only row.
				seat["ready"] = true
			elif cursor == _tune_row(seat):
				_buy_tune(seat)
			elif cursor == _melee_tune_row(seat):
				_buy_melee_tune(seat)
			else:
				_buy_item(seat, cursor)
		"bank":
			if on_shop and cursor < seat["offer"].size():
				_toggle_bank(seat, cursor)
		"reroll":
			if on_shop:
				_reroll(seat)
		"start":
			seat["ready"] = true
		"back":
			seat["ready"] = false
	_refresh()
	_check_all_ready()


## SHOP tab rows: one per offered item, the two UPGRADE KITs, then READY.
func _row_count(seat: Dictionary) -> int:
	return seat["offer"].size() + 3


func _tune_row(seat: Dictionary) -> int:
	return seat["offer"].size()


func _melee_tune_row(seat: Dictionary) -> int:
	return seat["offer"].size() + 1


func _ready_row(seat: Dictionary) -> int:
	return _row_count(seat) - 1


func _buy_tune(seat: Dictionary) -> void:
	var row: PanelContainer = seat["rows"][_tune_row(seat)]
	_flash(row, Color(0.5, 1.0, 0.5) if Items.buy_tune(seat["player"], _waves_done) else Color(1.0, 0.4, 0.4))


func _buy_melee_tune(seat: Dictionary) -> void:
	var row: PanelContainer = seat["rows"][_melee_tune_row(seat)]
	_flash(row, Color(0.5, 1.0, 0.5) if Items.buy_melee_tune(seat["player"], _waves_done)
		else Color(1.0, 0.4, 0.4))


func _buy_item(seat: Dictionary, slot: int) -> void:
	var row: PanelContainer = seat["rows"][slot]
	if seat["sold"][slot] or not Items.buy(seat["player"], Items.find(seat["offer"][slot]),
			seat["price_waves"][slot]):
		_flash(row, Color(1.0, 0.4, 0.4))
		return
	seat["sold"][slot] = true
	seat["banked"][slot] = false  # bought, so no longer held for later
	_flash(row, Color(0.5, 1.0, 0.5))


## Replaces every unbanked item (bought ones too) with a new random one, not
## one already on offer. Fails, at no cost, if everything is banked or the
## player can't afford it.
func _reroll(seat: Dictionary) -> void:
	var player: Node = seat["player"]
	var row: Control = seat["reroll"]
	var cost := Items.reroll_cost(seat["rerolls"], _waves_done, player)
	var slots: Array[int] = []
	for slot in seat["offer"].size():
		if not seat["banked"][slot]:
			slots.append(slot)
	if slots.is_empty() or player.resources < cost:
		_flash(row, Color(1.0, 0.4, 0.4))
		return
	var keep: Array[String] = []
	for slot in seat["offer"].size():
		if seat["banked"][slot]:
			keep.append(seat["offer"][slot])
	var fresh := Items.roll_random(player, slots.size(), seat["offer"], keep)
	if fresh.size() < slots.size():
		# Not enough unseen items: allow the replaced ones back.
		fresh.append_array(Items.roll_random(player, slots.size() - fresh.size(),
			keep + fresh, keep + fresh))
	player.spend_resources(cost)
	seat["rerolls"] += 1
	for i in mini(slots.size(), fresh.size()):
		seat["offer"][slots[i]] = fresh[i]
		seat["sold"][slots[i]] = false
		seat["price_waves"][slots[i]] = _waves_done
	_flash(row, Color(0.5, 1.0, 0.5))


func _toggle_bank(seat: Dictionary, slot: int) -> void:
	if seat["sold"][slot]:
		return
	seat["banked"][slot] = not seat["banked"][slot]
	_flash(seat["rows"][slot], BANK_COLOR)


## Remembers each player's banked (unsold) items for the next shop, each
## with the price it's locked at.
func _save_banks() -> void:
	for seat in _seats:
		var kept: Array[String] = []
		var locked := {}
		for slot in seat["offer"].size():
			if seat["banked"][slot] and not seat["sold"][slot]:
				kept.append(seat["offer"][slot])
				locked[seat["offer"][slot]] = seat["price_waves"][slot]
		seat["player"].banked_items = kept
		seat["player"].banked_price_waves = locked


func _check_all_ready() -> void:
	for seat in _seats:
		if not seat["ready"]:
			return
	_done = true
	_save_banks()
	all_ready.emit()
	queue_free()


func _seat_for(device: int) -> Dictionary:
	for seat in _seats:
		if seat["player"].device == device:
			return seat
	return {}


## A player whose controller is unplugged can't ready up, so don't wait on them.
func _ready_up_disconnected() -> void:
	var connected := Input.get_connected_joypads()
	for seat in _seats:
		var device: int = seat["player"].device
		if device != Global.KEYBOARD and device not in connected:
			seat["ready"] = true


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected or _done:
		return
	_menu_input.forget(device)
	_ready_up_disconnected()
	_refresh()
	_check_all_ready()


func _on_player_changed() -> void:
	if not _done:
		_refresh()


# --- Mouse (keyboard player's column only) ----------------------------------

func _on_row_mouse(event: InputEvent, seat: Dictionary, slot: int) -> void:
	if _done:
		return
	if event is InputEventMouseMotion:
		if not seat["ready"] and seat["cursor"] != slot:
			seat["cursor"] = slot
			_refresh()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if seat["ready"]:
				# Clicking READY! again un-readies.
				if slot == _ready_row(seat):
					_handle(seat, "back")
			else:
				seat["cursor"] = slot
				_handle(seat, "accept")
		MOUSE_BUTTON_RIGHT:
			if not seat["ready"]:
				seat["cursor"] = slot
				_handle(seat, "bank")
		_:
			return
	get_viewport().set_input_as_handled()


func _on_reroll_mouse(event: InputEvent, seat: Dictionary) -> void:
	if _done or seat["ready"] or not (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_handle(seat, "reroll")
	get_viewport().set_input_as_handled()


func _on_tab_mouse(event: InputEvent, seat: Dictionary, tab: int) -> void:
	if _done or not (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	seat["tab"] = tab
	_refresh()
	get_viewport().set_input_as_handled()


## Clicks anywhere on `control` land on it, not its children.
func _make_clickable(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for child in control.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- UI ---------------------------------------------------------------------

func _build_column(seat: Dictionary, parent: Node) -> void:
	var player: Node = seat["player"]

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.08, 0.95)
	style.set_border_width_all(8)
	style.border_color = BORDER_IDLE
	style.set_corner_radius_all(24)
	style.set_content_margin_all(32)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var tag := _label("P%d" % (player.player_index + 1), player.color, 80, 12)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(tag)
	var resource_box := HBoxContainer.new()
	resource_box.add_theme_constant_override("separation", 12)
	header.add_child(resource_box)
	resource_box.add_child(ResourceIcon.new(44.0))
	var resources := _label("", RESOURCE_COLOR, 64, 10)
	resource_box.add_child(resources)

	# Tab bar: LB  [SHOP]  [STATS]  RB
	var tab_bar := HBoxContainer.new()
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 12)
	vbox.add_child(tab_bar)
	tab_bar.add_child(ButtonPrompts.label("{LB}", MUTED, 34))
	var tab_labels: Array[PanelContainer] = []
	# MODS only once the player has a Class Mod (picks never change in the shop).
	var tab_count := TAB_NAMES.size() if not BraidClassMod.picks(player).is_empty() \
		else Tab.MODS
	for tab_name in TAB_NAMES.slice(0, tab_count):
		var tab_style := StyleBoxFlat.new()
		tab_style.set_corner_radius_all(10)
		tab_style.content_margin_left = 28
		tab_style.content_margin_right = 28
		tab_style.content_margin_top = 4
		tab_style.content_margin_bottom = 4
		var tab_panel := PanelContainer.new()
		tab_panel.add_theme_stylebox_override("panel", tab_style)
		tab_panel.add_child(_label(tab_name, Color.WHITE, 40, 6))
		tab_bar.add_child(tab_panel)
		tab_labels.append(tab_panel)
	tab_bar.add_child(ButtonPrompts.label("{RB}", MUTED, 34))

	var shop_page := VBoxContainer.new()
	shop_page.custom_minimum_size.y = PAGE_HEIGHT
	shop_page.add_theme_constant_override("separation", 16)
	vbox.add_child(shop_page)
	var stats_page := VBoxContainer.new()
	stats_page.custom_minimum_size.y = PAGE_HEIGHT
	stats_page.add_theme_constant_override("separation", 16)
	vbox.add_child(stats_page)
	var mods_page := VBoxContainer.new()
	mods_page.custom_minimum_size.y = PAGE_HEIGHT
	mods_page.add_theme_constant_override("separation", 24)
	vbox.add_child(mods_page)
	_build_mods_page(seat, mods_page)

	# --- SHOP page: items, their details, READY.
	var rows: Array[PanelContainer] = []
	var names: Array[Label] = []
	var tags: Array[Label] = []
	var costs: Array[Label] = []
	for slot in seat["offer"].size() + 3:
		var r := _build_row(shop_page)
		rows.append(r[0])
		names.append(r[1])
		tags.append(r[2])
		costs.append(r[3])
	# The READY row has no tag or price, so its text centres on the whole row.
	names[-1].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tags[-1].hide()
	costs[-1].hide()
	# Under the items: what a re-roll costs (Y, or click it).
	var reroll := HBoxContainer.new()
	reroll.alignment = BoxContainer.ALIGNMENT_END
	reroll.add_theme_constant_override("separation", 10)
	shop_page.add_child(reroll)
	var reroll_text := "Re-roll" if player.device == Global.KEYBOARD else "{Y} Re-roll"
	reroll.add_child(ButtonPrompts.label(reroll_text, MUTED, 36, 6))
	reroll.add_child(ResourceIcon.new(26.0))
	var reroll_cost := _label("", RESOURCE_COLOR, 36, 6)
	reroll.add_child(reroll_cost)
	# The re-roll line belongs to the items, so it goes above the UPGRADE KITs.
	shop_page.move_child(reroll, rows[_tune_row(seat)].get_index())
	var description := RichTextLabel.new()
	description.bbcode_enabled = true
	# Not fit_content: its height is set (_refresh_seat) to fit the tallest
	# details, and a wrapping label measured while hidden would be far too tall.
	description.fit_content = false
	description.scroll_active = false
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("normal_font_size", 38)
	description.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	shop_page.add_child(description)
	# READY sits under the pages, so every tab has it.
	shop_page.remove_child(rows[-1])
	vbox.add_child(rows[-1])

	# --- STATS page: attribute bars, then the stats they produce.
	var stats := PlayerStats.new()
	stats.framed = false
	stats.show_header = false
	stats_page.add_child(stats)

	if player.device == Global.KEYBOARD:
		for slot in rows.size():
			_make_clickable(rows[slot])
			rows[slot].gui_input.connect(_on_row_mouse.bind(seat, slot))
		for t in tab_labels.size():
			_make_clickable(tab_labels[t])
			tab_labels[t].gui_input.connect(_on_tab_mouse.bind(seat, t))
		_make_clickable(reroll)
		reroll.gui_input.connect(_on_reroll_mouse.bind(seat))

	seat.merge({
		"style": style, "resources": resources, "tab_labels": tab_labels,
		"shop_page": shop_page, "stats_page": stats_page, "mods_page": mods_page,
		"rows": rows, "names": names, "tags": tags, "costs": costs, "description": description,
		"reroll": reroll, "reroll_cost": reroll_cost,
		"stats": stats,
	})


## Inner margin of a MODS page card.
const MOD_CARD_MARGIN := 18


## MODS page: one card per Class Mod `player` has, at the stage they've
## reached. Their texts wrap, so _refresh_seat sets their heights (a
## wrapping label measured while its page is hidden would be far too tall).
func _build_mods_page(seat: Dictionary, page: VBoxContainer) -> void:
	var player: Node = seat["player"]
	seat["mod_kinds"] = []
	seat["mod_texts"] = []
	for a in BraidClassMod.actives(player):
		var card := {"slot": a["slot"], "branch": a["branch"], "level": a["level"]}
		var gun: bool = a["slot"] == "gun"
		var style := StyleBoxFlat.new()
		style.bg_color = ROW_BG
		style.set_corner_radius_all(12)
		style.set_content_margin_all(MOD_CARD_MARGIN)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", style)
		page.add_child(panel)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 4)
		panel.add_child(inner)
		var kind := _label("", BraidClassMod.GUN_COLOR if gun else BraidClassMod.MELEE_COLOR, 30, 5)
		kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		inner.add_child(kind)
		seat["mod_kinds"].append([kind, gun])
		var title := _label(BraidClassMod.card_title(card), Color.WHITE, 48, 8)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		inner.add_child(title)
		var text := RichTextLabel.new()
		text.scroll_active = false
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("normal_font_size", 34)
		text.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
		text.text = BraidClassMod.card_text(card)
		inner.add_child(text)
		seat["mod_texts"].append(text)


## The MODS page's weapon names (they change if the player buys a weapon).
func _refresh_mods_page(seat: Dictionary) -> void:
	var player: Node = seat["player"]
	for k in seat["mod_kinds"]:
		var weapon: Dictionary = player.gun if k[1] else player.melee
		k[0].text = "%s: %s" % ["GUN" if k[1] else "MELEE", str(weapon.get("name", "")).to_upper()]


## Gives each MODS card text the height its wrapped text needs at page
## width `width`.
func _size_mod_texts(seat: Dictionary, width: float) -> void:
	var text_width := width - 2 * MOD_CARD_MARGIN
	for text: RichTextLabel in seat["mod_texts"]:
		var measure: RichTextLabel = text.duplicate()
		measure.visible = false
		add_child(measure)
		measure.size = Vector2(text_width, 10.0)
		text.custom_minimum_size.y = ceilf(measure.get_content_height())
		measure.queue_free()


## Returns [panel, name_label, tag_label, cost_label].
func _build_row(parent: Node) -> Array:
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_BG
	style.set_border_width_all(4)
	style.border_color = ROW_BG
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 8
	style.content_margin_bottom = 8

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", style)
	parent.add_child(row)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	row.add_child(hbox)
	var name_label := _label("", Color.WHITE, 44, 6)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(name_label)
	var tag_label := _label("", BANK_COLOR, 28, 4)
	hbox.add_child(tag_label)
	var cost_label := _label("", RESOURCE_COLOR, 44, 6)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.custom_minimum_size.x = 70
	hbox.add_child(cost_label)
	return [row, name_label, tag_label, cost_label]


func _refresh() -> void:
	var ready_count := 0
	for seat in _seats:
		_refresh_seat(seat)
		if seat["ready"]:
			ready_count += 1
	if _hint:
		ButtonPrompts.set_text(_hint, HINT + "          Ready: %d / %d" % [ready_count, _seats.size()])


func _refresh_seat(seat: Dictionary) -> void:
	var player: Node = seat["player"]
	var is_ready: bool = seat["ready"]
	seat["resources"].text = str(player.resources)
	seat["style"].border_color = player.color if is_ready else BORDER_IDLE.lerp(player.color, 0.4)

	for t in seat["tab_labels"].size():
		var tab_panel: PanelContainer = seat["tab_labels"][t]
		var active: bool = t == seat["tab"]
		var tab_style: StyleBoxFlat = tab_panel.get_theme_stylebox("panel")
		tab_style.bg_color = player.color.darkened(0.45) if active else ROW_BG
		tab_panel.modulate = Color.WHITE if active else Color(1, 1, 1, 0.55)
	seat["shop_page"].visible = seat["tab"] == Tab.SHOP
	seat["stats_page"].visible = seat["tab"] == Tab.STATS
	seat["mods_page"].visible = seat["tab"] == Tab.MODS

	_refresh_shop_page(seat)
	_refresh_stats_page(seat)
	_refresh_mods_page(seat)
	# Every page shares one size, big enough for any of them, and it never
	# shrinks, so switching tabs (or buying) never resizes the column.
	var stats_size: Vector2 = seat["stats"].get_combined_minimum_size()
	var width := maxf(stats_size.x, _widest_row(seat))
	for page in ["shop_page", "mods_page"]:
		for child: Control in seat[page].get_children():
			width = maxf(width, child.get_combined_minimum_size().x)
	width = maxf(width, seat.get("page_width", 0.0))
	# The item details box is always as tall as the tallest details any row
	# could show (any item in the game, either Upgrade Kit), so moving the
	# cursor, buying or re-rolling never changes the shop's height.
	if seat.get("measured_width", -1.0) != width:
		seat["measured_width"] = width
		seat["description_height"] = maxf(seat.get("description_height", 0.0),
			_tallest_description(seat, width))
	seat["description"].custom_minimum_size.y = seat["description_height"]
	_size_mod_texts(seat, width)
	# get_minimum_size(): what a page's contents need, not its last size.
	var height := maxf(PAGE_HEIGHT, maxf(stats_size.y, seat.get("page_height", 0.0)))
	for page in ["shop_page", "stats_page", "mods_page"]:
		height = maxf(height, seat[page].get_minimum_size().y)
	seat["page_width"] = width
	seat["page_height"] = height
	var page_size := Vector2(width, height)
	seat["shop_page"].custom_minimum_size = page_size
	seat["stats_page"].custom_minimum_size = page_size
	seat["mods_page"].custom_minimum_size = page_size


## Height of the tallest item details the SHOP page could show `seat`'s
## player at this width: every item in the game (bought or not), and both
## Upgrade Kits as they stand. Measured on a hidden copy of the details box.
func _tallest_description(seat: Dictionary, width: float) -> float:
	var player: Node = seat["player"]
	var description: RichTextLabel = seat["description"]
	var measure: RichTextLabel = description.duplicate()
	measure.visible = false
	measure.fit_content = false
	measure.size_flags_vertical = Control.SIZE_FILL
	add_child(measure)
	measure.size = Vector2(width, 10.0)
	var texts: PackedStringArray = [_tune_description(player), _melee_tune_description(player),
		"Waiting for others..."]
	for item in Items.all():
		texts.append(_describe_item(player, item, false))
		texts.append(_describe_item(player, item, true))
	var tallest := 0.0
	for text in texts:
		measure.text = text
		tallest = maxf(tallest, measure.get_content_height())
	measure.queue_free()
	return ceilf(tallest)


## How wide an item row must be to show the longest item name in the game
## (e.g. "Legendary Sledgehammer") untrimmed next to the highest price
## anything reaches (in the last shop). The column is
## at least this wide, so it doesn't change width from wave to wave. (A
## BANKED tag can still trim a long name.)
func _widest_row(seat: Dictionary) -> float:
	var name_label: Label = seat["names"][0]
	var font := name_label.get_theme_font("font")
	var font_size := name_label.get_theme_font_size("font_size")
	var cost: Label = seat["costs"][0]
	var cost_font := cost.get_theme_font("font")
	var cost_size := cost.get_theme_font_size("font_size")
	var longest := 0.0
	var priciest := maxf(cost.custom_minimum_size.x,
		cost_font.get_string_size("SOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, cost_size).x)
	for item in Items.all():
		longest = maxf(longest, font.get_string_size(item["name"], HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x)
		priciest = maxf(priciest, cost_font.get_string_size(str(Items.price(item, _last_waves_done)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, cost_size).x)
	# Everything in the row besides the name and price: margins, border,
	# separations, the (empty) tag. The name label itself only asks for an
	# ellipsis' width.
	var rest: float = seat["rows"][0].get_combined_minimum_size().x \
		- name_label.get_combined_minimum_size().x - cost.get_combined_minimum_size().x
	return ceilf(longest + priciest + rest)


func _refresh_shop_page(seat: Dictionary) -> void:
	var player: Node = seat["player"]
	var is_ready: bool = seat["ready"]

	for slot in seat["offer"].size():
		var item := Items.find(seat["offer"][slot])
		var name_label: Label = seat["names"][slot]
		var tag_label: Label = seat["tags"][slot]
		var cost_label: Label = seat["costs"][slot]
		var sold: bool = seat["sold"][slot]
		name_label.text = item["name"]
		name_label.add_theme_color_override("font_color",
			MUTED if sold else item.get("color", Color.WHITE))
		tag_label.text = "BANKED" if seat["banked"][slot] else ""
		if sold:
			cost_label.text = "SOLD"
			_set_label_color(cost_label, MUTED)
		else:
			var price_waves: int = seat["price_waves"][slot]
			cost_label.text = str(Items.price(item, price_waves, player))
			_set_label_color(cost_label,
				RESOURCE_COLOR if Items.can_buy(player, item, price_waves) else TOO_EXPENSIVE)

	_refresh_tune_row(seat)
	_refresh_melee_tune_row(seat)

	var reroll_cost := Items.reroll_cost(seat["rerolls"], _waves_done, player)
	seat["reroll_cost"].text = str(reroll_cost)
	_set_label_color(seat["reroll_cost"],
		RESOURCE_COLOR if player.resources >= reroll_cost else TOO_EXPENSIVE)
	seat["reroll"].modulate.a = 0.4 if is_ready else 1.0

	var ready_label: Label = seat["names"][_ready_row(seat)]
	ready_label.text = "READY!" if is_ready else "READY UP"
	ready_label.add_theme_color_override("font_color", player.color if is_ready else Color.WHITE)

	for i in seat["rows"].size():
		var style: StyleBoxFlat = seat["rows"][i].get_theme_stylebox("panel")
		var selected: bool = not is_ready and (i == seat["cursor"]
			if seat["tab"] == Tab.SHOP else i == _ready_row(seat))
		var banked: bool = i < seat["offer"].size() and seat["banked"][i]
		style.bg_color = ROW_SELECTED_BG if selected else ROW_BG
		if selected:
			style.border_color = player.color
		else:
			style.border_color = BANK_COLOR.darkened(0.3) if banked else ROW_BG

	var cursor: int = seat["cursor"]
	var description: RichTextLabel = seat["description"]
	if is_ready:
		description.text = "Waiting for others..."
	elif cursor < seat["offer"].size():
		description.text = _item_description(seat, cursor)
	elif cursor == _tune_row(seat):
		description.text = _tune_description(seat["player"])
	elif cursor == _melee_tune_row(seat):
		description.text = _melee_tune_description(seat["player"])
	else:
		description.text = "Done shopping"


## The gun's UPGRADE KIT row.
func _refresh_tune_row(seat: Dictionary) -> void:
	var player: Node = seat["player"]
	var offer := Items.tune_offer(player, _waves_done)
	_show_tune_row(seat, _tune_row(seat), "Gun", offer, Guns.tier_of(offer["gun"]),
		player.gun_level, Guns.MAX_LEVEL)


## The melee weapon's UPGRADE KIT row.
func _refresh_melee_tune_row(seat: Dictionary) -> void:
	var player: Node = seat["player"]
	var offer := Items.melee_tune_offer(player, _waves_done)
	_show_tune_row(seat, _melee_tune_row(seat), "Melee", offer, Melee.tier_of(offer["weapon"]),
		player.melee_level, Melee.MAX_LEVEL)


## An UPGRADE KIT row: "<what> Upgrade Kit" (with the current level),
## "<what> to <tier>" (a promotion), or "<what> Maxed". `next_tier` is the
## rarity tier of the weapon after buying.
func _show_tune_row(seat: Dictionary, slot: int, what: String, offer: Dictionary,
		next_tier: Dictionary, level: int, max_level: int) -> void:
	var player: Node = seat["player"]
	var name_label: Label = seat["names"][slot]
	var tag_label: Label = seat["tags"][slot]
	var cost_label: Label = seat["costs"][slot]
	match offer["kind"]:
		"tune":
			name_label.text = "%s Upgrade Kit" % what
			name_label.add_theme_color_override("font_color", TUNE_COLOR)
		"promote":
			name_label.text = "%s to %s" % [what, next_tier["name"]]
			name_label.add_theme_color_override("font_color", next_tier["color"])
		_:
			name_label.text = "%s Maxed" % what
			name_label.add_theme_color_override("font_color", MUTED)
	tag_label.text = "LV %d/%d" % [level, max_level]
	_set_label_color(tag_label, TUNE_COLOR)
	if offer["kind"] == "max":
		cost_label.text = "MAX"
		_set_label_color(cost_label, MUTED)
	else:
		cost_label.text = str(offer["cost"])
		_set_label_color(cost_label,
			RESOURCE_COLOR if player.resources >= offer["cost"] else TOO_EXPENSIVE)


## What the UPGRADE KIT row would do to the player's gun, stats beside the
## current ones.
func _tune_description(player: Node) -> String:
	var offer := Items.tune_offer(player, _waves_done)
	var muted := MUTED.to_html(false)
	var now: Dictionary = player.gun_stats(player.gun, player.gun_level)
	var lines: PackedStringArray = []
	match offer["kind"]:
		"tune":
			var bonus: Dictionary = Guns.LEVEL_BONUSES[offer["level"] - 1]
			var parts: PackedStringArray = []
			for stat in bonus:
				parts.append("+%d%% %s" % [roundi(bonus[stat] * 100.0), UPGRADE_STAT_NAMES[stat]])
			lines.append("[color=#%s]Upgrades your %s: %s[/color]" % [
				muted, player.gun["name"], ", ".join(parts)])
			var new: Dictionary = player.gun_stats(player.gun, offer["level"])
			if bonus.has("damage"):
				lines.append(_compare("Damage", _damage_text(new), _damage_text(now),
					new["damage"], now["damage"], false))
			if bonus.has("fire_rate"):
				lines.append(_compare("Fire rate", "%.1f/s" % (1.0 / new["interval"]),
					"%.1f/s" % (1.0 / now["interval"]), 1.0 / new["interval"],
					1.0 / now["interval"], false))
			if bonus.has("range"):
				lines.append(_compare("Range", str(roundi(new["range"])), str(roundi(now["range"])),
					new["range"], now["range"], false))
		"promote":
			lines.append("[color=#%s]Turns your %s into a %s[/color]" % [
				muted, player.gun_name(), offer["gun"]["name"]])
			lines.append_array(_gun_lines(player.gun_stats(offer["gun"]), now, false))
		_:
			lines.append("[color=#%s]Your %s is as good as it gets[/color]" % [
				muted, player.gun_name()])
	return "\n".join(lines)


## What the melee UPGRADE KIT row would do to the player's melee weapon,
## stats beside the current ones.
func _melee_tune_description(player: Node) -> String:
	var offer := Items.melee_tune_offer(player, _waves_done)
	var muted := MUTED.to_html(false)
	var now: Dictionary = player.melee_stats(player.melee, player.melee_level)
	var lines: PackedStringArray = []
	match offer["kind"]:
		"tune":
			var bonus: Dictionary = Melee.LEVEL_BONUSES[offer["level"] - 1]
			var parts: PackedStringArray = []
			for stat in bonus:
				parts.append("+%d%% %s" % [roundi(bonus[stat] * 100.0), MELEE_UPGRADE_STAT_NAMES[stat]])
			lines.append("[color=#%s]Upgrades your %s: %s[/color]" % [
				muted, player.melee["name"], ", ".join(parts)])
			var new: Dictionary = player.melee_stats(player.melee, offer["level"])
			if bonus.has("damage"):
				lines.append(_compare("Melee dmg", str(new["damage"]), str(now["damage"]),
					new["damage"], now["damage"], false))
			if bonus.has("fire_rate"):
				lines.append(_compare("Swings", "%.1f/s" % (1.0 / new["interval"]),
					"%.1f/s" % (1.0 / now["interval"]), 1.0 / new["interval"],
					1.0 / now["interval"], false))
			if bonus.has("range"):
				lines.append(_compare("Reach", str(roundi(new["range"])), str(roundi(now["range"])),
					new["range"], now["range"], false))
		"promote":
			lines.append("[color=#%s]Turns your %s into a %s[/color]" % [
				muted, player.melee_name(), offer["weapon"]["name"]])
			lines.append_array(_melee_lines(player.melee_stats(offer["weapon"]), now, false))
		_:
			lines.append("[color=#%s]Your %s is as good as it gets[/color]" % [
				muted, player.melee_name()])
	return "\n".join(lines)


## The item's effects, one per line: buffs in green, then debuffs in red.
## A gun or melee weapon instead lists its stats next to the held one's.
func _item_description(seat: Dictionary, slot: int) -> String:
	return _describe_item(seat["player"], Items.find(seat["offer"][slot]), seat["sold"][slot])


func _describe_item(player: Node, item: Dictionary, sold: bool) -> String:
	var buff := BUFF_COLOR.to_html(false)
	var lines: PackedStringArray = []
	if sold:
		lines.append("[color=#%s]Bought[/color]" % MUTED.to_html(false))
	if Items.is_gun(item):
		lines.append_array(_gun_description(player, item, sold))
	if Items.is_melee(item):
		lines.append_array(_melee_description(player, item, sold))
	if Items.is_equipment(item):
		lines.append_array(_equipment_description(player, item, sold))
	if item.has("blurb"):
		lines.append("[color=#%s]%s[/color]" % [buff, item["blurb"]])
	for effect in Items.effects_in_order(item):
		var delta: int = effect[1]
		lines.append("[color=#%s]%s %+d[/color]" % [
			buff if delta > 0 else DEBUFF_COLOR.to_html(false), effect[0]["name"], delta])
	return "\n".join(lines)


## A gun's stats in the player's hands, each beside the held gun's (green if
## the new one is better, red if worse).
func _gun_description(player: Node, item: Dictionary, sold: bool) -> PackedStringArray:
	var lines: PackedStringArray = []
	var new: Dictionary = player.gun_stats(Guns.get_gun(item["gun"]))
	var now: Dictionary = player.gun_stats(player.gun, player.gun_level)
	if not sold:
		lines.append("[color=#%s]Replaces your %s[/color]" % [
			MUTED.to_html(false), player.gun_name()])
	lines.append_array(_gun_lines(new, now, sold))
	return lines


## Damage, fire rate, range and knockback of gun stats `new` beside `now`.
func _gun_lines(new: Dictionary, now: Dictionary, sold: bool) -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append(_compare("Damage", _damage_text(new), _damage_text(now),
		new["damage"] * new["pellets"], now["damage"] * now["pellets"], sold))
	lines.append(_compare("Fire rate", "%.1f/s" % (1.0 / new["interval"]),
		"%.1f/s" % (1.0 / now["interval"]), 1.0 / new["interval"], 1.0 / now["interval"], sold))
	lines.append(_compare("Range", str(roundi(new["range"])), str(roundi(now["range"])),
		new["range"], now["range"], sold))
	lines.append(_compare("Knockback",
		PlayerStats.damage_text(roundi(new["knockback"]), new["pellets"]),
		PlayerStats.damage_text(roundi(now["knockback"]), now["pellets"]),
		new["knockback"] * new["pellets"], now["knockback"] * now["pellets"], sold))
	if new["overheat"] > 0.0:
		lines.append("[color=#%s]Overheats after %.0fs of non-stop fire[/color]" % [
			MUTED.to_html(false), new["overheat"]])
	if new["recoil"] > 0.0:
		lines.append("[color=#%s]Recoil pushes you back[/color]" % MUTED.to_html(false))
	if new["overkill"]:
		lines.append("[color=#%s]Kills carry leftover damage into the next enemy[/color]" % MUTED.to_html(false))
	return lines


## A melee weapon's damage, reach, arc and knockback in the player's hands, each beside the
## held weapon's. (Swing speed isn't shown.)
func _melee_description(player: Node, item: Dictionary, sold: bool) -> PackedStringArray:
	var lines: PackedStringArray = []
	var new: Dictionary = player.melee_stats(Melee.get_weapon(item["melee"]))
	var now: Dictionary = player.melee_stats(player.melee, player.melee_level)
	if not sold:
		lines.append("[color=#%s]Replaces your %s[/color]" % [
			MUTED.to_html(false), player.melee_name()])
	lines.append_array(_melee_lines(new, now, sold))
	return lines


## Damage, reach, arc and knockback of melee stats `new` beside `now`.
func _melee_lines(new: Dictionary, now: Dictionary, sold: bool) -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append(_compare("Melee dmg", str(new["damage"]), str(now["damage"]),
		new["damage"], now["damage"], sold))
	lines.append(_compare("Reach", str(roundi(new["range"])), str(roundi(now["range"])),
		new["range"], now["range"], sold))
	lines.append(_compare("Swing", "%d°" % roundi(rad_to_deg(new["arc"])),
		"%d°" % roundi(rad_to_deg(now["arc"])), new["arc"], now["arc"], sold))
	lines.append(_compare("Knockback", str(roundi(new["knockback"])),
		str(roundi(now["knockback"])), new["knockback"], now["knockback"], sold))
	return lines


## What a piece of equipment does, then its numbers in the player's hands
## (engineering changes them).
func _equipment_description(player: Node, item: Dictionary, sold: bool) -> PackedStringArray:
	var equipment := Equipment.find(item["equipment"])
	var muted := MUTED.to_html(false)
	var lines: PackedStringArray = []
	var key := "" if player.device == Global.KEYBOARD \
		else " " + ButtonPrompts.bbcode("{LT}", 38, MUTED)
	var header := "Equipment" + key
	if not sold and player.has_equipment():
		header += ", replaces %s" % player.equipment["name"]
	lines.append("[color=#%s]%s[/color]" % [muted, header])
	lines.append(equipment["blurb"])
	lines.append_array(Equipment.describe(equipment, player.get_attribute("engineering"),
		player.wave_enemy_health, player.equipment_tuning))
	return lines


## "Name  new  (now old)", coloured by whether new beats old. Just "Name  new"
## once bought (it's the held gun then).
func _compare(stat: String, new_text: String, old_text: String,
		new_value: float, old_value: float, sold: bool) -> String:
	if sold:
		return "%s  %s" % [stat, new_text]
	var color := MUTED
	if new_value > old_value:
		color = BUFF_COLOR
	elif new_value < old_value:
		color = DEBUFF_COLOR
	return "[color=#%s]%s  %s[/color]  [color=#%s](now %s)[/color]" % [
		color.to_html(false), stat, new_text, MUTED.to_html(false), old_text]


## Damage per projectile, with the count if the gun fires several.
func _damage_text(stats: Dictionary) -> String:
	return PlayerStats.damage_text(stats["damage"], stats["pellets"])


func _refresh_stats_page(seat: Dictionary) -> void:
	seat["stats"].show_stats(PlayerStats.snapshot(seat["player"]))


func _flash(row: Control, color: Color) -> void:
	row.modulate = color
	create_tween().tween_property(row, "modulate", Color.WHITE, 0.25)


func _set_label_color(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)


func _label(text: String, color: Color, font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	return label
