extends Node
## LAN "Squads" session (autoload as Squads).
##
## There is no dedicated server: one game instance hosts and up to three others
## join over the LAN. Each instance is a *squad* (its local players) playing in
## its own copy of the map. The host is always Alpha; joiners get the next free
## squad. Squad maps tile a 2x2 grid (see SQUAD_GRID) and neighbours overlap by
## MAP_OVERLAP of the map, so players can wander into the shared strip.
##
## Discovery: a joiner broadcasts a small "query" datagram on DISCOVERY_PORT;
## every host listening there replies directly to the sender with its info.
## Only hosts bind the fixed port, so any number of joiners can browse from the
## same machine.
##
## Session: ENet on GAME_PORT. The host (peer 1) owns the roster and is the
## only peer that changes it; joiners send their status and receive the roster.
##
## In game the host also owns the wave clock: it broadcasts the time, ends each
## wave, starts the next one once every squad has left the shop, and calls game
## over once every squad is down. Ending the game from the host's pause menu
## returns everyone to character select; losing the host returns everyone to
## the title screen.
##
## The world itself (players in shared strips, enemies near other squads' maps,
## hits and kills) is synced squad to squad by scripts/net/squad_link.gd; this
## only carries its messages. Joiners reach each other through the host, which
## relays for them.

signal hosts_changed                 ## The discovered-host list changed (browsing).
signal joined                        ## This joiner was accepted and given a squad.
signal roster_changed                ## Any squad joined, left or changed status.
signal game_starting                 ## The host started the game.
signal session_ended(reason: String) ## The session closed (host left, rejected...).
signal wave_clock(index: int, elapsed: float) ## Host's time into the current wave.
## The host ended the wave (its time ran out, or its objective was done or
## failed: `failed`).
signal wave_ended(index: int, failed: bool)
signal wave_begin(index: int)        ## Every squad is ready: start this wave.
signal all_squads_down(index: int)   ## Every squad was wiped out this wave.
signal returned_to_lobby             ## Host ended the game: back to character select.
## Another squad's end-of-run results (see send_final_results).
signal final_results(squad: int, results: Dictionary)
## World sync (see scripts/net/squad_link.gd for what these carry).
signal remote_players(squad: int, players: Array, shots: Array)
signal remote_enemies(owner_squad: int, wave: int, ids: PackedInt32Array,
	positions: PackedVector2Array, kinds: PackedByteArray, states: PackedByteArray)
signal enemy_hit(shooter_squad: int, enemy_id: int, damage: int, shooter_slot: int,
		knockback: Vector2)
signal enemy_died(owner_squad: int, enemy_id: int, killer_squad: int, killer_slot: int,
	points: int, drops: int, at: Vector2)
## Objective waves (scripts/objectives/objective.gd): a squad's report, heard
## by the host only, and the host's state of the objective, heard by everyone.
signal objective_report(squad: int, wave: int, data: Dictionary)
signal objective_state(wave: int, data: Dictionary)
## A message for whichever game mode is being played (only Braid uses these:
## scripts/braid/braid_link.gd). `data` is plain data; its first item says
## what it is.
signal mode_message(from_squad: int, data: Array)

const GAME_ID := "triantis-squads"
## Games only see and join hosts with the same version. Bump it whenever the
## messages change, or anything both sides must agree on (like MAP_OVERLAP).
const PROTOCOL_VERSION := 13
const DISCOVERY_PORT := 47800
const GAME_PORT := 47801
const CONNECT_FAILED := "Couldn't connect to that game."
const MAX_SQUADS := 4

const SQUAD_NAMES := ["Alpha", "Bravo", "Charlie", "Delta"]
const SQUAD_COLORS := [
	Color(0.95, 0.35, 0.3),
	Color(0.3, 0.6, 1.0),
	Color(0.35, 0.9, 0.4),
	Color(1.0, 0.8, 0.2),
]
## Each squad's map position in the 2x2 grid: Alpha | Bravo over Charlie | Delta.
## Alpha/Bravo and Alpha/Charlie share edges, Bravo/Delta and Charlie/Delta too,
## and the centre is shared by everyone.
const SQUAD_GRID := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
## Fraction of a map's width/height that overlaps a neighbouring squad's map.
const MAP_OVERLAP := 0.35

const MAX_NAME_LENGTH := 32  ## Longest game name shown in the join list.
const QUERY_INTERVAL := 1.0  ## Seconds between discovery broadcasts.
const HOST_TIMEOUT := 3.5    ## Drop a host we haven't heard from for this long.
const CONNECT_TIMEOUT := 10.0 ## Give up on an unanswered join after this long (ENet waits ~30s+).

enum Mode { NONE, HOST, CLIENT }

var mode := Mode.NONE
## peer id -> {"squad": int, "name": String, "joined": int, "ready": int}
var roster := {}
## Discovered hosts, keyed by session id:
## {"ip", "port", "name", "squads", "open": bool, "seen": msec}
var hosts := {}
## Why the last session ended; the title screen shows it once, then clears it.
var notice := ""
## Name of the hosted game, shown to players searching the LAN.
var game_name := ""
## The session's game mode (Global.MODE_*), chosen by the host.
var game_mode := "standard"
## Custom game settings chosen by the host (Global.custom_settings), shared
## with the roster. Empty unless game_mode is Global.MODE_CUSTOM.
var custom_settings := {}
## The host's Global.run_seed for the game in progress (sent as it starts).
var run_seed := 0
## The host's Campaign modifiers for the game in progress (BraidModifiers
## ids, sent as it starts).
var modifiers: Array = []

var _session_id := ""
var _started := false
## Host only, in game: peer id -> wave index it's ready to start (left the shop).
var _ready_for_wave := {}
## Host only, in game: peer id -> wave index in which its squad was wiped out.
var _down := {}
var _discovery: PacketPeerUDP     ## Host: answers queries. Joiner: sends them.
var _browsing := false
var _query_timer := 0.0
var _join_attempt := 0           ## Bumped per join() so a stale timeout is ignored.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## False in a web export: browsers can't open the UDP sockets ENet and LAN
## discovery need, so the title screen hides Squads there.
func is_supported() -> bool:
	return not OS.has_feature("web")


func is_active() -> bool:
	return mode != Mode.NONE


func is_host() -> bool:
	return mode == Mode.HOST


## True while a squads game is being played (not in the lobby).
func in_game() -> bool:
	return is_active() and _started


## This instance's squad index (0 = Alpha), or -1 if not in a session yet.
func my_squad() -> int:
	if not is_active():
		return -1
	var me: Dictionary = roster.get(multiplayer.get_unique_id(), {})
	return me.get("squad", -1)


## Squad indices of everyone in the session (including us).
func squads_present() -> Array:
	var squads := []
	for id in roster:
		squads.append(roster[id]["squad"])
	return squads


## Peer id of the game playing as `squad`, or 0 if nobody is.
func _peer_of_squad(squad: int) -> int:
	for id in roster:
		if roster[id]["squad"] == squad:
			return id
	return 0


## Squad of whoever sent the RPC being handled, or -1.
func _sender_squad() -> int:
	var entry: Dictionary = roster.get(multiplayer.get_remote_sender_id(), {})
	return entry.get("squad", -1)


## Roster entry for a squad index, or {} if that squad is open.
func squad_entry(squad: int) -> Dictionary:
	for id in roster:
		if roster[id]["squad"] == squad:
			return roster[id]
	return {}


## True when every squad in the session has players and all of them are ready.
func all_squads_ready() -> bool:
	if roster.is_empty():
		return false
	for id in roster:
		var e: Dictionary = roster[id]
		if e["joined"] == 0 or e["ready"] < e["joined"]:
			return false
	return true


## The name this game gives the host for its roster entry. Deliberately not
## the computer's user name, which shouldn't go out on the LAN unasked.
func local_name() -> String:
	return "Player"


# --- Hosting ----------------------------------------------------------------

## Default game name, used until the host types their own (which is saved).
func default_game_name() -> String:
	return "Squads game"


## Trim a game name to something sensible to show in the join list.
func clean_game_name(text: String) -> String:
	text = text.strip_edges().left(MAX_NAME_LENGTH).strip_edges()
	return text if not text.is_empty() else default_game_name()


func host(name_for_game: String, mode_for_game: String, custom := {}) -> Error:
	if not is_supported():
		return ERR_UNAVAILABLE
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_SQUADS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	_started = false
	_session_id = "%x%x" % [Time.get_ticks_usec(), randi()]
	game_name = clean_game_name(name_for_game)
	game_mode = mode_for_game
	custom_settings = custom.duplicate(true)
	roster = {1: _entry(0, local_name())}

	_discovery = PacketPeerUDP.new()
	if _discovery.bind(DISCOVERY_PORT) != OK:
		# Still hosting, but nobody can find us (another host on this machine?).
		push_warning("Squads: couldn't listen for LAN discovery on port %d" % DISCOVERY_PORT)
		_discovery = null
	roster_changed.emit()
	return OK


## Host only: tell every squad to start, with these Campaign modifiers
## (BraidModifiers ids). Returns false if not everyone's ready.
func start_game(mods: Array = []) -> bool:
	if not is_host() or not all_squads_ready():
		return false
	_started = true
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	_begin.rpc(randi(), mods)
	return true


func _answer_queries() -> void:
	while _discovery.get_available_packet_count() > 0:
		var packet := _discovery.get_packet()
		var ip := _discovery.get_packet_ip()
		var port := _discovery.get_packet_port()
		var msg: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not (msg is Dictionary) or msg.get("game") != GAME_ID or msg.get("type") != "query":
			continue
		var reply := {
			"game": GAME_ID, "type": "host", "v": PROTOCOL_VERSION,
			"id": _session_id, "name": game_name, "port": GAME_PORT,
			"squads": roster.size(), "open": not _started and roster.size() < MAX_SQUADS,
			"mode": game_mode,
		}
		_discovery.set_dest_address(ip, port)
		_discovery.put_packet(JSON.stringify(reply).to_utf8_buffer())


func _on_peer_connected(_id: int) -> void:
	pass  # Wait for _register; the joiner sends it as soon as it connects.


func _on_peer_disconnected(id: int) -> void:
	if is_host() and roster.erase(id):
		# Forget what it said about the wave, so the checks below only go by
		# squads still here.
		_ready_for_wave.erase(id)
		_down.erase(id)
		_push_roster()
		# The squad that left may have been the last one everyone was waiting on.
		_check_wave_begin()
		_check_all_down()


@rpc("any_peer", "reliable")
func _register(player_name: String, version: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if version != PROTOCOL_VERSION:
		reason = "That host is running a different version of the game."
	elif _started:
		reason = "That game has already started."
	var squad := _free_squad()
	if reason.is_empty() and squad == -1:
		reason = "That game is full."
	if not reason.is_empty():
		_rejected.rpc_id(id, reason)
		return
	roster[id] = _entry(squad, player_name)
	_push_roster()


@rpc("any_peer", "reliable")
func _status(joined_count: int, ready_count: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id):
		roster[id]["joined"] = joined_count
		roster[id]["ready"] = ready_count
		_push_roster()


func _free_squad() -> int:
	for squad in MAX_SQUADS:
		if squad_entry(squad).is_empty():
			return squad
	return -1


func _push_roster() -> void:
	_sync_roster.rpc(roster, game_mode, custom_settings)
	roster_changed.emit()


# --- Joining ----------------------------------------------------------------

## Start looking for hosts on the LAN. hosts_changed fires as they come and go.
func start_browsing() -> void:
	if not is_supported():
		return
	stop_browsing()
	hosts.clear()
	_discovery = PacketPeerUDP.new()
	_discovery.set_broadcast_enabled(true)
	if _discovery.bind(0) != OK:
		push_warning("Squads: couldn't open a socket for LAN discovery")
		_discovery = null
		return
	_browsing = true
	_query_timer = 0.0
	hosts_changed.emit()


func stop_browsing() -> void:
	if _browsing and _discovery:
		_discovery.close()
		_discovery = null
	_browsing = false


## Parse a typed address: "1.2.3.4", "host.name", "host:port", "[::1]:port" or a
## bare IPv6 address. Hostnames aren't looked up here: pass "host" to
## resolve_host. Returns {"host", "port"} on success, or {"error": message}.
func parse_address(text: String) -> Dictionary:
	var address := text.strip_edges()
	var port := GAME_PORT
	if address.is_empty():
		return {"error": "Type the host's IP address or hostname."}
	var port_text := ""
	if address.begins_with("["):  # [IPv6]:port
		var close := address.find("]")
		if close == -1:
			return {"error": "Missing ] in \"%s\"." % address}
		port_text = address.substr(close + 1).trim_prefix(":")
		address = address.substr(1, close - 1)
	elif address.count(":") == 1:  # host:port (more colons means bare IPv6)
		port_text = address.get_slice(":", 1)
		address = address.get_slice(":", 0)
	if not port_text.is_empty():
		if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
			return {"error": "\"%s\" isn't a valid port." % port_text}
		port = int(port_text)
	if address.is_empty():
		return {"error": "Type the host's IP address or hostname."}
	return {"host": address, "port": port}


## The IP address of `host` (an IP address already, or a hostname to look
## up), or "" if it can't be found. A coroutine (await it): the lookup runs
## in the background so the game doesn't freeze on a slow DNS server.
func resolve_host(host: String) -> String:
	if host.is_valid_ip_address():
		return host
	# Prefer IPv4: port forwarding on home routers is almost always IPv4.
	for type: IP.Type in [IP.TYPE_IPV4, IP.TYPE_ANY]:
		var id := IP.resolve_hostname_queue_item(host, type)
		if id == IP.RESOLVER_INVALID_ID:
			continue
		while IP.get_resolve_item_status(id) == IP.RESOLVER_STATUS_WAITING:
			await get_tree().process_frame
		var ip := ""
		if IP.get_resolve_item_status(id) == IP.RESOLVER_STATUS_DONE:
			ip = IP.get_resolve_item_address(id)
		IP.erase_resolve_item(id)
		if not ip.is_empty():
			return ip
	return ""


func join(ip: String, port: int) -> Error:
	if not is_supported():
		return ERR_UNAVAILABLE
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	_join_attempt += 1
	var attempt := _join_attempt
	get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(func():
		if attempt == _join_attempt and mode == Mode.CLIENT \
				and peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			_on_connection_failed())
	return OK


func _send_query() -> void:
	var packet := JSON.stringify({"game": GAME_ID, "type": "query", "v": PROTOCOL_VERSION}).to_utf8_buffer()
	# Broadcast for other machines; loopback so a host on this machine shows up too.
	for address in ["255.255.255.255", "127.0.0.1"]:
		_discovery.set_dest_address(address, DISCOVERY_PORT)
		_discovery.put_packet(packet)


func _read_replies() -> void:
	var changed := false
	var now := Time.get_ticks_msec()
	while _discovery.get_available_packet_count() > 0:
		var packet := _discovery.get_packet()
		var ip := _discovery.get_packet_ip()
		var msg: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not (msg is Dictionary) or msg.get("game") != GAME_ID or msg.get("type") != "host":
			continue
		if int(msg.get("v", 0)) != PROTOCOL_VERSION:
			continue
		var id := str(msg.get("id", ""))
		var info := {
			"ip": ip, "port": int(msg.get("port", GAME_PORT)),
			"name": str(msg.get("name", "?")).strip_edges().left(MAX_NAME_LENGTH), "squads": int(msg.get("squads", 1)),
			"open": bool(msg.get("open", false)), "seen": now,
			"mode": str(msg.get("mode", "standard")),
		}
		var old: Dictionary = hosts.get(id, {})
		if not old.is_empty():
			info["ip"] = old["ip"]  # Same host seen via broadcast and loopback.
			changed = changed or old["squads"] != info["squads"] or old["open"] != info["open"]
		else:
			changed = true
		hosts[id] = info
	for id in hosts.keys():
		if now - hosts[id]["seen"] > HOST_TIMEOUT * 1000.0:
			hosts.erase(id)
			changed = true
	if changed:
		hosts_changed.emit()


func _on_connected_to_server() -> void:
	_register.rpc_id(1, local_name(), PROTOCOL_VERSION)


func _on_connection_failed() -> void:
	_end(CONNECT_FAILED)


func _on_server_disconnected() -> void:
	_end("The host left the game.")


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	_end(reason)


@rpc("authority", "reliable")
func _sync_roster(new_roster: Dictionary, mode_of_game: String, custom: Dictionary) -> void:
	var was_waiting := my_squad() == -1
	roster = new_roster
	game_mode = mode_of_game
	custom_settings = custom
	if my_squad() == -1:
		if not was_waiting:
			# We were dropped from the roster; nothing to stay connected for.
			_end("You were removed from the game.")
		return
	if was_waiting:
		joined.emit()
	roster_changed.emit()


# --- Shared -----------------------------------------------------------------

## Report this squad's local player counts (from character select).
func set_local_status(joined_count: int, ready_count: int) -> void:
	var me: Dictionary = roster.get(multiplayer.get_unique_id(), {})
	if me.is_empty() or (me["joined"] == joined_count and me["ready"] == ready_count):
		return
	me["joined"] = joined_count
	me["ready"] = ready_count
	if is_host():
		_push_roster()
	else:
		_status.rpc_id(1, joined_count, ready_count)
		roster_changed.emit()


@rpc("authority", "call_local", "reliable")
func _begin(seed_for_run: int, mods: Array) -> void:
	run_seed = seed_for_run
	modifiers = mods.duplicate()
	_started = true
	game_starting.emit()


# --- In game ----------------------------------------------------------------

## Host: share the current wave's clock with the other squads.
func send_wave_clock(index: int, elapsed: float) -> void:
	if is_host() and roster.size() > 1:
		_wave_clock.rpc(index, elapsed)


@rpc("authority", "unreliable_ordered")
func _wave_clock(index: int, elapsed: float) -> void:
	# The host's time was this old when it arrived: half a round trip.
	var latency := 0.0
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var host_peer := enet.get_peer(1) if enet else null
	if host_peer:
		latency = host_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 2000.0
	wave_clock.emit(index, elapsed + latency)


## Host: this wave is over for everyone (`failed`: its objective failed).
func end_wave(index: int, failed := false) -> void:
	if is_host():
		_down.clear()
		_wave_ended.rpc(index, failed)


@rpc("authority", "reliable")
func _wave_ended(index: int, failed: bool) -> void:
	wave_ended.emit(index, failed)


## This squad is done shopping and ready for wave `index`.
func report_ready_for_wave(index: int) -> void:
	if is_host():
		_ready_for_wave[1] = index
		_check_wave_begin()
	elif is_active():
		_ready_for_wave_rpc.rpc_id(1, index)


@rpc("any_peer", "reliable")
func _ready_for_wave_rpc(index: int) -> void:
	if is_host():
		_ready_for_wave[multiplayer.get_remote_sender_id()] = index
		_check_wave_begin()


## Host: starts the wave once every squad still here is ready for the same
## one as us. (A report about another wave, like a late one from before,
## just waits to be replaced by that squad's next.)
func _check_wave_begin() -> void:
	if not is_host() or not _ready_for_wave.has(1):
		return
	var index: int = _ready_for_wave[1]
	for id in roster:
		if _ready_for_wave.get(id, -1) != index:
			return
	_ready_for_wave.clear()
	_wave_begin.rpc(index)


@rpc("authority", "call_local", "reliable")
func _wave_begin(index: int) -> void:
	wave_begin.emit(index)


## Every player in this squad is down during wave `index`.
func report_squad_down(index: int) -> void:
	if is_host():
		_down[1] = index
		_check_all_down()
	elif is_active():
		_squad_down_rpc.rpc_id(1, index)


@rpc("any_peer", "reliable")
func _squad_down_rpc(index: int) -> void:
	if is_host():
		_down[multiplayer.get_remote_sender_id()] = index
		_check_all_down()


## Host: every squad still here (us too) is down in the same wave.
func _check_all_down() -> void:
	if not is_host() or not _down.has(1):
		return
	var index: int = _down[1]
	for id in roster:
		if _down.get(id, -1) != index:
			return
	_down.clear()
	_all_down.rpc(index)


@rpc("authority", "call_local", "reliable")
func _all_down(index: int) -> void:
	all_squads_down.emit(index)


## Host: end the game and send every squad back to character select.
func return_to_lobby() -> void:
	if is_host():
		_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _to_lobby() -> void:
	_started = false
	_ready_for_wave.clear()
	_down.clear()
	if is_host():
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
		# Everyone picks players again; character select reports the new counts.
		for id in roster:
			roster[id]["joined"] = 0
			roster[id]["ready"] = 0
		_push_roster()
	returned_to_lobby.emit()


## The run is over (won or lost): our squad's results for everyone's summary
## screen. `results` is plain data (see game.gd _cash_in_resources).
func send_final_results(results: Dictionary) -> void:
	if in_game() and roster.size() > 1:
		_net_final_results.rpc(results)


@rpc("any_peer", "reliable")
func _net_final_results(results: Dictionary) -> void:
	var squad := _sender_squad()
	if squad >= 0:
		final_results.emit(squad, results)


# --- World sync (scripts/net/squad_link.gd) ------------------------------------

## Our players' states (and shots fired since last time), to everyone.
func send_players(players: Array, shots: Array) -> void:
	if in_game() and roster.size() > 1:
		_net_players.rpc(players, shots)


@rpc("any_peer", "unreliable_ordered")
func _net_players(players: Array, shots: Array) -> void:
	var squad := _sender_squad()
	if squad >= 0:
		remote_players.emit(squad, players, shots)


## Our enemies near `to_squad`'s map, to that squad.
func send_enemies(to_squad: int, wave: int, ids: PackedInt32Array,
		positions: PackedVector2Array, kinds: PackedByteArray, states: PackedByteArray) -> void:
	var peer := _peer_of_squad(to_squad)
	if in_game() and peer != 0:
		_net_enemies.rpc_id(peer, wave, ids, positions, kinds, states)


@rpc("any_peer", "unreliable_ordered")
func _net_enemies(wave: int, ids: PackedInt32Array, positions: PackedVector2Array,
		kinds: PackedByteArray, states: PackedByteArray) -> void:
	var squad := _sender_squad()
	if squad >= 0:
		remote_enemies.emit(squad, wave, ids, positions, kinds, states)


## One of our players hit `owner_squad`'s enemy.
func send_enemy_hit(owner_squad: int, enemy_id: int, damage: int, shooter_slot: int,
		knockback := Vector2.ZERO) -> void:
	var peer := _peer_of_squad(owner_squad)
	if in_game() and peer != 0:
		_net_enemy_hit.rpc_id(peer, enemy_id, damage, shooter_slot, knockback)


@rpc("any_peer", "reliable")
func _net_enemy_hit(enemy_id: int, damage: int, shooter_slot: int, knockback: Vector2) -> void:
	var squad := _sender_squad()
	if squad >= 0:
		enemy_hit.emit(squad, enemy_id, damage, shooter_slot, knockback)


## One of our enemies died, to everyone. killer_squad is -1 unless another
## squad's player finished it off.
func send_enemy_died(enemy_id: int, killer_squad: int, killer_slot: int,
		points: int, drops: int, at: Vector2) -> void:
	if in_game() and roster.size() > 1:
		_net_enemy_died.rpc(enemy_id, killer_squad, killer_slot, points, drops, at)


@rpc("any_peer", "reliable")
func _net_enemy_died(enemy_id: int, killer_squad: int, killer_slot: int,
		points: int, drops: int, at: Vector2) -> void:
	var squad := _sender_squad()
	if squad >= 0:
		enemy_died.emit(squad, enemy_id, killer_squad, killer_slot, points, drops, at)


# --- Objective waves (scripts/objectives/objective.gd) ---------------------------

## Our squad's report on wave `wave`'s objective, for the host.
func send_objective_report(wave: int, data: Dictionary) -> void:
	if is_host():
		objective_report.emit(my_squad(), wave, data)
	elif in_game():
		_net_objective_report.rpc_id(1, wave, data)


@rpc("any_peer", "reliable")
func _net_objective_report(wave: int, data: Dictionary) -> void:
	var squad := _sender_squad()
	if is_host() and squad >= 0:
		objective_report.emit(squad, wave, data)


## Host: the objective's state, for every other squad.
func send_objective_state(wave: int, data: Dictionary) -> void:
	if is_host() and in_game() and roster.size() > 1:
		_net_objective_state.rpc(wave, data)


@rpc("authority", "reliable")
func _net_objective_state(wave: int, data: Dictionary) -> void:
	objective_state.emit(wave, data)


# --- Game-mode messages ---------------------------------------------------------

## Sends `data` (plain data, first item = its kind) to `to_squad`'s game, or to
## every other squad's if `to_squad` is -1. `reliable`: false for frequent
## updates where only the latest matters.
func send_mode_message(to_squad: int, data: Array, reliable := true) -> void:
	if not in_game() or roster.size() < 2:
		return
	if to_squad < 0:
		if reliable:
			_net_mode_message.rpc(data)
		else:
			_net_mode_stream.rpc(data)
		return
	var peer := _peer_of_squad(to_squad)
	if peer == 0 or to_squad == my_squad():
		return
	if reliable:
		_net_mode_message.rpc_id(peer, data)
	else:
		_net_mode_stream.rpc_id(peer, data)


@rpc("any_peer", "reliable")
func _net_mode_message(data: Array) -> void:
	var squad := _sender_squad()
	if squad >= 0:
		mode_message.emit(squad, data)


@rpc("any_peer", "unreliable_ordered")
func _net_mode_stream(data: Array) -> void:
	var squad := _sender_squad()
	if squad >= 0:
		mode_message.emit(squad, data)


## Close any session and stop discovery. Safe to call when not in a session.
func leave() -> void:
	stop_browsing()
	if _discovery:
		_discovery.close()
		_discovery = null
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE
	roster = {}
	_started = false
	_ready_for_wave.clear()
	_down.clear()


func _end(reason: String) -> void:
	var was_active := is_active()
	leave()
	if was_active:
		notice = reason
		session_ended.emit(reason)


func _entry(squad: int, player_name: String) -> Dictionary:
	return {"squad": squad, "name": player_name, "joined": 0, "ready": 0}


func _process(delta: float) -> void:
	if _discovery == null:
		return
	if is_host():
		_answer_queries()
	elif _browsing:
		_query_timer -= delta
		if _query_timer <= 0.0:
			_query_timer = QUERY_INTERVAL
			_send_query()
		_read_replies()
