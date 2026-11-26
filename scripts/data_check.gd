extends RefCounted
## Checks the game's hand-written data tables (guns, melee weapons, equipment,
## shop items, classes, characters, bosses, objectives and the standard run)
## for the mistakes a typo makes: a missing or misspelled key, an id that
## names nothing, a script path that doesn't exist. They're plain
## Dictionaries, so nothing else catches those until the game trips over
## them mid-run.
##
## Global runs this at startup when playing from the editor and reports each
## problem with push_error; tests/test_data.gd runs it too.

const Guns := preload("res://scripts/guns.gd")
const Melee := preload("res://scripts/melee.gd")
const Equipment := preload("res://scripts/equipment.gd")
const Items := preload("res://scripts/items.gd")
const CharacterClasses := preload("res://scripts/character_classes.gd")
const PlayerGun := preload("res://scripts/player/player_gun.gd")
const STANDARD_RUN := "res://data/waves/standard_run.tres"

## Keys every entry of each table must have, and the type of their values
## (TYPE_FLOAT also accepts ints).
const GUN_KEYS := {"id": TYPE_STRING, "name": TYPE_STRING, "type": TYPE_STRING,
	"cost": TYPE_FLOAT, "damage": TYPE_FLOAT, "interval": TYPE_FLOAT, "range": TYPE_FLOAT}
const MELEE_KEYS := {"id": TYPE_STRING, "name": TYPE_STRING, "type": TYPE_STRING,
	"cost": TYPE_FLOAT, "damage": TYPE_FLOAT, "interval": TYPE_FLOAT, "range": TYPE_FLOAT,
	"arc": TYPE_FLOAT}
const EQUIPMENT_KEYS := {"id": TYPE_STRING, "name": TYPE_STRING, "cost": TYPE_FLOAT,
	"blurb": TYPE_STRING}
const ITEM_KEYS := {"id": TYPE_STRING, "name": TYPE_STRING, "cost": TYPE_FLOAT,
	"effects": TYPE_DICTIONARY}
const CLASS_KEYS := {"name": TYPE_STRING, "gun": TYPE_STRING, "melee": TYPE_STRING,
	"attributes": TYPE_DICTIONARY}
const BOSS_KEYS := {"id": TYPE_STRING, "name": TYPE_STRING, "epithet": TYPE_STRING,
	"color": TYPE_COLOR, "script": TYPE_STRING, "summary": TYPE_STRING}
const OBJECTIVE_KEYS := {"id": TYPE_STRING, "name": TYPE_STRING, "color": TYPE_COLOR,
	"script": TYPE_STRING, "summary": TYPE_STRING}


## Every problem found, as readable lines ([] if the data is fine).
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var attribute_ids := {}
	for attr: Dictionary in CharacterClasses.ATTRIBUTES:
		attribute_ids[attr["id"]] = true

	_check_table(out, "Guns", Guns.LIST, GUN_KEYS)
	_check_positive(out, "Guns", Guns.LIST, ["damage", "interval", "range"])
	for type: Dictionary in Guns.TYPES:
		if not PlayerGun.TEXTURES.has(type.get("id", "")):
			out.append("Gun type %s: no image in PlayerGun.TEXTURES (it draws as a %s)" % [
				type.get("id", "?"), PlayerGun.DEFAULT_TYPE])
	_check_table(out, "Melee", Melee.LIST, MELEE_KEYS)
	_check_positive(out, "Melee", Melee.LIST, ["damage", "interval", "range"])
	_check_table(out, "Equipment", Equipment.LIST, EQUIPMENT_KEYS)
	for item: Dictionary in Equipment.LIST:
		if not Equipment.SCRIPTS.has(item.get("id", "")):
			out.append("Equipment %s: no script in Equipment.SCRIPTS" % item.get("id", "?"))

	_check_table(out, "Items", Items.all(), ITEM_KEYS)
	for item: Dictionary in Items.all():
		var id: String = item.get("id", "?")
		for key: String in item.get("effects", {}):
			if not attribute_ids.has(key):
				out.append("Item %s: effect \"%s\" isn't an attribute" % [id, key])
		if item.has("equipment") and Equipment.find(item["equipment"]).is_empty():
			out.append("Item %s: no equipment \"%s\"" % [id, item["equipment"]])

	for class_id: String in CharacterClasses.CLASSES:
		var data: Dictionary = CharacterClasses.CLASSES[class_id]
		_check_keys(out, "Class %s" % class_id, data, CLASS_KEYS)
		for key: String in data.get("attributes", {}):
			if not attribute_ids.has(key):
				out.append("Class %s: attribute \"%s\" doesn't exist" % [class_id, key])
		if Guns.find(data.get("gun", "")).is_empty():
			out.append("Class %s: no gun \"%s\"" % [class_id, data.get("gun", "")])
		if Melee.find(data.get("melee", "")).is_empty():
			out.append("Class %s: no melee weapon \"%s\"" % [class_id, data.get("melee", "")])
		var equipment: String = data.get("equipment", "")
		if not equipment.is_empty() and Equipment.find(equipment).is_empty():
			out.append("Class %s: no equipment \"%s\"" % [class_id, equipment])
	for character: Dictionary in Global.CHARACTERS:
		var class_id: String = character.get("class", "")
		# The sandbox character's class isn't in the table: its kit is set by hand.
		if not character.get("sandbox", false) and not CharacterClasses.CLASSES.has(class_id):
			out.append("Character %s: no class \"%s\"" % [character.get("name", "?"), class_id])

	for boss_id: String in Boss.BOSSES:
		var info: Dictionary = Boss.BOSSES[boss_id]
		_check_keys(out, "Boss %s" % boss_id, info, BOSS_KEYS)
		if info.get("id", "") != boss_id:
			out.append("Boss %s: its \"id\" says \"%s\"" % [boss_id, info.get("id", "")])
		_check_script(out, "Boss %s" % boss_id, info.get("script", ""))
	_check_table(out, "Objectives", Objective.TYPES, OBJECTIVE_KEYS)
	for type: Dictionary in Objective.TYPES:
		_check_script(out, "Objective %s" % type.get("id", "?"), type.get("script", ""))

	var run: WaveSet = load(STANDARD_RUN)
	if run == null:
		out.append("Can't load %s" % STANDARD_RUN)
	else:
		for i in run.waves.size():
			var wave := run.waves[i]
			if wave == null:
				out.append("Standard run wave %d: missing" % (i + 1))
				continue
			if wave.is_boss_wave() and not Boss.exists(wave.boss_id):
				out.append("Standard run wave %d: no boss \"%s\"" % [i + 1, wave.boss_id])
			for group in wave.enemy_groups:
				if group == null or group.enemy_scene == null:
					out.append("Standard run wave %d: an enemy group has no enemy scene" % (i + 1))
	return out


## Every entry has `keys` (of the right types) and ids are unique.
static func _check_table(out: PackedStringArray, table: String, entries: Array,
		keys: Dictionary) -> void:
	var seen := {}
	for entry: Dictionary in entries:
		var id: String = str(entry.get("id", "?"))
		_check_keys(out, "%s %s" % [table, id], entry, keys)
		if seen.has(id):
			out.append("%s: id \"%s\" is used twice" % [table, id])
		seen[id] = true


static func _check_keys(out: PackedStringArray, what: String, entry: Dictionary,
		keys: Dictionary) -> void:
	for key: String in keys:
		if not entry.has(key):
			out.append("%s: missing \"%s\"" % [what, key])
			continue
		var want: int = keys[key]
		var got := typeof(entry[key])
		if got != want and not (want == TYPE_FLOAT and got == TYPE_INT):
			out.append("%s: \"%s\" should be a %s" % [what, key, type_string(want)])


static func _check_positive(out: PackedStringArray, table: String, entries: Array,
		keys: Array) -> void:
	for entry: Dictionary in entries:
		for key: String in keys:
			var value: Variant = entry.get(key)
			if (value is int or value is float) and value <= 0:
				out.append("%s %s: \"%s\" must be above 0" % [table, entry.get("id", "?"), key])


static func _check_script(out: PackedStringArray, what: String, path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		out.append("%s: script \"%s\" doesn't exist" % [what, path])
