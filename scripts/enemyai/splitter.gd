extends Enemy
## Splitter: an ordinary walker that bursts into `split_count` smaller
## enemies (child_scene, runners by default) when it dies. Elites burst into
## two more. The pieces are scaled like the rest of the wave and fly apart.
##
## child_scene needn't appear in any wave: the squads game finds it here
## (scripts/net/squad_link.gd's _add_kind).
##
## Drawn as a mole in its mound (the meadow's, the default), popping in and
## out (splitter-1a..c), or the theme's splitter-1.png (ActTheme): the
## scene's green ColorRect is swapped for a Sprite2D and the collision
## rectangle resized to the art. The mole bursts into jackrabbits (runners).

const ActTheme := preload("res://scripts/act_theme.gd")

## The pieces fly this far apart (pixels of knockback).
const SPLIT_KICK := 52.0
## Pieces appear this far from where it died.
const SPLIT_SPREAD := 10.0

## The default (meadow) mole's frames, played a, b, c, b..., and seconds each.
const FRAMES: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/splitter-1a.png"),
	preload("res://assets/meadow/enemies/splitter-1b.png"),
	preload("res://assets/meadow/enemies/splitter-1c.png"),
	preload("res://assets/meadow/enemies/splitter-1b.png"),
]
const FRAME_TIME := 0.22

@export var child_scene: PackedScene = preload("res://scenenodethings/enemies/runner.tscn")
@export var split_count := 3

var _frames: Array = []
var _anim := 0.0
var _sprite: Sprite2D


func _ready() -> void:
	var look := ActTheme.enemy_look("splitter")
	_frames = [look] if look else FRAMES
	var rect := get_node_or_null("ColorRect")
	if rect:
		remove_child(rect)
		rect.free()
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	add_child(_sprite)
	ActTheme.apply_look(self, _frames[0])
	if is_elite:  # (made elite before it entered the tree)
		_sprite.self_modulate = elite_color
	super()
	_anim = randf() * FRAME_TIME * _frames.size()


func _process(delta: float) -> void:
	_anim += delta
	_sprite.texture = ActTheme.frame_at(_frames, _anim, FRAME_TIME)
	# The art faces right: mirrored while heading left.
	var facing := facing_x()
	if facing != 0.0:
		_sprite.flip_h = facing < 0.0


## Elites with art tint the sprite (the base class recolours the ColorRect).
## self_modulate, so it stacks with the Freeze Ray's modulate.
func make_elite(scaling: PlayerScaling) -> void:
	super(scaling)
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.self_modulate = elite_color


func _on_death(_killer: Node) -> void:
	var game := get_parent() as GameBase
	if child_scene == null or game == null:
		return
	var count := split_count + (2 if is_elite else 0)
	var start := randf() * TAU
	for i in count:
		var dir := Vector2.from_angle(start + TAU * i / count)
		# Deferred: it may be dying in the middle of a physics query.
		game.spawn_enemy_at.call_deferred(child_scene, global_position + dir * SPLIT_SPREAD,
			false, dir * SPLIT_KICK)
