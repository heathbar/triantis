extends PanelContainer
## One player's attributes: attribute bars, then their held gun, melee
## weapon and equipment.
##
## Shown from plain data (snapshot()), not the player node, so a squads game
## can show other squads' players from data they sent over the network.
##
## Used by the shop's STATS tab (framed = false, show_header = false), the
## pause menu and the end-of-run summary (a framed card with a "P1" header).

const CharacterClasses := preload("res://scripts/character_classes.gd")
const AttributeBar := preload("res://scripts/ui/attribute_bar.gd")
const Hearts := preload("res://scripts/ui/hearts.gd")
const Guns := preload("res://scripts/guns.gd")
const Melee := preload("res://scripts/melee.gd")
const Equipment := preload("res://scripts/equipment.gd")

const BUFF_COLOR := AttributeBar.POSITIVE_COLOR
const DEBUFF_COLOR := AttributeBar.NEGATIVE_COLOR
const MUTED := Color(0.55, 0.55, 0.55)
const CARD_BG := Color(0.08, 0.11, 0.08, 0.95)

## Set before adding to the tree.
var framed := true
var show_header := true

var _built := false
var _header: Label
var _style: StyleBoxFlat
var _bars: Array = []
var _values: Array[Label] = []
var _gun_label: Label
var _melee_label: Label
var _equipment_label: Label


## Everything the panel shows about `player`, as plain data:
## {"label", "slot", "color", "attributes" (id -> int), "health", "max_health" (half hearts),
##  "gun", "melee", "equipment" (name, "" for none)}.
static func snapshot(player: Node) -> Dictionary:
	var attributes := {}
	for attr in CharacterClasses.ATTRIBUTES:
		attributes[attr["id"]] = player.get_attribute(attr["id"])
	return {
		"label": player.display_name(),
		"slot": player.player_index,
		"color": player.color,
		"attributes": attributes,
		"health": player.health,
		"max_health": player.max_health,
		"gun": player.gun_name(),
		"melee": player.melee_name(),
		"equipment": player.equipment.get("name", ""),
	}


## Damage per projectile, with the count if the gun fires several.
static func damage_text(damage: int, pellets: int) -> String:
	if pellets > 1:
		return "%d x%d" % [damage, pellets]
	return str(damage)


func _ready() -> void:
	_build()


func show_stats(data: Dictionary) -> void:
	_build()
	if _header:
		_header.text = data["label"]
		_header.add_theme_color_override("font_color", data["color"])
	if _style:
		_style.border_color = (data["color"] as Color).darkened(0.3)

	var attributes: Dictionary = data["attributes"]
	for a in CharacterClasses.ATTRIBUTES.size():
		var attr: Dictionary = CharacterClasses.ATTRIBUTES[a]
		var value: int = attributes.get(attr["id"], CharacterClasses.default_value(attr["id"]))
		var value_label: Label = _values[a]
		if attr.get("hearts", false):
			_bars[a].max_health = data["max_health"]
			_bars[a].health = data["health"]
			value_label.text = str(value)
		else:
			_bars[a].value = value
			value_label.text = "%+d" % value if value != 0 else "0"
		# Coloured by how it compares to an average character.
		var diff: int = value - CharacterClasses.default_value(attr["id"])
		value_label.add_theme_color_override("font_color", BUFF_COLOR if diff > 0
			else (DEBUFF_COLOR if diff < 0 else MUTED))

	_gun_label.text = "Gun:  %s" % data["gun"]
	_melee_label.text = "Melee:  %s" % data["melee"]
	# Results from an older game (squads) may not say.
	var equipment: String = data.get("equipment", "")
	_equipment_label.text = "Equip:  %s" % (equipment if equipment != "" else "None")
	_equipment_label.modulate = Color.WHITE if equipment != "" else Color(1, 1, 1, 0.5)


func _build() -> void:
	if _built:
		return
	_built = true

	if framed:
		_style = StyleBoxFlat.new()
		_style.bg_color = CARD_BG
		_style.set_border_width_all(6)
		_style.border_color = MUTED
		_style.set_corner_radius_all(20)
		_style.set_content_margin_all(28)
		add_theme_stylebox_override("panel", _style)
	else:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)

	if show_header:
		_header = _label("", Color.WHITE, 64, 10)
		_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		vbox.add_child(_header)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)
	for attr in CharacterClasses.ATTRIBUTES:
		var attr_name := _label(attr["name"], Color.WHITE, 34, 4)
		attr_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		attr_name.custom_minimum_size.x = 200
		grid.add_child(attr_name)
		# Lives is a heart count, so it gets hearts instead of a -100..+100 bar.
		var bar: Control
		if attr.get("hearts", false):
			bar = Hearts.new()
			bar.heart_size = 32
			bar.max_width = 250
		else:
			bar = AttributeBar.new()
			bar.custom_minimum_size = Vector2(250, 26)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		_bars.append(bar)
		var value_label := _label("", Color.WHITE, 34, 4)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.custom_minimum_size.x = 80
		grid.add_child(value_label)
		_values.append(value_label)

	_gun_label = _label("", Color.WHITE, 40, 6)
	_gun_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(_gun_label)
	_melee_label = _label("", Color.WHITE, 40, 6)
	_melee_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(_melee_label)
	_equipment_label = _label("", Color.WHITE, 40, 6)
	_equipment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(_equipment_label)
	# Wide enough for the longest weapon name in the game, so the card is the
	# same width whatever the player holds.
	var font := _gun_label.get_theme_font("font")
	var font_size := _gun_label.get_theme_font_size("font_size")
	var widest := 0.0
	for gun in Guns.LIST:
		widest = maxf(widest, font.get_string_size("Gun:  " + Guns.display_name(gun, Guns.MAX_LEVEL),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	for weapon in Melee.LIST:
		widest = maxf(widest, font.get_string_size("Melee:  " + Melee.display_name(weapon, Melee.MAX_LEVEL),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	for equipment in Equipment.LIST:
		widest = maxf(widest, font.get_string_size("Equip:  " + equipment["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	_gun_label.custom_minimum_size.x = ceilf(widest)


func _label(text: String, color: Color, font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	return label
