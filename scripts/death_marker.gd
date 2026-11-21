extends Node2D
## A big "X" drawn over a knocked-out player.

var color := Color.WHITE
var size := 18.0
var thickness := 4.0
var outline := 2.0


func _ready() -> void:
	z_index = 100
	# Pop in so it's noticeable.
	scale = Vector2(1.6, 1.6)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var h := size / 2.0
	var a := [Vector2(-h, -h), Vector2(h, h)]
	var b := [Vector2(h, -h), Vector2(-h, h)]
	# Dark outline first so the X reads against any background.
	for line in [a, b]:
		draw_line(line[0], line[1], Color.BLACK, thickness + outline * 2.0)
		draw_circle(line[0], (thickness + outline * 2.0) / 2.0, Color.BLACK)
		draw_circle(line[1], (thickness + outline * 2.0) / 2.0, Color.BLACK)
	for line in [a, b]:
		draw_line(line[0], line[1], color, thickness)
		draw_circle(line[0], thickness / 2.0, color)
		draw_circle(line[1], thickness / 2.0, color)
