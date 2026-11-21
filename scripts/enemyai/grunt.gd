extends Enemy
## Grunt: a plain chaser, drawn as an apple, orange or lime, picked at random
## per grunt. The collision rectangle is resized to the picked image's opaque
## pixels (the orange and lime have a transparent margin), and the Sprite2D is
## uncentered with a whole-pixel offset that centres those pixels on the
## grunt, so odd sizes don't land on half pixels.

const ActTheme := preload("res://scripts/act_theme.gd")

const LOOKS: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/grunt-1.png"),
	preload("res://assets/meadow/enemies/grunt-2.png"),
	preload("res://assets/meadow/enemies/grunt-3.png"),
]

var _sprite: Sprite2D


func _ready() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite:
		# Act-themed art (Braid act 2: fish), else a fruit.
		var texture: Texture2D = ActTheme.enemy_look("grunt")
		if texture == null:
			texture = LOOKS.pick_random()
		ActTheme.apply_look(self, texture)
	super()


## Elites tint the sprite (there's no ColorRect for the base class to recolour).
## self_modulate, so it stacks with the Freeze Ray's modulate.
func make_elite(scaling: PlayerScaling) -> void:
	super(scaling)
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.self_modulate = elite_color


func _process(_delta: float) -> void:
	if _sprite == null:
		return
	# The art faces right: mirror it while heading left. Face the way it's
	# walking, not the way a hit knocked it (see facing_x).
	var facing := facing_x()
	if facing != 0.0:
		_sprite.flip_h = facing < 0.0
