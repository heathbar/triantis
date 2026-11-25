extends "res://scripts/bosses/crusher.gd"
## The Crusher in a Braid convergence room (scripts/braid/braid_game.gd):
## the arena's Crusher (scripts/bosses/crusher.gd) with the map hooks pointed
## at the room (scripts/braid/bosses/braid_room.gd). It can't drive into the
## lane mouths, so they're cover, and their ends are walls it can crash into.

const BraidRoom := preload("res://scripts/braid/bosses/braid_room.gd")
const BraidBossMortars := preload("res://scripts/braid/bosses/braid_boss_mortars.gd")
const BraidModifiers := preload("res://scripts/braid/braid_modifiers.gd")


func map_rect() -> Rect2:
	return BraidRoom.arena(self)


func shared_centre() -> Vector2:
	return BraidRoom.arena(self).get_center()


func squad_map_shared(_squad: int) -> Rect2:
	return BraidRoom.arena(self)


func own_area() -> Rect2:
	return BraidRoom.arena(self).grow(-EDGE_INSET)


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
