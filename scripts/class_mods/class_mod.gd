extends RefCounted
## Class Mods (arena and Campaign): the trees, the cards a player is
## offered, and what each player has picked. (What the picks do in play is
## scripts/class_mods/class_mod_fx.gd.)
##
## Every class leans on one weapon: gun classes mod their gun, melee
## classes their melee weapon. Each class has five branches (TREES): four
## for that main weapon and one for its other weapon. Every branch is three
## stages deep.
##
## After every boss fight each player is offered cards (offer) and picks
## one (pick). The next stage of every branch they've started is always
## offered; the rest (up to OFFER_COUNT cards) are stage 1 of branches they
## haven't, so a player can spread their picks over several branches or push
## one to stage 3. Classes not
## in TREES get no cards.
##
## Every branch changes how its weapon behaves through one "mechanic"
## (class_mod_fx.gd), with that stage's numbers. A mechanic appears at
## most once per class, so the effects code can look picks up by mechanic
## (mechanics()). Each stage's dict holds all of its numbers, not just what
## changed. Picks are kept on the player (Player.class_mod_picks) for the
## rest of the run.

const OFFER_COUNT := 3
const STAGE_SUFFIX := ["", " II", " III"]

const GUN_COLOR := Color(1.0, 0.75, 0.35)
const MELEE_COLOR := Color(0.6, 0.85, 1.0)

## Shared stage lists (several classes use the same mechanic and numbers).
const _RICOCHET := [
	{"text": "Shots bounce off walls once.", "bounces": 1, "gain": 0.0},
	{"text": "Shots bounce 3 times, +20% damage per bounce.", "bounces": 3, "gain": 0.2},
	{"text": "Shots bounce 3 times, +20% damage per bounce, and turn toward the nearest enemy after each bounce.",
		"bounces": 3, "gain": 0.2, "seek": true},
]
const _FULL_SPIN := [
	{"text": "Swings go all the way round.", "reach": 1.0},
	{"text": "Swings go all the way round and reach 40% further.", "reach": 1.4},
]

## class id -> {"main": "gun" or "melee", "gun": [branch, ...], "melee": [...]}.
## branch: {"id", "name", "mechanic", "stages": [stage 1, stage 2, stage 3]};
## stage: {"text", ...that stage's numbers}.
const TREES := {
	"sniper": {
		"main": "gun",
		"gun": [
			{"id": "rail", "name": "Rail", "mechanic": "pierce", "stages": [
				{"text": "Shots go through 3 enemies without losing damage", "pierce": 3, "gain": 0.0},
				{"text": "Shots go through everything, +15% damage for each enemy passed.", "pierce": 99, "gain": 0.15},
				{"text": "Shots go through everything (+15% damage for each enemy passed) and leave a burning line along their path for 3 s.",
					"pierce": 99, "gain": 0.15, "line": 3.0}]},
			{"id": "spotter", "name": "Spotter", "mechanic": "mark", "stages": [
				{"text": "Hits mark enemies for 3 s: they take +25% damage from everyone, other squads too.", "mult": 1.25, "secs": 3.0},
				{"text": "Hits mark enemies for 5 s: they take +50% damage from everyone, other squads too.", "mult": 1.5, "secs": 5.0},
				{"text": "Hits mark enemies for 5 s (+50% damage from everyone). A marked enemy that dies passes its mark to enemies within 48 px.",
					"mult": 1.5, "secs": 5.0, "spread": 48.0}]},
			{"id": "ricochet", "name": "Ricochet", "mechanic": "ricochet", "stages": _RICOCHET},
			# Each stage covers one more of the Sniper's weak spots (fire rate,
			# then speed, then armor) while the laser is on an enemy.
			{"id": "laser", "name": "Laser Sight", "mechanic": "laser", "stages": [
				{"text": "A laser sight shows your line of fire. While it's on an enemy you fire 25% faster.",
					"rate": 0.10},
				{"text": "While your laser is on an enemy you fire 20% faster and move 20% faster.",
					"rate": 0.2, "speed": 0.2},
				{"text": "While your laser is on an enemy you fire 25% faster, move 25% faster and have +50 armor.",
					"rate": 0.25, "speed": 0.25, "armor": 50}]},
		],
		"melee": [
			{"id": "lunge", "name": "Lunge", "mechanic": "lunge", "stages": [
				{"text": "Each swing carries you 40 px forward, through enemies.", "dist": 40.0, "guard": 0.0},
				{"text": "Each swing carries you 64 px forward, through enemies, and you can't be hurt during it.", "dist": 64.0, "guard": 0.35},
				{"text": "Each swing carries you 64 px forward and you can't be hurt during it. Your next shot after it does +50% damage.",
					"dist": 64.0, "guard": 0.35, "next_shot": 1.5}]},
		],
	},
	"soldier": {
		"main": "gun",
		"gun": [
			{"id": "underbarrel", "name": "Underbarrel", "mechanic": "grenade", "stages": [
				{"text": "Every 8th shot is a grenade that bursts where it stops (24 px).", "every": 8, "radius": 24.0, "dmg": 1.5},
				{"text": "Every 6th shot is a grenade, with bigger bursts (36 px).", "every": 6, "radius": 36.0, "dmg": 1.5},
				{"text": "Every 6th shot is a grenade (36 px bursts) that also scatters 3 bomblets.",
					"every": 6, "radius": 36.0, "dmg": 1.5, "bomblets": 3}]},
			{"id": "suppression", "name": "Suppression", "mechanic": "slow", "stages": [
				{"text": "Hits slow enemies by 20% for 1 s.", "mult": 0.8, "secs": 1.0},
				{"text": "Hits slow enemies by 35% for 1 s.", "mult": 0.65, "secs": 1.0},
				{"text": "Hits slow enemies by 35% for 1 s, and 3 hits within 1 s stun the enemy for 0.5 s.",
					"mult": 0.65, "secs": 1.0, "stun_hits": 3, "stun": 0.5}]},
			{"id": "ap", "name": "AP Rounds", "mechanic": "pierce", "stages": [
				{"text": "Shots go through 1 enemy.", "pierce": 1, "gain": 0.0},
				{"text": "Shots go through 2 enemies; +20% damage against Brutes, elites and bosses.",
					"pierce": 2, "gain": 0.0, "big": 0.2},
				{"text": "Shots go through 2 enemies (+20% damage against Brutes, elites and bosses). Enemies you go through take +15% damage from everyone for 3 s.",
					"pierce": 2, "gain": 0.0, "big": 0.2, "pierced_mark": 1.15, "pierced_secs": 3.0}]},
			{"id": "drum", "name": "Drum Mag", "mechanic": "drum", "stages": [
				{"text": "Holding fire speeds the gun up: +10% fire rate a second, up to +30%.", "per_sec": 0.1, "max": 0.3},
				{"text": "Holding fire speeds the gun up: +10% fire rate a second, up to +60%.", "per_sec": 0.1, "max": 0.6},
				{"text": "Holding fire speeds the gun up to +60% fire rate, and at full speed shots also go through 1 enemy.",
					"per_sec": 0.1, "max": 0.6, "pierce": 1}]},
		],
		"melee": [
			{"id": "bayonet", "name": "Bayonet", "mechanic": "lunge", "stages": [
				{"text": "Each swing lunges you 40 px forward, through enemies.", "dist": 40.0, "guard": 0.0},
				{"text": "Each swing lunges you 56 px forward, through enemies, and you can't be hurt during it.", "dist": 56.0, "guard": 0.35},
				{"text": "Each swing lunges you 56 px forward and you can't be hurt during it. Melee kills give +25% fire rate for 3 s.",
					"dist": 56.0, "guard": 0.35, "kill_rate": 0.25, "kill_secs": 3.0}]},
		],
	},
	"scavenger": {
		"main": "gun",
		"gun": [
			{"id": "salvage", "name": "Salvage", "mechanic": "salvage", "stages": [
				{"text": "Your kills have a 10% chance to drop an extra resource.", "chance": 0.1},
				{"text": "Your kills have a 20% chance to drop an extra resource.", "chance": 0.2},
				{"text": "Resources the tide swallows go to you instead of being lost.", "tide": true}]},
			{"id": "shredder", "name": "Shredder", "mechanic": "shred", "stages": [
				{"text": "Each hit makes the enemy take +5% damage from everyone (up to 5 times, for 4 s).", "per": 0.05, "max": 5},
				{"text": "Each hit makes the enemy take +8% damage from everyone (up to 8 times, for 4 s).", "per": 0.08, "max": 8},
				{"text": "Each hit makes the enemy take +8% damage from everyone (up to 8 times, for 4 s), and fully shredded enemies bleed.",
					"per": 0.08, "max": 8, "bleed": 0.5}]},
			{"id": "spray", "name": "Spray", "mechanic": "fan", "stages": [
				{"text": "Every shot is a burst of 2.", "extra": 1},
				{"text": "Every shot is a burst of 3.", "extra": 2},
				{"text": "Every shot is a burst of 3, and every bullet goes through 1 enemy.", "extra": 2, "pierce": 1}]},
			{"id": "recycler", "name": "Recycler", "mechanic": "recycler", "stages": [
				{"text": "Every 25 kills heal you half a heart.", "kills": 25},
				{"text": "Every 15 kills heal you half a heart.", "kills": 15},
				{"text": "Every 15 kills heal you half a heart and make you immune to damage for 1 s.", "kills": 15, "guard": 1.0}]},
		],
		"melee": [
			{"id": "clearcut", "name": "Clear-Cut", "mechanic": "spin", "stages": [
				{"text": "The machete swings all the way round.", "reach": 1.0},
				{"text": "The machete swings all the way round and reaches 10% further.", "reach": 1.1},
				{"text": "The machete swings all the way round and reaches 10% further, and melee kills always drop an extra resource.",
					"reach": 1.1, "kill_drop": 1}]},
		],
	},
	"engineer": {
		"main": "gun",
		"gun": [
			{"id": "nailer", "name": "Nailer", "mechanic": "nail", "stages": [
				{"text": "Rivets that stop leave a spike trap for 5 s (up to 8).", "secs": 5.0, "max": 8},
				{"text": "Rivets that stop leave a spike trap for 9 s (up to 14 at once).", "secs": 9.0, "max": 14},
				{"text": "Rivets that stop leave a spike trap for 9 s (up to 14) that slows enemies on it by 40%.", "secs": 9.0, "max": 14, "slow": 0.6}]},
			{"id": "mortar", "name": "Mortar", "mechanic": "mortar", "stages": [
				{"text": "Rivets arc over walls and burst where they land (28 px), even in a neighbour's lane.", "radius": 28.0, "dmg": 1.2},
				{"text": "Rivets arc over walls and burst where they land, with bigger (44 px), harder-hitting bursts.", "radius": 44.0, "dmg": 1.5},
				{"text": "Rivets arc over walls and burst where they land (44 px, harder-hitting), leaving a corrosive puddle for 3 s.", "radius": 44.0, "dmg": 1.5, "puddle": 3.0}]},
			{"id": "linker", "name": "Linker", "mechanic": "chain", "stages": [
				{"text": "Hits jump to 1 more enemy nearby.", "jumps": 1, "share": 0.6},
				{"text": "Hits jump to 3 more enemies nearby.", "jumps": 3, "share": 0.6},
				{"text": "Hits jump to 3 more enemies nearby, and to your equipment nearby, which zaps an enemy too.",
					"jumps": 3, "share": 0.6, "gadgets": true}]},
			{"id": "overclock", "name": "Overclock", "mechanic": "overclock", "stages": [
				{"text": "Each hit takes 0.2 s off your equipment's cooldown.", "per_hit": 0.2},
				{"text": "Each hit takes 0.4 s off your equipment's cooldown.", "per_hit": 0.4},
				{"text": "Each hit takes 0.4 s off your equipment's cooldown, and each kill adds 1 s to your equipment that's out.", "per_hit": 0.4, "kill_extend": 1.0}]},
		],
		"melee": [
			{"id": "torque", "name": "Torque", "mechanic": "spin", "stages": [
				{"text": "The wrench swings all the way round.", "reach": 1.0},
				{"text": "The wrench swings all the way round and reaches 40% further.", "reach": 1.4},
				{"text": "The wrench swings all the way round and reaches 40% further, and hitting your own equipment tops it up by 3 s.",
					"reach": 1.4, "extend": 3.0}]},
		],
	},
	"medic": {
		"main": "gun",
		"gun": [
			{"id": "triage", "name": "Triage", "mechanic": "heal", "stages": [
				{"text": "Shots heal your squad's players they pass (half a heart, at most once a second each).", "remote": false},
				{"text": "Shots heal players they pass, other squads' too (through windows and in shared rooms): half a heart, at most once a second each.", "remote": true},
				{"text": "Shots heal players they pass, other squads' too, and a squadmate already at full health gets a shield that stops one hit.",
					"remote": true, "shield": true}]},
			{"id": "toxin", "name": "Toxin", "mechanic": "toxin", "stages": [
				{"text": "Hits poison enemies for 3 s.", "dps": 0.6, "secs": 3.0, "spread": 0.0},
				{"text": "Hits poison enemies for 4 s with stronger poison, which spreads to enemies nearby when its host dies.", "dps": 1.0, "secs": 4.0, "spread": 48.0},
				{"text": "Stronger 4 s poison that spreads when its host dies. A poisoned enemy dying heals your squad's nearest player (you too) half a heart, at most once a second.",
					"dps": 1.0, "secs": 4.0, "spread": 48.0, "heal_kill": true}]},
			{"id": "fan", "name": "Fan", "mechanic": "fan", "stages": [
				{"text": "Every shot is a burst of 2.", "extra": 1},
				{"text": "Every shot is a burst of 4.", "extra": 3},
				{"text": "Every shot is a burst of 4, and the last bullet homes in on an enemy.", "extra": 3, "home_last": true}]},
			{"id": "stim", "name": "Stim Darts", "mechanic": "stim", "stages": [
				{"text": "Shots that pass squadmates give them +15% speed and fire rate for 3 s.", "boost": 0.15, "secs": 3.0},
				{"text": "Shots that pass squadmates give them +30% speed and fire rate for 3 s.", "boost": 0.3, "secs": 3.0},
				{"text": "Shots that pass squadmates give them +30% speed and fire rate for 3 s, and 6 of your shots passing a knocked-out squadmate revive them.",
					"boost": 0.3, "secs": 3.0, "revive_hits": 6}]},
		],
		"melee": [
			{"id": "sidestep", "name": "Side Step", "mechanic": "lunge", "stages": [
				{"text": "Each swing carries you 36 px forward, through enemies.", "dist": 36.0, "guard": 0.0},
				{"text": "Each swing carries you 56 px forward, through enemies, and you can't be hurt during it.", "dist": 56.0, "guard": 0.35},
				{"text": "Each swing carries you 56 px forward and you can't be hurt during it. Stepping through a squadmate heals them half a heart (once every 2 s each).",
					"dist": 56.0, "guard": 0.35, "heal_pass": 2.0}]},
		],
	},
	"gunner": {
		"main": "gun",
		"gun": [
			{"id": "incendiary", "name": "Incendiary", "mechanic": "burn", "stages": [
				{"text": "Hits set enemies on fire for 2 s. Each hit stacks more fire (up to 10).",
					"dps": 0.25, "secs": 2.0, "stacks": 10},
				{"text": "Hits set enemies on hotter fire for 3 s. Each hit stacks more fire (up to 10).", "dps": 0.4, "secs": 3.0, "stacks": 10},
				{"text": "Hits set enemies on hotter fire for 3 s, stacking up to 10, and burning enemies explode when they die (24 px).",
					"dps": 0.4, "secs": 3.0, "stacks": 10, "explode": 24.0}]},
			{"id": "bulldozer", "name": "Bulldozer", "mechanic": "push", "stages": [
				{"text": "Shots push enemies much harder.", "push": 3.0, "add": 6.0},
				{"text": "Shots push enemies even harder.", "push": 5.0, "add": 10.0},
				{"text": "Shots push enemies even harder, and enemies knocked into a wall are stunned for 1 s.",
					"push": 5.0, "add": 10.0, "wall_stun": 1.0}]},
			{"id": "emplacement", "name": "Emplacement", "mechanic": "brace", "stages": [
				{"text": "Standing still for 1 s gives +25% damage.", "after": 1.0, "dmg": 0.25},
				{"text": "Standing still for 1 s gives +50% damage.", "after": 1.0, "dmg": 0.5},
				{"text": "Standing still for 1 s gives +50% damage and +25 armor until you move.", "after": 1.0, "dmg": 0.5, "armor": 25}]},
			{"id": "tracer", "name": "Tracer Belt", "mechanic": "tracer", "stages": [
				{"text": "Every 5th shot marks the enemy for 3 s: +20% damage from everyone.", "every": 5, "mult": 1.2, "secs": 3.0},
				{"text": "Every 3rd shot marks the enemy for 3 s: +20% damage from everyone.", "every": 3, "mult": 1.2, "secs": 3.0},
				{"text": "Every 3rd shot marks the enemy for 3 s (+20% damage from everyone), and a marked enemy that dies passes its mark to enemies within 48 px.",
					"every": 3, "mult": 1.2, "secs": 3.0, "spread": 48.0}]},
		],
		"melee": [
			{"id": "shove", "name": "Shove", "mechanic": "shove", "stages": [
				{"text": "Swings push enemies back 48 px.", "push": 48.0, "stun": 0.0},
				{"text": "Swings push enemies back 72 px and stun them for 0.5 s.", "push": 72.0, "stun": 0.5},
				{"text": "Swings push enemies back 72 px and stun them for 0.5 s, and shoved enemies take +25% damage for 2 s.",
					"push": 72.0, "stun": 0.5, "mark": 1.25, "mark_secs": 2.0}]},
		],
	},
	"scout": {
		"main": "gun",
		"gun": [
			{"id": "runandgun", "name": "Run & Gun", "mechanic": "moving", "stages": [
				{"text": "+20% damage while moving.", "dmg": 0.2},
				{"text": "+35% damage while moving.", "dmg": 0.35},
				{"text": "+35% damage while moving, and shots fired on the move go through 1 enemy.", "dmg": 0.35, "pierce": 1}]},
			{"id": "hitandrun", "name": "Hit & Run", "mechanic": "hitrun", "stages": [
				{"text": "Kills give +20% speed for 2 s.", "speed": 0.2, "secs": 2.0, "stacks": 1},
				{"text": "Kills give +35% speed for 2 s.", "speed": 0.35, "secs": 2.0, "stacks": 1},
				{"text": "Kills give +35% speed for 2 s, stacking up to 3 times, and while it's on, touching enemies doesn't hurt.",
					"speed": 0.35, "secs": 2.0, "stacks": 3, "shield": true}]},
			{"id": "ricochet", "name": "Ricochet", "mechanic": "ricochet", "stages": _RICOCHET},
			{"id": "flare", "name": "Flare", "mechanic": "mark", "stages": [
				{"text": "Hits mark enemies for 3 s: +20% damage from everyone.", "mult": 1.2, "secs": 3.0},
				{"text": "Hits mark enemies for 5 s: +35% damage from everyone.", "mult": 1.35, "secs": 5.0},
				{"text": "Hits mark enemies for 5 s (+35% damage from everyone), and marked enemies drop an extra resource when they die.",
					"mult": 1.35, "secs": 5.0, "drop": 1}]},
		],
		"melee": [
			{"id": "slip", "name": "Slip", "mechanic": "lunge", "stages": [
				{"text": "Each swing dashes you 48 px forward, through enemies.", "dist": 48.0, "guard": 0.0},
				{"text": "Each swing dashes you 72 px forward, through enemies, and you can't be hurt during it.", "dist": 72.0, "guard": 0.35},
				{"text": "Each swing dashes you 72 px forward and you can't be hurt during it. Enemies you dash through are marked for 3 s (+20% damage from everyone).",
					"dist": 72.0, "guard": 0.35, "mark": 1.2, "mark_secs": 3.0}]},
		],
	},
	"brawler": {
		"main": "melee",
		"melee": [
			{"id": "charge", "name": "Shoulder Charge", "mechanic": "lunge", "stages": [
				{"text": "Each swing charges you 48 px forward, through enemies.", "dist": 48.0, "guard": 0.0},
				{"text": "Each swing charges you 72 px forward, through enemies, and you can't be hurt during it.", "dist": 72.0, "guard": 0.4},
				{"text": "Each swing charges you 72 px forward and you can't be hurt during it, stunning everything you go through for 0.6 s.",
					"dist": 72.0, "guard": 0.4, "stun": 0.6}]},
			{"id": "haymaker", "name": "Haymaker", "mechanic": "spin", "stages": [
				_FULL_SPIN[0], _FULL_SPIN[1],
				{"text": "Swings go all the way round and reach 40% further, and hits pull enemies 24 px toward you.", "reach": 1.4, "pull": 24.0}]},
			{"id": "shockwave", "name": "Shockwave", "mechanic": "wave", "stages": [
				{"text": "Swings send a short shockwave ahead.", "count": 1, "range": 0.25, "width": 24.0},
				{"text": "Swings send a bigger shockwave that goes further.", "count": 1, "range": 0.4, "width": 40.0},
				{"text": "Swings send an even longer shockwave that goes through walls (into the next lane, in the Campaign).",
					"count": 1, "range": 0.55, "width": 40.0, "walls": true}]},
			{"id": "combo", "name": "Combo", "mechanic": "combo", "stages": [
				{"text": "Melee hits within 1.5 s of each other add +10% melee damage (up to 5).", "per": 0.1, "max": 5, "window": 1.5},
				{"text": "Melee hits within 1.5 s of each other add +15% melee damage (up to 6).", "per": 0.15, "max": 6, "window": 1.5},
				{"text": "Melee hits within 1.5 s of each other add +15% melee damage (up to 6). At full combo your next swing is a ground slam that stuns everything within 48 px for 0.8 s.",
					"per": 0.15, "max": 6, "window": 1.5, "slam": 48.0, "stun": 0.8}]},
		],
		"gun": [
			{"id": "flak", "name": "Flak", "mechanic": "flak", "stages": [
				{"text": "Pellets burst into shrapnel after a short distance: hits round corners.", "shards": 3, "at": 0.45},
				{"text": "Pellets burst into more shrapnel, sooner: hits round corners.", "shards": 5, "at": 0.3},
				{"text": "Pellets burst into more shrapnel, sooner, and shrapnel hits add to your Combo.", "shards": 5, "at": 0.3, "combo": true}]},
		],
	},
	"duelist": {
		"main": "melee",
		"melee": [
			{"id": "dash", "name": "Dash", "mechanic": "lunge", "stages": [
				{"text": "Each swing dashes you 56 px forward, through enemies.", "dist": 56.0, "guard": 0.0},
				{"text": "Each swing dashes you 88 px forward, through enemies, and you can't be hurt during it.", "dist": 88.0, "guard": 0.35},
				{"text": "Each swing dashes you 88 px forward and you can't be hurt during it. A melee kill lets you swing again straight away.",
					"dist": 88.0, "guard": 0.35, "kill_reset": true}]},
			{"id": "whirlwind", "name": "Whirlwind", "mechanic": "spin", "stages": [
				{"text": "The katana spins all the way round.", "reach": 1.0},
				{"text": "The katana spins all the way round and reaches 40% further.", "reach": 1.4},
				{"text": "The katana spins all the way round, reaches 40% further, and each spin hits a second time.", "reach": 1.4, "twice": true}]},
			{"id": "windcutter", "name": "Wind Cutter", "mechanic": "wave", "stages": [
				{"text": "Swings send a blade of wind ahead.", "count": 1, "range": 0.35, "width": 16.0},
				{"text": "Swings send a wider blade of wind that goes further.", "count": 1, "range": 0.55, "width": 28.0},
				{"text": "Swings send a wider, longer blade of wind that flies back to you, hitting again.",
					"count": 1, "range": 0.55, "width": 28.0, "returns": true}]},
			{"id": "riposte", "name": "Riposte", "mechanic": "riposte", "stages": [
				{"text": "An enemy hit in the first 0.2 s of a swing is blocked.", "window": 0.2, "counter": 0.0},
				{"text": "An enemy hit in the first 0.3 s of a swing is blocked, and the block hits back for 2x melee damage.", "window": 0.3, "counter": 2.0},
				{"text": "Enemy hits in the first 0.3 s of a swing are blocked and hit back for 2x melee damage. A block also stuns enemies close by for 1 s and doubles your next swing.",
					"window": 0.3, "counter": 2.0, "stun": 1.0, "next_double": true}]},
		],
		"gun": [
			{"id": "deadeye", "name": "Dead-Eye", "mechanic": "mark", "stages": [
				{"text": "Hits mark enemies for 3 s: they take +25% damage from everyone, other squads too.", "mult": 1.25, "secs": 3.0},
				{"text": "Hits mark enemies for 5 s: they take +50% damage from everyone, other squads too.", "mult": 1.5, "secs": 5.0},
				{"text": "Hits mark enemies for 5 s (+50% damage from everyone), and a katana hit on a marked enemy does double damage and uses up the mark.",
					"mult": 1.5, "secs": 5.0, "melee_double": true}]},
		],
	},
	"tank": {
		"main": "melee",
		"melee": [
			{"id": "juggernaut", "name": "Juggernaut", "mechanic": "lunge", "stages": [
				{"text": "Each swing steps you 32 px forward, through enemies.", "dist": 32.0, "guard": 0.0},
				{"text": "Each swing steps you 48 px forward, through enemies, and you can't be hurt during it.", "dist": 48.0, "guard": 0.35},
				{"text": "Each swing steps you 48 px forward and you can't be hurt during it, and enemies you hit are thrown, damaging whatever they land on.",
					"dist": 48.0, "guard": 0.35, "throw": 48.0}]},
			{"id": "wideswing", "name": "Wide Swing", "mechanic": "spin", "stages": [
				_FULL_SPIN[0], _FULL_SPIN[1],
				{"text": "Swings go all the way round and reach 40% further, and hits pull enemies 24 px toward you.", "reach": 1.4, "pull": 24.0}]},
			{"id": "groundpound", "name": "Ground Pound", "mechanic": "ring", "stages": [
				{"text": "Swings send out a ring that hits everything within 24 px.", "radius": 24.0, "stun": 0.0},
				{"text": "Swings send out a bigger ring that hits everything within 40 px and stuns for 0.4 s.", "radius": 40.0, "stun": 0.4},
				{"text": "Swings send out a ring that hits and stuns everything within 40 px, and every 3rd swing is a quake that hits everything within 120 px.",
					"radius": 40.0, "stun": 0.4, "quake_every": 3, "quake": 120.0}]},
			{"id": "bulwark", "name": "Bulwark", "mechanic": "bulwark", "stages": [
				{"text": "Each melee hit gives +5 armor for 4 s (up to +25).", "per": 5, "max": 25, "secs": 4.0},
				{"text": "Each melee hit gives +8 armor for 4 s (up to +40).", "per": 8, "max": 40, "secs": 4.0},
				{"text": "Each melee hit gives +8 armor for 4 s (up to +40). At full armor, enemies touching you take damage.",
					"per": 8, "max": 40, "secs": 4.0, "thorns": 0.5}]},
		],
		"gun": [
			{"id": "concussion", "name": "Concussion", "mechanic": "concussion", "stages": [
				{"text": "Shots knock enemies back much harder.", "push": 3.0, "stun": 0.0, "blast": 0.0},
				{"text": "Shots knock enemies back much harder and stun them for 0.5 s.", "push": 3.0, "stun": 0.5, "blast": 0.0},
				{"text": "Shots knock enemies back much harder, stun them for 0.5 s, and burst on impact (32 px).", "push": 3.0, "stun": 0.5, "blast": 32.0}]},
		],
	},
}


## True if `class_id` has Class Mod trees.
static func has_trees(class_id: String) -> bool:
	return TREES.has(class_id)


## "gun" or "melee": the weapon `class_id` leans on ("" without trees).
static func main_slot(class_id: String) -> String:
	return TREES.get(class_id, {}).get("main", "")


## What `player` has picked: {branch id: stage reached (1..3)}.
static func picks(player: Node) -> Dictionary:
	return player.class_mod_picks


## Every branch `player` has started: [{"slot", "branch", "level", "stage"}].
static func actives(player: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mine := picks(player)
	var tree: Dictionary = TREES.get(player.class_id, {})
	for slot in ["gun", "melee"]:
		for branch in tree.get(slot, []):
			var level := int(mine.get(branch["id"], 0))
			if level > 0:
				out.append({"slot": slot, "branch": branch, "level": level,
					"stage": branch["stages"][level - 1]})
	return out


## `player`'s current stage numbers by mechanic: {mechanic: stage dict}.
## A stage dict also carries "level" (1..3) and "slot".
static func mechanics(player: Node) -> Dictionary:
	var out := {}
	for a in actives(player):
		var stage: Dictionary = a["stage"].duplicate()
		stage["level"] = a["level"]
		stage["slot"] = a["slot"]
		out[a["branch"]["mechanic"]] = stage
	return out


## True if `player` has started any branch for `slot`.
static func has_slot(player: Node, slot: String) -> bool:
	for a in actives(player):
		if a["slot"] == slot:
			return true
	return false


## Every card `player` could be offered now: [{"slot", "branch", "level"}]:
## stage 1 of each branch not started, and the next stage of each started
## branch that isn't at stage 3 yet.
static func pool(player: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mine := picks(player)
	var tree: Dictionary = TREES.get(player.class_id, {})
	for slot in ["gun", "melee"]:
		for branch in tree.get(slot, []):
			var level := int(mine.get(branch["id"], 0))
			if level < branch["stages"].size():
				out.append({"slot": slot, "branch": branch, "level": level + 1})
	return out


## The cards for `player`: the next stage of every class mod they've
## started (always offered, so a mod can always be pushed further), then
## stage 1 of mods they haven't, drawn at random with `rng`, up to
## OFFER_COUNT cards in all (more if they have more mods to upgrade).
static func offer(player: Node, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var fresh: Array[Dictionary] = []
	for c in pool(player):
		if int(c["level"]) > 1:
			out.append(c)
		else:
			fresh.append(c)
	while out.size() < OFFER_COUNT and not fresh.is_empty():
		var c: Dictionary = fresh[rng.randi_range(0, fresh.size() - 1)]
		out.append(c)
		fresh.erase(c)
	return out


## `player` takes `card` (one of their offer).
static func pick(player: Node, card: Dictionary) -> void:
	var mine: Dictionary = picks(player).duplicate()
	mine[card["branch"]["id"]] = int(card["level"])
	player.class_mod_picks = mine


## A card's title, e.g. "Rail II".
static func card_title(card: Dictionary) -> String:
	return card["branch"]["name"] + STAGE_SUFFIX[clampi(int(card["level"]) - 1, 0, 2)]


static func card_text(card: Dictionary) -> String:
	return card["branch"]["stages"][card["level"] - 1]["text"]
