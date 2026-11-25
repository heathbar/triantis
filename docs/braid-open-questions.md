# Braid: open questions and calls Claude made

Running list kept while building Braid without playtests. Each item says
what's in the build now, so you can play it and answer. Newest phase first.
Answered items move to the bottom with your answer.

Design doc: https://claude.ai/artifact/DczSfRHizDwo5siPRsWK3u

## Airstrike pads and mounted turrets (2026-11-23)

You decided: turrets sit in their own gun ports (not at windows), 1-2 per
lane per act, no limit apart from the tide, and the airstrike is a carpet
box. Claude's calls (unplaytested):

- **Interact button:** X on a controller, **E** on the keyboard (new
  "interact" action). The X bubble is drawn as pixel art (blue X button, or
  an E key for the keyboard player), not the menu's X.svg.
- **Airstrike:** hold X for 1 s in the pad's circle (it used to be standing
  on it). Release and hold again for another once it recharges (12 s, as
  before). 0.9 s blinking warning box, then 4 columns x 3 staggered bombs
  land left to right over 240 x 300 px (the crusher was 160 x 300). Each
  enemy is hit once for the same 400 x enemy health. The other squad sees
  the warning, so their enemies may walk out (or be herded in). Never hurts
  players. Blast sound is the bomber's. Its kills go to the player who
  held the pad, like their shots' through a window: they get the points,
  and the drops land where the enemy died (across the window, so they
  reach that squad when the chapter ends; the bombed squad gets none).
- **Turret numbers:** 6 damage x the segment's enemy health multiplier
  every 0.08 s (about 75 x mult per second, roughly 5x a starting pistol at
  wave 1 and the same share of an enemy's health at any wave), 5 degree
  spread, 480 px range, slight knockback. It ignores the gunner's upgrades,
  attributes and Class Mods.
- **Turret rules:** press X within 22 px of the seat to get on, X again or
  B (E or Q on the keyboard) to get off. Knocked out, or shoved off the seat (the tide does this), lets
  go. While on it: no moving, own gun, melee or equipment. The camera zooms
  out to show both lanes while anyone of yours is on a turret (not when
  just walking past).
- **Kills and drops** from turret shots go to the gunner's squad (as
  window shots do already); drops land where the enemy died, in its lane.
- **Placement:** in a slot where the wall to the neighbour is plain (not
  a window or junction), spread over different segments, at most two per
  wall per slot. Segments are only 2-3 slots long and windows, junctions
  and slices take most of them (a 2-lane act often has no plain normal
  slot), so ports can also go in openers (start/calm strips) and in the
  walls of vertical slices, firing sideways; normal slots are tried first.
  The spot along the slot avoids door spots and strip blocks (gunner room
  on the seat side, a clear muzzle on the other); with no clear spot the
  turret is skipped.
- **Only with 2+ squads,** like windows (a solo run has one lane).
- **Not synced:** other squads see the turret's shots but its barrel
  doesn't turn on their screens.

## Playtest round 2 (2026-11-17): calls Claude made

- **Caltrop Trail and Dash Pack, in both modes** (you asked). Caltrops: 10 s
  of spikes behind you every 14 px, each patch 6 s, 3 damage + slow to 60%
  every 0.5 s; cooldown 30 s (Braid 12 s). Dash: 110 px in 0.18 s, through
  enemies, untouchable until 0.15 s after; 10 damage + knockback to each
  enemy passed; cooldown 12 s (Braid ~7 s). The arena shop now has two more
  equipment items, so equipment turns up a little more often there.
- **Splitter pieces (Braid):** harmless and fleeing for 1.2 s, drawn faded.
- **Favour plates recharge** (12 s) instead of working once; step off and
  back on to drop another.
- **Window panes doubled** (96 -> 192 px; pillars still 32).
- **A wiped squad's enemies now stay** (no spawning for it). They still only
  chase other squads in junction rooms and the boss room, so in a boss fight
  a wiped squad's leftovers go after the others.

## Phase 6: content (code side so far)

- **Art is waiting on you.** The doc's Phase 6 starts with the first act
  theme's tileset (TileMapLayer with terrain sets) and the act themes
  (setting, tide look, enemy mix per act). Everything is still greybox
  blocks on the arena's grass. What are the 4 (or 5) settings, and do you
  want to draw the tiles, or should Claude make placeholder pixel tiles?
- **All four bosses now have Braid versions,** in the doc's order: Crusher,
  Lighthouse, Fruit Bowl, Vault (act 1 to 4). Changes for the shared room:
  - Fruit Bowl: every piece is in everyone's reach, so pieces spread round the
    room as in a solo game (the doc's "each piece heads toward a lane
    mouth" isn't done).
  - Vault: each squad's keypad turns up in the first third of the room, in
    its own lane's band (near its mouth).
  - Lighthouse: unchanged.
  The bots beat the Crusher, Lighthouse and Fruit Bowl in the room; the Vault
  needs codes typed at its keypad, which only a person can test.
- **15 normal greybox strips** now (+ start + rest): added columns,
  courtyard (a walled yard with a vent inside: an ambush), bunkers, pinch,
  split (pick the top or bottom corridor) and zigzag (tide 50 px/s).
- **Braid has its own player-scaling table** (data/braid/
  braid_player_scaling.tres), starting at the arena's values.
- **Not built:** Long runs (5 × 5) and the fifth boss they need; zone tags
  (calm/normal/ambush) driving the enemy budget within a segment; resource
  caches in side alcoves.

## Phase 5: Class Mods

- **Rebuilt 2026-11-19 from the user's chart:** every class except the
  new equipment class (skipped) has five branches, each three stages deep.
  Gun classes (Soldier, Scavenger, Sniper, Engineer, Medic, Gunner, Scout)
  get four gun branches plus one melee branch; melee classes (Brawler,
  Duelist, Tank) get four melee branches plus one gun branch. Slug,
  Breacher, Fan the Hammer, Trick Shot and Thrown Knives are gone.
- **Picks can spread:** each card is stage 1 of a branch not started, or
  the next stage of one started (3 cards drawn at random from those). Only
  3 picks in a Standard run (after bosses 1-3), so stage 3 means putting
  every pick into one branch. Want more picks (mid-act, or run start)?
- **Changes from the chart** (things that didn't fit the game):
  - Drum Mag ramps +10% a second, not +3% (at +3% it took 10-20 s of
    nonstop fire to reach the cap).
  - Flare II: "seen through walls" means nothing (nothing is hidden), so
    it's 5 s marks at +35% instead.
  - Stim Darts III: there's no revive-by-standing to speed up, so 6 of the
    Medic's shots passing a knocked-out squadmate revive them.
  - Whirlwind III: "hold to keep spinning" became "each spin hits a second
    time".
  - Riposte: blocks already give the usual 1 s of safety, so stage 3 stuns
    enemies close by and doubles your next swing instead.
  - Ground Pound III's quake hits everything within 120 px, not "the whole
    lane width".
  - Triage III's shield is for a squadmate already at full health that
    the shot passes; it stops one hit.
  - Lunges now pass through enemies (they used to stop at the first one).
- **Charge Shot** stops the gun firing on its own: hold fire to charge,
  release to shoot (a ring round the player shows the charge).
- **Damage-over-time numbers are relative** (x the hit's damage a second),
  so "bleed", "burn" and puddles keep up with the gun.
- **Cross-squad branches:** Spotter / Dead-Eye marks work on other squads'
  enemies (their game is told); Triage II heals other squads' players it
  passes (through windows, in junctions and the boss room); Mortar arcs
  over walls, including into a neighbour's lane.
- **Other squads see modded shots as plain white shots** (only the effects
  are real); Fan bursts are shown; Flak isn't reshaped for them.
- **A shared-script change:** enemies got a damage-taken multiplier
  (chasesplayer.gd, always 1 in the arena) for marks.
- All numbers are first guesses (e.g. mark +25%/+50%, poison 0.6×/1.0× the
  shot's damage per second).

## Phase 4: convergence rooms, bosses, the act loop

- **Boss for every act is the Crusher (for now).** Only the Crusher is ported
  (as the doc's plan says); acts 2 to 4 use the Crusher with the prize of
  that act's boss wave (waves 10, 15, 20) and its own health scaled by how
  much tougher that act's enemies are: 2100, ~3640, 5600, 7000 for one
  player (+85% per extra player, every squad counted). The Lighthouse,
  Fruit Bowl and Vault come in Phase 6. OK, or port the Lighthouse now too?
- **A shop before the boss.** The last segment of an act ends at a checkpoint
  with a shop like any other, then the boss fight starts in the room (like
  the arena's wave 4 → shop → wave 5 boss). So an act is 4 segments + 1 boss
  round, 5 shops. The doc can be read either way.
- **The room is at least two lanes tall.** With one squad the room is two
  bands (720 px) tall, not one: the Crusher needs room to turn. With 2 to 4
  squads it's one band per lane. It's 1920 px long, with 192 px "lane mouths"
  at the left that the truck can't drive into (cover, and where squads wait).
- **Camera in the room:** zoomed out to ½, following your squad (the room is
  too tall to show whole with 3 or 4 lanes). The boss is marked at the
  screen edge when it's off screen.
- **Lanes at the start of each act rotate:** squad k starts act a in lane
  (k + a) mod lanes, so everyone gets a turn in the inner lanes. (Doc open
  question: by seed, or squads pick by walking into a lane mouth?)
- **Boss health when a squad wipes mid-fight:** left alone (doc open
  question).
- **After the boss:** prize summary → (Class Mod pick, Phase 5) → shop →
  next act's level. The boss entrance plays before everyone readies up.
- **Each act is a fresh level** starting at x 0 (keeps levels small to build).

## Phase 3: lanes and network

- **Braid bar at the bottom of the HUD,** not the top (the timer and player
  panels are at the top).
- **"Host Braid (prototype)" is on the Squads menu,** not the Game Mode menu
  (that menu is already 21 px taller than the screen, before Braid).
- **Zoom ½ at windows and junctions:** halves the pixel art (every other
  pixel dropped). Readable?
- **Enemies chase other squads' players only inside junction rooms;**
  elsewhere each squad's enemies stay on that squad.
- **Favour crusher damage:** 400 × the segment's enemy health multiplier
  (kills most things). One use per plate.
- **Junction seals only block your own squad,** so you'll see the other
  squad walk "through" your seal.
- **Wiped squads spectate only** (Left/Right switches squad). Doc open
  question: let them work a favour device?
- **Squads.gd protocol version 9 → 10** (adds a mode message channel the
  arena never uses).

## Phase 2: pieces and generator

- (Superseded by the pacing change below.) **Segments are 55 to 78 s (median 66),** shorter than the doc's 75 s,
  because there are no short normal strips: segments come out as 3 strips
  (3.5 with a start/rest opener). Raise SEGMENT_LENGTHS or add one-screen
  strips?
- **Maze strip slows the tide to 40 px/s** (its path is much longer than the
  strip). With several lanes, a slot's tide speed is the slowest of its
  strips.
- **Braid dock** must be enabled once: Project > Project Settings > Plugins >
  Braid Tools.

## Phase 1

- Tide: 60 px/s, half a heart a second after a 0.5 s grace, pushes you
  along, and knocks you out if it pins you against a wall until it covers
  you. (Doc open question: harsher or softer?)

## Still open from the design doc

- Run length: offer Standard (4×4) and Long (5×5), or one? (Standard only
  is built.)
- Class Mods: only after each boss, or also a small one mid-act?
- Shop: a 60 s countdown once the first squad is ready? Sending supplies in
  the first version? (Neither is built: everyone waits for the slowest squad.)
- Which 4 or 5 classes launch first? Act themes?
- The early-arrival comment on the doc: should arriving early buy anything?

## Answered

- **Pacing (2026-11-17, after your playtest: "a lot of running and very
  little shooting").** Segments are 25% shorter (2 or 2.5 strips, 2560 or
  3200 px), the tide is a third slower (60 → 40 px/s; maze 27, zigzag 33),
  and enemies come twice as fast (ENEMY_DENSITY 0.85 → 1.7). Segments still
  last about the same time (median 67 s), so roughly twice the enemies
  over a third less ground. All in scripts/braid/braid_tuning.gd.
- **Fast-forward at the checkpoint (2026-11-17, you asked: "don't keep them
  waiting").** Once every squad's standing players are within 96 px of the
  gate (a downed squad counts as arrived), the tide runs 10× as fast and
  no more enemies spawn. Enemies already out still have to be dealt with.
  A banner says "ALL AT THE CHECKPOINT". The host decides in a squads game.
  Not in boss rounds. Numbers: CHECKPOINT_ARRIVE_DISTANCE and FAST_FORWARD
  in braid_tuning.gd. Calls Claude made: it doesn't switch off if someone
  walks back, and dead players in an otherwise arrived squad don't hold it
  up.
- **Side effect of doubling enemies:** syncing enemies to a neighbouring
  squad could go over a network packet (lost packets). Now at most 80 per
  squad per update, nearest to their view's centre.
- **No spawns at the tide while it's on screen (2026-11-17, you said enemies
  appeared in/near the tide at the start).** The tide still sends out a
  quarter of the enemies, but only while it's off screen behind the squad.
  Otherwise they come from vents ahead, or from just off screen ahead if no
  vent is in reach. A splitter that dies near the tide still breaks into
  runners there.
- **Enemies from behind and through doors (2026-11-18, you said it was
  always walking and shooting right).** Each enemy group now rolls where it
  comes from: 30% from just off the left of the screen (between the tide and
  the squad, when there's room), 30% through a door in the lane's top or
  bottom wall (the door flashes red for 0.9 s first, and never one within
  96 px of a player), and the rest as before (vents ahead, or the tide).
  Doors are added by the level, 2 in the top wall and 2 in the bottom wall
  of each slot, dropped where a strip's walls are in the way, at windows and
  in junctions. Numbers: BEHIND_SPAWN_SHARE, DOOR_SPAWN_SHARE, DOOR_* in
  braid_tuning.gd. Boss fights unchanged. Unplaytested.
- **Hearts, equipment, pack-up, Riot Shield and Air Strike in both modes
  (2026-11-18, you said make the arena match Braid).**
  - Hearts: every class's hearts are doubled in the class data itself
    (scripts/character_classes.gd: 1 -> 2, 2 -> 4, 3 -> 6; the "average"
    is now 4), so the character screen shows the real number. Braid's own
    x2 is gone (it would have made 4x). Items that add or cost a heart
    still move it by one, so they matter half as much as before.
  - Equipment: Braid's numbers are now the shared numbers in
    scripts/equipment.gd: cooldowns 24 s at 0 engineering (was 60; 4 s at
    +100, 48 s at -100), durations 12 s (was 20); Turret 20 s; Drone 20 s;
    Adrenaline Shot 10 s / 22.5 s cooldown; Cluster Grenade 9 s cooldown;
    Caltrop Trail 12 s cooldown; Dash Pack 7.2 s cooldown. Braid's
    EQUIPMENT_TUNING overlay is now empty (kept in case the modes need to
    differ again).
  - Turret and Tesla Coil pack-up works in the arena ("pickup" is a
    normal item stat now).
  - Riot Shield and Air Strike are no longer hidden: the arena shop offers
    them (the arena shop now has 17 equipment items, so equipment turns up
    a bit more often again).
- **Vertical slices (2026-11-18: you liked the one-lane turn test and asked
  for the full version, turns in pairs, two slices per act, one up and one
  down, kept short).** Every act now has one slice up and one down, in two
  different segments (never the act's first), each after that segment's
  first normal slot. All lanes turn together; in a corner each lane takes
  its own L round the inside corner, the inside lane short and the outside
  lane long, and the second corner turns the other way so every lane is
  exactly as long over the slice. The tide runs at one speed across the
  whole slice (0.85x the slowest of its strips). Junctions, windows and
  checkpoints only appear where the lanes run right. The one-lane test
  (its title button and dock button) is gone. Open questions:
  - Slice length: SLICE_STRIPS_BY_LANES = [1, 1, 0, 0] strips between the
    corners for 1-4 lanes, because with 3-4 lanes the corners' arms already
    climb 720-1080 px per lane. A slice then takes about 54 s of tide (1
    lane), 75 s (2), 59 s (3) or 80 s (4). Short enough?
  - The long corner arms (up to 1080 px with 4 lanes) are plain corridors
    with a pillar and a spawn vent every 360 px, not hand-built strips.
  - A segment with a slice runs longer than one without (up to about
    2.5 min with 4 lanes).
  - In a vertical stretch the lanes are side by side but not level with
    each other (a lane is 720 px behind the one inside it), which is why
    there are no windows there.
  - Still unplaytested with more than one lane (headless tests only).
