extends CenterContainer
## The Controls screen on the title screen: the controller diagram
## (res://assets/ui/controls/controller.svg) with what each button does in game
## written at the end of its callout line. `closed` when the player backs out.

signal closed

const DIAGRAM := "res://assets/ui/controls/controller.svg"
## Part of the diagram shown, in its own (SVG) units: trims the empty space
## above and below the controller.
const CROP := Rect2(0, 0, 4096, 1744)
## How wide the diagram is drawn, and the room around it for the labels.
const DIAGRAM_WIDTH := 1900.0
const AREA_WIDTH := 2560.0
const FONT_SIZE := 44
const LABEL_BOX := Vector2(720, 80)
const TEXT_COLOR := Color(1, 1, 1, 0.92)
const UNUSED_COLOR := Color(1, 1, 1, 0.4)

## What each callout says, and where: "at" is the end of its callout line in
## SVG units, "side" which way the text runs from there (LEFT = text ends at
## "at", RIGHT = starts there, CENTER = centred above it).
const CALLOUTS := [
	{"text": "Shop: previous tab", "at": Vector2(912, 240), "side": HORIZONTAL_ALIGNMENT_RIGHT},
	{"text": "Use equipment", "at": Vector2(912, 400), "side": HORIZONTAL_ALIGNMENT_RIGHT},
	{"text": "Shop: next tab", "at": Vector2(3200, 240), "side": HORIZONTAL_ALIGNMENT_LEFT},
	{"text": "Melee attack", "at": Vector2(3200, 400), "side": HORIZONTAL_ALIGNMENT_LEFT},
	{"text": "Not used", "at": Vector2(1770, 300), "side": HORIZONTAL_ALIGNMENT_CENTER},
	{"text": "Pause\nShop: ready", "at": Vector2(2330, 300), "side": HORIZONTAL_ALIGNMENT_CENTER},
	{"text": "Continue / Shop: buy", "at": Vector2(3200, 784), "side": HORIZONTAL_ALIGNMENT_LEFT},
	{"text": "Drop hot potato / Back", "at": Vector2(3200, 928), "side": HORIZONTAL_ALIGNMENT_LEFT},
	{"text": "Shop: bank", "at": Vector2(3200, 1066), "side": HORIZONTAL_ALIGNMENT_LEFT},
	{"text": "Shop: re-roll", "at": Vector2(3200, 1210), "side": HORIZONTAL_ALIGNMENT_LEFT},
	{"text": "Move", "at": Vector2(1018, 998), "side": HORIZONTAL_ALIGNMENT_RIGHT},
	{"text": "Move up", "at": Vector2(752, 1216), "side": HORIZONTAL_ALIGNMENT_RIGHT},
	{"text": "Move right", "at": Vector2(752, 1360), "side": HORIZONTAL_ALIGNMENT_RIGHT},
	{"text": "Move down", "at": Vector2(752, 1504), "side": HORIZONTAL_ALIGNMENT_RIGHT},
	{"text": "Move left", "at": Vector2(752, 1648), "side": HORIZONTAL_ALIGNMENT_RIGHT},
	{"text": "Aim and shoot", "at": Vector2(3312, 1670), "side": HORIZONTAL_ALIGNMENT_LEFT},
]

var back_button: Button


## `panel_style`: the panel look. `accent`: the heading colour.
func build(panel_style: StyleBox, accent := Color(0.45, 0.95, 0.45)) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	panel.add_child(vbox)

	var heading := Label.new()
	heading.text = "Controls"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 120)
	heading.add_theme_color_override("font_color", accent)
	vbox.add_child(heading)

	vbox.add_child(_build_diagram())

	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(600, 140)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(func() -> void: closed.emit())
	vbox.add_child(back_button)


func open() -> void:
	show()
	back_button.grab_focus()


func _build_diagram() -> Control:
	var scale := DIAGRAM_WIDTH / CROP.size.x
	var offset := Vector2((AREA_WIDTH - DIAGRAM_WIDTH) / 2.0, 0.0)
	var area := Control.new()
	area.custom_minimum_size = Vector2(AREA_WIDTH, CROP.size.y * scale)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var image := AtlasTexture.new()
	image.atlas = load(DIAGRAM)
	# The SVG may be imported at another scale than its own units.
	var import_scale := image.atlas.get_width() / 4096.0
	image.region = Rect2(CROP.position * import_scale, CROP.size * import_scale)
	var picture := TextureRect.new()
	picture.texture = image
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.position = offset
	picture.size = CROP.size * scale
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(picture)

	for callout in CALLOUTS:
		var at: Vector2 = offset + (callout["at"] - CROP.position) * scale
		var label := Label.new()
		label.text = callout["text"]
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color",
			UNUSED_COLOR if callout["text"] == "Not used" else TEXT_COLOR)
		label.horizontal_alignment = callout["side"]
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = LABEL_BOX
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gap := 16.0
		match callout["side"]:
			HORIZONTAL_ALIGNMENT_RIGHT:
				label.position = Vector2(at.x - LABEL_BOX.x - gap, at.y - LABEL_BOX.y / 2.0)
			HORIZONTAL_ALIGNMENT_LEFT:
				label.position = Vector2(at.x + gap, at.y - LABEL_BOX.y / 2.0)
			_:
				# Above the line's end; may run to two lines.
				label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
				label.size = Vector2(LABEL_BOX.x, LABEL_BOX.y * 2.0)
				label.position = Vector2(at.x - LABEL_BOX.x / 2.0, at.y - label.size.y - gap / 2.0)
		area.add_child(label)
	return area
