extends Node2D
## Connects this squad's Braid game to the other squads' games (squads games
## only; scripts/braid/braid_game.gd adds it). Messages travel through the
## Squads autoload, mostly the same ones the arena game's link uses
## (scripts/net/squad_link.gd), plus Squads.send_mode_message for Braid's own.
##
## Every game builds the same level, so positions need no converting.
##
## Players: every squad sends its players to everyone, and each game shows the
## others' as BraidRemotePlayers (seen through windows, met in junctions). Their
## shots are copied over just for show.
##
## Views: every squad also sends the part of the world its camera shows. We
## only send a squad the enemies of ours that are in (or near) its view, and it
## shows them as mirrors: they can be shot (through windows too), and hits on
## them go to us, as in the arena game. Whoever lands the final blow gets the
## kill and the drops.
##
## Favours: an airstrike pad one of our players held X on (scripts/braid/
## braid_favour.gd) bombs the squad across the window; we tell that squad's
## game, which hurts its enemies there as the bombs land.
##
## Everything here is drawn as a child of this node, at the world origin.

const BraidRemotePlayer := preload("res://scripts/braid/braid_remote_player.gd")
const BraidFavour := preload("res://scripts/braid/braid_favour.gd")
const Projectile := preload("res://scripts/projectile.gd")
const Guns := preload("res://scripts/guns.gd")

## Seconds between updates sent to the other squads.
const SEND_INTERVAL := 0.05
## Enemies this close to another squad's view are sent to it.
const VIEW_MARGIN := 80.0
## Most enemies sent to one squad per update (14 bytes each: more than about
## 95 goes over a network packet). The ones nearest its view's centre win.
const MAX_SENT_ENEMIES := 80
## Drop other squads' players and enemies we stop hearing about for this long
## (seconds of play).
const STALE_TIME := 0.5

## The game scene (scripts/braid/braid_game.gd).
var game: Node2D
var my_squad := -1

## Every enemy scene the run uses, by resource path (an enemy's kind is its
## index in here: the same in every game).
var _kinds: Array[String] = []
var _scene_cache := {}
var _next_enemy_id := 1
## id -> our enemy.
var _owned := {}
## Vector2i(owner squad, id) -> mirror of another squad's enemy.
var _mirrors := {}
var _mirrors_heard := {}
## (squad << 4) | slot -> BraidRemotePlayer.
var _remote_players := {}
## Squad -> the world rect its camera shows (from its last "view" message).
var _views := {}
var _sent_enemies_to := {}
var _pending_shots := []
var _send_timer := 0.0
var _clock := 0.0


## Call before adding to the tree.
func setup(game_node: Node2D) -> void:
	game = game_node
	my_squad = Squads.my_squad()
	for wave in game.wave_set.waves:
		for group in wave.enemy_groups:
			if group.enemy_scene:
				_add_kind(group.enemy_scene)
	_kinds.sort()


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
	Squads.mode_message.connect(_on_mode_message)
	Squads.roster_changed.connect(_forget_departed_squads)


func _physics_process(delta: float) -> void:
	_clock += delta
	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = SEND_INTERVAL
		_send_players()
		Squads.send_mode_message(-1, ["view", game.view_rect()], false)
		if game.is_wave_running():
			_send_enemies()
	_forget_stale()


# --- Players ------------------------------------------------------------------

## One of our players fired (connected to each player's shot_fired), or a
## mounted turret did (`gun_id` names the gun it looks like).
func report_shot(shot: Node, gun_id := "") -> void:
	if gun_id.is_empty() and is_instance_valid(shot.shooter):
		gun_id = shot.shooter.gun_id
	_pending_shots.append([shot.global_position, shot.direction, shot.lifetime, gun_id])


func _send_players() -> void:
	var states := []
	for player in game.all_players:
		states.append([player.player_index, player.global_position,
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
		var key := (squad << 4) | int(state[0])
		var proxy: Variant = _remote_players.get(key)
		if proxy == null or not is_instance_valid(proxy):
			proxy = BraidRemotePlayer.new()
			proxy.chase_rects = game.chase_rects()
			proxy.setup(state[3], int(state[5]) if state.size() >= 6 else 0)
			proxy.apply(state[1], state[2], state[4], _gun_of(state))
			add_child(proxy)
			_remote_players[key] = proxy
		else:
			proxy.apply(state[1], state[2], state[4], _gun_of(state))
		proxy.heard_at = _clock
	var view: Rect2 = game.view_rect().grow(VIEW_MARGIN)
	for shot in shots:
		if shot is Array and shot.size() >= 3 and view.has_point(shot[0]):
			_show_shot(shot[0], shot[1], shot[2], str(shot[3]) if shot.size() >= 4 else "")


## The gun id in a remote player's state ("" from an older build).
static func _gun_of(state: Array) -> String:
	return str(state[6]) if state.size() >= 7 else ""


## Another squad's shot, just for show (it stops at walls and enemies).
func _show_shot(origin: Vector2, direction: Vector2, lifetime: float, gun_id: String) -> void:
	var shot := Projectile.new()
	shot.cosmetic = true
	shot.cosmetic_bounds = game.level.bounds
	shot.direction = direction
	shot.lifetime = lifetime
	var gun := Guns.get_gun(gun_id)
	shot.speed = gun.get("speed", Projectile.SPEED)
	shot.size = gun.get("size", Projectile.SIZE)
	shot.position = origin
	add_child(shot)


## Where each other squad is: {squad: {"pos": average position of its
## players, "x": its x, "alive": any standing}} (for the HUD and spectating:
## BraidLevel.progress(pos) is how far along it is).
func squad_positions() -> Dictionary:
	var sums := {}
	for key in _remote_players:
		var proxy: Variant = _remote_players[key]
		if not is_instance_valid(proxy):
			continue
		var squad: int = key >> 4
		var s: Dictionary = sums.get(squad, {"sum": Vector2.ZERO, "n": 0, "alive": false})
		s["sum"] += proxy.position
		s["n"] += 1
		s["alive"] = s["alive"] or proxy.is_alive()
		sums[squad] = s
	var out := {}
	for squad in sums:
		var s: Dictionary = sums[squad]
		out[squad] = {"pos": s["sum"] / float(s["n"]), "x": s["sum"].x / float(s["n"]), "alive": s["alive"]}
	return out


# --- Enemies ------------------------------------------------------------------

## One of our new enemies, before it enters the tree.
func register_enemy(enemy: Node, scene_path: String) -> void:
	enemy.net_id = _next_enemy_id
	_next_enemy_id += 1
	enemy.net_kind = maxi(_kinds.find(scene_path), 0) * 2 + int(enemy.is_elite)
	_owned[enemy.net_id] = enemy


func _send_enemies() -> void:
	for id in _owned.keys():
		var enemy: Variant = _owned[id]
		if not is_instance_valid(enemy) or enemy.is_dead():
			_owned.erase(id)
	for squad in Squads.squads_present():
		if squad == my_squad or not _views.has(squad):
			continue
		var near: Rect2 = (_views[squad] as Rect2).grow(VIEW_MARGIN)
		var ids := PackedInt32Array()
		var positions := PackedVector2Array()
		var kinds := PackedByteArray()
		var states := PackedByteArray()
		var picked := []
		for id in _owned:
			if near.has_point(_owned[id].global_position):
				picked.append(id)
		if picked.size() > MAX_SENT_ENEMIES:
			var centre := near.get_center()
			picked.sort_custom(func(a, b): return _owned[a].global_position.distance_squared_to(centre) \
				< _owned[b].global_position.distance_squared_to(centre))
			picked.resize(MAX_SENT_ENEMIES)
		for id in picked:
			var enemy: Variant = _owned[id]
			ids.append(id)
			positions.append(enemy.global_position)
			kinds.append(enemy.net_kind)
			states.append(enemy.net_state())
		if ids.is_empty() and not _sent_enemies_to.get(squad, false):
			continue
		_sent_enemies_to[squad] = not ids.is_empty()
		Squads.send_enemies(squad, game.round_index(), ids, positions, kinds, states)


func _on_remote_enemies(owner_squad: int, wave: int, ids: PackedInt32Array,
		positions: PackedVector2Array, kinds: PackedByteArray, states: PackedByteArray) -> void:
	if owner_squad == my_squad or not game.is_wave_running() or wave != game.round_index():
		return
	_mirrors_heard[owner_squad] = _clock
	var listed := {}
	for i in mini(ids.size(), mini(positions.size(), kinds.size())):
		var key := Vector2i(owner_squad, ids[i])
		listed[key] = true
		var mirror: Variant = _mirrors.get(key)
		if mirror != null and is_instance_valid(mirror):
			mirror.mirror_report(positions[i])
		else:
			mirror = _make_mirror(owner_squad, ids[i], kinds[i], positions[i])
			if mirror:
				_mirrors[key] = mirror
		if mirror and i < states.size():
			mirror.mirror_state(states[i])
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
	var wave: WaveDefinition = game.segment_wave
	if wave:
		mirror.apply_modifiers(wave.enemy_health_multiplier, wave.enemy_speed_multiplier)
	if kind & 1:
		mirror.make_elite(game.player_scaling)
	mirror.mirror_report(at)
	add_child(mirror)
	return mirror


func _remove_mirror(key: Vector2i) -> void:
	var mirror: Variant = _mirrors.get(key)
	_mirrors.erase(key)
	if mirror != null and is_instance_valid(mirror):
		mirror.remove_from_group("enemies")
		mirror.queue_free()


func _on_mirror_hit(amount: int, source: Node, knockback: Vector2,
		owner_squad: int, id: int) -> void:
	var slot := -1
	if is_instance_valid(source) and "player_index" in source:
		slot = source.player_index
	Squads.send_enemy_hit(owner_squad, id, amount, slot, knockback)


func _on_enemy_hit(shooter_squad: int, id: int, amount: int, shooter_slot: int,
		knockback: Vector2) -> void:
	if not game.is_wave_running():
		return
	var enemy: Variant = _owned.get(id)
	if enemy != null and is_instance_valid(enemy) and not enemy.is_dead():
		enemy.take_remote_damage(amount, shooter_squad, shooter_slot, knockback)


## One of our enemies died (braid_game.gd calls this). Returns true if another
## squad's player killed it (the kill and drops are theirs).
func owned_enemy_died(enemy: Node, at: Vector2) -> bool:
	_owned.erase(enemy.net_id)
	var killer: Vector2i = enemy.remote_killer
	Squads.send_enemy_died(enemy.net_id, killer.x, killer.y,
		enemy.points_value, enemy.resource_drops, at)
	return killer.x >= 0


func _on_enemy_died(owner_squad: int, id: int, killer_squad: int, killer_slot: int,
		points: int, drops: int, at: Vector2) -> void:
	var mirror: Variant = _mirrors.get(Vector2i(owner_squad, id))
	if mirror != null and is_instance_valid(mirror) and game.is_wave_running():
		mirror.mirror_died(at)
	_remove_mirror(Vector2i(owner_squad, id))
	if killer_squad == my_squad:
		game.credit_remote_kill(killer_slot, points, drops, at)


## A new act's level: other squads' players may be chased in its rooms.
func new_act() -> void:
	for key in _remote_players:
		var proxy: Variant = _remote_players[key]
		if is_instance_valid(proxy):
			proxy.chase_rects = game.chase_rects()


## The segment is over and the field is being cleared: forget its enemies.
func clear_wave() -> void:
	for key in _mirrors.keys():
		_remove_mirror(key)
	_mirrors_heard.clear()
	_owned.clear()
	_sent_enemies_to.clear()


# --- Favours --------------------------------------------------------------------

## Our player `slot` called an airstrike from `plate`: bomb whoever's across
## the window (we only see it; their game hurts their enemies, and credits
## us with the kills).
func send_favour(plate: Node2D, slot: int) -> void:
	var rect: Rect2 = plate.crush_rect()
	BraidFavour.show_crush(self, rect)
	var target: int = game.squad_in_lane(plate.target_lane, plate.s)
	if target >= 0 and target != my_squad:
		Squads.send_mode_message(target, ["favour", rect.position, rect.size, slot])


func _on_mode_message(squad: int, data: Array) -> void:
	if data.is_empty() or squad == my_squad:
		return
	match str(data[0]):
		"view":
			if data.size() >= 2 and data[1] is Rect2:
				_views[squad] = data[1]
		"favour":
			if data.size() >= 4 and game.is_wave_running():
				game.receive_favour(Rect2(data[1], data[2]), squad, int(data[3]))
		"mark":
			# Another squad's Spotter marked one of our enemies.
			if data.size() >= 4 and game.is_wave_running():
				var enemy: Variant = _owned.get(int(data[1]))
				if enemy != null and is_instance_valid(enemy) and game.class_mod_fx:
					game.class_mod_fx.mark(enemy, float(data[2]), float(data[3]))
		"gate":
			# To the host: that squad's checkpoint light (on its plate, or not, or down).
			if data.size() >= 3 and Squads.is_host():
				game._on_squad_plate(squad, int(data[1]), int(data[2]))
		"lights":
			# From the host: every squad's checkpoint light.
			if data.size() >= 3 and data[2] is Dictionary:
				game.on_shop_lights(int(data[1]), data[2])
		"heal":
			# Another squad's Triage shot passed one of our players.
			if data.size() >= 3 and game.is_wave_running():
				game.receive_heal(int(data[1]), int(data[2]))


## One of our Spotters hit `mirror` (another squad's enemy): mark it in its
## owner's game.
func send_mark(mirror: Node, mult: float, secs: float) -> void:
	for key in _mirrors:
		if _mirrors[key] == mirror:
			Squads.send_mode_message(key.x, ["mark", key.y, mult, secs])
			return


## A Triage shot of ours passed `squad`'s player `slot`.
func send_heal(squad: int, slot: int, amount: int) -> void:
	Squads.send_mode_message(squad, ["heal", slot, amount])


## Other squads' players, by (squad << 4) | slot.
func remote_player_keys() -> Array:
	return _remote_players.keys()


func remote_player(key: int) -> Node2D:
	var proxy: Variant = _remote_players.get(key)
	return proxy if proxy != null and is_instance_valid(proxy) else null


# --- Housekeeping ---------------------------------------------------------------

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
	for squad in _views.keys():
		if squad not in present:
			_views.erase(squad)


func _remove_remote_player(key: int) -> void:
	var proxy: Variant = _remote_players.get(key)
	_remote_players.erase(key)
	if proxy != null and is_instance_valid(proxy):
		proxy.queue_free()
