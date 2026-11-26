extends Node2D
## An explosion (scripts/explosion_art.gd), its fireball `radius` across.
## Purely visual (the damage is dealt by Deployable.explode in
## scripts/equipment/deployable.gd, a bomber, the hot potato...).

const ExplosionArt := preload("res://scripts/explosion_art.gd")

var radius := 60.0
var _age := 0.0


func _ready() -> void:
	add_to_group("deployables")  # Cleared with the rest when the wave ends.
	z_index = 20


func _process(delta: float) -> void:
	_age += delta
	if _age >= ExplosionArt.DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	ExplosionArt.draw(self, Vector2.ZERO, _age, radius)
