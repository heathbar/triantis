@tool
extends Node2D
## A Braid checkpoint, drawn: the shop the lane runs into at the end of each
## segment (scripts/braid/braid_level.gd puts one across every lane, over the
## solid gate block that stops players walking past it).
##
## Seen from above: a brick building (brick-1.png) with a SHOP sign, a front
## door on the left with a welcome mat (store-mat-1.png, the checkpoint plate)
## in front of it, and a back door on the right that squads leave by after the shop. Under the sign is
## one indicator light per squad in the game (ringed in its colour): red while
## none of that squad is on its plate, green once one of them is, grey if the
## squad is down (it doesn't hold anyone up). It says LOCKED until every light
## is lit, then OPEN. braid_game.gd decides the lights (the host does, in a
## squads game, so every lane shows the same) and sets them with set_lights.
##
## The node's position is the building's top-left corner; it is `size` big.
## The plate is outside it, to its left (plate_rect).

## The building's walls and the door mat, tiled.
const BRICK := preload("res://assets/meadow/environment/brick-1.png")
const MAT := preload("res://assets/meadow/environment/store-mat-1.png")
## Act-themed replacements for BRICK and MAT, when the act has them.
const ActTheme := preload("res://scripts/act_theme.gd")

## Light states (set_lights): nobody on the plate, someone on it, squad down.
enum Light { WAITING, ON_PLATE, OUT }

const PLATE_SIZE := Vector2(48, 96)
## The plate stands this far out from the front wall.
const PLATE_GAP := 4.0

const EAVE := Color(0.22, 0.12, 0.1)
const SHADOW := Color(0, 0, 0, 0.3)
## Darkens the building's bottom half (the old roof's slopes were 0.62 / 0.48 red).
const HALF_SHADE := Color(0, 0, 0, 0.5)
const BOARD := Color(0.42, 0.29, 0.17)
const BOARD_EDGE := Color(0.24, 0.15, 0.08)
const LETTERS := Color(1.0, 0.85, 0.35)
const DOOR := Color(0.36, 0.24, 0.14)
const DOOR_OPEN := Color(0.08, 0.06, 0.05)
const RED := Color(0.95, 0.2, 0.15)
const GREEN := Color(0.3, 1.0, 0.35)
const GREY := Color(0.4, 0.4, 0.42)

## 3x5 pixel letters, rows top to bottom.
const GLYPHS := {
	"S": ["111", "100", "111", "001", "111"],
	"H": ["101", "101", "111", "101", "101"],
	"O": ["111", "101", "101", "101", "111"],
	"P": ["111", "101", "111", "100", "100"],
	"L": ["100", "100", "100", "100", "111"],
	"C": ["111", "100", "100", "100", "111"],
	"K": ["101", "101", "110", "101", "101"],
	"E": ["111", "100", "110", "100", "111"],
	"D": ["110", "101", "101", "101", "110"],
	"N": ["111", "101", "101", "101", "101"],
}

@export var size := Vector2(128, 328):
	set(value):
		size = value
		queue_redraw()

## The squads with a light, in order, and their colours.
var squads: Array = [0]
var colors: Array = [Color.WHITE]
## {squad: Light}; squads not in it are WAITING.
var states := {}
## Squads have been through: the doors stand open and the lights are off.
var opened := false


func _ready() -> void:
	z_index = -8
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


## Which squads get a light (and their colours).
func set_squads(squad_list: Array, color_list: Array) -> void:
	squads = squad_list.duplicate()
	colors = color_list.duplicate()
	queue_redraw()


func set_lights(new_states: Dictionary) -> void:
	states = new_states.duplicate()
	queue_redraw()


func open() -> void:
	opened = true
	queue_redraw()


## Every squad on its plate (or down).
func unlocked() -> bool:
	for squad in squads:
		if states.get(squad, Light.WAITING) == Light.WAITING:
			return false
	return true


## The checkpoint plate, relative to the building's parent.
func plate_rect() -> Rect2:
	return Rect2(position + Vector2(-PLATE_SIZE.x - PLATE_GAP, (size.y - PLATE_SIZE.y) / 2.0), PLATE_SIZE)


func _draw() -> void:
	_draw_plate(plate_rect().position - position)
	var mid := size.y / 2.0
	# Shadow, then the brick building with a dark edge.
	draw_rect(Rect2(Vector2(4, 6), size), SHADOW)
	draw_texture_rect_region(ActTheme.environment("brick", BRICK), Rect2(Vector2.ZERO, size), Rect2(Vector2.ZERO, size))
	# The bottom half in shade (as the old roof's far slope was).
	draw_rect(Rect2(Vector2(0, mid), Vector2(size.x, size.y - mid)), HALF_SHADE)
	draw_rect(Rect2(Vector2.ZERO, size), EAVE, false, 2.0)

	# Front door (left) and back door (right): squads go in the front and
	# leave by the back.
	var door := Vector2(6, 40)
	var front := Rect2(Vector2(-2, mid - door.y / 2.0), door)
	var back := Rect2(Vector2(size.x - door.x + 2, mid - door.y / 2.0), door)
	for r in [front, back]:
		draw_rect(r, DOOR_OPEN if opened else DOOR)
		draw_rect(r, BOARD_EDGE, false, 1.0)

	# The sign.
	var board := Rect2(Vector2((size.x - 96.0) / 2.0, mid - 64.0), Vector2(96, 36))
	draw_rect(board, BOARD)
	draw_rect(board, BOARD_EDGE, false, 2.0)
	_draw_text("SHOP", board.get_center(), 4, LETTERS)

	# The status plaque: a light per squad and LOCKED / OPEN.
	var lights := squads.size()
	var plaque := Rect2(Vector2((size.x - 96.0) / 2.0, mid + 14.0), Vector2(96, 54))
	draw_rect(plaque, Color(0.12, 0.12, 0.14))
	draw_rect(plaque, BOARD_EDGE, false, 2.0)
	var spacing := 20.0
	var lx := plaque.get_center().x - spacing * (lights - 1) / 2.0
	for k in lights:
		var at := Vector2(lx + k * spacing, plaque.position.y + 16.0)
		var state: int = states.get(squads[k], Light.WAITING)
		var lit: Color = GREY if opened or state == Light.OUT else (GREEN if state == Light.ON_PLATE else RED)
		if not opened and state != Light.OUT:
			draw_circle(at, 9.0, Color(lit, 0.25))
		draw_circle(at, 7.0, colors[k] if k < colors.size() else Color.WHITE)
		draw_circle(at, 4.0, lit)
		draw_rect(Rect2(at + Vector2(-2, -3), Vector2(2, 2)), Color(1, 1, 1, 0.6))
	var text_at := Vector2(plaque.get_center().x, plaque.position.y + 40.0)
	if opened:
		return
	if unlocked():
		_draw_text("OPEN", text_at, 2, GREEN)
	else:
		_draw_padlock(text_at + Vector2(-34, 0))
		_draw_text("LOCKED", text_at + Vector2(6, 0), 2, RED)


## The welcome mat: the act's store-mat texture tiled (top-left at `at`).
func _draw_plate(at: Vector2) -> void:
	var r := Rect2(at, PLATE_SIZE)
	draw_rect(Rect2(r.position + Vector2(2, 3), r.size), SHADOW)
	draw_texture_rect_region(ActTheme.environment("store-mat", MAT), r, Rect2(Vector2.ZERO, r.size))
	draw_rect(r, BOARD_EDGE, false, 1.0)


func _draw_padlock(center: Vector2) -> void:
	draw_arc(center + Vector2(0, -3), 3.0, PI, TAU, 8, RED, 1.5)
	draw_rect(Rect2(center + Vector2(-4, -2), Vector2(8, 7)), RED)


## `text` in GLYPHS letters `scale` px per dot, centred on `center`.
func _draw_text(text: String, center: Vector2, scale: int, color: Color) -> void:
	var advance := 4 * scale
	var width := text.length() * advance - scale
	var origin := (center - Vector2(width, 5 * scale) / 2.0).round()
	for i in text.length():
		var glyph: Array = GLYPHS.get(text[i], [])
		for gy in glyph.size():
			var line: String = glyph[gy]
			for gx in line.length():
				if line[gx] == "1":
					draw_rect(Rect2(origin + Vector2(i * advance + gx * scale, gy * scale),
						Vector2(scale, scale)), color)
