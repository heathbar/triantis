extends Control
## The HUD's equipment readout: a wrench in a disc when the equipment is
## ready. Once it's used, the wrench gives way to a dark disc that fills with
## a white wedge, clockwise from 12 o'clock, as the cooldown passes (like a
## clock); when the disc is all white, the wrench is back. Set `player`
## before adding it; hidden while they have no equipment.

const WRENCH := preload("res://assets/ui/wrench_32x32.png")
const Equipment := preload("res://scripts/equipment.gd")
const DISC_COLOR := Color(0, 0, 0, 0.5)
const COOLING_COLOR := Color(0.06, 0.06, 0.06, 0.9)
const ELAPSED_COLOR := Color(1, 1, 1, 0.95)
const RIM_COOLING := Color(0.45, 0.45, 0.45)
const RIM_WIDTH := 4.0
const PIE_STEPS := 48

var player: Node
var diameter := 52.0

var _fraction := -1.0  # cooldown left, 0..1, as last drawn


func _init(disc_diameter: float = 52.0) -> void:
	diameter = disc_diameter
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2.ONE * diameter
	# Pixel art: keep the wrench crisp when scaled up.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	visible = player.has_equipment()
	var fraction := 0.0
	if player.equipment_cooldown > 0.0 and player.equipment_cooldown_total > 0.0:
		fraction = clampf(player.equipment_cooldown / player.equipment_cooldown_total, 0.0, 1.0)
	if fraction != _fraction:
		_fraction = fraction
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := diameter / 2.0
	if _fraction <= 0.0:
		# Ready: the wrench.
		draw_circle(center, radius, DISC_COLOR)
		var icon := diameter * 0.7
		draw_texture_rect(WRENCH, Rect2(center - Vector2.ONE * icon / 2.0, Vector2.ONE * icon), false)
		draw_arc(center, radius - RIM_WIDTH / 2.0, 0.0, TAU, PIE_STEPS, Equipment.COLOR,
			RIM_WIDTH, true)
		return
	# Recharging: a dark disc that fills with white clockwise from 12 o'clock
	# as the cooldown passes (a quarter gone = the top-right quarter white).
	draw_circle(center, radius, COOLING_COLOR)
	var elapsed := 1.0 - _fraction
	if elapsed > 0.0:
		# An arc as thick as the radius is a pie slice (a polygon fails to
		# triangulate when nearly full).
		var steps := maxi(ceili(PIE_STEPS * elapsed), 2)
		draw_arc(center, radius / 2.0, -PI / 2.0, -PI / 2.0 + TAU * elapsed, steps,
			ELAPSED_COLOR, radius)
	draw_arc(center, radius - RIM_WIDTH / 2.0, 0.0, TAU, PIE_STEPS, RIM_COOLING, RIM_WIDTH, true)
