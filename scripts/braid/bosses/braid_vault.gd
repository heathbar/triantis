extends "res://scripts/bosses/vault.gd"
## The Vault in a Braid convergence room (scripts/braid/braid_game.gd): the
## arena's Vault (scripts/bosses/vault.gd) with the map hooks pointed at the
## room (scripts/braid/bosses/braid_room.gd). The wall is sized to the
## room, and in a squads game each squad's lock or keypad is on its own side
## of it, picked by its lane (BRAID_SIDES): the top lane's squad gets the
## north side, the bottom lane's the south, the ones between west then east.

const BraidRoom := preload("res://scripts/braid/bosses/braid_room.gd")
const BraidBossMortars := preload("res://scripts/braid/bosses/braid_boss_mortars.gd")
const BraidModifiers := preload("res://scripts/braid/braid_modifiers.gd")


func map_rect() -> Rect2:
	return BraidRoom.arena(self)


func shared_centre() -> Vector2:
	return BraidRoom.arena(self).get_center()


func squad_map_shared(_squad: int) -> Rect2:
	return BraidRoom.arena(self)


## The sides (SIDES) by lane, for each number of lanes.
const BRAID_SIDES := {2: [0, 2], 3: [0, 3, 2], 4: [0, 3, 1, 2]}


func _squad_side() -> int:
	if not squads_game:
		return -1
	var sides: Array = BRAID_SIDES.get(game.level.lanes, [])
	var lane: int = game.my_lane()
	if lane < 0 or lane >= sides.size():
		return -1
	return sides[lane]


func outer_point(_squad: int, u: Vector2) -> Vector2:
	return BraidRoom.outer_point(self, u)


func to_local_pos(shared_pos: Vector2) -> Vector2:
	return shared_pos


func to_shared_pos(local_pos: Vector2) -> Vector2:
	return local_pos


# --- Tyrants modifier (scripts/braid/braid_modifiers.gd) --------------------------

## Its mortar volleys while the Tyrants modifier is on (else null).
var mortars: BraidBossMortars


func boss_begin() -> void:
	super()
	if BraidModifiers.is_on("tyrants"):
		mortars = BraidBossMortars.new()


func boss_tick(delta: float) -> void:
	super(delta)
	if mortars:
		mortars.tick(self)


## (Shells are played out whether or not this copy fires them: a joiner's
## come from the host.)
func hazard_tick(h: Dictionary, delta: float) -> void:
	if not BraidBossMortars.hazard_tick(self, h):
		super(h, delta)


func draw_hazard(h: Dictionary) -> void:
	if not BraidBossMortars.draw(self, h):
		super(h)
