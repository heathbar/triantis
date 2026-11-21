extends Node2D
## Another squad's player, shown on our map while they're in a strip our maps
## share (scripts/net/squad_link.gd moves it). It's only a picture: it doesn't
## collide with anything or collect pickups. Our enemies chase it while it's
## alive and on our map (group "remote_players"); whether they hurt it is up to
## its own game.

const PLAYER_SCENE := preload("res://scenenodethings/player.tscn")
const DeathMarker := preload("res://scripts/death_marker.gd")
const NetFollow := preload("res://scripts/net/net_follow.gd")

## Drawn this far past our map's edge, so it slides out of view instead of
## vanishing while still partly on the grass.
const VISIBLE_MARGIN := 20.0

## Our map. The player can't be chased while off it, and isn't drawn far off it.
var map_bounds := Rect2()
## When we last heard about this player (squad_link.gd's clock), so the link
## can drop players it stops hearing about.
var heard_at := 0.0

var _body: ColorRect
var _sprite: Sprite2D
var _gun: Sprite2D
var _gun_id := ""
var _color := Color.WHITE
var _alive := true
var _marker: Node2D
var _follow := NetFollow.new()


func _init() -> void:
	# Borrow the player scene's look (square, art and gun) without its script.
	var template := PLAYER_SCENE.instantiate()
	_body = template.get_node("ColorRect")
	_sprite = template.get_node("Sprite")
	_gun = template.get_node("Gun")
	for part: Node in [_body, _sprite, _gun]:
		template.remove_child(part)
		part.owner = null
		add_child(part)
	template.free()
	# Rotate the square around the player's centre, like the real thing.
	_body.pivot_offset = -_body.position


func setup(color: Color, skin: int) -> void:
	_color = color
	_body.color = color
	_sprite.armor_color = color
	_sprite.skin = skin


## The latest state from the player's own game (position in our coordinates).
## `gun_id`: the gun they hold ("" leaves the one shown).
func apply(pos: Vector2, aim: float, alive: bool, gun_id := "") -> void:
	if _follow.report(pos):
		position = pos
	_body.rotation = aim
	_sprite.face(aim)
	_gun.aim(aim)
	if gun_id != _gun_id:
		_gun_id = gun_id
		if gun_id != "":
			_gun.show_gun_id(gun_id)
	if alive != _alive:
		_set_alive(alive)


func is_alive() -> bool:
	return _alive


func _physics_process(delta: float) -> void:
	position = _follow.step(position, delta)
	visible = map_bounds.grow(VISIBLE_MARGIN).has_point(position)
	var chaseable := _alive and map_bounds.has_point(position)
	if chaseable != is_in_group("remote_players"):
		if chaseable:
			add_to_group("remote_players")
		else:
			remove_from_group("remote_players")


## Knocked out (dim, with an X like our own players) or back on their feet.
func _set_alive(alive: bool) -> void:
	_alive = alive
	_sprite.dimmed = not alive
	_gun.set_dimmed(not alive)
	if is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	if not alive:
		_marker = DeathMarker.new()
		_marker.color = _color
		add_child(_marker)
