extends Node2D
## Short-lived effect pictures for Braid Class Mods: a ring (a burst),
## a line (a chain jump). Each fades out and frees itself. Use the static
## helpers: BraidFxVisuals.ring(parent, at, radius, colour), .line(...).

const LIFE := 0.25

var kind := "ring"
var radius := 10.0
var to := Vector2.ZERO
var color := Color.WHITE
var _t := 0.0


static func ring(parent: Node, at: Vector2, r: float, c: Color) -> void:
	var fx: Variant = load("res://scripts/braid/braid_fx_visuals.gd").new()
	fx.kind = "ring"
	fx.radius = r
	fx.color = c
	fx.position = at
	parent.add_child(fx)


static func line(parent: Node, a: Vector2, b: Vector2, c: Color) -> void:
	var fx: Variant = load("res://scripts/braid/braid_fx_visuals.gd").new()
	fx.kind = "line"
	fx.to = b - a
	fx.color = c
	fx.position = a
	parent.add_child(fx)


func _ready() -> void:
	z_index = 20


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var c := Color(color, 1.0 - _t / LIFE)
	if kind == "ring":
		draw_arc(Vector2.ZERO, radius * (0.6 + 0.4 * _t / LIFE), 0.0, TAU, 24, c, 2.0)
	else:
		# A jagged bolt.
		var points := PackedVector2Array([Vector2.ZERO])
		var n := 4
		for i in range(1, n):
			var p := to * float(i) / n
			points.append(p + to.orthogonal().normalized() * randf_range(-4.0, 4.0))
		points.append(to)
		draw_polyline(points, c, 1.5)
