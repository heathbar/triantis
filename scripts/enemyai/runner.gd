extends Enemy
## Runner: a plain chaser, drawn as fries or a burger, picked at random per
## runner. The two images differ in size (17x20 and 21x20), so the collision
## rectangle is resized to match whichever one it got. The Sprite2D is
## uncentered with a whole-pixel offset, so odd sizes don't land on half
## pixels.

const ActTheme := preload("res://scripts/act_theme.gd")

const LOOKS: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/runner-1.png"),
	preload("res://assets/meadow/enemies/runner-2.png"),
]

var _sprite: Sprite2D


func _ready() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite:
		# Act-themed art (Braid act 2: a tuna), else fries or a burger.
		var texture: Texture2D = ActTheme.enemy_look("runner")
		if texture == null:
			texture = LOOKS.pick_random()
		var size := texture.get_size()
		var offset := -(size / 2.0).floor()
		_sprite.texture = texture
		_sprite.offset = offset
		var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape_node:
			var rect := RectangleShape2D.new()  # Own copy: the scene's is shared.
			rect.size = size
			shape_node.shape = rect
			shape_node.position = offset + size / 2.0
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
