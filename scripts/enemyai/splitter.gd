extends Enemy
## Splitter: an ordinary walker that bursts into `split_count` smaller
## enemies (child_scene, runners by default) when it dies. Elites burst into
## two more. The pieces are scaled like the rest of the wave and fly apart.
##
## child_scene needn't appear in any wave: the squads game finds it here
## (scripts/net/squad_link.gd's _add_kind).
##
## Drawn as a green ColorRect, or in Braid act 2 as a sea urchin (ActTheme):
## the rect is swapped for a Sprite2D and the collision rectangle resized.

const ActTheme := preload("res://scripts/act_theme.gd")

## The pieces fly this far apart (pixels of knockback).
const SPLIT_KICK := 52.0
## Pieces appear this far from where it died.
const SPLIT_SPREAD := 10.0

@export var child_scene: PackedScene = preload("res://scenenodethings/enemies/runner.tscn")
@export var split_count := 3


func _ready() -> void:
	var look := ActTheme.enemy_look("splitter")
	if look:
		var rect := get_node_or_null("ColorRect")
		if rect:
			remove_child(rect)
			rect.free()
		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)
		ActTheme.apply_look(self, look)
		if is_elite:  # (made elite before it entered the tree)
			sprite.self_modulate = elite_color
	super()


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
