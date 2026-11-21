extends RefCounted
## The rarity tiers every gun (scripts/guns.gd) and melee weapon
## (scripts/melee.gd) comes in, weakest/commonest first. A weapon's id is
## "<tier>_<type>" (e.g. "scrap_smg", "mythic_katana") and its name is
## "<Tier> <Type>".
##
##   damage    - x damage per hit
##   fire_rate - x attacks per second (the weapon's interval is divided by it)
##   knockback - x how far each hit shoves an enemy
##   cost      - x price
##   weight    - how likely the shop is to offer it, next to a normal item's
##               1.0 (see Items.roll_offer)
##   color     - the weapon's name colour in the shop
##
## Guns and melee weapons each scale their other numbers (range, spread,
## reach, arc) in their own files.

const TIERS := [
	{"id": "scrap", "name": "Scrap", "damage": 1.0, "fire_rate": 1.0, "knockback": 1.0,
		"cost": 1.0, "weight": 0.6, "color": Color(1.0, 1.0, 1.0)},
	{"id": "solid", "name": "Solid", "damage": 1.25, "fire_rate": 1.2, "knockback": 1.1,
		"cost": 1.5, "weight": 0.35, "color": Color(0.3, 0.95, 0.3)},
	{"id": "legit", "name": "Legit", "damage": 1.55, "fire_rate": 1.4, "knockback": 1.2,
		"cost": 2.0, "weight": 0.17, "color": Color(0.3, 0.6, 1.0)},
	{"id": "legendary", "name": "Legendary", "damage": 2.0, "fire_rate": 1.6, "knockback": 1.35,
		"cost": 3.5, "weight": 0.07, "color": Color(0.85, 0.35, 1.0)},
	{"id": "mythic", "name": "Mythic", "damage": 2.7, "fire_rate": 1.8, "knockback": 1.5,
		"cost": 5.0, "weight": 0.025, "color": Color(1.0, 0.55, 0.1)},
]


## `type` (a gun or melee type entry) at tier index `t`, with the shared
## numbers scaled: id, name, type, tier, damage, interval, knockback and
## cost. Every tier deals at least 1 more damage than the one below it.
static func make(type: Dictionary, t: int) -> Dictionary:
	var tier: Dictionary = TIERS[t]
	var weapon: Dictionary = type.duplicate()
	weapon["id"] = "%s_%s" % [tier["id"], type["id"]]
	weapon["name"] = "%s %s" % [tier["name"], type["name"]]
	weapon["type"] = type["id"]
	weapon["tier"] = t
	weapon["damage"] = maxi(roundi(type["damage"] * tier["damage"]), int(type["damage"]) + t)
	weapon["interval"] = snappedf(type["interval"] / tier["fire_rate"], 0.001)
	# Not rounded: knockback numbers are small in pixel-art units (a few px).
	weapon["knockback"] = type.get("knockback", 0) * tier["knockback"]
	weapon["cost"] = roundi(type["cost"] * tier["cost"])
	return weapon


## The entry in `list` with this id. A bare type id ("smg") means its Scrap
## tier.
static func find_in(list: Array, id: String) -> Dictionary:
	for weapon in list:
		if weapon["id"] == id:
			return weapon
	var scrap: String = TIERS[0]["id"] + "_"
	if not id.is_empty() and not id.begins_with(scrap):
		return find_in(list, scrap + id)
	return {}


static func tier_of(weapon: Dictionary) -> Dictionary:
	return TIERS[weapon.get("tier", 0)]
