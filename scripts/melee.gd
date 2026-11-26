extends RefCounted
## Every melee weapon in the game. A player holds exactly one: their class's
## starting weapon (scripts/character_classes.gd), kept all run in every
## mode. Melee weapons aren't sold: Upgrade Kits improve and promote it.
##
## A player swings by pulling their controller's right trigger (Space or right
## mouse button on the keyboard), hitting every enemy inside the swing's arc and within reach.
## Holding the trigger keeps swinging, once per interval; swings have their
## own cooldown, separate from shooting. The swing shows the weapon's image
## (scripts/melee_swing.gd, assets/weapons/<type id>.png). The melee damage attribute scales the
## damage and the fire rate attribute scales the swing speed (see
## Player.melee_stats() in scripts/player/character_body.gd).
##
## Melee weapons come in TYPES (Knife, Katana, ...) and every type comes in
## each rarity tier (scripts/rarity.gd): Scrap, Solid, Exquisite, Legendary,
## Mythic, e.g. "scrap_knife" / "Mythic Katana". LIST holds every combination.
##
## To add a weapon type: add an entry to TYPES (all five tiers of it are made
## automatically) and give it to a class. Its numbers are the Scrap tier:
##   id        - unique key
##   name      - shown in the shop and on character select (after the tier)
##   cost      - Scrap price in resources (sets Upgrade Kit and promotion prices)
##   damage    - damage per enemy hit
##   interval  - seconds between swings
##   range     - reach in pixels, from the edge of the player's square to the
##               edge of the enemy (guns reach far further)
##   arc       - degrees: how wide the swing is, centred on where the player faces
##   knockback - pixels each hit shoves the enemy away from the player
##
## Each tier scales damage, swing speed, knockback and cost (Rarity.TIERS),
## and reach and
## arc (TIER_SCALING).
##
## UPGRADE KITS (tune-ups in the code), the same as for guns (scripts/guns.gd):
## in the shop a player can upgrade the melee weapon they hold, up to
## MAX_LEVEL times; level L adds LEVEL_BONUSES[L - 1]. A fully upgraded
## weapon can then be promoted to the next tier of its type (its level starts
## over).

const Rarity := preload("res://scripts/rarity.gd")

const TYPES := [
	{"id": "knife", "name": "Knife", "cost": 6,
		"damage": 8, "interval": 0.4, "range": 14, "arc": 70, "knockback": 10},
	{"id": "wrench", "name": "Wrench", "cost": 8,
		"damage": 11, "interval": 0.6, "range": 17, "arc": 90, "knockback": 28},
	{"id": "machete", "name": "Machete", "cost": 10,
		"damage": 12, "interval": 0.5, "range": 22, "arc": 110, "knockback": 20},
	{"id": "spiked_bat", "name": "Spiked Bat", "cost": 12,
		"damage": 16, "interval": 0.75, "range": 24, "arc": 130, "knockback": 52},
	{"id": "katana", "name": "Katana", "cost": 16,
		"damage": 18, "interval": 0.6, "range": 28, "arc": 120, "knockback": 14},
	{"id": "chainsaw", "name": "Chainsaw", "cost": 18,
		"damage": 6, "interval": 0.12, "range": 16, "arc": 60, "knockback": 6},
	{"id": "sledgehammer", "name": "Sledgehammer", "cost": 18,
		"damage": 38, "interval": 1.3, "range": 26, "arc": 150, "knockback": 80},
]


## Per tier (same order as Rarity.TIERS): x reach, x arc, and x the price
## of each Upgrade Kit level (see tune_cost; the same steps as guns).
const TIER_SCALING := [
	{"range": 1.0, "arc": 1.0, "upgrade_cost": 1.0},
	{"range": 1.1, "arc": 1.1, "upgrade_cost": 1.4},
	{"range": 1.2, "arc": 1.2, "upgrade_cost": 2.0},
	{"range": 1.4, "arc": 1.4, "upgrade_cost": 2.8},
	{"range": 2.0, "arc": 1.6, "upgrade_cost": 4.0},
]

const DEFAULT_ID := "scrap_knife"

## Every weapon: each type in TYPES order, each in Rarity.TIERS order.
static var LIST: Array = _build_list()

## What each Upgrade Kit level adds, in order: stat -> fraction of the
## weapon's own number (0.1 = +10%). Stats: "fire_rate" (swing speed),
## "damage", "range" (reach). Bonuses to the same stat add up. Damage is
## applied before rounding, together with the melee damage attribute, and
## each damage level adds at least 1.
const LEVEL_BONUSES := [
	{"fire_rate": 0.05},
	{"damage": 0.1},
	{"fire_rate": 0.1},
	{"range": 0.15},
]
## Upgrade Kit levels a weapon can take before it can be promoted.
static var MAX_LEVEL: int = LEVEL_BONUSES.size()
## Upgrade Kit price, before the shop's wave price rise (Items.price_mult):
## the weapon type's Scrap price x its tier's TIER_SCALING "upgrade_cost" x
## this x (1 + TUNE_COST_PER_LEVEL x the level it's upgraded from). So a
## Scrap Knife (6) costs 2, 4, 6, 8 for levels 1-4.
const TUNE_COST_FRACTION := 0.4
const TUNE_COST_PER_LEVEL := 0.75
## Promoting costs this x the next tier's own price (before the wave price
## rise).
const PROMOTE_COST_FRACTION := 0.75


static func _build_list() -> Array:
	var list := []
	for type in TYPES:
		for t in Rarity.TIERS.size():
			var weapon := Rarity.make(type, t)
			weapon["base_cost"] = type["cost"]  # the Scrap price, for Upgrade Kit prices
			weapon["range"] = type["range"] * TIER_SCALING[t]["range"]
			weapon["arc"] = roundi(type["arc"] * TIER_SCALING[t]["arc"])
			list.append(weapon)
	return list


static func find(id: String) -> Dictionary:
	return Rarity.find_in(LIST, id)


## The weapon with this id, or the default weapon if there's no such weapon.
static func get_weapon(id: String) -> Dictionary:
	var weapon := find(id)
	return weapon if not weapon.is_empty() else find(DEFAULT_ID)


static func tier_of(weapon: Dictionary) -> Dictionary:
	return Rarity.tier_of(weapon)


# --- Tune-ups -----------------------------------------------------------------

## Multiplier on `stat` ("fire_rate", "damage" or "range") of a weapon
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


## Damage per hit of a weapon dealing `damage` (after attributes, before
## rounding) upgraded `level` times.
static func upgraded_damage(damage: float, level: int) -> int:
	return maxi(roundi(damage * level_mult("damage", level)), roundi(damage) + damage_levels(level))


## Price of upgrading `weapon` from `level` to level + 1, before the shop's
## wave price rise (see TUNE_COST_FRACTION).
static func tune_cost(weapon: Dictionary, level: int) -> float:
	return weapon.get("base_cost", weapon["cost"]) * TIER_SCALING[weapon.get("tier", 0)]["upgrade_cost"] \
		* TUNE_COST_FRACTION * (1.0 + TUNE_COST_PER_LEVEL * level)


## The same type of weapon one tier up, or {} if it's already the top tier.
static func next_tier(weapon: Dictionary) -> Dictionary:
	var t: int = weapon.get("tier", 0) + 1
	if t >= Rarity.TIERS.size():
		return {}
	return find("%s_%s" % [Rarity.TIERS[t]["id"], weapon["type"]])


## Price of promoting a fully upgraded `weapon` to next_tier(), before the
## shop's wave price rise, or -1 if it's the top tier.
static func promote_cost(weapon: Dictionary) -> float:
	var next := next_tier(weapon)
	if next.is_empty():
		return -1.0
	return next["cost"] * PROMOTE_COST_FRACTION


## "Scrap Knife", or "Scrap Knife +2" once tuned up.
static func display_name(weapon: Dictionary, level: int) -> String:
	return weapon["name"] if level <= 0 else "%s +%d" % [weapon["name"], level]
