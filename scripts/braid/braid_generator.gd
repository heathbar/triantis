@tool
extends RefCounted
## Lays out a Braid act from a seed and a lane count (one lane per squad).
## The same seed and lane count always give the same layout, so every game in
## a run builds the same level without sending it.
##
## An act is segments; a segment is slots side by side across every lane, so
## all lanes line up in x (one tide, one row of checkpoint gates):
##   - an opener slot (a screen long): a "start" strip to open each act
##     (where the squads spawn, including after a boss), or sometimes
##     (CALM_CHANCE) a "calm" strip after a checkpoint,
##   - then SLOT_LENGTH slots, one "normal" strip per lane, until the
##     segment holds about one of SEGMENT_LENGTHS of tide time.
## Strips aim for a difficulty on a line from DIFFICULTY_FIRST (first segment)
## to DIFFICULTY_LAST (last), and never repeat in a lane back to back;
## neighbouring lanes get different strips where there are enough.
##
## With 2+ lanes, each segment also gets the braid: one slot where pairs of
## neighbouring lanes share a junction (levels/braid/junctions/: the squads
## swap lanes) and, if there's room, another where other pairs share a window.
## Which pairs take turns (the doc's braid pattern):
##   4 lanes: 1-2 and 3-4 junction, 2-3 window; next segment the other way.
##   3 lanes: 1-2 junction, 2-3 window; next segment the other way.
##   2 lanes: 1-2 junction, and a 1-2 window in another slot.
## Vertical slices: twice an act, in two different segments (never the
## act's first), the lanes turn up through a corner, run up for
## SLICE_STRIPS_BY_LANES strips, and turn back to running right; once up,
## once down (which comes first is by the seed). A slice goes after its
## segment's first normal slot, and counts toward the segment's tide time;
## junctions and windows stay out of it (BraidLevel needs the lanes running
## right for those).
## BraidLevel.build then checks the result (doors, a way through, widths).
##
## Layout format (BraidLevel.build takes it):
##   {"lanes": n, "segments": [{"slots": [slot, ...]}, ...]}
##   slot: {"length": px, "strips": [name per lane, "" where a junction
##     covers it], "seams": [per pair of lanes k/k+1: "solid", "window" or
##     "junction"], "junctions": {pair k: junction scene name}}
##   A slice's slots also have "slice": true; its corners are
##     {"corner": "up" / "down" / "right" (the way out), "length": 0, ...}
##     (strips all "", seams all "solid").

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")

const STRIP_DIR := "res://levels/braid/strips/"
const JUNCTION_DIR := "res://levels/braid/junctions/"

## Every strip: [{"name", "length", "difficulty", "zone", "theme",
## "seconds" (of tide to cross it), "speed"}], sorted by name. Filled on
## first use (see catalog).
static var _catalog: Array[Dictionary] = []
static var _junctions: Array[Dictionary] = []


## The strips there are. `refresh`: read them again (the editor dock does,
## as strips get edited).
static func catalog(refresh := false) -> Array[Dictionary]:
	if _catalog.is_empty() or refresh:
		_catalog = _read_dir(STRIP_DIR)
	return _catalog


## The junction pieces there are (same fields).
static func junction_catalog(refresh := false) -> Array[Dictionary]:
	if _junctions.is_empty() or refresh:
		_junctions = _read_dir(JUNCTION_DIR)
	return _junctions


static func _read_dir(dir: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for file in ResourceLoader.list_directory(dir):
		if not file.ends_with(".tscn"):
			continue
		var scene: PackedScene = load(dir + file)
		if scene == null:
			continue
		var strip := scene.instantiate()
		if strip.has_method("problems"):
			var speed: float = strip.tide_speed if strip.tide_speed > 0.0 else BraidTuning.TIDE_SPEED
			found.append({
				"name": file.get_basename(),
				"length": float(strip.length),
				"difficulty": int(strip.difficulty),
				"zone": String(strip.zone),
				"theme": String(strip.art_theme),
				"speed": speed,
				"seconds": strip.length / speed,
			})
		strip.free()
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	return found


## Act `act`'s layout for run seed `run_seed` with `lanes` lanes (see the
## layout format above).
static func act_layout(run_seed: int, act := 0, segments := BraidTuning.SEGMENTS_PER_ACT,
		lanes := 1) -> Dictionary:
	lanes = clampi(lanes, 1, BraidTuning.MAX_LANES)
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7919 + act * 104729 + lanes * 15485863 + 1
	var strips := catalog()
	var themes: Array[String] = []
	for s in strips:
		if s["zone"] == "normal" and s["theme"] not in themes:
			themes.append(s["theme"])
	themes.sort()
	if themes.is_empty():
		push_error("Braid: no normal strips in %s" % STRIP_DIR)
		return {"lanes": lanes, "segments": []}
	var theme: String = themes[rng.randi_range(0, themes.size() - 1)]
	var normal := _of(strips, theme, "normal")
	var calm := _of(strips, theme, "calm")
	var start := _of(strips, theme, "start")
	var junctions := junction_catalog()

	# Which segments get a slice, and which way: {segment: true for up}.
	var slice_in := {}
	var candidates := range(1, segments) if segments > 2 else range(segments)
	var going_up := rng.randf() < 0.5
	for k in mini(2, candidates.size()):
		var pick: int = candidates[rng.randi_range(0, candidates.size() - 1)]
		candidates.erase(pick)
		slice_in[pick] = going_up
		going_up = not going_up
	var out_segments := []
	var last := []  # per lane
	for lane in lanes:
		last.append("")
	for i in segments:
		var t := float(i) / float(maxi(segments - 1, 1))
		var target := lerpf(BraidTuning.DIFFICULTY_FIRST, BraidTuning.DIFFICULTY_LAST, t)
		var want_len: float = BraidTuning.SEGMENT_LENGTHS[rng.randi_range(0, BraidTuning.SEGMENT_LENGTHS.size() - 1)]
		var want := want_len / BraidTuning.TIDE_SPEED  # seconds of tide
		var slots := []
		var used := []  # per lane, names used this segment
		for lane in lanes:
			used.append([])
		var seconds := 0.0
		var opener := {}
		if i == 0 and not start.is_empty():
			opener = start[rng.randi_range(0, start.size() - 1)]
		elif i > 0 and not calm.is_empty() and rng.randf() < BraidTuning.CALM_CHANCE:
			opener = calm[rng.randi_range(0, calm.size() - 1)]
		if not opener.is_empty():
			var names := []
			for lane in lanes:
				names.append(opener["name"])
				last[lane] = opener["name"]
			slots.append(_slot(opener["length"], names, lanes))
			seconds += opener["seconds"]
		var first_normal := slots.size()
		# Fill to within a screen's worth of the time wanted (normal slots are
		# two screens, so this stops at the nearer whole slot).
		var screen := BraidTuning.SCREEN_WIDTH / BraidTuning.TIDE_SPEED
		while seconds < want - screen - 0.01:
			var names := []
			var slowest := INF
			for lane in lanes:
				var pick := _pick(rng, normal, target, last[lane], used[lane], want - seconds, names)
				if pick.is_empty():
					break
				names.append(pick["name"])
				used[lane].append(pick["name"])
				last[lane] = pick["name"]
				slowest = minf(slowest, pick["speed"])
			if names.size() < lanes:
				break
			slots.append(_slot(BraidTuning.SLOT_LENGTH, names, lanes))
			seconds += BraidTuning.SLOT_LENGTH / slowest
			if slice_in.has(i) and slots.size() == first_normal + 1:
				seconds += _add_slice(rng, slots, slice_in[i], lanes, normal, target, last, used)
		if lanes > 1:
			_add_braid(rng, slots, first_normal, lanes, i + act * segments, junctions)
		out_segments.append({"slots": slots})
	return {"lanes": lanes, "segments": out_segments}


## Appends a vertical slice (up or down) to `slots`: a corner, the vertical
## strips (picked per lane as normal slots are), and a corner back to running
## right. Returns about how many seconds of tide it adds.
static func _add_slice(rng: RandomNumberGenerator, slots: Array, up: bool, lanes: int,
		normal: Array[Dictionary], target: float, last: Array, used: Array) -> float:
	var band := BraidTuning.BAND_HEIGHT
	slots.append(_corner("up" if up else "down", lanes))
	var count: int = BraidTuning.SLICE_STRIPS_BY_LANES[clampi(lanes - 1, 0, BraidTuning.SLICE_STRIPS_BY_LANES.size() - 1)]
	var length := 0.0
	for n in count:
		var names := []
		for lane in lanes:
			var pick := _pick(rng, normal, target, last[lane], used[lane], INF, names)
			if pick.is_empty():
				break
			names.append(pick["name"])
			used[lane].append(pick["name"])
			last[lane] = pick["name"]
		if names.size() < lanes:
			break
		var slot := _slot(BraidTuning.SLOT_LENGTH, names, lanes)
		slot["slice"] = true
		slots.append(slot)
		length += BraidTuning.SLOT_LENGTH
	slots.append(_corner("right", lanes))
	# Both corners: every lane's arms add up to 2 * (lanes - 1) bands, plus
	# two turning squares.
	length += 2.0 * (lanes - 1) * band + 2.0 * band * PI / 4.0
	return length / (BraidTuning.TIDE_SPEED * BraidTuning.VERTICAL_TIDE_FACTOR)


static func _corner(way: String, lanes: int) -> Dictionary:
	var slot := _slot(0.0, [], lanes)
	for lane in lanes:
		slot["strips"].append("")
	slot["corner"] = way
	slot["slice"] = true
	return slot


## A one-lane layout from strip names, one array per segment (strip tests).
static func single_lane(segments_of_names: Array) -> Dictionary:
	var info := {}
	for s in catalog():
		info[s["name"]] = s
	var out := []
	for names in segments_of_names:
		var slots := []
		for n in names:
			slots.append(_slot(info.get(n, {}).get("length", BraidTuning.SLOT_LENGTH), [n], 1))
		out.append({"slots": slots})
	return {"lanes": 1, "segments": out}


## Segment `seg` of `layout`, lane by lane: the strip names in each slot
## ("[name]" for a junction), for showing.
static func strip_names(layout: Dictionary, seg: int) -> Array:
	var lanes := []
	for lane in int(layout["lanes"]):
		var names := []
		for slot in layout["segments"][seg]["slots"]:
			if slot.has("corner"):
				names.append("(turn %s)" % slot["corner"])
				continue
			var n: String = slot["strips"][lane]
			if n.is_empty():
				for pair in slot["junctions"]:
					if lane == pair or lane == pair + 1:
						n = "[%s]" % slot["junctions"][pair]
			names.append(n)
		lanes.append(names)
	return lanes


static func _slot(length: float, strips: Array, lanes: int) -> Dictionary:
	var seams := []
	for k in lanes - 1:
		seams.append("solid")
	return {"length": length, "strips": strips.duplicate(), "seams": seams, "junctions": {}}


## The segment's junction and window (see the pattern above). `turn` counts
## segments through the run, to alternate the pairs.
static func _add_braid(rng: RandomNumberGenerator, slots: Array, first_normal: int,
		lanes: int, turn: int, junctions: Array[Dictionary]) -> void:
	var normal_slots := range(first_normal, slots.size()).filter(func(k: int) -> bool:
		return not slots[k].get("slice", false))
	if normal_slots.is_empty() or junctions.is_empty():
		return
	var even := turn % 2 == 0
	var junction_pairs: Array = []
	var window_pairs: Array = []
	match lanes:
		2:
			junction_pairs = [0]
			window_pairs = [0]
		3:
			junction_pairs = [0] if even else [1]
			window_pairs = [1] if even else [0]
		_:
			junction_pairs = [0, 2] if even else [1]
			window_pairs = [1] if even else [0, 2]
	# The junction goes after the first normal slot when there's room, so the
	# squads have a stretch to themselves first.
	var choices: Array = normal_slots.slice(1) if normal_slots.size() > 1 else normal_slots
	var j_index: int = choices[rng.randi_range(0, choices.size() - 1)]
	var piece: Dictionary = junctions[rng.randi_range(0, junctions.size() - 1)]
	var slot: Dictionary = slots[j_index]
	for pair in junction_pairs:
		slot["seams"][pair] = "junction"
		slot["junctions"][pair] = piece["name"]
		slot["strips"][pair] = ""
		slot["strips"][pair + 1] = ""
	var others := normal_slots.filter(func(k: int) -> bool: return k != j_index)
	if others.is_empty():
		return
	var w_slot: Dictionary = slots[others[rng.randi_range(0, others.size() - 1)]]
	for pair in window_pairs:
		w_slot["seams"][pair] = "window"


static func _of(strips: Array[Dictionary], theme: String, zone: String) -> Array[Dictionary]:
	return strips.filter(func(s: Dictionary) -> bool: return s["theme"] == theme and s["zone"] == zone)


## A strip to add: weighted toward `target` difficulty, not `last`, not
## already used STRIP_REPEATS times in `used`, preferably taking no longer
## than `room` (seconds of tide left to fill) and not in `avoid` (the other
## lanes' strips in this slot).
static func _pick(rng: RandomNumberGenerator, pool: Array[Dictionary], target: float,
		last: String, used: Array, room: float, avoid: Array = []) -> Dictionary:
	var options: Array[Dictionary] = []
	var weights: Array[float] = []
	for strict in [true, false]:
		for s in pool:
			if s["name"] == last or used.count(s["name"]) >= BraidTuning.STRIP_REPEATS:
				continue
			if strict and (s["name"] in avoid
					or s["seconds"] > room + BraidTuning.SCREEN_WIDTH / 2.0 / BraidTuning.TIDE_SPEED):
				continue
			options.append(s)
			var off := absf(float(s["difficulty"]) - target)
			weights.append(1.0 / pow(1.0 + off, 2.5))
		if not options.is_empty():
			break
	if options.is_empty():
		# A tiny pool: allow anything but a repeat of the last one.
		for s in pool:
			if s["name"] != last:
				options.append(s)
				weights.append(1.0)
	if options.is_empty():
		return pool[0] if not pool.is_empty() else {}
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	for k in options.size():
		roll -= weights[k]
		if roll <= 0.0:
			return options[k]
	return options[-1]
