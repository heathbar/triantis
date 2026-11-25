extends Deployable
## Air Strike: marks a line `length` pixels long, starting just in front of
## the player and running the way they aim. After WARNING seconds `bombs`
## bombs fall along it one after another, each a blast (`radius`, `damage`,
## `knockback`). It never hurts players. Engineering raises the damage and
## the bomb count (scripts/equipment.gd).

const TargetMarker := preload("res://scripts/target_marker.gd")
## The aim marks blink between their art and this tint.
const BLINK_DIM := Color(0.6, 0.6, 0.6)
## Seconds the target line shows before the first bomb.
const WARNING := 0.9
## Seconds between bombs.
const BOMB_GAP := 0.08
## The line starts this far in front of the player.
const START_OFFSET := 40.0

## Where each bomb lands (world), in order.
var _targets: Array[Vector2] = []
var _clock := 0.0
var _dropped := 0


func _ready() -> void:
	super()
	z_index = 15
	var facing := Vector2.RIGHT
	var bounds := Rect2()
	if is_instance_valid(owner_player):
		facing = Vector2.from_angle(owner_player.body.rotation)
		bounds = owner_player.move_bounds
	var count := maxi(int(stats.get("bombs", 7)), 1)
	var start := global_position + facing * START_OFFSET
	for i in count:
		var p: Vector2 = start + facing * stats.get("length", 280.0) * (float(i) / maxf(count - 1, 1))
		if bounds.has_area():
			p = p.clamp(bounds.position, bounds.end)
		_targets.append(p)


func _tick(delta: float) -> void:
	_clock += delta
	while _dropped < _targets.size() and _clock >= WARNING + _dropped * BOMB_GAP:
		explode(_targets[_dropped], stats["radius"], int(stats["damage"]), stats.get("knockback", 0.0))
		_dropped += 1
	if _dropped >= _targets.size():
		expire()
		return
	queue_redraw()


func _draw() -> void:
	var lit := fmod(_clock, 0.2) < 0.1
	for i in range(_dropped, _targets.size()):
		var at := to_local(_targets[i])
		TargetMarker.draw(self, at, TargetMarker.AIM_SIZE / 2.0, Color.WHITE if lit else BLINK_DIM)
	# The plane's shadow sweeping along the line as the bombs fall.
	if _clock >= WARNING and _dropped < _targets.size():
		var at := to_local(_targets[_dropped])
		draw_rect(Rect2(at + Vector2(-10, -3), Vector2(20, 6)), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(at + Vector2(-3, -9), Vector2(6, 18)), Color(0, 0, 0, 0.35))
