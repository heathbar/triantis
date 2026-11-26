extends RefCounted
## Everything sold in the between-wave shop. Most items permanently shift some
## of the buyer's attributes (scripts/character_classes.gd) - some are pure
## buffs, most trade one strength for a weakness.
##
## Every wave each player is offered OFFER_COUNT different items: whatever
## they banked last wave, topped up with random ones they haven't banked.
## Each offered item can be bought once that wave. A banked item keeps the
## price it had when it was banked (prices otherwise rise every wave, see
## price_mult). Items not bought or banked
## are gone (but can turn up again later). Buying the same item again in a
## later wave stacks its effects.
##
## To add one: add an entry to LIST.
##   id       - unique key (used for banking and counting purchases)
##   name     - shown in the shop
##   cost     - price in resources in the first shop; it rises by
##              PRICE_RISE_PER_WAVE of that each wave after (price)
##   effects  - attribute id -> change. Lives changes are whole hearts; the
##              other attributes stay within -100 .. +100.
##   blurb    - optional: one line on what it does, for items whose effect
##              isn't an attribute (their code checks how many the player
##              owns: owned()). Shown in the shop above any effects.
##
## Every gun (scripts/guns.gd) is also sold, mixed in with these, as an item
## with a "gun" key and no effects. Buying one swaps out the buyer's current
## gun, which is lost. A player is never offered a gun of the type they're
## holding at the same rarity tier or lower (holding an Exquisite SMG, they can
## still be offered a Legendary SMG, or a Scrap Shotgun). Rarer tiers turn up
## less often (Rarity.TIERS "weight"; every other item weighs 1.0). Guns of
## the type the player already holds turn up SAME_GUN_TYPE_WEIGHT times as
## often as other guns of their tier, so the shop leans towards upgrades of
## the gun they've chosen. Melee weapons lean the same way, by
## SAME_MELEE_TYPE_WEIGHT.
##
## Melee weapons (scripts/melee.gd) are sold the same way, with a "melee" key:
## buying one replaces the buyer's melee weapon. The same tier rule applies.
##
## Equipment (scripts/equipment.gd) is sold too, with an "equipment" key, and
## turns up as often as a Solid weapon. Buying it replaces the buyer's
## equipment; they're never offered the one they already hold.
##
## Besides the offer, every shop has an UPGRADE KIT row for the player's gun
## (tune_offer): tune it up, promote it once fully tuned, or nothing (a fully
## tuned top-tier gun). See Guns UPGRADE KITS. A second row does the same for
## their melee weapon (melee_tune_offer; Melee UPGRADE KITS).
##
## A player can re-roll their offer in the shop (Y / R): every item they haven't
## banked is replaced with a new random one. Each re-roll in the same wave
## costs twice the last (reroll_cost). Re-rolls, Upgrade Kits and promotions
## rise with the wave like everything else (price_mult).

const CharacterClasses := preload("res://scripts/character_classes.gd")
const Guns := preload("res://scripts/guns.gd")
const Melee := preload("res://scripts/melee.gd")
const Equipment := preload("res://scripts/equipment.gd")
const Rarity := preload("res://scripts/rarity.gd")

const OFFER_COUNT := 4
## The first re-roll in a wave costs this; each one after costs double.
const REROLL_BASE_COST := 8
## How much likelier a gun of the held gun's type is to be offered than
## another gun of the same tier.
const SAME_GUN_TYPE_WEIGHT := 8.0
## The same for melee weapons of the held melee weapon's type.
const SAME_MELEE_TYPE_WEIGHT := 4.0

const LIST := [
	# --- Upgrades: small single-stat boosts ---------------------------------
	{"id": "extra_heart", "name": "Extra Heart", "cost": 25, "effects": {"lives": 1}},
	{"id": "heavy_rounds", "name": "Heavy Rounds", "cost": 7, "effects": {"ranged_damage": 10}},
	{"id": "light_boots", "name": "Light Boots", "cost": 6, "effects": {"speed": 10}},
	{"id": "quick_trigger", "name": "Quick Trigger", "cost": 7, "effects": {"fire_rate": 10}},
	{"id": "heavy_slugs", "name": "Heavy Slugs", "cost": 6, "effects": {"knockback": 15}},

	# --- Pure buffs: small and cheap ----------------------------------------
	{"id": "running_shoes", "name": "Running Shoes", "cost": 8, "effects": {"speed": 15}},
	{"id": "lucky_charm", "name": "Loot Glutes", "cost": 8, "effects": {"harvesting": 15}},
	{"id": "whetstone", "name": "Whetstone", "cost": 7, "effects": {"melee_damage": 20}},
	{"id": "toolkit", "name": "Toolkit", "cost": 7, "effects": {"engineering": 20}},
	{"id": "weighted_grip", "name": "Weighted Grip", "cost": 9,
		"effects": {"knockback": 15, "melee_damage": 10}},
	{"id": "padded_vest", "name": "Padded Vest", "cost": 8, "effects": {"armor": 15}},
	{"id": "long_barrel", "name": "Long Barrel", "cost": 9, "effects": {"range": 15}},
	{"id": "hollow_points", "name": "Hollow Points", "cost": 10, "effects": {"ranged_damage": 15}},
	{"id": "vitamins", "name": "Vitamins", "cost": 10, "effects": {"lives": 1, "speed": -15}},
	{"id": "field_manual", "name": "Field Manual", "cost": 12,
		"effects": {"range": 5, "speed": 5, "ranged_damage": 5, "armor": 5}},

	# --- Trade-offs: bigger gains with a cost --------------------------------
	{"id": "scope", "name": "Scope", "cost": 12,
		"effects": {"ranged_damage": 20, "armor": -5}},
	{"id": "bipod", "name": "Bipod", "cost": 12,
		"effects": {"range": 15, "ranged_damage": 10, "speed": -15}},
	{"id": "glass_cannon", "name": "Glass Cannon", "cost": 14,
		"effects": {"ranged_damage": 50, "lives": -1}},
	{"id": "sawed_off", "name": "Sawed-Off Barrel", "cost": 10,
		"effects": {"ranged_damage": 40, "range": -30}},
	{"id": "heavy_armor", "name": "Heavy Armor", "cost": 12,
		"effects": {"armor": 20, "speed": -10}},
	{"id": "tower_shield", "name": "Tower Shield", "cost": 12,
		"effects": {"armor": 25, "ranged_damage": -10, "range": -5}},
	{"id": "iron_skin", "name": "Iron Skin", "cost": 15,
		"effects": {"lives": 1, "armor": 10, "speed": -20}},
	{"id": "jetpack", "name": "Jetpack", "cost": 12,
		"effects": {"speed": 20, "armor": -10}},
	{"id": "light_pack", "name": "Light Pack", "cost": 10,
		"effects": {"speed": 20, "harvesting": 15, "armor": -15}},
	{"id": "combat_stims", "name": "Combat Stims", "cost": 12,
		"effects": {"ranged_damage": 20, "speed": 20, "armor": -15}},
	{"id": "bad_fruit_loops", "name": "Bad Fruit Loops", "cost": 10,
		"effects": {"speed": 35, "melee_damage": 30, "lives": -1}},
	{"id": "spiked_gauntlets", "name": "Spiked Gauntlets", "cost": 10,
		"effects": {"melee_damage": 25, "ranged_damage": -10}},
	{"id": "scavenger_sack", "name": "Scavenger's Sack", "cost": 11,
		"effects": {"harvesting": 20, "speed": -5}},
	{"id": "greedy_gloves", "name": "Greedy Gloves", "cost": 10,
		"effects": {"harvesting": 20, "ranged_damage": -5}},
	{"id": "blueprints", "name": "Blueprint Satchel", "cost": 10,
		"effects": {"engineering": 20, "melee_damage": -10}},
	{"id": "concussion_rounds", "name": "Concussion Rounds", "cost": 11,
		"effects": {"knockback": 30, "fire_rate": -10}},
	{"id": "shoulder_guard", "name": "Shoulder Guard", "cost": 12,
		"effects": {"knockback": 20, "armor": 15, "speed": -10}},
	{"id": "pneumatic_ram", "name": "Pneumatic Ram", "cost": 12,
		"effects": {"knockback": 25, "melee_damage": 15, "range": -25}},
	{"id": "overclocked_rig", "name": "Overclocked Rig", "cost": 13,
		"effects": {"engineering": 35, "ranged_damage": 25, "lives": -1}},
	{"id": "duct_tape", "name": "Duct Tape", "cost": 6,
		"effects": {"engineering": 15, "armor": -10}},
	{"id": "ear_plugs", "name": "Ear Plugs", "cost": 8,
		"effects": {"fire_rate": 15, "range": -15}},
	{"id": "ankle_weights", "name": "Ankle Weights", "cost": 7,
		"effects": {"melee_damage": 20, "speed": -10}},
	{"id": "pawn_ticket", "name": "Pawn Ticket", "cost": 10,
		"effects": {"harvesting": 30, "lives": -1}},
	{"id": "sandbags", "name": "Sandbags", "cost": 8,
		"effects": {"armor": 25, "speed": -20, "fire_rate": -10}},

	# --- Specials: effects that aren't attributes (see "blurb") --------------
	# Vampire Fangs: Player.record_kill. Each copy shortens the wait between
	# heals (FANG_KILLS); after the last there's none to sell (can_offer).
	# The shop shows fang_blurb() in place of this.
	{"id": "vampire_fangs", "name": "Vampire Fangs", "cost": 14, "effects": {},
		"blurb": "Every 50 kills heals half a heart"},
	# Coupon: discount(). Copies stack (0.9 x 0.9 = 19% off for two).
	{"id": "coupon", "name": "Coupon", "cost": 30, "effects": {},
		"blurb": "10% off everything in the shop from now on"},
]

## Vampire Fangs: half a heart every FANG_KILLS[n - 1] kills with n owned. The
## shop stops offering them once a player has them all.
const FANG_KILLS: Array[int] = [50, 40, 30]
## Each Coupon takes this share off every later shop price.
const COUPON_DISCOUNT := 0.1


## Shop ids of gun items are the gun id with this in front.
const GUN_PREFIX := "gun:"
## Shop ids of melee items are the weapon id with this in front.
const MELEE_PREFIX := "melee:"
## Shop ids of equipment are the equipment id with this in front.
const EQUIPMENT_PREFIX := "equip:"
## Equipment is offered as often as a Solid weapon (some piece of it turns
## up in about 1 shop in 5).
const EQUIPMENT_RARITY := "solid"

static var _all: Array = []


## Every item for sale: LIST, then one per gun, one per melee weapon, then
## each piece of equipment.
static func all() -> Array:
	if _all.is_empty():
		_all = LIST.duplicate()
		for gun in Guns.LIST:
			_all.append({"id": GUN_PREFIX + gun["id"], "name": gun["name"],
				"cost": gun["cost"], "gun": gun["id"], "effects": {},
				"weight": Guns.tier_of(gun)["weight"], "color": Guns.tier_of(gun)["color"]})
		for weapon in Melee.LIST:
			_all.append({"id": MELEE_PREFIX + weapon["id"], "name": weapon["name"],
				"cost": weapon["cost"], "melee": weapon["id"], "effects": {},
				"weight": Melee.tier_of(weapon)["weight"], "color": Melee.tier_of(weapon)["color"]})
		var equipment_weight := 1.0
		for tier in Rarity.TIERS:
			if tier["id"] == EQUIPMENT_RARITY:
				equipment_weight = tier["weight"]
		for equipment in Equipment.LIST:
			_all.append({"id": EQUIPMENT_PREFIX + equipment["id"], "name": equipment["name"],
				"cost": equipment["cost"], "equipment": equipment["id"], "effects": {},
				"weight": equipment_weight, "color": Equipment.COLOR})
	return _all


static func find(id: String) -> Dictionary:
	for item in all():
		if item["id"] == id:
			return item
	return {}


static func is_gun(item: Dictionary) -> bool:
	return item.has("gun")


static func is_melee(item: Dictionary) -> bool:
	return item.has("melee")


static func is_equipment(item: Dictionary) -> bool:
	return item.has("equipment")


## False for guns and melee weapons of the type `player` holds at the same
## tier or lower, for the equipment they hold, and for items that would take
## their hearts below CharacterClasses.LIVES_MIN (so a player on 1 heart is
## never offered one that costs a heart); everything else can be offered.
## A player whose gun and melee weapon can't be changed (Player.weapons_locked,
## Braid mode) is never offered weapons.
static func can_offer(player: Node, item: Dictionary) -> bool:
	if item.is_empty():
		return false
	if item["id"] == "vampire_fangs" and owned(player, "vampire_fangs") >= FANG_KILLS.size():
		return false
	var lives_delta := int(item["effects"].get("lives", 0))
	if lives_delta < 0 and player.get_attribute("lives") + lives_delta < CharacterClasses.LIVES_MIN:
		return false
	# Braid mode locks each class to its own gun and melee weapon.
	if (is_gun(item) or is_melee(item)) and player.weapons_locked:
		return false
	if is_gun(item):
		return not _same_type_no_better(Guns.get_gun(item["gun"]), player.gun)
	if is_melee(item):
		return not _same_type_no_better(Melee.get_weapon(item["melee"]), player.melee)
	if is_equipment(item):
		return item["equipment"] != player.equipment_id \
			and Equipment.available_to(Equipment.find(item["equipment"]), player)
	return true


static func _same_type_no_better(weapon: Dictionary, held: Dictionary) -> bool:
	return weapon["type"] == held["type"] and weapon["tier"] <= held["tier"]


## This wave's offer for `player`: their banked items (in order) followed by
## random others, OFFER_COUNT in all, with no repeats. Each random pick is
## weighted by the item's "weight" (default 1.0), so rare guns are rare.
static func roll_offer(player: Node) -> Array[String]:
	var offer: Array[String] = []
	for id in player.banked_items:
		if offer.size() < OFFER_COUNT and can_offer(player, find(id)) and id not in offer:
			offer.append(id)
	offer.append_array(roll_random(player, OFFER_COUNT - offer.size(), offer, offer))
	return offer


## Up to `count` random item ids `player` can be offered, none of them in
## `exclude`, weighted by offer_weight().
##
## An offer never holds two weapons of the same type (say a Scrap SMG and a
## Solid SMG): `keep` are the items staying on offer beside these (banked
## ones), and no pick shares a type with them. Between two picks of the same
## type the higher tier stays and the other slot gets a different item.
static func roll_random(player: Node, count: int, exclude: Array, keep: Array = []) -> Array[String]:
	# Weighted sampling without replacement: give each item the key
	# randf() ^ (1 / weight) and take the highest keys.
	var pool := []
	for item in all():
		if item["id"] not in exclude and can_offer(player, item):
			pool.append([pow(randf(), 1.0 / offer_weight(player, item)), item["id"]])
	pool.sort_custom(func(a, b): return a[0] > b[0])
	var kept_types := {}
	for id in keep:
		var type := weapon_type(find(id))
		if type != "":
			kept_types[type] = true
	var picked: Array[String] = []
	for entry in pool:
		if picked.size() >= count:
			break
		var item := find(entry[1])
		var type := weapon_type(item)
		if type == "":
			picked.append(entry[1])
			continue
		if kept_types.has(type):
			continue
		var rival := -1
		for i in picked.size():
			if weapon_type(find(picked[i])) == type:
				rival = i
		if rival == -1:
			picked.append(entry[1])
		elif _weapon_of(item).get("tier", 0) > _weapon_of(find(picked[rival])).get("tier", 0):
			picked[rival] = entry[1]  # the better one takes the slot
	return picked


## "gun:<type>" / "melee:<type>" for a gun or melee weapon item, "" for
## anything else. Two items with the same weapon type are never offered
## together.
static func weapon_type(item: Dictionary) -> String:
	if is_gun(item):
		return "gun:" + _weapon_of(item)["type"]
	if is_melee(item):
		return "melee:" + _weapon_of(item)["type"]
	return ""


## The Guns / Melee entry a weapon item sells ({} for other items).
static func _weapon_of(item: Dictionary) -> Dictionary:
	if is_gun(item):
		return Guns.get_gun(item["gun"])
	if is_melee(item):
		return Melee.get_weapon(item["melee"])
	return {}


## How likely `item` is to be offered to `player`: its "weight" (default
## 1.0), times SAME_GUN_TYPE_WEIGHT for a gun of the type they're holding
## (SAME_MELEE_TYPE_WEIGHT for a melee weapon of the type they're holding).
static func offer_weight(player: Node, item: Dictionary) -> float:
	var weight := float(item.get("weight", 1.0))
	if is_gun(item) and Guns.get_gun(item["gun"])["type"] == player.gun.get("type", ""):
		weight *= SAME_GUN_TYPE_WEIGHT
	elif is_melee(item) and Melee.get_weapon(item["melee"])["type"] == player.melee.get("type", ""):
		weight *= SAME_MELEE_TYPE_WEIGHT
	return weight


## Price of a player's re-roll after `rerolls` re-rolls already this wave,
## in the shop after `waves_done` waves: 8, 16, 32, 64, ... in the first shop.
static func reroll_cost(rerolls: int, waves_done: int, player: Node = null) -> int:
	return roundi(REROLL_BASE_COST * pow(2.0, rerolls) * price_mult(waves_done, player))


## Effects in display order: buffs, then debuffs, each in the attribute order
## from CharacterClasses. Returns [[attribute_dict, delta], ...].
static func effects_in_order(item: Dictionary) -> Array:
	var buffs := []
	var debuffs := []
	for attr in CharacterClasses.ATTRIBUTES:
		if item["effects"].has(attr["id"]):
			var delta := int(item["effects"][attr["id"]])
			(buffs if delta > 0 else debuffs).append([attr, delta])
	return buffs + debuffs


## Each shop after the first adds this fraction of an item's listed cost
## (not compounding), so the shop after wave n charges
## cost * (1 + 0.5 * (n - 1)): x1.5 after wave 2, x5.5 after wave 10.
## Linear because income grows about linearly with the wave: this keeps a
## wave's earnings worth ~2-3 shop items all run, where compounding prices
## would leave nothing affordable in the late waves.
const PRICE_RISE_PER_WAVE := 0.5


## Multiplier on every shop price after `waves_done` waves (1 for the first
## shop), times `player`'s Coupon discount if a player is given.
static func price_mult(waves_done: int, player: Node = null) -> float:
	return (1.0 + PRICE_RISE_PER_WAVE * maxi(waves_done - 1, 0)) * discount(player) \
		* squad_mult(player)


## Every player in a squad gets their own copy of every resource picked up,
## and each extra player brings more enemies (PlayerScaling
## enemy_count_per_player), so each player earns more the bigger the squad.
## Prices rise by this share for each player in the squad after the first
## to make up for it.
const PRICE_RISE_PER_EXTRA_PLAYER := 0.5


## Price multiplier for the size of `player`'s squad (the players in their
## own game; other squads in a Squads game don't count). 1 alone or for null.
static func squad_mult(player: Node) -> float:
	if player == null or not player.is_inside_tree():
		return 1.0
	var squad := player.get_tree().get_nodes_in_group("all_players").size()
	return 1.0 + PRICE_RISE_PER_EXTRA_PLAYER * maxi(squad - 1, 0)


## Kills per Vampire Fangs heal with `count` owned (0 for none).
static func fang_kills(count: int) -> int:
	return FANG_KILLS[mini(count, FANG_KILLS.size()) - 1] if count > 0 else 0


## The Vampire Fangs line in `player`'s shop: what owning one more would do
## (`sold`: what the one just bought does).
static func fang_blurb(player: Node, sold: bool) -> String:
	var count := owned(player, "vampire_fangs") + (0 if sold else 1)
	return "Every %d kills heals half a heart" % fang_kills(count)


## How many of item `id` `player` has bought.
static func owned(player: Node, id: String) -> int:
	return player.items.count(id) if player else 0


## Multiplier on `player`'s shop prices from their Coupons (1 with none).
static func discount(player: Node) -> float:
	return pow(1.0 - COUPON_DISCOUNT, owned(player, "coupon"))


## What `item` sells for in the shop after `waves_done` waves (1 = the first
## shop, at the item's listed cost) to `player` (their Coupons; null = full
## price), rounded to the nearest whole resource.
static func price(item: Dictionary, waves_done: int, player: Node = null) -> int:
	return roundi(item["cost"] * price_mult(waves_done, player))


static func can_buy(player: Node, item: Dictionary, waves_done: int) -> bool:
	return player.resources >= price(item, waves_done, player)


## Charges the player and applies the item (a gun, melee weapon or
## equipment replaces the one they hold).
## Charges price(item, waves_done). Returns false if they can't afford it.
## (The shop allows one purchase per offered item per wave.)
static func buy(player: Node, item: Dictionary, waves_done: int) -> bool:
	if not can_buy(player, item, waves_done):
		return false
	player.spend_resources(price(item, waves_done, player))
	player.items.append(item["id"])
	if is_gun(item):
		player.equip_gun(item["gun"])
	if is_melee(item):
		player.equip_melee(item["melee"])
	if is_equipment(item):
		player.equip_equipment(item["equipment"])
	for id in item["effects"]:
		player.change_attribute(id, int(item["effects"][id]))
	return true


## What the shop's Upgrade Kit row offers `player` for their gun in the shop
## after `waves_done` waves: {"kind": "tune" | "promote" | "max", "cost" (-1
## for "max"), "gun" (the gun after buying), "level" (its level after buying)}.
static func tune_offer(player: Node, waves_done: int) -> Dictionary:
	var gun: Dictionary = player.gun
	var level: int = player.gun_level
	var mult := price_mult(waves_done, player)
	if level < Guns.MAX_LEVEL:
		return {"kind": "tune", "cost": maxi(roundi(Guns.tune_cost(gun, level) * mult), 1),
			"gun": gun, "level": level + 1}
	var next := Guns.next_tier(gun)
	if next.is_empty():
		return {"kind": "max", "cost": -1, "gun": gun, "level": level}
	return {"kind": "promote", "cost": roundi(Guns.promote_cost(gun) * mult), "gun": next, "level": 0}


## The same as tune_offer() for the player's melee weapon: {"kind", "cost",
## "weapon" (the weapon after buying), "level"}.
static func melee_tune_offer(player: Node, waves_done: int) -> Dictionary:
	var weapon: Dictionary = player.melee
	var level: int = player.melee_level
	var mult := price_mult(waves_done, player)
	if level < Melee.MAX_LEVEL:
		return {"kind": "tune", "cost": maxi(roundi(Melee.tune_cost(weapon, level) * mult), 1),
			"weapon": weapon, "level": level + 1}
	var next := Melee.next_tier(weapon)
	if next.is_empty():
		return {"kind": "max", "cost": -1, "weapon": weapon, "level": level}
	return {"kind": "promote", "cost": roundi(Melee.promote_cost(weapon) * mult),
		"weapon": next, "level": 0}


## Charges the player for melee_tune_offer() and applies it. Returns false
## if there's nothing to buy or they can't afford it.
static func buy_melee_tune(player: Node, waves_done: int) -> bool:
	var offer := melee_tune_offer(player, waves_done)
	if offer["kind"] == "max" or player.resources < offer["cost"]:
		return false
	player.spend_resources(offer["cost"])
	if offer["kind"] == "promote":
		player.equip_melee(offer["weapon"]["id"])
	else:
		player.tune_melee()
	return true


## Charges the player for tune_offer() and applies it. Returns false if
## there's nothing to buy or they can't afford it.
static func buy_tune(player: Node, waves_done: int) -> bool:
	var offer := tune_offer(player, waves_done)
	if offer["kind"] == "max" or player.resources < offer["cost"]:
		return false
	player.spend_resources(offer["cost"])
	if offer["kind"] == "promote":
		player.equip_gun(offer["gun"]["id"])
	else:
		player.tune_gun()
	return true
