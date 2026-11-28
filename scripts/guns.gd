extends RefCounted
## Every gun in the game. A player holds exactly one: their class's starting
## gun (scripts/character_classes.gd), kept all run in every mode. Guns
## aren't sold: the shop's Upgrade Kits improve it and promote it up the tiers.
##
## Guns come in TYPES (SMG, Shotgun, ...) and every type comes in each rarity
## tier (scripts/rarity.gd): Scrap, Solid, Exquisite, Legendary, Mythic, e.g.
## "scrap_smg" / "Mythic Sniper Rifle". LIST holds every combination.
##
## A gun sets the base numbers for shooting; the player's range, ranged
## damage and fire rate attributes then scale them (see
## Player._recalculate_stats() in scripts/player/character_body.gd).
##
## To add a gun type: add an entry to TYPES (all five tiers of it are made
## automatically) and give it to a class. Its numbers are the Scrap tier:
##   id        - unique key
##   name      - shown in the shop and on character select (after the tier)
##   cost      - Scrap price in resources (sets Upgrade Kit and promotion prices)
##   damage    - damage per projectile
##   interval  - seconds between shots
##   range     - how far a shot flies, in pixels
##   knockback - pixels each projectile shoves the enemy it hits (heavier,
##               slower guns push harder; shotguns push per pellet)
##   pellets   - projectiles per shot (optional, default 1)
##   spread    - degrees: pellets fan out evenly across it; a single
##               projectile is aimed randomly within it (optional, default 0)
##   speed     - projectile speed in pixels/second (optional, default
##               Projectile.SPEED)
##   size      - projectile rectangle (optional, default Projectile.SIZE)
##   overkill  - true: a shot that kills flies on with the damage left over
##               (optional, default false; see Projectile.overkill)
##   recoil    - pixels/second each shot pushes the shooter backwards, fading
##               over Player.RECOIL_FADE (optional, default 0)
##   overheat  - seconds of non-stop fire that overheat the gun (optional,
##               default 0 = never). Heat drains while the trigger is let go
##               (fully in Player.HEAT_COOL_TIME); once overheated the gun
##               can't fire until it has cooled right down, which takes
##               "lockout" seconds (optional, default Player.HEAT_LOCKOUT).
##               Fire rate bonuses don't change how long it lasts: faster
##               fire heats it faster.
##
## Each tier scales damage, 	fire rate and cost (Rarity.TIERS), knockback
## (Rarity.TIERS), and range and spread (TIER_SCALING; spread tightens, but
## pellet fans keep theirs).
##
## UPGRADE KITS (called tune-ups in the code): in the shop a player can
## upgrade the gun they hold, up to MAX_LEVEL times; level L adds
## LEVEL_BONUSES[L - 1]. A fully upgraded gun can then be promoted to the
## next tier of its type (its level starts over).

const Rarity := preload("res://scripts/rarity.gd")

const TYPES := [
	{"id": "pistol", "name": "Pistol", "cost": 8,
		"damage": 8, "interval": 0.45, "range": 400, "knockback": 8},
	{"id": "smg", "name": "SMG", "cost": 10,
		"damage": 3, "interval": 0.25, "range": 300, "knockback": 3, "spread": 12},
	{"id": "rivet_gun", "name": "Rivet Gun", "cost": 10,
		"damage": 10, "interval": 0.6, "range": 480, "knockback": 14, "speed": 680},
	{"id": "revolver", "name": "Revolver", "cost": 14,
		"damage": 14, "interval": 0.45, "range": 280, "knockback": 16, "size": Vector2(6, 2)},
	{"id": "shotgun", "name": "Shotgun", "cost": 14,
		"damage": 5, "interval": 0.9, "range": 160, "knockback": 9, "pellets": 5, "spread": 35,
		"speed": 480, "size": Vector2(4, 2)},
	{"id": "hand_cannon", "name": "Hand Cannon", "cost": 14,
		"damage": 22, "interval": 1.0, "range": 300, "knockback": 32, "speed": 360, "size": Vector2(7, 4)},
	{"id": "assault_rifle", "name": "Assault Rifle", "cost": 16,
		"damage": 9, "interval": 0.3, "range": 480, "knockback": 6, "spread": 3},
	{"id": "sniper_rifle", "name": "Sniper Rifle", "cost": 18,
		"damage": 45, "interval": 1.2, "range": 800, "knockback": 28, "speed": 1120, "size": Vector2(14, 1),
		"overkill": true},
	{"id": "minigun", "name": "Minigun", "cost": 22,
		"damage": 6, "interval": 0.1, "range": 560, "knockback": 2, "spread": 10, "size": Vector2(5, 2),
		"recoil": 50, "overheat": 3.0, "lockout": 2.0},
]

## Per tier (same order as Rarity.TIERS): x range, x spread, and x the
## price of each Upgrade Kit level (see tune_cost; steeper than the gun
## prices themselves, so upgrading a rare gun costs much more).
const TIER_SCALING := [
	{"range": 1.0, "spread": 1.0, "upgrade_cost": 1.0},
	{"range": 1.08, "spread": 0.85, "upgrade_cost": 1.4},
	{"range": 1.15, "spread": 0.7, "upgrade_cost": 2.0},
	{"range": 1.25, "spread": 0.55, "upgrade_cost": 2.8},
	{"range": 1.35, "spread": 0.4, "upgrade_cost": 4.0},
]

const DEFAULT_ID := "scrap_pistol"

## Every gun: each type in TYPES order, each in Rarity.TIERS order.
static var LIST: Array = _build_list()

## What each Upgrade Kit level adds, in order: stat -> fraction of the
## gun's own number (0.1 = +10%). Stats: "fire_rate", "damage", "range".
## Bonuses to the same stat add up (two +10% fire rate levels = +20%).
## Damage is a whole number, so it's applied before rounding, together with
## the ranged damage attribute, and each damage level adds at least 1 (a
## 4-damage SMG goes to 5, not 4.4 -> 4).
const LEVEL_BONUSES := [
	{"fire_rate": 0.05},
	{"damage": 0.1},
	{"fire_rate": 0.1},
	{"range": 0.1},
]
## Upgrade Kit levels a gun can take before it can be promoted.
static var MAX_LEVEL: int = LEVEL_BONUSES.size()
## Upgrade Kit price, before the shop's wave price rise (Items.price_mult):
## the gun type's Scrap price x its tier's TIER_SCALING "upgrade_cost" x this
## x (1 + TUNE_COST_PER_LEVEL x the level it's upgraded from). So a Scrap
## Pistol (8) costs 3, 6, 8, 10 for levels 1-4.
const TUNE_COST_FRACTION := 0.4
const TUNE_COST_PER_LEVEL := 0.75
## Promoting costs this x the next tier's own price (before the wave price
## rise): cheaper than buying it, but not by much.
const PROMOTE_COST_FRACTION := 0.75


static func _build_list() -> Array:
	var list := []
	for type in TYPES:
		for t in Rarity.TIERS.size():
			list.append(_make(type, t))
	return list


static func _make(type: Dictionary, t: int) -> Dictionary:
	var gun := Rarity.make(type, t)
	gun["base_cost"] = type["cost"]  # the Scrap price, for Upgrade Kit prices
	gun["range"] = roundi(type["range"] * TIER_SCALING[t]["range"])
	if type.has("spread") and int(type.get("pellets", 1)) == 1:
		gun["spread"] = type["spread"] * TIER_SCALING[t]["spread"]
	return gun


static func find(id: String) -> Dictionary:
	return Rarity.find_in(LIST, id)


## The gun with this id, or the default gun if there's no such gun.
static func get_gun(id: String) -> Dictionary:
	var gun := find(id)
	return gun if not gun.is_empty() else find(DEFAULT_ID)


static func tier_of(gun: Dictionary) -> Dictionary:
	return Rarity.tier_of(gun)


# --- Tune-ups -----------------------------------------------------------------

## Damage per second on paper (no attributes, no tune-ups).
static func base_dps(gun: Dictionary) -> float:
	return gun["damage"] * int(gun.get("pellets", 1)) / float(gun["interval"])


## Multiplier on `stat` ("fire_rate", "damage" or "range") of a gun
## upgraded `level` times: 1 + every LEVEL_BONUSES entry up to that level.
static func level_mult(stat: String, level: int) -> float:
	var mult := 1.0
	for l in clampi(level, 0, MAX_LEVEL):
		mult += float(LEVEL_BONUSES[l].get(stat, 0.0))
	return mult


## How many of the first `level` levels raise damage (each adds at least 1).
static func damage_levels(level: int) -> int:
	var count := 0
	for l in clampi(level, 0, MAX_LEVEL):
		if float(LEVEL_BONUSES[l].get("damage", 0.0)) > 0.0:
			count += 1
	return count


## Damage per projectile of a gun dealing `damage` (after attributes,
## before rounding) upgraded `level` times.
static func upgraded_damage(damage: float, level: int) -> int:
	return maxi(roundi(damage * level_mult("damage", level)), roundi(damage) + damage_levels(level))


## Price of upgrading `gun` from `level` to level + 1, before the shop's
## wave price rise (see TUNE_COST_FRACTION).
static func tune_cost(gun: Dictionary, level: int) -> float:
	return gun.get("base_cost", gun["cost"]) * TIER_SCALING[gun.get("tier", 0)]["upgrade_cost"] \
		* TUNE_COST_FRACTION * (1.0 + TUNE_COST_PER_LEVEL * level)


## The same type of gun one tier up, or {} if `gun` is already the top tier.
static func next_tier(gun: Dictionary) -> Dictionary:
	var t: int = gun.get("tier", 0) + 1
	if t >= Rarity.TIERS.size():
		return {}
	return find("%s_%s" % [Rarity.TIERS[t]["id"], gun["type"]])


## Price of promoting a fully upgraded `gun` to next_tier(), before the
## shop's wave price rise, or -1 if it's the top tier.
static func promote_cost(gun: Dictionary) -> float:
	var next := next_tier(gun)
	if next.is_empty():
		return -1.0
	return next["cost"] * PROMOTE_COST_FRACTION


## "Scrap Pistol", or "Scrap Pistol +2" once tuned up.
static func display_name(gun: Dictionary, level: int) -> String:
	return gun["name"] if level <= 0 else "%s +%d" % [gun["name"], level]
