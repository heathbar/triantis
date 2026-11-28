extends Enemy
## Brute: a slow, tough chaser, drawn as a mossy stone golem (dark-outlined
## so it stands out on the grass) stomping through its walk (brute-1a..f):
## each foot lifts in turn while the body leans onto the other leg, and it
## sinks a pixel as each foot lands, arms swinging. Act-themed art (ActTheme:
## Braid act 2's hermit crab...) is one still image. The collision rectangle
## is resized to the art either way, and the art faces right: it's mirrored
## to face left.

const ActTheme := preload("res://scripts/act_theme.gd")

## The default (meadow) walk frames.
const FRAMES: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/brute-1a.png"),
	preload("res://assets/meadow/enemies/brute-1b.png"),
	preload("res://assets/meadow/enemies/brute-1c.png"),
	preload("res://assets/meadow/enemies/brute-1d.png"),
	preload("res://assets/meadow/enemies/brute-1e.png"),
	preload("res://assets/meadow/enemies/brute-1f.png"),
]
## Seconds per walk frame (one stride is 6 frames: slow and heavy).
const FRAME_TIME := 0.16

var _frames: Array = []
var _walk := 0.0


func _ready() -> void:
	var look := ActTheme.enemy_look("brute")
	_frames = [look] if look else FRAMES
	ActTheme.apply_look(self, _frames[0])
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
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	_walk += delta
	sprite.texture = ActTheme.frame_at(_frames, _walk, FRAME_TIME)
	# Mirrored while heading left.
	var facing := facing_x()
	if facing != 0.0:
		sprite.flip_h = facing < 0.0
