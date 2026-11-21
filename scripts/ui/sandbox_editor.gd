extends Control
## Loadout screen for the sandbox ("Custom") character, shown over character
## select when that character is confirmed. Every attribute, the gun (and its
## tune-ups), the melee weapon, the equipment and starting resources can be
## set by hand, for testing and balancing. Only reachable when
## Global.sandbox_enabled().
##
## Done saves the loadout to Global.custom_loadout (and settings.cfg, so it
## comes back next run); Cancel / Escape / B leaves it unchanged.
##
## Built in code; driven by the mouse, or the keyboard / a controller through
## normal focus navigation (D-pad / arrows move and change sliders).

const CharacterClasses := preload("res://scripts/character_classes.gd")
const Guns := preload("res://scripts/guns.gd")
const Melee := preload("res://scripts/melee.gd")
const Equipment := preload("res://scripts/equipment.gd")

## true = Done (Global.custom_loadout updated), false = cancelled.
signal finished(confirmed: bool)

const FONT_SIZE := 40
const HEARTS_MAX := 20
const RESOURCES_MAX := 99999

## Attribute id -> SpinBox (sliders are kept in step with them).
var _spins := {}
var _sliders := {}
var _gun_option: OptionButton
var _gun_level_spin: SpinBox
var _melee_level_spin: SpinBox
var _melee_option: OptionButton
var _equipment_option: OptionButton
var _resources_spin: SpinBox
var _copy_option: OptionButton
var _gun_info: Label
var _melee_info: Label
var _equipment_info: Label
## Class ids in _copy_option order (index 0 is the "Copy a class..." prompt).
var _copy_ids: Array[String] = []
var _done_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var theme_res := Theme.new()
	theme_res.default_font_size = FONT_SIZE
	theme = theme_res
	_build()
	_load(Global.loadout_for_character(_sandbox_index()))
	_done_button.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	# Escape / B backs out, unless a dropdown popup is open (it closes itself).
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not _popup_open():
		get_viewport().set_input_as_handled()
		_finish(false)


func _popup_open() -> bool:
	for option in [_gun_option, _melee_option, _equipment_option, _copy_option]:
		if option.get_popup().visible:
			return true
	return false


static func _sandbox_index() -> int:
	for i in Global.CHARACTERS.size():
		if Global.CHARACTERS[i].get("sandbox", false):
			return i
	return 0


# --- Building ---------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.set_border_width_all(8)
	style.border_color = Color(0.45, 0.45, 0.5)
	style.set_corner_radius_all(24)
	style.set_content_margin_all(40)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 28)
	panel.add_child(root)

	var title := _label(root, "Custom Loadout  (sandbox)", 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 80)
	root.add_child(columns)
	_build_attributes(columns)
	_build_items(columns)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	root.add_child(buttons)
	_copy_option = OptionButton.new()
	_copy_option.add_item("Copy a class...")
	_copy_ids.append("")
	for id in CharacterClasses.CLASSES:
		if not CharacterClasses.CLASSES[id].get("sandbox", false):
			_copy_option.add_item(CharacterClasses.CLASSES[id]["name"])
			_copy_ids.append(id)
	_copy_option.item_selected.connect(_on_copy_selected)
	_style_option(_copy_option)
	buttons.add_child(_copy_option)
	_button(buttons, "Reset", func() -> void: _load(_class_loadout("custom")))
	_button(buttons, "Cancel", _finish.bind(false))
	_done_button = _button(buttons, "Done", _finish.bind(true))


func _build_attributes(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	parent.add_child(box)
	_label(box, "Attributes", 52).modulate = Color(1.0, 0.85, 0.5)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for attr in CharacterClasses.ATTRIBUTES:
		var id: String = attr["id"]
		var hearts: bool = attr.get("hearts", false)
		var name_label := _label(grid, attr["name"], FONT_SIZE)
		name_label.custom_minimum_size.x = 240
		var spin := _spin(CharacterClasses.LIVES_MIN if hearts else CharacterClasses.MIN_VALUE,
			HEARTS_MAX if hearts else CharacterClasses.MAX_VALUE)
		if hearts:
			# Hearts have no upper limit; the slider stops at HEARTS_MAX.
			spin.allow_greater = true
		var slider := HSlider.new()
		slider.min_value = spin.min_value
		slider.max_value = spin.max_value
		slider.step = 1
		slider.custom_minimum_size = Vector2(420, 48)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(v: float) -> void: spin.set_value_no_signal(v))
		spin.value_changed.connect(func(v: float) -> void: slider.set_value_no_signal(v))
		grid.add_child(slider)
		grid.add_child(spin)
		if id == "engineering":
			# Equipment numbers scale with engineering.
			spin.value_changed.connect(func(_v: float) -> void: _update_info())
		_spins[id] = spin
		_sliders[id] = slider


func _build_items(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = 900
	parent.add_child(box)

	_label(box, "Gun", 52).modulate = Color(1.0, 0.85, 0.5)
	_gun_option = OptionButton.new()
	for gun in Guns.LIST:
		_gun_option.add_item(gun["name"])
	_style_option(_gun_option)
	_gun_option.item_selected.connect(func(_i: int) -> void: _update_info())
	box.add_child(_gun_option)
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 24)
	box.add_child(level_row)
	_label(level_row, "Upgrade kits (tune-ups)", FONT_SIZE)
	_gun_level_spin = _spin(0, Guns.MAX_LEVEL)
	_gun_level_spin.value_changed.connect(func(_v: float) -> void: _update_info())
	level_row.add_child(_gun_level_spin)
	_gun_info = _info_label(box)

	_label(box, "Melee", 52).modulate = Color(1.0, 0.85, 0.5)
	_melee_option = OptionButton.new()
	for weapon in Melee.LIST:
		_melee_option.add_item(weapon["name"])
	_style_option(_melee_option)
	_melee_option.item_selected.connect(func(_i: int) -> void: _update_info())
	box.add_child(_melee_option)
	var melee_level_row := HBoxContainer.new()
	melee_level_row.add_theme_constant_override("separation", 24)
	box.add_child(melee_level_row)
	_label(melee_level_row, "Upgrade kits (tune-ups)", FONT_SIZE)
	_melee_level_spin = _spin(0, Melee.MAX_LEVEL)
	_melee_level_spin.value_changed.connect(func(_v: float) -> void: _update_info())
	melee_level_row.add_child(_melee_level_spin)
	_melee_info = _info_label(box)

	_label(box, "Equipment", 52).modulate = Color(1.0, 0.85, 0.5)
	_equipment_option = OptionButton.new()
	_equipment_option.add_item("None")
	for item in Equipment.LIST:
		_equipment_option.add_item(item["name"])
	_style_option(_equipment_option)
	_equipment_option.item_selected.connect(func(_i: int) -> void: _update_info())
	box.add_child(_equipment_option)
	_equipment_info = _info_label(box)

	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 24)
	box.add_child(res_row)
	_label(res_row, "Starting resources", 52).modulate = Color(1.0, 0.85, 0.5)
	_resources_spin = _spin(0, RESOURCES_MAX)
	_resources_spin.custom_minimum_size.x = 260
	res_row.add_child(_resources_spin)


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _info_label(parent: Node) -> Label:
	var label := _label(parent, "", 32)
	label.modulate = Color(1, 1, 1, 0.65)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(900, 0)
	return label


func _spin(lo: int, hi: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = 1
	spin.rounded = true
	spin.select_all_on_focus = true
	spin.custom_minimum_size.x = 200
	spin.get_line_edit().add_theme_font_size_override("font_size", FONT_SIZE)
	return spin


func _style_option(option: OptionButton) -> void:
	option.custom_minimum_size = Vector2(600, 72)
	option.get_popup().add_theme_font_size_override("font_size", FONT_SIZE)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260, 90)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


# --- Values -------------------------------------------------------------------

## A class's own starting kit, in loadout form (see Global.loadout_for_character).
static func _class_loadout(class_id: String) -> Dictionary:
	return {
		"attributes": CharacterClasses.starting_attributes(class_id),
		"gun": CharacterClasses.starting_gun(class_id),
		"gun_level": 0,
		"melee": CharacterClasses.starting_melee(class_id),
		"melee_level": 0,
		"equipment": CharacterClasses.starting_equipment(class_id),
		"resources": 0,
	}


func _load(loadout: Dictionary) -> void:
	for id in _spins:
		var v: int = loadout["attributes"].get(id, CharacterClasses.default_value(id))
		_spins[id].value = v
		_sliders[id].set_value_no_signal(v)
	_gun_option.select(maxi(_index_of(Guns.LIST, Guns.get_gun(loadout["gun"])["id"]), 0))
	_gun_level_spin.value = clampi(loadout["gun_level"], 0, Guns.MAX_LEVEL)
	_melee_option.select(maxi(_index_of(Melee.LIST, Melee.get_weapon(loadout["melee"])["id"]), 0))
	_melee_level_spin.value = clampi(loadout.get("melee_level", 0), 0, Melee.MAX_LEVEL)
	# Index 0 is "None".
	_equipment_option.select(_index_of(Equipment.LIST, loadout["equipment"]) + 1)
	_resources_spin.value = loadout["resources"]
	_update_info()


func _collect() -> Dictionary:
	var attrs := {}
	for id in _spins:
		attrs[id] = CharacterClasses.clamp_attribute(id, int(_spins[id].value))
	var eq := _equipment_option.selected
	return {
		"attributes": attrs,
		"gun": Guns.LIST[_gun_option.selected]["id"],
		"gun_level": int(_gun_level_spin.value),
		"melee": Melee.LIST[_melee_option.selected]["id"],
		"melee_level": int(_melee_level_spin.value),
		"equipment": Equipment.LIST[eq - 1]["id"] if eq > 0 else "",
		"resources": int(_resources_spin.value),
	}


static func _index_of(list: Array, id: String) -> int:
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return -1


## Base numbers of the chosen items (before attributes), as a quick reference.
func _update_info() -> void:
	if _gun_option == null or _equipment_option == null or _gun_option.selected < 0:
		return
	var gun: Dictionary = Guns.LIST[_gun_option.selected]
	var level := int(_gun_level_spin.value)
	var pellets := int(gun.get("pellets", 1))
	var damage := Guns.upgraded_damage(gun["damage"], level)
	var interval: float = gun["interval"] / Guns.level_mult("fire_rate", level)
	_gun_info.text = "Damage %d%s, every %.2fs (%.1f DPS), range %d, knockback %d" % [
		damage, " x%d" % pellets if pellets > 1 else "", interval,
		damage * pellets / interval, roundi(gun["range"] * Guns.level_mult("range", level)),
		gun.get("knockback", 0)]

	var melee: Dictionary = Melee.LIST[_melee_option.selected]
	var melee_level := int(_melee_level_spin.value)
	_melee_info.text = "Damage %d, every %.2fs, reach %d, arc %d°, knockback %d" % [
		Melee.upgraded_damage(melee["damage"], melee_level),
		melee["interval"] / Melee.level_mult("fire_rate", melee_level),
		roundi(melee["range"] * Melee.level_mult("range", melee_level)), melee["arc"],
		melee.get("knockback", 0)]

	var eq := _equipment_option.selected
	if eq == 0:
		_equipment_info.text = "No equipment"
	else:
		var item: Dictionary = Equipment.LIST[eq - 1]
		var lines := Equipment.describe(item, int(_spins["engineering"].value))
		_equipment_info.text = "%s\n%s" % [item.get("blurb", ""), "\n".join(lines)]


func _on_copy_selected(index: int) -> void:
	if index > 0:
		_load(_class_loadout(_copy_ids[index]))
	_copy_option.select(0)


func _finish(confirmed: bool) -> void:
	if confirmed:
		Global.custom_loadout = _collect()
		Global.save_settings()
	finished.emit(confirmed)
	queue_free()
