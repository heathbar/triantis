extends Control
## The resource symbol: a dark blue dot with a white rim, the same as the
## pickups in the world (scripts/resource_pickup.gd). COLOR is also the
## colour resource numbers are written in.

const COLOR := Color(0.08, 0.3, 0.8)
const STROKE_COLOR := Color.WHITE

## Diameter of the dot, not counting the rim.
var diameter := 30.0
var stroke := 4.0


func _init(dot_diameter: float = 30.0) -> void:
	diameter = dot_diameter
	stroke = maxf(roundf(dot_diameter * 0.13), 2.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2.ONE * (diameter + stroke * 2.0)


func _draw() -> void:
	draw_dot(self, size / 2.0, diameter / 2.0, stroke)


## A resource dot of `radius` (plus a `stroke`-wide white rim) at `center`.
static func draw_dot(canvas: CanvasItem, center: Vector2, radius: float, rim: float) -> void:
	canvas.draw_circle(center, radius + rim, STROKE_COLOR)
	canvas.draw_circle(center, radius, COLOR)
