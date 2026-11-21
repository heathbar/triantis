extends "res://scripts/projectile.gd"
## A shot from a modded Braid weapon (scripts/braid/braid_class_mod_fx.gd
## makes these in place of the player's own projectiles, and for melee
## waves). It flies and hits like a projectile (scripts/projectile.gd), plus
## whatever its Class Mods add (all off by default):
##   pierce   goes through `pierce_left` enemies, damage x (1 + pierce_gain)
##            after each; pierced_mark > 1 marks each enemy it goes through
##   overkill (from the gun, see projectile.gd) once out of pierces, a kill
##            lets it fly on with the damage left over
##   big      x (1 + big_bonus) damage to Brutes, elites and bosses
##   bounce   reflects off walls `bounces_left` times (braid_shot_walls.gd
##            calls on_wall), damage x (1 + bounce_gain) each time; with
##            `seek` it turns toward the nearest enemy after each bounce
##   homing   steers toward the nearest enemy as it flies
##   mark     hit enemies take x mark_mult damage from everyone for
##            mark_secs (other squads' enemies: their game is told)
##   stun     hit enemies stop for stun_secs; blast_radius > 0 also hits
##            everything that close
##   slow     hit enemies move at slow_mult for slow_secs
##   flak     bursts into flak_shards shards at flak_at of its range
##   grenade  bursts where it stops (burst_radius, burst_mult x its damage),
##            scattering `bomblets` small bursts
##   nail     leaves a spike trap where it stops (nail_secs)
##   line     leaves a burning line along its whole path (line_secs)
##   mortar   arcs over walls, hits nothing in flight, and bursts where it
##            lands (mortar_radius), leaving a puddle for puddle_secs
##   chain    each hit jumps to chain_jumps more enemies (chain_share
##            damage); with chain_gadgets, also via its shooter's equipment
##   heal     heals our players it passes (and other squads' with
##            heal_remote)
##   stim     boosts (or revives) our players it passes
##   toxin    poisons what it hits (toxin_dps x its damage a second, for
##            toxin_secs; spreads toxin_spread px when the host dies)
##   walls    through_walls: walls don't stop it
##   returns  at the end of its range it flies back to its shooter once,
##            able to hit everything again
## Everything else a hit does (shred, burn, overclock...) is the effects
## node's on_shot_hit().

const Zap := preload("res://scripts/braid/braid_fx_visuals.gd")

## The Class Mod effects node (for spikes, heals, hit effects and messages
## to other squads). Set before adding.
var fx: Node

var pierce_left := 0
var pierce_gain := 0.0
var pierced_mark := 1.0
var pierced_secs := 0.0
var big_bonus := 0.0
var bounces_left := 0
var bounce_gain := 0.0
var seek := false
var homing := false
var mark_mult := 1.0
var mark_secs := 0.0
var mark_spread := 0.0
var mark_drop := 0
var stun_secs := 0.0
var blast_radius := 0.0
var slow_mult := 1.0
var slow_secs := 0.0
var flak_shards := 0
var flak_at := 1.0
## A flak shard (so the effects node can tell).
var is_shard := false
var burst_radius := 0.0
var burst_mult := 1.0
var bomblets := 0
var nail_secs := 0.0
var line_secs := 0.0
var mortar_radius := 0.0
var mortar_damage := 1.0
var puddle_secs := 0.0
var chain_jumps := 0
var chain_share := 0.0
var chain_gadgets := false
var heal := false
var heal_remote := false
var stim := false
var toxin_dps := 0.0
var toxin_secs := 0.0
var toxin_spread := 0.0
var toxin_heals := false
var through_walls := false
var returns := false
## A colour for its Class Mods (drawn instead of white).
var tint := Color.WHITE

## Seek / homing reach, and how fast homing turns (radians a second).
const SEEK_RANGE := 200.0
const HOMING_RANGE := 140.0
const HOMING_TURN := 8.0

var _hit_ids := {}
var _start := Vector2.ZERO
var _returned := false
## Our players this shot has already passed (stim, revive).
var allies_passed := {}


func _ready() -> void:
	super()
	_start = global_position


func is_mortar() -> bool:
	return mortar_radius > 0.0


func _physics_process(delta: float) -> void:
	if homing:
		_steer_home(delta)
	var from := global_position
	var to := from + direction * speed * delta
	if is_mortar():
		global_position = to
		_age += delta
		queue_redraw()
		if _age >= lifetime:
			_burst_mortar()
			queue_free()
		return
	if (heal or stim) and fx:
		fx.ally_along(self, from, to)
	# Every enemy along this frame's path, nearest first, until one stops it.
	for _i in MAX_HITS_PER_FRAME:
		var enemy := _find_hit_excluding(from, to)
		if not enemy:
			break
		var left := _hit(enemy)
		if pierce_left > 0:
			pierce_left -= 1
			damage = roundi(damage * (1.0 + pierce_gain))
			if pierced_mark > 1.0 and fx and is_instance_valid(enemy) and not enemy is BossBody:
				fx.mark(enemy, pierced_mark, pierced_secs)
		elif overkill and left > 0:
			damage = left
		else:
			global_position = from.lerp(to, 0.5)
			_stop()
			queue_free()
			return
	global_position = to
	_age += delta
	if flak_shards > 0 and _age >= lifetime * flak_at:
		_burst_flak()
		queue_free()
		return
	if _age >= lifetime and returns and not _returned:
		_fly_back()
		return
	if _age >= lifetime or (cosmetic_bounds.has_area() and not cosmetic_bounds.has_point(to)):
		_stop()
		queue_free()


## The nearest enemy along from -> to that this shot hasn't hit yet.
func _find_hit_excluding(from: Vector2, to: Vector2) -> Node:
	var best: Node = null
	var best_dist := INF
	for result in get_world_2d().direct_space_state.intersect_shape(_sweep(from, to), 64):
		var collider: Node2D = result.collider
		if not (collider.is_in_group("enemies") and collider.has_method("take_damage")):
			continue
		if _hit_ids.has(collider.get_instance_id()):
			continue
		var d := from.distance_squared_to(collider.global_position)
		if d < best_dist:
			best_dist = d
			best = collider
	return best


static func is_big(enemy: Node) -> bool:
	return enemy is BossBody or bool(enemy.get("is_elite")) \
		or str(enemy.scene_file_path).ends_with("brute.tscn")


## Hits `enemy` with everything this shot carries. Returns the damage left
## over if the hit killed it (for overkill), else 0.
func _hit(enemy: Node) -> int:
	_hit_ids[enemy.get_instance_id()] = true
	var amount := damage
	if big_bonus > 0.0 and is_big(enemy):
		amount = roundi(amount * (1.0 + big_bonus))
	var left := mini(deal_overkill(enemy, amount, shooter, direction * knockback, global_position,
		from_equipment), damage)
	if fx:
		fx.on_shot_hit(self, enemy)
	if enemy is BossBody:
		return 0
	if mark_secs > 0.0 and fx:
		fx.mark(enemy, mark_mult, mark_secs, mark_spread, mark_drop)
	if stun_secs > 0.0 and enemy.has_method("apply_slow"):
		enemy.apply_slow(0.02, stun_secs)
	if slow_secs > 0.0 and enemy.has_method("apply_slow"):
		enemy.apply_slow(slow_mult, slow_secs)
	if blast_radius > 0.0:
		_area_damage(global_position, blast_radius, roundi(damage * 0.5), enemy)
		Zap.ring(get_parent(), global_position, blast_radius, tint)
	if toxin_secs > 0.0 and fx:
		fx.poison(enemy, maxf(damage * toxin_dps, 1.0), toxin_secs, toxin_spread, shooter, toxin_heals)
	if chain_jumps > 0:
		_chain(enemy)
	return left


## Damage `amount` to every enemy within `radius` of `at` (but `skip`).
func _area_damage(at: Vector2, radius: float, amount: int, skip: Node = null) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == skip or not e.has_method("take_damage"):
			continue
		var reach: float = radius + (e.half_extent() if e.has_method("half_extent") else 8.0)
		if e.global_position.distance_to(at) <= reach:
			BossBody.deal(e, maxi(amount, 1), shooter, Vector2.ZERO, at, from_equipment)


func _chain(first: Node) -> void:
	var at: Vector2 = first.global_position
	var done := {first.get_instance_id(): true}
	var amount := maxi(roundi(damage * chain_share), 1)
	for i in chain_jumps:
		var best := _nearest_enemy(at, 90.0, done)
		if best == null:
			break
		done[best.get_instance_id()] = true
		Zap.line(get_parent(), at, best.global_position, tint)
		BossBody.deal(best, amount, shooter, Vector2.ZERO, best.global_position, from_equipment)
		at = best.global_position
	if not chain_gadgets:
		return
	# Linker III: our shooter's equipment near the first hit zaps too.
	var origin: Vector2 = first.global_position if is_instance_valid(first) else global_position
	var used := 0
	for d: Node2D in get_tree().get_nodes_in_group("deployables"):
		if used >= 2 or d.get("owner_player") != shooter or d.global_position.distance_to(origin) > 90.0:
			continue
		used += 1
		Zap.line(get_parent(), origin, d.global_position, tint)
		var target := _nearest_enemy(d.global_position, 90.0, done)
		if target:
			done[target.get_instance_id()] = true
			Zap.line(get_parent(), d.global_position, target.global_position, tint)
			BossBody.deal(target, amount, shooter, Vector2.ZERO, target.global_position, from_equipment)


## The nearest live enemy within `reach` of `at` not in `skip` (ids), or null.
## Bosses count only when `bosses`.
func _nearest_enemy(at: Vector2, reach: float, skip := {}, bosses := false) -> Node2D:
	var best: Node2D = null
	var best_d := reach * reach
	for e: Node2D in get_tree().get_nodes_in_group("enemies"):
		if skip.has(e.get_instance_id()) or (e is BossBody and not bosses) or not e.has_method("take_damage"):
			continue
		var d := at.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _steer_home(delta: float) -> void:
	var target := _nearest_enemy(global_position, HOMING_RANGE, _hit_ids, true)
	if target == null:
		return
	var want := global_position.direction_to(target.global_position)
	var turn := clampf(direction.angle_to(want), -HOMING_TURN * delta, HOMING_TURN * delta)
	direction = direction.rotated(turn)
	rotation = direction.angle()


## Hit a wall at `at` (normal `normal`): true if it bounced and flies on.
func on_wall(at: Vector2, normal: Vector2) -> bool:
	if bounces_left > 0 and normal != Vector2.ZERO:
		bounces_left -= 1
		direction = direction.bounce(normal).normalized()
		global_position = at + normal * 2.0
		damage = roundi(damage * (1.0 + bounce_gain))
		if seek:
			var target := _nearest_enemy(global_position, SEEK_RANGE, _hit_ids, true)
			if target:
				direction = global_position.direction_to(target.global_position)
		rotation = direction.angle()
		return true
	global_position = at - direction * 2.0
	_stop()
	return false


## Wind Cutter III: turns round at the end of its range and comes back.
func _fly_back() -> void:
	_returned = true
	_age = 0.0
	_hit_ids.clear()
	if is_instance_valid(shooter):
		direction = global_position.direction_to(shooter.global_position)
	else:
		direction = -direction
	rotation = direction.angle()


## Where it stops (an enemy, a wall, or its range): a spike, a grenade
## burst or a burning line, if it has one.
func _stop() -> void:
	if not fx:
		return
	if nail_secs > 0.0:
		fx.add_spike(shooter, global_position, nail_secs, damage)
	if line_secs > 0.0:
		fx.add_hazard(_start, global_position, 6.0, line_secs, maxi(roundi(damage * 0.15), 1), shooter,
			Color(1.0, 0.55, 0.2))
	if burst_radius > 0.0:
		_area_damage(global_position, burst_radius, roundi(damage * burst_mult))
		Zap.ring(get_parent(), global_position, burst_radius, tint)
		if bomblets > 0:
			fx.bomblets(global_position, bomblets, maxi(roundi(damage * 0.6), 1), shooter, tint)


func _burst_flak() -> void:
	for i in flak_shards:
		var shard: Node2D = get_script().new()
		var spread := lerpf(-0.9, 0.9, (i + 0.5) / flak_shards)
		shard.direction = direction.rotated(spread)
		shard.damage = maxi(roundi(damage * 0.6), 1)
		shard.speed = speed * 0.8
		shard.lifetime = 0.12
		shard.size = Vector2(3, 2)
		shard.shooter = shooter
		shard.tint = tint
		shard.fx = fx
		shard.is_shard = true
		shard.position = global_position
		get_parent().add_child(shard)
	Zap.ring(get_parent(), global_position, 10.0, tint)


func _burst_mortar() -> void:
	_area_damage(global_position, mortar_radius, roundi(damage * mortar_damage))
	Zap.ring(get_parent(), global_position, mortar_radius, tint)
	if puddle_secs > 0.0 and fx:
		fx.add_hazard(global_position, global_position, mortar_radius * 0.7, puddle_secs,
			maxi(roundi(damage * 0.2), 1), shooter, Color(0.6, 1.0, 0.2))


func _draw() -> void:
	if is_mortar():
		# A rivet on a high arc: drawn lifted off its shadow.
		var lift := -sin(PI * clampf(_age / lifetime, 0.0, 1.0)) * 26.0
		draw_rect(Rect2(-size / 2.0, size), Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2(0, lift).rotated(-rotation), 0.0, Vector2.ONE)
		draw_rect(Rect2(-size / 2.0, size), tint)
		return
	draw_rect(Rect2(-size / 2.0, size), tint)
