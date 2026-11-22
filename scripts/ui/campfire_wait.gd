extends CanvasLayer
## Squads game: the cut scene a squad sits in once it's ready for the next wave
## (or campaign chapter) but the other squads aren't yet. The squad's players
## gather round an animated bonfire in a forest clearing at night: the first
## two to its left and right, toasting marshmallows, the rest behind it. The
## waiting text stays at the top, where the HUD shows it.
## Covers the frozen game (and the HUD) until close(). Runs while the tree is
## paused.
## Used by game_base.gd's show_waiting_campfire().

const PlayerSprite := preload("res://scripts/player/player_sprite.gd")
const PlayerSkins := preload("res://scripts/player/player_skins.gd")
const BACKGROUND := preload("res://assets/misc/forest-night.png")
const MARSHMALLOW := preload("res://assets/misc/marshmallow-1.png")
const FIRE_FRAMES: Array[Texture2D] = [
	preload("res://assets/misc/bonfire-1.png"),
	preload("res://assets/misc/bonfire-2.png"),
	preload("res://assets/misc/bonfire-3.png"),
	preload("res://assets/misc/bonfire-4.png"),
	preload("res://assets/misc/bonfire-5.png"),
	preload("res://assets/misc/bonfire-6.png"),
]

## Everything below is placed in the background picture's own pixels; the
## whole scene is then scaled to cover the screen (cropping its sides or top
## and bottom on other aspect ratios, never stretching it).
## Middle of the bonfire's base, in the clearing's lit grass.
const FIRE_BASE := Vector2(836, 800)
## Picture pixels per art pixel: the fire is drawn larger than the people so
## it holds its own beside them and the marshmallows.
const FIRE_SCALE := 6.0
const PLAYER_SCALE := 4.0
const MARSHMALLOW_SCALE := 3.0
const FIRE_FRAME_SECS := 0.1
## The left and right players' distance from the fire's middle.
const SIDE_DISTANCE := 175.0
## How far up (back) the players behind the fire stand, and how far either
## side of its middle (two of them: one each side; one: to the right).
const BEHIND_RISE := 70.0
const BEHIND_SPREAD := 50.0
## Where the stick's held: in front of the figure, a bit under halfway up.
const HAND_FORWARD := 16.0
const HAND_HEIGHT := 0.45
## The stick's held end in marshmallow-1.png (its marshmallow is up and to
## the right).
const STICK_GRIP := Vector2(3, 30)
## How far the sticks are tipped down toward the fire, and the slow sway
## either way of it (radians, seconds per sway).
const STICK_TILT := deg_to_rad(25.0)
const STICK_SWAY := deg_to_rad(4.0)
const STICK_SWAY_SECS := 2.6
## The fire's warm glow on the clearing: colour, radius (picture pixels) and
## how much its brightness flickers.
const GLOW_COLOR := Color(1.0, 0.55, 0.2, 0.32)
const GLOW_RADIUS := 300.0
const GLOW_FLICKER := 0.25
## Same look as the HUD's notice (health_hud.gd).
const TEXT_COLOR := Color(1, 0.85, 0.3)
const TEXT_SIZE := 64
const TEXT_OUTLINE := 14
const TEXT_TOP := 40.0
const FADE_IN_SECS := 0.35

var _root: Control
## Holds the scene in background-picture pixels (see _fit()).
var _stage: Node2D
var _fire: Sprite2D
var _glow: Sprite2D
var _label: Label
## [Sprite2D stick, base rotation, sway phase] for each marshmallow.
var _sticks: Array = []
var _time := 0.0


func _init() -> void:
	layer = 40  # Over the world and HUD, under the shop/summary screens and pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Shows `players` (this squad's, in player order) round the fire, with
## `text` at the top.
func open(players: Array[Node], text: String) -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var blackout := ColorRect.new()  # Behind the picture's cropped edges, just in case.
	blackout.color = Color.BLACK
	blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(blackout)

	_stage = Node2D.new()
	_root.add_child(_stage)
	var background := Sprite2D.new()
	background.texture = BACKGROUND
	background.centered = false
	_stage.add_child(background)
	_glow = _make_glow()
	_stage.add_child(_glow)

	var ordered := players.filter(func(p: Node) -> bool: return is_instance_valid(p))
	ordered.sort_custom(func(a: Node, b: Node) -> bool: return a.player_index < b.player_index)
	# Behind the fire first, so it's drawn over their legs.
	var behind := ordered.slice(2)
	for i in behind.size():
		# Off to one side even alone: dead centre, the flames hide them.
		var x := FIRE_BASE.x + BEHIND_SPREAD * (-1.0 if i == 0 and behind.size() > 1 else 1.0)
		_add_player(behind[i], Vector2(x, FIRE_BASE.y - BEHIND_RISE), x < FIRE_BASE.x, false)

	_fire = Sprite2D.new()
	_fire.texture = FIRE_FRAMES[0]
	_fire.centered = false
	_fire.scale = Vector2.ONE * FIRE_SCALE
	_fire.position = FIRE_BASE - Vector2(FIRE_FRAMES[0].get_width() / 2.0, FIRE_FRAMES[0].get_height()) * FIRE_SCALE
	_stage.add_child(_fire)

	for i in mini(ordered.size(), 2):
		var left := i == 0
		var x := FIRE_BASE.x + SIDE_DISTANCE * (-1.0 if left else 1.0)
		_add_player(ordered[i], Vector2(x, FIRE_BASE.y), left, true)

	_label = Label.new()
	_label.text = text
	_label.add_theme_font_size_override("font_size", TEXT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", TEXT_OUTLINE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.offset_top = TEXT_TOP
	_root.add_child(_label)

	get_viewport().size_changed.connect(_fit)
	_fit()
	_animate(0.0)
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, FADE_IN_SECS)


func set_text(text: String) -> void:
	if _label:
		_label.text = text


func close() -> void:
	queue_free()


## One player standing with their feet at `feet`, facing the fire (left of it
## faces right). `marshmallow`: a stick held out over the fire.
func _add_player(player: Node, feet: Vector2, faces_right: bool, marshmallow: bool) -> void:
	var sprite := PlayerSprite.new()
	sprite.skin = player.skin
	sprite.armor_color = player.color
	sprite.face(0.0 if faces_right else PI)
	sprite.scale = Vector2.ONE * PLAYER_SCALE
	# The sprite centres its figure on its position (player_sprite.gd).
	var height := PlayerSkins.art_rect(player.skin).size.y * PLAYER_SCALE
	sprite.position = (feet - Vector2(0, height / 2.0)).round()
	_stage.add_child(sprite)
	if not marshmallow:
		return
	var toward := 1.0 if faces_right else -1.0
	var stick := Sprite2D.new()
	stick.texture = MARSHMALLOW
	stick.centered = false
	stick.flip_h = not faces_right
	var grip := STICK_GRIP
	if not faces_right:
		grip.x = MARSHMALLOW.get_width() - grip.x
	stick.offset = -grip
	stick.scale = Vector2.ONE * MARSHMALLOW_SCALE
	stick.position = (feet + Vector2(HAND_FORWARD * toward, -height * HAND_HEIGHT)).round()
	_stage.add_child(stick)
	# Tipped down toward the fire: clockwise on the left, anticlockwise on the right.
	_sticks.append([stick, STICK_TILT * toward, randf() * TAU])


## A soft orange light pooled round the fire, added onto what's under it.
func _make_glow() -> Sprite2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	var glow := Sprite2D.new()
	glow.texture = texture
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = additive
	glow.modulate = GLOW_COLOR
	# Squashed flat, lying on the ground round the fire.
	glow.scale = Vector2(1.0, 0.6) * (GLOW_RADIUS * 2.0 / texture.width)
	glow.position = FIRE_BASE - Vector2(0, FIRE_FRAMES[0].get_height() * FIRE_SCALE * 0.3)
	return glow


## Scales the stage so the background covers the whole screen, centred.
func _fit() -> void:
	var view := get_viewport().get_visible_rect()
	var picture := Vector2(BACKGROUND.get_size())
	var k := maxf(view.size.x / picture.x, view.size.y / picture.y)
	_stage.scale = Vector2.ONE * k
	_stage.position = view.position + (view.size - picture * k) / 2.0


func _process(delta: float) -> void:
	_time += delta
	_animate(_time)


func _animate(t: float) -> void:
	_fire.texture = FIRE_FRAMES[int(t / FIRE_FRAME_SECS) % FIRE_FRAMES.size()]
	# Two out-of-step waves, so the flicker doesn't look like a loop.
	var flicker := 0.5 * sin(t * 13.0) + 0.5 * sin(t * 7.3 + 1.7)
	_glow.modulate.a = GLOW_COLOR.a * (1.0 + GLOW_FLICKER * flicker)
	for entry in _sticks:
		entry[0].rotation = entry[1] + STICK_SWAY * sin(t * TAU / STICK_SWAY_SECS + entry[2])
