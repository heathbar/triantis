extends RefCounted
## Campaign modifiers: optional rules that make a Campaign (Braid) run harder
## for a higher score, picked on the modifiers page
## (scripts/ui/modifiers_menu.gd) after character select. The page only
## shows once this machine has won the Campaign (Global.campaign_cleared),
## or while Global.sandbox_enabled() (testing). None are on by default.
##
## The picks are Global.campaign_modifiers (kept for the session, not saved);
## in a Squads game the host's picks go to everyone as the game starts
## (Squads.modifiers). Global.current_modifiers() is whichever applies.
##
## Each modifier adds its "score" to the run's score multiplier (1 + the sum),
## which every point earned in the run is multiplied by
## (Player.score_multiplier), the end-of-run cash-in included.
##
## What each one does is played out by scripts/braid/braid_game.gd (and,
## for Tyrants' mortars, scripts/braid/bosses/braid_boss_mortars.gd), using
## the numbers below.

const ICON_DIR := "res://assets/ui/modifiers/%s.png"

## In page order (4 to a row). "score" is the score multiplier it adds.
const LIST := [
	{"id": "champions", "name": "Champions", "score": 0.2,
		"blurb": "More elites: about 1 in 15 more enemies spawn as an elite, bosses' adds too."},
	{"id": "riptide", "name": "Riptide", "score": 0.25,
		"blurb": "The tide moves 25% faster, and its enemies come just as fast."},
	{"id": "ambush", "name": "Ambush", "score": 0.2,
		"blurb": "More enemies come from behind and through doors, and doors give less warning."},
	{"id": "tyrants", "name": "Tyrants", "score": 0.25,
		"blurb": "Bosses have 40% more health, and rain mortar shells on the room."},
	{"id": "glass_heart", "name": "Glass Heart", "score": 0.3,
		"blurb": "Everyone starts with one heart fewer (never below one)."},
	{"id": "horde", "name": "Horde", "score": 0.15,
		"blurb": "25% more enemies, in chapters and boss fights."},
	{"id": "ironhide", "name": "Ironhide", "score": 0.2,
		"blurb": "Enemies have 25% more health."},
	{"id": "famine", "name": "Famine", "score": 0.25,
		"blurb": "Enemies drop 30% fewer resources."},
]

## Champions: added to every round's elite chance (still capped by the
## player scaling's max_elite_chance).
const ELITE_CHANCE_BONUS := 1.0 / 15.0
## Riptide: the tide's speed, everywhere.
const TIDE_SPEED_MULT := 1.25
## Ambush: shares of spawns from behind the squad and through doors, and the
## doors' warning flash (seconds). Without it: BraidTuning's.
const AMBUSH_BEHIND_SHARE := 0.4
const AMBUSH_DOOR_SHARE := 0.4
const AMBUSH_DOOR_WARNING := 0.5
## Tyrants: boss health (the mortars' numbers are in braid_boss_mortars.gd).
const BOSS_HEALTH_MULT := 1.4
## Glass Heart: hearts taken off every player's class (never below
## CharacterClasses.LIVES_MIN).
const HEARTS_LOST := 1
## Horde: enemy counts.
const ENEMY_COUNT_MULT := 1.25
## Ironhide: enemy health (not bosses').
const ENEMY_HEALTH_MULT := 1.25
## Famine: each resource an enemy would drop is kept with this chance.
const DROP_KEEP_CHANCE := 0.7


## The modifier with id `id` ({} if none).
static func find(id: String) -> Dictionary:
	for m: Dictionary in LIST:
		if m["id"] == id:
			return m
	return {}


static func icon(id: String) -> Texture2D:
	var path := ICON_DIR % id
	return load(path) if ResourceLoader.exists(path) else null


## Whether modifier `id` is on for the game being played.
static func is_on(id: String) -> bool:
	return id in Global.current_modifiers()


## 1 + every picked modifier's score.
static func score_multiplier(ids: Array) -> float:
	var total := 1.0
	for id in ids:
		total += float(find(str(id)).get("score", 0.0))
	return total


## "x1.45" for a multiplier.
static func multiplier_text(mult: float) -> String:
	return "x%.2f" % mult


## "Riptide, Horde" (in page order), or "" for none.
static func names(ids: Array) -> String:
	var parts := PackedStringArray()
	for m: Dictionary in LIST:
		if m["id"] in ids:
			parts.append(m["name"])
	return ", ".join(parts)


## Whether character select shows the modifiers page before a Campaign run.
static func page_unlocked() -> bool:
	return Global.campaign_cleared or Global.sandbox_enabled()
