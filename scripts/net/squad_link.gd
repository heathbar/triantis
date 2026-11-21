extends Node2D
## Connects this squad's game to the other squads' games (squads game only;
## game.gd adds it). Messages travel through the Squads autoload.
##
## Maps: every squad plays on its own copy of the map. The copies tile a 2x2
## grid (Squads.SQUAD_GRID) and neighbours overlap by Squads.MAP_OVERLAP, so
## the strips along shared edges (and the centre, shared by all four) are on
## two or more squads' maps at once. Positions sent between games are in
## shared coordinates: a squad's own (local) position plus its map's offset.
##
## Players: every squad sends its players' positions to everyone. Another
## squad's player shows up here as a RemotePlayer while they're on our map,
## which (as nobody can leave their own map) means in a strip we share. Our
## enemies chase them too. Their shots are copied over just for show.
##
## Enemies: each enemy belongs to the squad that spawned it, and only that
## squad's game moves it, damages it and kills it. Enemies can't leave their
## owner's map. While one is near another squad's map, the owner sends its
## position there and that game shows a mirror: it hurts to touch (decided by
## the game whose player touched it) and can be shot, but hits on it are sent
## to the owner. Whoever lands the final blow gets the kill and the resource
## drops; nobody else does.
##
## Everything here is drawn as a child of this node, which sits at the world
## origin like the game scene's root.

const RemotePlayer := preload("res://scripts/net/remote_player.gd")
const Projectile := preload("res://scripts/projectile.gd")
const Guns := preload("res://scripts/guns.gd")

## Seconds between updates sent to the other squads.
const SEND_INTERVAL := 0.05
## An enemy this close to another squad's map (or on it) is mirrored there.
## It's also how far past their map edge their shots can still hit.
const NEAR_MAP_MARGIN := 60.0
## Drop other squads' players and enemies we stop hearing about for this long
## (seconds of play; time spent paused between waves doesn't count).
const STALE_TIME := 0.5

## The game scene (scripts/game.gd).
var game: Node2D
var my_squad := -1

## Size of one step across the grid: a map minus the strip it shares.
var _stride := Vector2.ZERO
## Our map's offset in shared coordinates.
var _offset := Vector2.ZERO
## Every enemy scene the run uses, by resource path. Enemies are identified to
## other squads by their index in here (the same in every game).
var _kinds: Array[String] = []
var _scene_cache := {}
var _next_enemy_id := 1
## id -> our enemy.
var _owned := {}
## Vector2i(owner squad, id) -> mirror of another squad's enemy.
var _mirrors := {}
## Owner squad -> when its last enemy update arrived.
var _mirrors_heard := {}
## (squad << 4) | slot -> RemotePlayer.
var _remote_players := {}
## Squad -> whether the last enemy update we sent them listed any enemies.
## (Once there's nothing to send, one empty update clears their mirrors.)
var _sent_enemies_to := {}
## Shots our players fired since the last update:
## [origin, direction, lifetime, gun id].
var _pending_shots := []
var _send_timer := 0.0
## Seconds of play since the game started (stops while the game is paused).
var _clock := 0.0


## Call before adding to the tree.
func setup(game_node: Node2D) -> void:
	game = game_node
	my_squad = Squads.my_squad()
	_stride = game.grass_bounds.size * (1.0 - Squads.MAP_OVERLAP)
	_offset = _grid(my_squad) * _stride
	for wave in game.wave_set.waves:
		for group in wave.enemy_groups:
			if group.enemy_scene:
				_add_kind(group.enemy_scene)
	_kinds.sort()


## Adds `scene` to _kinds, and any enemies it spawns itself (a splitter's
## runners: its `child_scene`), which needn't appear in any wave.
func _add_kind(scene: PackedScene) -> void:
	if scene.resource_path in _kinds:
		return
	_kinds.append(scene.resource_path)
	var probe := scene.instantiate()
	var child: Variant = probe.get("child_scene")
	probe.free()
	if child is PackedScene:
		_add_kind(child)


func _ready() -> void:
	Squads.remote_players.connect(_on_remote_players)
	Squads.remote_enemies.connect(_on_remote_enemies)
	Squads.enemy_hit.connect(_on_enemy_hit)
	Squads.enemy_died.connect(_on_enemy_died)
	Squads.roster_changed.connect(_forget_departed_squads)


func _physics_process(delta: float) -> void:
	_clock += delta
	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = SEND_INTERVAL
		_send_players()
		if game.is_wave_running():
			_send_enemies()
	_forget_stale()


# --- Maps ---------------------------------------------------------------------

func _grid(squad: int) -> Vector2:
	return Vector2(Squads.SQUAD_GRID[squad])


func _to_shared(local_pos: Vector2) -> Vector2:
	return local_pos + _offset


func _to_local(shared_pos: Vector2) -> Vector2:
	return shared_pos - _offset


## A shared-coordinates position in our map's coordinates, and back.
func shared_to_local(shared_pos: Vector2) -> Vector2:
	return _to_local(shared_pos)


func local_to_shared(local_pos: Vector2) -> Vector2:
	return _to_shared(local_pos)


## Another squad's map, in our coordinates.
func _map_rect(squad: int) -> Rect2:
	var bounds: Rect2 = game.grass_bounds
	return Rect2(bounds.position + (_grid(squad) - _grid(my_squad)) * _stride, bounds.size)


## True if `local_pos` is also on another squad's map (a strip we share).
func is_shared(local_pos: Vector2) -> bool:
	for squad in Squads.squads_present():
		if squad != my_squad and _map_rect(squad).has_point(local_pos):
			return true
	return false


# --- Players ------------------------------------------------------------------

## One of our players fired (connected to each player's shot_fired).
func report_shot(shot: Node) -> void:
	_pending_shots.append([_to_shared(shot.global_position), shot.direction, shot.lifetime,
		shot.shooter.gun_id if is_instance_valid(shot.shooter) else ""])


func _send_players() -> void:
	var states := []
	for player in game.all_players:
		states.append([player.player_index, _to_shared(player.global_position),
			player.body.rotation, player.color, not player.is_dead(), player.skin,
			player.gun_id])
	Squads.send_players(states, _pending_shots)
	_pending_shots = []


func _on_remote_players(squad: int, states: Array, shots: Array) -> void:
	if squad == my_squad or squad < 0 or squad >= Squads.MAX_SQUADS:
		return
	for state in states:
		if not (state is Array and state.size() >= 5):
			continue
		var slot := int(state[0])
		var key := (squad << 4) | slot
		var proxy: Variant = _remote_players.get(key)
		if proxy == null or not is_instance_valid(proxy):
			proxy = RemotePlayer.new()
			proxy.map_bounds = game.grass_bounds
			proxy.setup(state[3], int(state[5]) if state.size() >= 6 else 0)
			proxy.apply(_to_local(state[1]), state[2], state[4], _gun_of(state))
			add_child(proxy)
			_remote_players[key] = proxy
		else:
			proxy.apply(_to_local(state[1]), state[2], state[4], _gun_of(state))
		proxy.heard_at = _clock
	for shot in shots:
		if shot is Array and shot.size() >= 3:
			_show_shot(squad, _to_local(shot[0]), shot[1], shot[2],
				str(shot[3]) if shot.size() >= 4 else "")


## The gun id in a remote player's state ("" from an older build).
static func _gun_of(state: Array) -> String:
	return str(state[6]) if state.size() >= 7 else ""


## Another squad's shot, just for show. It stops at the first enemy it meets,
## as the real one (in their game) does, and vanishes where theirs could no
## longer hit anything.
func _show_shot(squad: int, origin: Vector2, direction: Vector2, lifetime: float,
		gun_id: String) -> void:
	if not game.grass_bounds.grow(NEAR_MAP_MARGIN).has_point(origin):
		return  # Nowhere near our map.
	var shot := Projectile.new()
	shot.cosmetic = true
	shot.cosmetic_bounds = _map_rect(squad).grow(NEAR_MAP_MARGIN)
	shot.direction = direction
	shot.lifetime = lifetime
	var gun := Guns.get_gun(gun_id)
	shot.speed = gun.get("speed", Projectile.SPEED)
	shot.size = gun.get("size", Projectile.SIZE)
	shot.position = origin  # before add_child, so it never appears at the origin
	add_child(shot)


# --- Enemies ------------------------------------------------------------------

## One of our new enemies (spawned by game.gd), before it enters the tree and
## after it's been made elite (or not).
func register_enemy(enemy: Node, scene_path: String) -> void:
	enemy.net_id = _next_enemy_id
	_next_enemy_id += 1
	enemy.net_kind = maxi(_kinds.find(scene_path), 0) * 2 + int(enemy.is_elite)
	enemy.move_bounds = game.grass_bounds
	_owned[enemy.net_id] = enemy


## Send each other squad where our enemies near their map are.
func _send_enemies() -> void:
	for id in _owned.keys():
		var enemy: Variant = _owned[id]
		if not is_instance_valid(enemy) or enemy.is_dead():
			_owned.erase(id)
	for squad in Squads.squads_present():
		if squad == my_squad:
			continue
		var near := _map_rect(squad).grow(NEAR_MAP_MARGIN)
		var ids := PackedInt32Array()
		var positions := PackedVector2Array()
		var kinds := PackedByteArray()
		var states := PackedByteArray()
		for id in _owned:
			var enemy: Variant = _owned[id]
			if near.has_point(enemy.global_position):
				ids.append(id)
				positions.append(_to_shared(enemy.global_position))
				kinds.append(enemy.net_kind)
				states.append(enemy.net_state())
		if ids.is_empty() and not _sent_enemies_to.get(squad, false):
			continue
		_sent_enemies_to[squad] = not ids.is_empty()
		Squads.send_enemies(squad, game.director.index, ids, positions, kinds, states)


## The full list of `owner_squad`'s enemies near our map.
func _on_remote_enemies(owner_squad: int, wave: int, ids: PackedInt32Array,
		positions: PackedVector2Array, kinds: PackedByteArray, states: PackedByteArray) -> void:
	if owner_squad == my_squad or not game.is_wave_running() or wave != game.director.index:
		return
	_mirrors_heard[owner_squad] = _clock
	var listed := {}
	for i in mini(ids.size(), mini(positions.size(), kinds.size())):
		var key := Vector2i(owner_squad, ids[i])
		listed[key] = true
		var at := _to_local(positions[i])
		var mirror: Variant = _mirrors.get(key)
		if mirror != null and is_instance_valid(mirror):
			mirror.mirror_report(at)
		else:
			mirror = _make_mirror(owner_squad, ids[i], kinds[i], at)
			if mirror:
				_mirrors[key] = mirror
		if mirror and i < states.size():
			mirror.mirror_state(states[i])
	# Anything not listed has moved away from our map (or died).
	for key in _mirrors.keys():
		if key.x == owner_squad and not listed.has(key):
			_remove_mirror(key)


func _make_mirror(owner_squad: int, id: int, kind: int, at: Vector2) -> Node:
	var kind_index := kind >> 1
	if kind_index >= _kinds.size():
		return null
	var path := _kinds[kind_index]
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	var node := (_scene_cache[path] as PackedScene).instantiate()
	if not node is Enemy:
		node.free()
		return null
	var mirror: Enemy = node
	mirror.is_mirror = true
	mirror.forward_hit = _on_mirror_hit.bind(owner_squad, id)
	# Only matters for what it does to our side when it dies (a bomber's blast).
	var wave: WaveDefinition = game.director.wave
	if wave:
		var scaling: PlayerScaling = game.wave_set.get_player_scaling()
		mirror.apply_modifiers(
			wave.enemy_health_multiplier * scaling.health_multiplier(game.director.player_count),
			wave.enemy_speed_multiplier)
	if kind & 1:
		mirror.make_elite(game.wave_set.get_player_scaling())
	mirror.mirror_report(at)  # also places it, before it enters the tree
	add_child(mirror)
	return mirror


func _remove_mirror(key: Vector2i) -> void:
	var mirror: Variant = _mirrors.get(key)
	_mirrors.erase(key)
	if mirror != null and is_instance_valid(mirror):
		mirror.remove_from_group("enemies")
		mirror.queue_free()


## One of our players hit a mirror: the damage is for its owner to apply.
func _on_mirror_hit(amount: int, source: Node, knockback: Vector2,
		owner_squad: int, id: int) -> void:
	var slot := -1
	if is_instance_valid(source) and "player_index" in source:
		slot = source.player_index
	Squads.send_enemy_hit(owner_squad, id, amount, slot, knockback)


## Another squad's player hit one of our enemies.
func _on_enemy_hit(shooter_squad: int, id: int, amount: int, shooter_slot: int,
		knockback: Vector2) -> void:
	if not game.is_wave_running():
		return
	var enemy: Variant = _owned.get(id)
	if enemy != null and is_instance_valid(enemy) and not enemy.is_dead():
		enemy.take_remote_damage(amount, shooter_squad, shooter_slot, knockback)


## One of our enemies died (game.gd calls this from the enemy's `died`). Tells
## the other squads, so their mirrors of it go, and if one of their players
## landed the final blow, that squad gets the kill and the drops.
## Returns true if it was another squad's kill.
func owned_enemy_died(enemy: Node, at: Vector2) -> bool:
	_owned.erase(enemy.net_id)
	var killer: Vector2i = enemy.remote_killer
	Squads.send_enemy_died(enemy.net_id, killer.x, killer.y,
		enemy.points_value, enemy.resource_drops, _to_shared(at))
	return killer.x >= 0


func _on_enemy_died(owner_squad: int, id: int, killer_squad: int, killer_slot: int,
		points: int, drops: int, at: Vector2) -> void:
	var mirror: Variant = _mirrors.get(Vector2i(owner_squad, id))
	if mirror != null and is_instance_valid(mirror) and game.is_wave_running():
		mirror.mirror_died(_to_local(at))
	_remove_mirror(Vector2i(owner_squad, id))
	if killer_squad == my_squad:
		game.credit_remote_kill(killer_slot, points, drops, _to_local(at))


## The wave is over and the field is being cleared: forget its enemies.
func clear_wave() -> void:
	for key in _mirrors.keys():
		_remove_mirror(key)
	_mirrors_heard.clear()
	_owned.clear()
	_sent_enemies_to.clear()


# --- Housekeeping ---------------------------------------------------------------

## Drop players and enemies of squads that have gone quiet (e.g. disconnected).
func _forget_stale() -> void:
	for key in _remote_players.keys():
		var proxy: Variant = _remote_players[key]
		if not is_instance_valid(proxy) or _clock - proxy.heard_at > STALE_TIME:
			_remove_remote_player(key)
	for owner_squad in _mirrors_heard.keys():
		if _clock - _mirrors_heard[owner_squad] > STALE_TIME:
			_mirrors_heard.erase(owner_squad)
			for key in _mirrors.keys():
				if key.x == owner_squad:
					_remove_mirror(key)


func _forget_departed_squads() -> void:
	var present := Squads.squads_present()
	for key in _remote_players.keys():
		if (key >> 4) not in present:
			_remove_remote_player(key)
	for key in _mirrors.keys():
		if key.x not in present:
			_remove_mirror(key)


func _remove_remote_player(key: int) -> void:
	var proxy: Variant = _remote_players.get(key)
	_remote_players.erase(key)
	if proxy != null and is_instance_valid(proxy):
		proxy.queue_free()
