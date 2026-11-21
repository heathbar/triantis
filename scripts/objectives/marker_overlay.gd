extends CanvasLayer
## Arrows at the screen edge pointing at an objective's markers()
## (scripts/objectives/objective.gd) that are off screen.

const INSET := 90.0
const SIZE := 46.0

var objective: Node2D
var _canvas: Control


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_arrows)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _draw_arrows() -> void:
	if not is_instance_valid(objective):
		return
	# The world is drawn in the game's pixel-art view, not this viewport.
	var game: Node2D = objective.game
	var view: Rect2 = game.world_view_rect()
	var to_screen: Transform2D = game.world_to_ui()
	var inner := view.grow(-INSET)
	var middle := view.get_center()
	for marker: Array in objective.markers():
		var at: Vector2 = to_screen * (marker[0] as Vector2)
		if view.grow(-20.0).has_point(at):
			continue
		var dir := middle.direction_to(at)
		# Where the line from the middle to the marker leaves the inner rect.
		var t := INF
		if dir.x != 0.0:
			t = minf(t, ((inner.end.x if dir.x > 0 else inner.position.x) - middle.x) / dir.x)
		if dir.y != 0.0:
			t = minf(t, ((inner.end.y if dir.y > 0 else inner.position.y) - middle.y) / dir.y)
		var tip := middle + dir * t
		var side := dir.orthogonal() * SIZE * 0.6
		var arrow := PackedVector2Array([tip + dir * SIZE * 0.5, tip - dir * SIZE * 0.5 + side,
			tip - dir * SIZE * 0.5 - side])
		_canvas.draw_colored_polygon(arrow, marker[1])
		_canvas.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.BLACK, 4.0)
