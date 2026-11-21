extends RefCounted
## Every piece of equipment in the game. A player holds at most one: their
## class's starting equipment (scripts/character_classes.gd, if it has one),
## until they buy another in the shop, which replaces it.
##
## Equipment is used with the left trigger on a controller (F on the
## keyboard), then has to recharge (cooldown). Using it puts something into the
## world next to the player (scripts/equipment/*.gd) that lasts for its
## duration. Equipment is never used up, and there's no limit on how many of
## a player's are out at once: whatever is already out stays until it runs
## out. The player's engineering attribute shortens the cooldown,
## lengthens the duration and boosts whatever the item lists in "scales".
## Some stats also grow with the wave (WAVE_SCALING), so equipment keeps up
## with tougher enemies.
##
## Every item is sold in the shop (scripts/items.gd), as often as a Solid
## weapon.
##
## To add one: add an entry to LIST and its script to SCRIPTS.
##   id          - unique key
##   name        - shown in the shop, HUD and stats
##   cost        - shop price in resources
##   blurb       - one line on what it does (shop)
##   duration    - seconds it lasts at 0 engineering (optional, default
##                 DEFAULT_DURATION; 0 = until triggered or the wave ends)
##   instant     - true for one-off effects with no duration (a grenade)
##   cooldown    - seconds to recharge at 0 engineering (optional, default
##                 COOLDOWN_DEFAULT); engineering scales it the same way
##   scales      - stat keys engineering boosts (x ENGINEERING_POWER_MIN at
##                 -100 .. x ENGINEERING_POWER_MAX at +100; an "interval" is
##                 divided instead, so it fires faster)
##   hidden      - true: only offered to (and tuned for) players whose
##                 TUNING_META lists it (a mode-only item; none right now)
##   pickup      - share of its unused time refunded off the cooldown when
##                 the owner packs it away (uses it again standing beside it)
##   anything else is a stat the item's script reads (see STAT_LABELS for
##   how the shop shows it).
##
## A mode can retune equipment for its players without touching these numbers:
## set TUNING_META on the player (see stats()).

const DEFAULT_DURATION := 12.0

## Cooldown at 0, +100 and -100 engineering. Exponential on each side of 0,
## like the other attributes (e.g. +50 -> ~10s, -50 -> ~34s). (Was 60/10/120;
## durations were 20: Braid's quicker, shorter-lived tuning, now in both modes.)
const COOLDOWN_DEFAULT := 24.0
const COOLDOWN_AT_MAX := 4.0
const COOLDOWN_AT_MIN := 48.0
## Multiplier on durations and "scales" stats at -100 and +100 engineering
## (exponential: +50 -> ~1.41x).
const ENGINEERING_POWER_MIN := 0.5
const ENGINEERING_POWER_MAX := 2.0

## Stats that grow with the wave, so equipment stays useful against tougher
## enemies: each is multiplied by 1 + weight x (the wave's enemy health
## multiplier - 1). Damage keeps up with most of the enemy health growth (0.8:
## at wave 20, 5x enemy health, it does 4.2x), toughness with less, and the
## Gravity Well's pull roughly with enemy speed.
const WAVE_SCALING := {"damage": 0.8, "ramp": 0.8, "health": 0.6, "lives": 0.4, "pull": 0.12}

## A player's equipment_tuning retunes their equipment: {item id or "*":
## {"cooldown": multiplier, "duration": multiplier, "stats": {key: value}}}.
## An item's own entry is laid over "*". Hidden items are offered only to
## players whose tuning names them. Neither mode retunes anything right now
## (both use the numbers below; see scripts/braid/braid_tuning.gd).

## Name colour in the shop.
const COLOR := Color(0.3, 0.9, 0.8)

const LIST := [
	{"id": "turret", "name": "Turret", "cost": 40, "duration": 20.0, "pickup": 1.0,
		"blurb": "Shoots the nearest enemy in range",
		"range": 150.0, "interval": 0.77, "damage": 6, "knockback": 4,
		"scales": ["range", "interval"]},
	{"id": "healing_bubble", "name": "Healing Bubble", "cost": 40,
		"blurb": "Revives fallen players inside it. Staying in it heals hearts",
		"radius": 104.0, "heal_time": 3.0,
		"scales": ["radius"]},
	{"id": "land_mine", "name": "Land Mine", "cost": 25, "duration": 0.0, "cooldown": 12.0,
		"blurb": "Blows up when an enemy steps on it, hurting all enemies nearby",
		"radius": 90.0, "damage": 40, "knockback": 30,
		"scales": ["radius", "damage"]},
	{"id": "decoy", "name": "Decoy", "cost": 30,
		"blurb": "Stands still and draws nearby enemies to it. Takes 10 hits",
		"lure": 300.0, "lives": 10, "invulnerable": 2.0,
		"scales": []},
	{"id": "spike_trap", "name": "Spike Trap", "cost": 30,
		"blurb": "A square of spikes that slows and keeps hurting enemies on it",
		"size": 140.0, "damage": 4, "tick": 0.5, "slow": 0.5,
		"scales": ["damage"]},
	{"id": "freeze_ray", "name": "Freeze Ray", "cost": 35,
		"blurb": "A cold beam where you aim. Freezes enemies in place, never players",
		"range": 180.0, "arc": 50.0, "freeze": 1.3,
		"scales": ["range", "freeze"]},
	{"id": "corrosive_goo", "name": "Corrosive Goo", "cost": 30,
		"blurb": "Eats away at enemies, more the longer they stay in it",
		"radius": 80.0, "damage": 1, "ramp": 1, "tick": 0.5,
		"scales": ["radius"]},
	{"id": "barricade", "name": "Barricade", "cost": 30,
		"blurb": "A wall in front of you. Enemies go around or break through",
		"length": 104.0, "health": 40,
		"scales": ["health"]},
	{"id": "drone", "name": "Drone", "cost": 40, "duration": 20.0,
		"blurb": "Flies alongside you, shooting nearby enemies",
		"range": 160.0, "interval": 0.6, "damage": 4, "knockback": 2,
		"scales": ["range", "interval"]},
	{"id": "cluster_grenade", "name": "Cluster Grenade", "cost": 30, "instant": true,
		"cooldown": 9.0,
		"blurb": "Thrown where you aim. Bursts into smaller blasts",
		"throw": 150.0, "radius": 52.0, "damage": 30, "bomblets": 5, "knockback": 24,
		"scales": ["radius", "damage"]},
	{"id": "gravity_well", "name": "Gravity Well", "cost": 35,
		"blurb": "Drags nearby enemies into its centre",
		"radius": 110.0, "pull": 64.0,
		"scales": ["radius"]},
	{"id": "tesla_coil", "name": "Tesla Coil", "cost": 40, "pickup": 1.0,
		"blurb": "Lightning that jumps between nearby enemies",
		"range": 140.0, "interval": 1.2, "damage": 8, "chains": 4, "chain_range": 70.0,
		"scales": ["damage", "chains"]},
	{"id": "adrenaline_shot", "name": "Adrenaline Shot", "cost": 35,
		"duration": 10.0, "cooldown": 22.5,
		"blurb": "A jab that makes you faster, quicker on the trigger and tougher for a while",
		"speed": 40, "fire_rate": 40, "armor": 40,
		"scales": ["speed", "fire_rate", "armor"]},
	{"id": "riot_shield", "name": "Riot Shield", "cost": 35,
		"duration": 6.0, "cooldown": 24.0,
		"blurb": "Raise a shield and plough through: enemies are shoved aside and can't hurt you by touch",
		"reach": 30.0, "push": 260.0, "damage": 4,
		"scales": ["reach", "damage"]},
	{"id": "air_strike", "name": "Air Strike", "cost": 40, "instant": true,
		"cooldown": 24.0,
		"blurb": "Calls in a bombing run along the way you aim",
		"length": 280.0, "bombs": 7, "radius": 40.0, "damage": 30, "knockback": 20,
		"scales": ["damage", "bombs"]},
	{"id": "caltrop_trail", "name": "Caltrop Trail", "cost": 30,
		"duration": 10.0, "cooldown": 12.0,
		"blurb": "Scatters spikes behind you as you run. They hurt and slow whatever follows",
		"spacing": 14.0, "linger": 6.0, "radius": 10.0, "damage": 3, "tick": 0.5, "slow": 0.6,
		"scales": ["damage", "linger"]},
	{"id": "dash_pack", "name": "Dash Pack", "cost": 35, "instant": true,
		"cooldown": 7.2,
		"blurb": "A burst of speed the way you're going. Nothing can hurt you mid-dash, and enemies you pass are knocked aside",
		"distance": 110.0, "damage": 10, "knockback": 30,
		"scales": ["distance", "damage"]},
]

const SCRIPTS := {
	"turret": preload("res://scripts/equipment/turret.gd"),
	"healing_bubble": preload("res://scripts/equipment/healing_bubble.gd"),
	"land_mine": preload("res://scripts/equipment/land_mine.gd"),
	"decoy": preload("res://scripts/equipment/decoy.gd"),
	"spike_trap": preload("res://scripts/equipment/damage_zone.gd"),
	"freeze_ray": preload("res://scripts/equipment/freeze_ray.gd"),
	"corrosive_goo": preload("res://scripts/equipment/damage_zone.gd"),
	"barricade": preload("res://scripts/equipment/barricade.gd"),
	"drone": preload("res://scripts/equipment/drone.gd"),
	"cluster_grenade": preload("res://scripts/equipment/cluster_grenade.gd"),
	"gravity_well": preload("res://scripts/equipment/gravity_well.gd"),
	"tesla_coil": preload("res://scripts/equipment/tesla_coil.gd"),
	"adrenaline_shot": preload("res://scripts/equipment/adrenaline_shot.gd"),
	"riot_shield": preload("res://scripts/equipment/riot_shield.gd"),
	"air_strike": preload("res://scripts/equipment/air_strike.gd"),
	"caltrop_trail": preload("res://scripts/equipment/caltrop_trail.gd"),
	"dash_pack": preload("res://scripts/equipment/dash_pack.gd"),
}

## How the shop shows each stat: [label, format]. Formats: "px", "per_sec"
## (an interval shown as shots per second), "int", "pct_speed", "deg", "s", "s1" (seconds to one decimal),
## "bonus" (attribute points added, "+40").
const STAT_LABELS := [
	["damage", "Damage", "int"],
	["interval", "Fire rate", "per_sec"],
	["range", "Range", "px"],
	["radius", "Radius", "px"],
	["size", "Size", "px"],
	["lure", "Lure range", "px"],
	["lives", "Hits", "int"],
	["health", "Toughness", "int"],
	["chains", "Jumps", "int"],
	["bomblets", "Bomblets", "int"],
	["throw", "Throw", "px"],
	["pull", "Pull", "int"],
	["slow", "Enemy speed", "pct_speed"],
	["freeze", "Freeze", "s1"],
	["arc", "Width", "deg"],
	["heal_time", "Heal every", "s"],
	["speed", "Speed", "bonus"],
	["fire_rate", "Fire rate", "bonus"],
	["armor", "Armor", "bonus"],
	["reach", "Reach", "px"],
	["push", "Shove", "int"],
	["bombs", "Bombs", "int"],
	["length", "Run length", "px"],
	["distance", "Dash", "px"],
	["linger", "Spikes last", "s"],
]


static func find(id: String) -> Dictionary:
	for item in LIST:
		if item["id"] == id:
			return item
	return {}


static func _t(engineering: int) -> float:
	return clampi(engineering, -100, 100) / 100.0


## Seconds to recharge after a use: 48s at -100, 24s at 0, 4s at +100.
## An item with its own `base` cooldown (at 0 engineering) scales the same
## way: / 6 at +100, x 2 at -100 (9s -> 1.5s .. 18s).
static func cooldown(engineering: int, base := COOLDOWN_DEFAULT) -> float:
	var t := _t(engineering)
	var end := COOLDOWN_AT_MAX if t >= 0.0 else COOLDOWN_AT_MIN
	return base * pow(end / COOLDOWN_DEFAULT, absf(t))


## x0.5 at -100, x1 at 0, x2 at +100.
static func power(engineering: int) -> float:
	var t := _t(engineering)
	var end := ENGINEERING_POWER_MAX if t >= 0.0 else ENGINEERING_POWER_MIN
	return pow(end, absf(t))


## Multiplier on WAVE_SCALING stat `key` in a wave with this enemy health
## multiplier.
static func wave_mult(key: String, enemy_health: float) -> float:
	return 1.0 + WAVE_SCALING.get(key, 0.0) * maxf(enemy_health - 1.0, 0.0)


## `item`'s numbers for a player with this engineering in a wave with this
## enemy health multiplier: every stat in the entry (with "scales" ones
## boosted by engineering and WAVE_SCALING ones by the wave), plus "cooldown"
## and "duration" (0 = until triggered, or instant). `tuning` is a player's
## TUNING_META ({} = none).
static func stats(item: Dictionary, engineering: int, enemy_health := 1.0, tuning := {}) -> Dictionary:
	var mult := power(engineering)
	var result := {}
	for key in item:
		var value: Variant = item[key]
		if (value is float or value is int) and key != "cost":
			result[key] = value
	for key in item.get("scales", []):
		if key == "interval":
			result[key] = item[key] / mult
		elif item[key] is int:
			result[key] = maxi(roundi(item[key] * mult), 1)
		else:
			result[key] = item[key] * mult
	for key in WAVE_SCALING:
		if result.has(key):
			var grown: float = result[key] * wave_mult(key, enemy_health)
			result[key] = maxi(roundi(grown), 1) if result[key] is int else grown
	result["cooldown"] = cooldown(engineering, float(item.get("cooldown", COOLDOWN_DEFAULT)))
	if item.get("instant", false):
		result["duration"] = 0.0
	else:
		result["duration"] = float(item.get("duration", DEFAULT_DURATION)) * mult
	var rules := tuning_for(item.get("id", ""), tuning)
	result["cooldown"] *= float(rules.get("cooldown", 1.0))
	result["duration"] *= float(rules.get("duration", 1.0))
	var extra: Dictionary = rules.get("stats", {})
	for key in extra:
		result[key] = extra[key]
	return result


## The rules `tuning` (a TUNING_META) has for item `id`: its own entry laid
## over "*" ({} if neither).
static func tuning_for(id: String, tuning: Dictionary) -> Dictionary:
	var rules: Dictionary = tuning.get("*", {}).duplicate()
	rules.merge(tuning.get(id, {}), true)
	return rules


## Whether `player` can have `item`: hidden items only with a tuning that
## names them.
static func available_to(item: Dictionary, player: Node) -> bool:
	if not item.get("hidden", false):
		return true
	return player.equipment_tuning.has(item.get("id", ""))


## Shop lines for `item` in the hands of a player with this engineering:
## cooldown and duration, then its own stats, two to a line.
static func describe(item: Dictionary, engineering: int, enemy_health := 1.0,
		tuning := {}) -> PackedStringArray:
	var s := stats(item, engineering, enemy_health, tuning)
	var lines: PackedStringArray = []
	var top := "Cooldown  %ds" % roundi(s["cooldown"])
	if not item.get("instant", false):
		var lasts := "until triggered" if s["duration"] <= 0.0 else "%ds" % roundi(s["duration"])
		top += "     Lasts  %s" % lasts
	lines.append(top)
	var parts: PackedStringArray = []
	for entry in STAT_LABELS:
		var key: String = entry[0]
		if not s.has(key):
			continue
		var value: float = s[key]
		var text := ""
		match entry[2]:
			"per_sec":
				text = "%.1f/s" % (1.0 / value)
			"pct_speed":
				text = "%d%%" % roundi(value * 100.0)
			"deg":
				text = "%d°" % roundi(value)
			"s":
				text = "%ds" % roundi(value)
			"s1":
				text = "%.1fs" % value
			"bonus":
				text = "%+d" % roundi(value)
			_:
				text = str(roundi(value))
		parts.append("%s  %s" % [entry[1], text])
	for i in range(0, parts.size(), 2):
		lines.append("     ".join(parts.slice(i, i + 2)))
	if s.get("pickup", 0.0) > 0.0:
		lines.append("Use it again beside it to pack it away (refunds cooldown)")
	return lines


## A new deployable for `item`, owned by `player`, using `item_stats` (from
## stats()). The caller positions it and adds it to the world.
static func create(item: Dictionary, player: Node, item_stats: Dictionary) -> Node2D:
	var node: Node2D = SCRIPTS[item["id"]].new()
	node.kind = item["id"]
	node.owner_player = player
	node.stats = item_stats
	node.duration = item_stats["duration"]
	return node
