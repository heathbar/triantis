extends Enemy
## Grunt: a plain chaser, drawn as a meadow beetle scuttling through its walk
## frames (grunt-1a..f). Act-themed art (ActTheme) is one still image picked
## at random. The collision rectangle is resized to the art's opaque pixels,
## and the Sprite2D is uncentered with a whole-pixel offset that centres those
## pixels on the grunt, so odd sizes don't land on half pixels.

const ActTheme := preload("res://scripts/act_theme.gd")

## The default (meadow) walk frames: one body, its six legs stepping in two
## alternating tripods (front + rear on the near side with the middle on the
## far side, then the others), each foot planted for 4 frames and swung
## forward for 2.
const FRAMES: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/grunt-1a.png"),
	preload("res://assets/meadow/enemies/grunt-1b.png"),
	preload("res://assets/meadow/enemies/grunt-1c.png"),
	preload("res://assets/meadow/enemies/grunt-1d.png"),
	preload("res://assets/meadow/enemies/grunt-1e.png"),
	preload("res://assets/meadow/enemies/grunt-1f.png"),
]
## Seconds per walk frame (a scurry: quick little steps).
const FRAME_TIME := 0.07

var _sprite: Sprite2D
var _frames: Array = []
var _walk := 0.0


func _ready() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite:
		# Act-themed art (Braid act 2: fish), else the beetle's walk.
		var texture: Texture2D = ActTheme.enemy_look("grunt")
		_frames = [texture] if texture else FRAMES
		ActTheme.apply_look(self, _frames[0])
	super()
	# Out of step with the others.
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
