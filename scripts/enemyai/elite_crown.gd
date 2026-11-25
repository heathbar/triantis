extends Node2D
## The crown hovering over an elite enemy (added by ChasesPlayer.make_elite),
## bobbing gently GAP pixels above the top of its sprite. Drawn at 1:1 pixels
## whatever the enemy's own scale (elites are scaled up).
##
## A plain Node2D, not a Sprite2D, so enemy code that looks through its
## sprites (hit flash, tints) leaves it alone.

const TEXTURE := preload("res://assets/ui/elite_crown.png")
## Pixels between the top of the enemy's sprite and the crown's bottom.
const GAP := 2.0
## The bob: pixels up and down, and seconds for one.
const BOB_HEIGHT := 1.0
const BOB_PERIOD := 1.4

## Pixels from the enemy's origin to the top of its sprite (measured on the
## first frame, once its sprites are set up), or NAN until then.
var _top := NAN
var _time := randf() * BOB_PERIOD


func _ready() -> void:
	z_index = 2  # (above the enemies around it)


func _process(delta: float) -> void:
	var enemy := get_parent() as Node2D
	if enemy == null:
		return
	if is_nan(_top):
		_top = _sprite_top(enemy)
	_time += delta
	var bob := roundf(sin(_time * TAU / BOB_PERIOD) * BOB_HEIGHT)
	var lift := _top - GAP - TEXTURE.get_height() / 2.0 + bob
	var size := enemy.scale.abs()
	scale = Vector2(1.0 / maxf(size.x, 0.01), 1.0 / maxf(size.y, 0.01))
	position = Vector2(0.0, lift * scale.y)


func _draw() -> void:
	draw_texture(TEXTURE, -TEXTURE.get_size() / 2.0)


## How far above the enemy's origin its art reaches (screen pixels, negative
## is up): the highest sprite or colour rectangle under it, else its size.
static func _sprite_top(enemy: Node2D) -> float:
	var to_enemy := enemy.get_global_transform().affine_inverse()
	var top := INF
	for node in enemy.find_children("*", "CanvasItem", true, false):
		var rect := _local_rect(node)
		if rect.has_area() and (node as CanvasItem).visible:
			var xf: Transform2D = to_enemy * (node as CanvasItem).get_global_transform()
			top = minf(top, (xf * rect).position.y)
	if top == INF:
		var half: float = enemy.call("half_extent") if enemy.has_method("half_extent") else 12.0
		return -half
	return top * enemy.scale.abs().y


static func _local_rect(node: Node) -> Rect2:
	if node is Sprite2D:
		return (node as Sprite2D).get_rect()
	if node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(sprite.animation):
			return Rect2()
		var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		if tex == null:
			return Rect2()
		var size := tex.get_size()
		var at := sprite.offset - (size / 2.0 if sprite.centered else Vector2.ZERO)
		return Rect2(at, size)
	if node is ColorRect:
		return Rect2(Vector2.ZERO, (node as ColorRect).size)
	return Rect2()
