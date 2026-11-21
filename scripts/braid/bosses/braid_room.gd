extends RefCounted
## What every Braid boss (scripts/braid/bosses/) changes about where its
## arena-game self (scripts/bosses/) fights: all squads share one world in
## Braid, so the "map" is the convergence room past the lane mouths
## (BraidLevel.arena), there are no squad maps to stitch together, and
## positions need no converting. Each Braid boss overrides the objective's
## map hooks with these one-liners.


static func arena(boss: Node) -> Rect2:
	return boss.game.level.arena


static func outer_point(boss: Node, u: Vector2) -> Vector2:
	var rect := arena(boss)
	return rect.position + rect.size * u


## The part of the room near our squad's lane mouth: the first third of the
## room past the mouths, in the band of the lane our squad came in by.
static func near_our_mouth(boss: Node) -> Rect2:
	var room := arena(boss)
	var band: Rect2 = boss.game.level.band_rect(boss.game.my_lane())
	var top := maxf(band.position.y, room.position.y)
	var bottom := minf(band.end.y, room.end.y)
	return Rect2(room.position.x, top, room.size.x / 3.0, bottom - top)
