extends Sprite2D
## The player's character art (a skin from scripts/player/player_skins.gd) with
## the green armour palette-swapped to the character's colour
## (scripts/player/armor_swap.gdshader). The skin is only a look: each is drawn
## at its art's own size (1 texture pixel = 1 world pixel) and doesn't touch
## the hitbox.
## Stays upright and flips left/right to face the aim, while the player's
## (invisible) square and the gun (player_gun.gd) do the rotating.
## Used by the player scene (scenenodethings/player.tscn) and remote squad
## players (scripts/net/remote_player.gd).

const PlayerSkins := preload("res://scripts/player/player_skins.gd")
const SHADER := preload("res://scripts/player/armor_swap.gdshader")
## Brightness of a knocked-out player (like the old square's darkened(0.7)).
const DEAD_BRIGHTNESS := 0.3
## How strongly a flash covers the art (1 = a solid silhouette).
const FLASH_STRENGTH := 0.8

## Index into PlayerSkins.SKINS.
var skin := 0:
	set(value):
		skin = value
		_apply_skin()
var armor_color := Color.WHITE:
	set(value):
		armor_color = value
		_material.set_shader_parameter("armor_color", value)
var dimmed := false:
	set(value):
		dimmed = value
		_material.set_shader_parameter("brightness", DEAD_BRIGHTNESS if value else 1.0)

var _material := ShaderMaterial.new()
var _flash_tween: Tween
var _facing_left := false


func _init() -> void:
	_material.shader = SHADER
	material = _material
	# Placed by _place() instead: centring an odd-sized picture puts its edges
	# on half pixels, where nearest-neighbour sampling flickers between a
	# pixel and its (often transparent) neighbour as the player moves.
	centered = false
	_apply_skin()


func _apply_skin() -> void:
	texture = PlayerSkins.texture(skin)
	_place()


## Faces right for aims pointing right of straight up/down, else left.
func face(angle: float) -> void:
	_facing_left = cos(angle) < -0.01
	_place()


func _place() -> void:
	flip_h = _facing_left
	# Keep the figure (not the PNG) centred on the player either way round,
	# on whole pixels (see _init).
	var centre := PlayerSkins.art_rect(skin).get_center()
	if _facing_left:
		centre.x = texture.get_width() - centre.x
	offset = (-centre).round()


## Briefly washes the art in `color`, then fades back.
func flash(color: Color, hold: float, fade: float) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_material.set_shader_parameter("flash_color", color)
	_set_flash(FLASH_STRENGTH)
	_flash_tween = create_tween()
	_flash_tween.tween_interval(hold)
	_flash_tween.tween_method(_set_flash, FLASH_STRENGTH, 0.0, fade)


func clear_flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_set_flash(0.0)


func _set_flash(amount: float) -> void:
	_material.set_shader_parameter("flash_amount", amount)


## A material for showing the art in UI (a TextureRect), e.g. character select.
static func make_material(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("armor_color", color)
	return m
