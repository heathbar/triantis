extends Control
## A horizontal bar for one attribute (-100 .. +100): centred at 0, filling
## right (green) for positive values and left (red) for negative ones.

const POSITIVE_COLOR := Color(0.35, 0.9, 0.4)
const NEGATIVE_COLOR := Color(1.0, 0.4, 0.35)

## The empty bar behind the fill.
var track_color := Color(1, 1, 1, 0.08)

var value := 0:
	set(v):
		value = v
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), track_color)
	var mid := size.x / 2.0
	var w := mid * absf(clampf(value / 100.0, -1.0, 1.0))
	var x := mid if value >= 0 else mid - w
	draw_rect(Rect2(x, 0, w, size.y), POSITIVE_COLOR if value >= 0 else NEGATIVE_COLOR)
	draw_rect(Rect2(mid - 2, -4, 4, size.y + 8), Color(1, 1, 1, 0.6))
