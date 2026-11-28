extends Enemy
## Runner: a plain chaser, drawn as a jackrabbit (dark-outlined so it stands
## out on the grass) bounding through its run frames (runner-1a..f). Act-themed art (ActTheme) is one still image. The
## collision rectangle is resized to match the art. The Sprite2D is
## uncentered with a whole-pixel offset, so odd sizes don't land on half
## pixels. (The meadow splitter's mole bursts into these.)

const ActTheme := preload("res://scripts/act_theme.gd")

## The default (meadow) run frames.
const FRAMES: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/runner-1a.png"),
	preload("res://assets/meadow/enemies/runner-1b.png"),
	preload("res://assets/meadow/enemies/runner-1c.png"),
	preload("res://assets/meadow/enemies/runner-1d.png"),
	preload("res://assets/meadow/enemies/runner-1e.png"),
	preload("res://assets/meadow/enemies/runner-1f.png"),
]
## Seconds per run frame.
const FRAME_TIME := 0.07

var _sprite: Sprite2D
var _frames: Array = []
var _walk := 0.0


func _ready() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite:
		# Act-themed art (Braid act 2: a tuna), else the jackrabbit.
		var themed: Texture2D = ActTheme.enemy_look("runner")
		_frames = [themed] if themed else FRAMES
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
	_walk += delta
	_sprite.texture = ActTheme.frame_at(_frames, _walk, FRAME_TIME)
	# The art faces right: mirror it while heading left. Face the way it's
	# walking, not the way a hit knocked it (see facing_x).
	var facing := facing_x()
	if facing != 0.0:
		_sprite.flip_h = facing < 0.0
