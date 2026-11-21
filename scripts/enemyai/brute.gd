extends Enemy
## Brute: a slow, tough chaser, drawn as a coconut (36x40). The collision
## rectangle in brute.tscn matches the image. In Braid act 2 it's a hermit
## crab instead (ActTheme), with the rectangle resized to match.

const ActTheme := preload("res://scripts/act_theme.gd")

var _themed := false


func _ready() -> void:
	var look := ActTheme.enemy_look("brute")
	if look:
		ActTheme.apply_look(self, look)
		_themed = true
	super()


## Elites tint the sprite (there's no ColorRect for the base class to recolour).
## self_modulate, so it stacks with the Freeze Ray's modulate.
func make_elite(scaling: PlayerScaling) -> void:
	super(scaling)
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.self_modulate = elite_color


func _process(_delta: float) -> void:
	# Themed art faces right: mirror it while heading left. (The coconut is
	# round, so it never turns.)
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or not _themed:
		return
	var facing := facing_x()
	if facing != 0.0:
		sprite.flip_h = facing < 0.0
