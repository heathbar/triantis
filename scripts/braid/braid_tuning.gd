@tool
extends RefCounted
## Braid mode's numbers in one place (first drafts, unplaytested). Braid is a
## separate mode (see scripts/braid/braid_game.gd): nothing here changes the
## arena game.
##
## Units are world pixels at the 640x360 pixel-art view.

## A lane is one band, exactly one screen tall.
const BAND_HEIGHT := 360.0
## The solid wall along the top and bottom of every band.
const OUTER_WALL := 16.0
## Lane strips are built in multiples of this (one screen wide).
const SCREEN_WIDTH := 640.0
## The usual strip length (two screens).
const STRIP_LENGTH := 1280.0
## Every strip leaves this part of its left and right ends open (y range), so
## any strip can follow any other: the "door slot".
const DOOR_SLOT := Vector2(120.0, 240.0)
## How far in from each end a strip must keep the door slot clear.
const DOOR_DEPTH := 32.0
## The narrowest a strip's way through may be (players are 26 px, elites
## bigger): checked by BraidStrip.problems and BraidLevel.check.
const MIN_CORRIDOR := 64.0

## Physics layer bit of Braid walls (PhysicsLayers.WALLS). Players and
## enemies get it added to their collision masks in Braid; nothing in the
## arena game uses it.
const WALL_LAYER := PhysicsLayers.WALLS
## Physics layer bit of window glass (PhysicsLayers.WINDOWS): bodies can't
## pass it, shots can (shots only stop at WALL_LAYER).
const WINDOW_LAYER := PhysicsLayers.WINDOWS

# --- Lanes (one per squad) and where they meet -----------------------------------

## Most lanes a level has (one per squad, Squads.MAX_SQUADS).
const MAX_LANES := 4
## The wall between two lanes: each band's own outer wall, back to back.
const SEPARATOR := OUTER_WALL * 2.0
## Every slot of a segment is this long: one strip per lane, or a junction
## or window across two lanes. (A run's first slot, and a calm opener, are
## SCREEN_WIDTH.)
const SLOT_LENGTH := 1280.0
## Window seams: glass panes this wide between pillars this wide, starting
## and ending this far in from the slot's ends.
const WINDOW_PANE := 192.0  # was 96: doubled after playtesting
const WINDOW_PILLAR := 32.0
const WINDOW_INSET := 64.0
## The camera zooms out to this while the squad is at a window or in a
## junction, so both lanes fit on screen.
const ZOOM_OUT := 0.5
## Favour plates (scripts/braid/braid_favour.gd): stand on one this long to
## drop a crusher on this much of the neighbouring lane, across the window.
const FAVOUR_HOLD := 1.0
const FAVOUR_CRUSH_SIZE := Vector2(160.0, 300.0)
## Damage a crusher deals each enemy it lands on (x the segment's enemy
## health multiplier).
const FAVOUR_DAMAGE := 400
## Seconds a favour plate takes to recharge after dropping its crusher (was
## one use per plate before playtesting).
const FAVOUR_RECHARGE := 12.0

# --- Players and equipment -----------------------------------------------------

## (Hearts were doubled here after playtesting; the classes themselves now
## have double hearts, in both modes: scripts/character_classes.gd.)
## Equipment retuning for Braid only (set on every player as
## Equipment.TUNING_META; see scripts/equipment.gd stats()). Empty: Braid's
## quicker, shorter-lived equipment numbers, the Turret/Tesla Coil pack-up and
## the Riot Shield and Air Strike are now the shared numbers in equipment.gd,
## the same in the arena.
const EQUIPMENT_TUNING := {}

# --- Enemies -----------------------------------------------------------------

## A splitter's pieces can't hurt anyone for this long after they burst out,
## and spend it scattering away from the players (so melee classes aren't
## punished for killing it up close).
const SPLIT_GRACE := 1.2

# --- The tide ---------------------------------------------------------------

## Pixels per second, unless a strip sets its own (BraidStrip.tide_speed).
## Players walk at 100. (Was 60: slowed after playtesting, so squads have
## time to stop and fight instead of running.)
const TIDE_SPEED := 40.0
## Where the tide starts, this far behind the segment's start.
const TIDE_START_GAP := 160.0
## The segment ends when the tide gets this close to the checkpoint gate.
const TIDE_GATE_STOP := 56.0
## (Squads go into the shop early once one player of every squad stands on
## their checkpoint plate: see braid_game.gd.)
## Half hearts a player loses every TIDE_DAMAGE_INTERVAL seconds while the
## tide touches them (ignores armour).
const TIDE_DAMAGE := 1
const TIDE_DAMAGE_INTERVAL := 1.0
## Players can't be further into the tide than this: it pushes them along.
const TIDE_PUSH_DEPTH := 6.0
## Enemies and pickups this far inside the tide are swallowed (enemies drop
## nothing, pickups are lost).
const TIDE_SWALLOW_DEPTH := 12.0

# --- Segments and enemies -----------------------------------------------------

## A Standard run: this many acts, each this many lane segments and then a
## boss fight in the convergence room.
const ACTS := 4
const SEGMENTS_PER_ACT := 4
## Act a's boss fight borrows standard-run wave BOSS_WAVES[a] (its boss,
## health, prize and the enemies that trickle in).
const BOSS_WAVES: Array[int] = [4, 9, 14, 19]
## Bosses that have a Braid version (scripts/braid/bosses/); an act whose
## boss isn't here yet fights FALLBACK_BOSS instead.
const BRAID_BOSSES := {
	"crusher": "res://scripts/braid/bosses/braid_crusher.gd",
	"lighthouse": "res://scripts/braid/bosses/braid_lighthouse.gd",
	"quartet": "res://scripts/braid/bosses/braid_quartet.gd",
	"vault": "res://scripts/braid/bosses/braid_vault.gd",
}
const FALLBACK_BOSS := "crusher"
## Boss fights: the enemies that trickle in (and the opening burst) are this
## many times the borrowed wave's, per boss. Bosses not listed: 1.
const BOSS_ADD_MULTIPLIER := {
	"crusher": 2.0,
}
## The generator (scripts/braid/braid_generator.gd) makes each segment's
## strips add up to one of these lengths (px), picked at random: 2 or 2.5
## two-screen strips, about 64 or 80 s of tide. (Was 3840/4480: 25% shorter
## after playtesting.)
const SEGMENT_LENGTHS: Array[float] = [2560.0, 3200.0]
## Strip difficulty (1-5) the generator aims for in an act's first and last
## segments (straight line between).
const DIFFICULTY_FIRST := 1.5
const DIFFICULTY_LAST := 4.5
## Chance a segment (not the first) opens with a calm strip, a breather
## after the shop.
const CALM_CHANCE := 0.35
## The same strip at most this many times in one segment.
const STRIP_REPEATS := 2
## The run's segment n (counting through every act) uses the enemy mix of
## this standard-run wave (0-based), skipping boss waves, with counts
## stretched to the segment's length.
const SEGMENT_WAVES: Array[int] = [0, 1, 2, 3, 5, 6, 7, 8, 10, 11, 12, 13, 15, 16, 17, 18]
## Enemies per second compared with the arena wave the segment borrows from
## (1.0 = the same rate).
const ENEMY_DENSITY := 1.7  # was 0.85: doubled after playtesting
## Where each spawn (one enemy group) comes from, so fights don't all happen
## facing right. Rolled in this order; one that can't happen right now (no
## room behind the squad, no door free) falls through to the vents ahead.
## Behind: just off the left edge of the screen (only with the tide far
## enough back), so the squad has to turn round.
const BEHIND_SPAWN_SHARE := 0.3
## Doors: through a door in the lane's top or bottom wall (BraidDoor), on
## screen or just ahead, after a warning.
const DOOR_SPAWN_SHARE := 0.3
## Of what's left: share that comes out of the tide (while it's off screen
## behind us) instead of a spawn vent ahead.
const TIDE_SPAWN_SHARE := 0.25
## Behind spawns land up to this far past the left edge of the screen.
const BEHIND_SPAWN_DEPTH := 160.0
## Doors (scripts/braid/braid_door.gd): at these fractions of each slot's
## length, in each lane's top and bottom wall (dropped where a strip's walls
## block them, at windows and in junctions).
const DOOR_SPOTS_TOP: Array[float] = [0.2, 0.7]
const DOOR_SPOTS_BOTTOM: Array[float] = [0.45, 0.95]
## A door is this wide; enemies step out this far into the lane.
const DOOR_WIDTH := 28.0
const DOOR_EXIT_DEPTH := 24.0
## Seconds a door flashes before enemies come through, and stays open after.
const DOOR_WARNING := 0.9
const DOOR_HOLD_OPEN := 0.6
## Doors closer than this ahead of where the tide will be when they open
## aren't used (enemies shouldn't appear in or right by the tide).
const DOOR_TIDE_MARGIN := 160.0
## A door isn't used if a player is this close to it.
const DOOR_MIN_PLAYER_DISTANCE := 96.0
## Doors this far past the right edge of the screen can still be used.
const DOOR_AHEAD := 160.0
## Spawn vents wake up between the edge of the screen (plus this margin) and
## this far ahead of the squad.
const SPAWN_SCREEN_MARGIN := 24.0
const SPAWN_AHEAD_MAX := 960.0
## Nothing spawns closer than this to the checkpoint gate.
const SPAWN_GATE_MARGIN := 48.0

# --- The convergence room ------------------------------------------------------

## The room at the end of each act: this long, at least ROOM_MIN_LANES bands
## tall (one per lane otherwise).
const ROOM_LENGTH := 1920.0
const ROOM_MIN_LANES := 2
## The lane mouths: the first this much of the room, where squads come in
## and gather. The boss stays out of it.
const MOUTH_DEPTH := 192.0
## Camera zoom in the room.
const ROOM_ZOOM := 0.5

# --- Pathing --------------------------------------------------------------------

## Flow field cell size. Corridors are at least 120 px, so 7+ cells.
const FLOW_CELL := 16.0
## Seconds between flow field rebuilds.
const FLOW_INTERVAL := 0.2
## The field covers from this far behind the squad to this far ahead; enemies
## outside it walk straight.
const FLOW_BEHIND := 720.0
const FLOW_AHEAD := 1280.0
## Walls are treated as this much bigger, so paths don't scrape them.
const FLOW_WALL_PAD := 4.0

# --- Vertical slices ------------------------------------------------------------

## Twice an act (never in its first segment) the lanes turn up (once) and
## down (once) for a short stretch, then back to running right
## (BraidGenerator.act_layout, BraidLevel). In a corner each lane turns along
## its own L: the corner's two arms in a lane are (lanes - 1 - its place
## from the inside) * BAND_HEIGHT long, the turning square in between counts
## as BAND_HEIGHT * PI / 4 (about 283 px), and the second corner turns the
## other way, so every lane is equally long over a slice.
## Two-screen strips in the vertical stretch between the corners, by how many
## lanes there are (1, 2, 3, 4): with more lanes the corners' own arms already
## climb (lanes - 1) * BAND_HEIGHT, so slices stay short.
const SLICE_STRIPS_BY_LANES: Array[int] = [1, 1, 0, 0]
## The tide's speed over a slice (corners too), times the slowest of its
## strips': a little slower, since the screen shows about half as far ahead
## running up or down.
const VERTICAL_TIDE_FACTOR := 0.85
## The camera zooms out to this through a vertical slice (corners too), so
## the screen shows more of the lane ahead and behind (it's only 360 tall).
const VERTICAL_ZOOM := 0.75
## The camera looks this far ahead along the lane while it runs up or down
## (0: centred on the squad, as when it runs right).
const VERTICAL_CAMERA_LEAD := 80.0

# --- Camera ---------------------------------------------------------------------

## Players can't spread further apart than the camera shows: the camera
## frames every living player in our squad, at least this far (world px,
## centre to screen edge) inside the screen's edge, and zooms out past the
## place's own zoom only to keep doing that. (At most 28, or two players
## against a lane's opposite walls would zoom the camera out.)
const SCREEN_MARGIN := 24.0
