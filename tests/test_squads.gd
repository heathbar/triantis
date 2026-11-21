extends "res://tests/test_case.gd"
## The Squads autoload's address parsing and the host's wave bookkeeping.


func test_parse_address() -> void:
	var port: int = Squads.GAME_PORT
	check_eq(Squads.parse_address("192.168.1.20"), {"host": "192.168.1.20", "port": port}, "IPv4")
	check_eq(Squads.parse_address("  example.lan  "), {"host": "example.lan", "port": port},
		"hostname, trimmed")
	check_eq(Squads.parse_address("example.lan:5000"), {"host": "example.lan", "port": 5000},
		"host:port")
	check_eq(Squads.parse_address("[::1]:6000"), {"host": "::1", "port": 6000}, "[IPv6]:port")
	check_eq(Squads.parse_address("fe80::1"), {"host": "fe80::1", "port": port}, "bare IPv6")
	check(Squads.parse_address("").has("error"), "empty")
	check(Squads.parse_address("host:99999").has("error"), "port out of range")
	check(Squads.parse_address("host:abc").has("error"), "port not a number")
	check(Squads.parse_address("[::1").has("error"), "missing ]")


func test_resolve_host_passes_ips_through() -> void:
	var ip: String = await Squads.resolve_host("10.0.0.7")
	check_eq(ip, "10.0.0.7", "an IP address needs no lookup")


func test_departed_squad_does_not_hold_up_the_wave() -> void:
	var began: Array[int] = []
	var on_begin := func(index: int) -> void: began.append(index)
	Squads.wave_begin.connect(on_begin)
	# A host (peer 1) and a joiner (peer 5) that said it was ready for an
	# earlier wave, then left.
	Squads.mode = Squads.Mode.HOST
	Squads.roster = {1: Squads._entry(0, "Player"), 5: Squads._entry(1, "Player")}
	Squads._ready_for_wave = {5: 2}
	Squads.report_ready_for_wave(3)
	check(began.is_empty(), "waits for the joiner while it's here")
	Squads._on_peer_disconnected(5)
	check_eq(began, [3] as Array[int], "starts once the joiner is gone")
	Squads.wave_begin.disconnect(on_begin)
	Squads.leave()


func test_all_down_goes_by_the_current_wave() -> void:
	var down: Array[int] = []
	var on_down := func(index: int) -> void: down.append(index)
	Squads.all_squads_down.connect(on_down)
	Squads.mode = Squads.Mode.HOST
	Squads.roster = {1: Squads._entry(0, "Player"), 5: Squads._entry(1, "Player")}
	# The joiner's report from the last wave arrived after that wave ended.
	Squads._down = {5: 4}
	Squads.report_squad_down(5)
	check(down.is_empty(), "an old report doesn't count")
	Squads._down[5] = 5  # Its report for this wave.
	Squads._check_all_down()
	check_eq(down, [5] as Array[int], "every squad down in wave 5")
	Squads.all_squads_down.disconnect(on_down)
	Squads.leave()
