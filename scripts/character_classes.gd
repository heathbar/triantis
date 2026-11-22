extends RefCounted
## Character classes and the attributes they start with.
##
## Lives is a plain count of whole hearts (4 = average, never below LIVES_MIN,
## no upper limit). In play each heart is HALVES_PER_HEART half hearts, the
## unit damage and healing use (Player.health). Every other attribute is on a -100 .. +100 scale
## (0 = average). Each selectable
## colour in Global.CHARACTERS names one of the classes below by its id.
## Players keep their own copy of the numbers (Player.attributes), so
## gameplay can change them later with Player.change_attribute().
##
## How each attribute affects play is decided in
## Player._recalculate_stats() (scripts/player/character_body.gd).
##
## "gun" is the gun the class starts with (scripts/guns.gd), by full id
## including its rarity tier ("scrap_smg"). The gun decides
## how the class shoots, so classes start with range, ranged damage and fire
## rate at 0; those attributes are for shop items to scale whatever gun the
## player is holding.
##
## "melee" is the melee weapon the class starts with (scripts/melee.gd), by
## full id including its rarity tier ("scrap_knife"). The
## melee damage attribute scales it, so that one does vary by class.
##
## "equipment" (optional) is the equipment the class starts with
## (scripts/equipment.gd), by id ("turret"). Most classes start without.
##
## "perks" (optional) are class rules that aren't attributes, kept for the
## whole run whatever the player buys (see perk()):
##   hit_cooldown         seconds the player can't be hurt after a hit or a
##                        blocked hit (default Player.HIT_COOLDOWN)
##   melee_interval_mult  x seconds between melee swings, any melee weapon
##   melee_reach_bonus    + pixels of melee reach, any melee weapon

const MIN_VALUE := -100
const MAX_VALUE := 100
## Lives is counted in hearts rather than on the -100 .. +100 scale.
const LIVES_DEFAULT := 4
const LIVES_MIN := 1
## Health is tracked in half hearts: a plain enemy hit takes one.
const HALVES_PER_HEART := 2

## Display order and labels. "id" is the key used in every attributes dict.
## "hearts" marks lives, which is a heart count instead of -100 .. +100.
const ATTRIBUTES := [
	{"id": "lives", "name": "Hearts", "hearts": true},
	{"id": "armor", "name": "Armor"},
	{"id": "speed", "name": "Speed"},
	{"id": "fire_rate", "name": "Fire Rate"},
	{"id": "range", "name": "Range"},
	{"id": "ranged_damage", "name": "Ranged Dmg"},
	{"id": "melee_damage", "name": "Melee Dmg"},
	{"id": "knockback", "name": "Knockback"},
	{"id": "harvesting", "name": "Harvesting"},
	{"id": "engineering", "name": "Engineering"},
]

const CLASSES := {
	"soldier": {
		"gun": "scrap_assault_rifle",
		"melee": "scrap_knife",
		"name": "Soldier",
		"description": "Steady all-rounder",
		"attributes": {
			"lives": 4, "range": 0, "speed": 0, "harvesting": 0,
			"ranged_damage": 0, "fire_rate": 0, "melee_damage": 10, "knockback": 0, "engineering": -10, "armor": 10,
		},
	},
	"scavenger": {
		"gun": "scrap_smg",
		"melee": "scrap_machete",
		"name": "Scavenger",
		"description": "Gathers far more resources",
		"attributes": {
			"lives": 4, "range": 0, "speed": 25, "harvesting": 50,
			"ranged_damage": 0, "fire_rate": 0, "melee_damage": -20, "knockback": -10, "engineering": 15, "armor": -30,
		},
	},
	"sniper": {
		"gun": "scrap_sniper_rifle",
		"melee": "scrap_knife",
		"equipment": "drone",
		"name": "Sniper",
		"description": "Long reach, hard hits, fragile",
		"attributes": {
			"lives": 2, "range": 0, "speed": -10, "harvesting": 20,
			"ranged_damage": 10, "fire_rate": 0, "melee_damage": -60, "knockback": 0, "engineering": 10, "armor": -30,
		},
	},
	"engineer": {
		"gun": "scrap_rivet_gun",
		"melee": "scrap_wrench",
		"equipment": "turret",
		"name": "Engineer",
		"description": "Builder and tinkerer",
		"attributes": {
			"lives": 4, "range": 0, "speed": -10, "harvesting": 25,
			"ranged_damage": 0, "fire_rate": 0, "melee_damage": -30, "knockback": 0, "engineering": 40, "armor": 15,
		},
	},
	"brawler": {
		"gun": "scrap_shotgun",
		"melee": "scrap_spiked_bat",
		"name": "Brawler",
		"description": "Tough up close, weak at range",
		"attributes": {
			"lives": 6, "range": 0, "speed": 15, "harvesting": -20,
			"ranged_damage": 0, "fire_rate": 0, "melee_damage": 60, "knockback": 25, "engineering": -30, "armor": 40,
		},
	},
	"scout": {
		"gun": "solid_smg",
		"melee": "scrap_chainsaw",
		"name": "Scout",
		"description": "Very fast, easily hurt",
		"attributes": {
			"lives": 2, "range": 0, "speed": 40, "harvesting": 30,
			"ranged_damage": 0, "fire_rate": 0, "melee_damage": -10, "knockback": -15, "engineering": 0, "armor": -40,
		},
	},
	"medic": {
		"gun": "scrap_pistol",
		"melee": "scrap_knife",
		"equipment": "healing_bubble",
		"name": "Medic",
		"description": "Hard to keep down",
		"attributes": {
			"lives": 4, "range": 0, "speed": 10, "harvesting": 10,
			"ranged_damage": 0, "fire_rate": 0, "melee_damage": -35, "knockback": 0, "engineering": 20, "armor": 10,
		},
	},
	"gunner": {
		"gun": "scrap_minigun",
		"melee": "scrap_knife",
		"name": "Gunner",
		"description": "Raw firepower, little else",
		"attributes": {
			"lives": 4, "range": 0, "speed": -15, "harvesting": -25,
			"ranged_damage": 0, "fire_rate": 0, "melee_damage": 0, "knockback": 15, "engineering": -35, "armor": 5,
		},
	},
	"tank": {
		"gun": "scrap_hand_cannon",
		"melee": "scrap_sledgehammer",
		"equipment": "barricade",
		"name": "Tank",
		"description": "Slow, armoured, many hearts",
		# A brawler that holds the line in a crowd: longer recovery after
		# hits, quicker and wider swings (a Sledgehammer swings every 0.9 s
		# instead of 1.3 s, reaching 32 px instead of 26).
		"perks": {"hit_cooldown": 1.6, "melee_interval_mult": 0.9 / 1.3, "melee_reach_bonus": 6.0},
		"attributes": {
			"lives": 6, "range": -15, "speed": -20, "harvesting": -20,
			"ranged_damage": 0, "fire_rate": 0, "melee_damage": 20, "knockback": 30, "engineering": 0, "armor": 50,
		},
	},
	"duelist": {
		"gun": "scrap_revolver",
		"melee": "scrap_katana",
		"name": "Duelist",
		"description": "Quick blade, thin skin",
		"attributes": {
			"lives": 2, "range": 0, "speed": 35, "harvesting": 0,
			"ranged_damage": 0, "fire_rate": 10, "melee_damage": 65, "knockback": 0, "engineering": -20, "armor": -25,
		},
	},
	# Sandbox class for testing: only offered from the editor (see
	# Global.sandbox_enabled), and its loadout is set by hand on its own
	# screen (scripts/ui/sandbox_editor.gd, Global.custom_loadout). These
	# are just the defaults that screen starts from.
	"custom": {
		"gun": "scrap_pistol",
		"melee": "scrap_knife",
		"name": "Custom",
		"description": "Sandbox: set every stat and item",
		"sandbox": true,
		"attributes": {
			"lives": 4, "range": 0, "speed": 0, "harvesting": 0,
			"ranged_damage": 0, "fire_rate": 0, "melee_damage": 0, "knockback": 0, "engineering": 0, "armor": 0,
		},
	},
}


static func get_class_data(class_id: String) -> Dictionary:
	return CLASSES.get(class_id, CLASSES["soldier"])


## A fresh, clamped copy of a class's starting attributes (missing ones
## get their default).
static func starting_attributes(class_id: String) -> Dictionary:
	var source: Dictionary = get_class_data(class_id)["attributes"]
	var result := {}
	for attr in ATTRIBUTES:
		var id: String = attr["id"]
		result[id] = clamp_attribute(id, int(source.get(id, default_value(id))))
	return result


## A class's `perk` (see "perks" above), or `default` if it has none.
static func perk(class_id: String, id: String, default: float) -> float:
	return float(get_class_data(class_id).get("perks", {}).get(id, default))


static func starting_gun(class_id: String) -> String:
	return get_class_data(class_id).get("gun", "")


static func starting_melee(class_id: String) -> String:
	return get_class_data(class_id).get("melee", "")


## "" if the class starts without equipment.
static func starting_equipment(class_id: String) -> String:
	return get_class_data(class_id).get("equipment", "")


## Half hearts as text: 3 -> "1.5", 4 -> "2".
static func hearts_text(halves: int) -> String:
	var whole := halves / HALVES_PER_HEART
	return str(whole) if halves % HALVES_PER_HEART == 0 else "%d.5" % whole


static func default_value(id: String) -> int:
	return LIVES_DEFAULT if id == "lives" else 0


## Keeps a value in its attribute's range: lives >= LIVES_MIN, others -100 .. +100.
static func clamp_attribute(id: String, value: int) -> int:
	if id == "lives":
		return maxi(value, LIVES_MIN)
	return clampi(value, MIN_VALUE, MAX_VALUE)


## Multiplier at -100 and +100 for speed, range, ranged damage, fire rate,
## knockback and harvesting.
const STAT_MULT_MIN := 0.35
const STAT_MULT_MAX := 3.0
## Speed bottoms out higher: -100 speed is what -50 used to be (~0.45x).
const SPEED_MULT_MIN := 0.4472136  # sqrt(STAT_MULT_MIN)


## Chance (0..1) that armor ignores an enemy hit, straight lines between
## these points (armor -> chance): -100 -> 0%, -50 -> 2.5%, 0 -> 5%,
## +50 -> 37.5%, +100 -> 80%.
const BLOCK_CHANCE_POINTS := [
	Vector2(-100, 0.0), Vector2(-50, 0.025), Vector2(0, 0.05),
	Vector2(50, 0.35), Vector2(100, 0.8),
]
## The chance at 0 armor.
const BLOCK_CHANCE_AVERAGE := 0.05


static func block_chance(armor: int) -> float:
	var a := float(clampi(armor, MIN_VALUE, MAX_VALUE))
	for i in range(1, BLOCK_CHANCE_POINTS.size()):
		var lo: Vector2 = BLOCK_CHANCE_POINTS[i - 1]
		var hi: Vector2 = BLOCK_CHANCE_POINTS[i]
		if a <= hi.x:
			return lerpf(lo.y, hi.y, (a - lo.x) / (hi.x - lo.x))
	return BLOCK_CHANCE_POINTS[-1].y


## Maps an attribute to a stat multiplier: -100 -> 0.2x, 0 -> 1x, +100 -> 4x.
## Exponential on each side of 0, so equal steps feel like equal changes:
## e.g. -50 -> ~0.45x, +50 -> 2x.
## Pass min_mult to override the -100 end (speed uses SPEED_MULT_MIN).
static func stat_multiplier(value: int, min_mult: float = STAT_MULT_MIN) -> float:
	var t := clampi(value, MIN_VALUE, MAX_VALUE) / 100.0
	var end := STAT_MULT_MAX if t >= 0.0 else min_mult
	return pow(end, absf(t))
