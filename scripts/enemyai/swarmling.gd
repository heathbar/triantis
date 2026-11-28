extends Enemy
## Swarmling: a plain chaser drawn as a grape wasp, looping through its
## wing-beat frames (swarmling-1a..c). Act-themed art may differ in size, so
## the collision rectangle is resized to match. The Sprite2D is uncentered
## with a whole-pixel offset, so odd sizes don't land on half pixels.

const ActTheme := preload("res://scripts/act_theme.gd")

## The default (meadow) wing-beat frames.
const FRAMES: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/swarmling-1a.png"),
	preload("res://assets/meadow/enemies/swarmling-1b.png"),
	preload("res://assets/meadow/enemies/swarmling-1c.png"),
]
## Seconds per frame.
const FRAME_TIME := 0.06

var _walk := 0.0
var _sprite: Sprite2D
## Its frames: FRAMES, or one still act-themed image.
var _frames: Array = []


func _ready() -> void:
	# Act-themed art (Braid act 2: one still shrimp, no walk frames), else the wasp.
	var themed := ActTheme.enemy_look("swarmling")
	_frames = [themed] if themed else FRAMES
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite:
		var texture: Texture2D = _frames[0]
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
	# Start each one at a random point in the cycle so a swarm doesn't step
	# in lockstep.
	_walk = randf() * FRAME_TIME * _frames.size()


## Elites tint the sprite (there's no ColorRect for the base class to recolour).
## self_modulate, so it stacks with the Freeze Ray's modulate.
func make_elite(scaling: PlayerScaling) -> void:
	super(scaling)
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.self_modulate = elite_color


func _process(delta: float) -> void:
	if _sprite == null:
		return
	# The art faces right: mirror it while heading left. Face the way it's
	# walking, not the way a hit knocked it (see facing_x).
	var facing := facing_x()
	if facing != 0.0:
		_sprite.flip_h = facing < 0.0
	_walk += delta
	_sprite.texture = ActTheme.frame_at(_frames, _walk, FRAME_TIME)
