extends Enemy
## Saboteur: ignores players while there's equipment to wreck. It goes for
## the nearest placed equipment it can see (anything whose
## can_be_sabotaged() is true: turrets, coils, barricades, decoys, traps,
## bubbles, wells; scripts/equipment/deployable.gd) and wrecks it after
## Deployable.WRECK_TIME seconds next to it. With nothing to wreck it chases
## players like anyone else.

## Notices equipment this far away.
const SIGHT := 360.0
## Close enough to wreck: this far past its own half size from the
## equipment's centre (or pushed up against a barricade).
const REACH := 14.0
const SPARK_COLOR := Color(1.0, 1.0, 1.0)

var _wrecking := false
var _blink := 0.0


func _pick_target() -> Node2D:
	var best: Node2D = null
	var best_dist := SIGHT * SIGHT
	for thing in _group(&"deployables"):
		if not is_instance_valid(thing) or not thing is Deployable or not thing.can_be_sabotaged() \
				or thing.is_queued_for_deletion():
			continue
		var d := global_position.distance_squared_to(thing.global_position)
		if d < best_dist:
			best_dist = d
			best = thing
	return best if best else super()


func _desired_velocity(target: Node2D, delta: float) -> Vector2:
	if target is Deployable and _in_reach(target):
		return Vector2.ZERO
	return super(target, delta)


func _after_move(delta: float) -> void:
	var target := _pick_target()
	_wrecking = target is Deployable and (_in_reach(target) or _pressed_against(target))
	if _wrecking:
		target.sabotage(delta)


func _in_reach(target: Node2D) -> bool:
	return global_position.distance_to(target.global_position) <= half_extent() + REACH


## Pushing on a part of `target` (a barricade's wall).
func _pressed_against(target: Node2D) -> bool:
	for i in get_slide_collision_count():
		var body := get_slide_collision(i).get_collider() as Node
		if body and body.get_parent() == target:
			return true
	return false


func net_state() -> int:
	return 1 if _wrecking else 0


func mirror_state(state: int) -> void:
	_wrecking = state == 1


func _process(delta: float) -> void:
	var rect := get_node_or_null("ColorRect") as ColorRect
	if rect == null:
		return
	if _wrecking:
		_blink += delta
		rect.color = SPARK_COLOR if fmod(_blink, 0.14) < 0.07 else base_color()
	else:
		rect.color = base_color()
