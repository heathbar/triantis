extends RefCounted
## Turns positions that arrive in network updates (about 20 a second, see
## scripts/net/squad_link.gd) into smooth movement: it keeps going at the last
## known velocity for a moment, and eases toward where that says it should be.

## Expected time between updates (seconds); squad_link.gd's SEND_INTERVAL.
const UPDATE_INTERVAL := 0.05
## Stop extrapolating if no update arrives for this long (seconds).
const MAX_EXTRAPOLATION := 0.15
## Further than this from where it should be: jump there instead of sliding.
const SNAP_DISTANCE := 400.0
## How quickly the drawn position catches up (higher = snappier).
const EASE := 18.0

var _reported := Vector2.ZERO
var _velocity := Vector2.ZERO
var _since := 0.0
var _started := false


## A new position arrived. Returns true for the very first one, which should
## be used as-is (nothing to ease from yet).
func report(pos: Vector2) -> bool:
	var first := not _started
	if _started:
		# Updates can bunch up; don't let two close together fake a huge speed.
		_velocity = (pos - _reported) / clampf(_since, UPDATE_INTERVAL * 0.8, 0.25)
	_reported = pos
	_since = 0.0
	_started = true
	return first


## Where to draw it this frame, given where it's drawn now.
func step(current: Vector2, delta: float) -> Vector2:
	_since += delta
	var target := _reported + _velocity * minf(_since, MAX_EXTRAPOLATION)
	if current.distance_to(target) > SNAP_DISTANCE:
		return target
	return current.lerp(target, 1.0 - exp(-EASE * delta))
