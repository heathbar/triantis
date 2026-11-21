extends "res://scripts/bosses/vault.gd"
## The Vault in a Braid convergence room (scripts/braid/braid_game.gd): the
## arena's Vault (scripts/bosses/vault.gd) with the map hooks pointed at the
## room (scripts/braid/bosses/braid_room.gd). Each squad's keypad turns up
## near its own lane mouth (own_area), so every squad has one close by.

const BraidRoom := preload("res://scripts/braid/bosses/braid_room.gd")


func map_rect() -> Rect2:
	return BraidRoom.arena(self)


func shared_centre() -> Vector2:
	return BraidRoom.arena(self).get_center()


func squad_map_shared(_squad: int) -> Rect2:
	return BraidRoom.arena(self)


func own_area() -> Rect2:
	return BraidRoom.near_our_mouth(self).grow(-KEYPAD_REACH)


func outer_point(_squad: int, u: Vector2) -> Vector2:
	return BraidRoom.outer_point(self, u)


func to_local_pos(shared_pos: Vector2) -> Vector2:
	return shared_pos


func to_shared_pos(local_pos: Vector2) -> Vector2:
	return local_pos
