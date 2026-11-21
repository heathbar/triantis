extends Deployable
## Land Mine: lies where it was placed until an enemy steps on it, then
## explodes, hurting (and shoving) every enemy within `radius`. No time
## limit; it's cleared when the wave ends. Engineering raises its blast
## radius and damage (scripts/equipment.gd).

## Seconds after placing before it can go off.
const ARM_TIME := 0.6
## An enemy this close to the mine (past its body's edge) sets it off.
const TRIGGER_RADIUS := 9.0
const TEXTURE := preload("res://assets/weapons/equipment/land_mine.png")
## The art's red light, relative to where draw_centered puts the texture's
## middle: covered over while the light blinks off.
const LIGHT_PIXELS: Array[Vector2] = [Vector2(-1, -1), Vector2(0, -2)]
const LIGHT_OFF := Color(0.35, 0.05, 0.05)

var _armed_in := ARM_TIME
var _blink := 0.0


func _ready() -> void:
	super()


func _tick(delta: float) -> void:
	_blink += delta
	_armed_in = maxf(_armed_in - delta, 0.0)
	if _armed_in == 0.0 and not enemies_within(global_position, TRIGGER_RADIUS).is_empty():
		_explode()
		return
	queue_redraw()


func _explode() -> void:
	explode(global_position, stats["radius"], int(stats["damage"]), stats.get("knockback", 0.0))
	expire()


func _draw() -> void:
	draw_centered(TEXTURE)
	# Red light: steady while arming, then blinking.
	var lit := _armed_in > 0.0 or fmod(_blink, 0.8) < 0.4
	if not lit:
		for p in LIGHT_PIXELS:
			draw_rect(Rect2(p, Vector2.ONE), LIGHT_OFF)

