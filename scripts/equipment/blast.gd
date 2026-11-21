extends Node2D
## An explosion: an expanding, fading orange disc. Purely visual (the damage
## is dealt by Deployable.explode in scripts/equipment/deployable.gd).

const DURATION := 0.35

var radius := 60.0
var _age := 0.0


func _ready() -> void:
	add_to_group("deployables")  # Cleared with the rest when the wave ends.
	z_index = 20


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _age / DURATION
	draw_circle(Vector2.ZERO, radius * (0.4 + 0.6 * t), Color(1.0, 0.55, 0.1, 0.55 * (1.0 - t)))
	draw_circle(Vector2.ZERO, radius * 0.5 * (0.4 + 0.6 * t), Color(1.0, 0.9, 0.4, 0.7 * (1.0 - t)))
