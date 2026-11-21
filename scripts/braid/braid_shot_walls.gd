extends Node
## Braid mode: stops shots at walls. Projectiles (scripts/projectile.gd) only
## look for enemies, so before they move each physics frame this checks each
## one's step against the walls (BraidTuning.WALL_LAYER) and removes any shot
## that would hit a wall before an enemy.

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")


func _ready() -> void:
	# Before the projectiles' own _physics_process (lower runs first).
	process_physics_priority = -100


func _physics_process(delta: float) -> void:
	var space := get_viewport().world_2d.direct_space_state
	for shot: Node2D in get_tree().get_nodes_in_group("projectiles"):
		# (Other squads' shots, shown just for show, stop at walls too.)
		if shot.is_queued_for_deletion():
			continue
		# A modded Mortar rivet arcs over walls.
		if shot.has_method("is_mortar") and shot.is_mortar():
			continue
		# A modded Shockwave goes through walls into the next lane.
		if shot.get("through_walls"):
			continue
		var from := shot.global_position
		var to: Vector2 = from + shot.direction * shot.speed * delta
		var query := PhysicsRayQueryParameters2D.create(from, to, BraidTuning.WALL_LAYER)
		query.hit_from_inside = true  # fired with the muzzle in a wall
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		# An enemy in front of the wall still gets hit (the shot does that itself).
		if shot.has_method("_find_hit") and shot._find_hit(from, hit["position"]) != null:
			continue
		# A modded shot may bounce (or leave something where it stops).
		if shot.has_method("on_wall") and shot.on_wall(hit["position"], hit["normal"]):
			continue
		shot.set_physics_process(false)
		shot.remove_from_group("projectiles")
		shot.queue_free()
