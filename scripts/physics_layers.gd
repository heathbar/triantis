class_name PhysicsLayers
extends RefCounted
## Every 2D physics layer the game uses, as bit values for collision_layer /
## collision_mask (layer N = 1 << (N - 1)). The same names are set under
## Project Settings > Layer Names > 2D Physics, so the inspector shows them.
## Scenes (player.tscn, the enemy scenes, Braid strips) set these numbers
## directly; keep them in step if a layer moves.

## Layer 1: living players (a knocked-out player is on no layer).
const PLAYERS := 1 << 0
## Layer 2: enemies, objective structures that can be shot (nests) and boss
## bodies. Shots and hurtboxes look for this one.
const ENEMIES := 1 << 1
## Layer 3: Barricades (scripts/equipment/barricade.gd) and solid objective
## structures that can't be shot (scripts/objectives/structure.gd): enemies
## can't walk through them.
const BARRICADES := 1 << 2
## Layer 5: Braid walls: nothing passes them, shots included.
const WALLS := 1 << 4
## Layer 6: Braid window glass: blocks players and enemies, but not shots.
const WINDOWS := 1 << 5
