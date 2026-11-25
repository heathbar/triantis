@tool
extends Node2D
## A mounted turret in a gun port: a slit of glass in the wall between two
## lanes (scripts/braid/braid_level.gd builds both). It sits in the wall with
## its seat in lane `lane` and fires into the neighbouring lane
## `target_lane`, at whichever squad's enemies are there.
##
## A player of ours near the seat sees an X bubble; pressing X (E on the
## keyboard) puts them on the gun (Player.set_mount): they can't move, and
## their aim (right stick, or the mouse while firing) swings the gun across
## the 180 degrees of the other lane. It never runs out or overheats. Press X
## again, or B (E or Q on the keyboard), to get off; being knocked out, or
## shoved off the seat (the tide does that), lets go too. The gunner is still open to their own lane's enemies;
## the other lane's can't reach them through the wall.
##
## Shots are ordinary projectiles credited to the gunner, so hits on other
## squads' enemies go to their games as window shots do (braid_link.gd), and
## the kills' drops come out in the gunner's lane. Damage scales with the
## segment's enemy health (BraidTuning.TURRET_DAMAGE).

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")
const BraidPrompt := preload("res://scripts/braid/braid_prompt.gd")
const Projectile := preload("res://scripts/projectile.gd")

const SHOT_SOUND := preload("res://assets/weapons/guns/minigun.ogg")
const SOUND_VOLUME := 0.2
const SOUND_POLYPHONY := 4
## The gunner stands this far out from the wall's face.
const SEAT_DEPTH := 14.0
## Off the seat by more than this (pixels): they've been shoved off.
const SEAT_SLACK := 4.0
## The art (assets/misc): the gun, drawn pointing right, turning about
## GUN_PIVOT (the middle of its housing; its muzzle is BARREL out from there),
## and the mount that fills the gun port, drawn for a turret facing down (its
## top on the seat side of the wall).
const GUN_TEXTURE := preload("res://assets/misc/mounted-turret.png")
const BASE_TEXTURE := preload("res://assets/misc/mounted-turret-base.png")
const GUN_PIVOT := Vector2(6.0, 5.5)
const BARREL := 21.0
const FLASH := Color(1.0, 0.9, 0.45)

## The lane its seat is in, the lane it fires into, and its progress along
## the lanes (BraidLevel.progress).
var lane := 0
var target_lane := 1
var s := 0.0
## Straight across into the target lane (world; Vector2.UP or DOWN).
var facing := Vector2.DOWN
## The game (scripts/braid/braid_game.gd), set when the level is built: for
## sending shots to the other squads and knowing when play is on.
var game: Node = null
## Who's on it (null if no one).
var gunner: Node2D = null

## The barrel's angle (world).
var _angle := 0.0
var _cooldown := 0.0
var _flash := 0.0
## Per player: X held last frame (a press is held now, not then), and X or
## B held last frame (to get off).
var _was_held := {}
var _was_leaving := {}
## The player shown the bubble (nearest to the seat, nobody on the gun).
var _near: Node2D = null
var _sound: AudioStreamPlayer


func _ready() -> void:
	z_index = 5
	_angle = facing.angle()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	add_to_group("braid_turrets")
	_sound = AudioStreamPlayer.new()
	_sound.stream = SHOT_SOUND
	_sound.bus = Global.SFX_BUS
	_sound.volume_db = linear_to_db(SOUND_VOLUME)
	_sound.max_polyphony = SOUND_POLYPHONY
	add_child(_sound)


func _exit_tree() -> void:
	_release()


## Where the gunner stands (world).
func seat() -> Vector2:
	return global_position - facing * (BraidTuning.SEPARATOR / 2.0 + SEAT_DEPTH)


func _physics_process(delta: float) -> void:
	var flashing := _flash > 0.0
	_flash = maxf(_flash - delta, 0.0)
	if gunner != null and (not is_instance_valid(gunner) or gunner.is_dead()
			or gunner.mount != self or gunner.global_position.distance_to(seat()) > SEAT_SLACK):
		_release()
	var near: Node2D = null
	var near_d := BraidTuning.TURRET_REACH
	var seen := {}
	for p: Node2D in get_tree().get_nodes_in_group("players"):
		seen[p] = true
		var held: bool = p.interact_held()
		var pressed: bool = held and not _was_held.get(p, false)
		_was_held[p] = held
		# (Kept for everyone: the X that got them on isn't a press to get off.)
		var leaving: bool = held or p.drop_held()
		var leave_pressed: bool = leaving and not _was_leaving.get(p, false)
		_was_leaving[p] = leaving
		if p.is_dead():
			continue
		if p == gunner:
			if leave_pressed:
				_release()
			continue
		var d := p.global_position.distance_to(seat())
		if gunner != null or d > BraidTuning.TURRET_REACH or p.is_mounted():
			continue
		if pressed and _can_mount(p):
			_take(p)
			continue
		if d <= near_d:
			near_d = d
			near = p
	for p in _was_held.keys():
		if not seen.has(p):
			_was_held.erase(p)
			_was_leaving.erase(p)
	if near != _near or near != null or flashing:
		_near = near
		queue_redraw()


func _can_mount(p: Node2D) -> bool:
	return not p.is_dashing() and not p.is_carrying() and _play_on()


func _play_on() -> bool:
	return game == null or not game.has_method("is_wave_running") or game.is_wave_running()


func _take(p: Node2D) -> void:
	gunner = p
	p.global_position = seat()
	p.velocity = Vector2.ZERO
	p.set_mount(self)
	_cooldown = 0.0
	queue_redraw()


func _release() -> void:
	if gunner != null and is_instance_valid(gunner) and gunner.mount == self:
		gunner.set_mount(null)
	gunner = null
	queue_redraw()


## The gunner's aim this frame (Player calls it while they're on the gun):
## swing the barrel there (kept to the other lane's half) and fire.
func mounted_aim(player: Node2D, aim: Vector2, delta: float) -> void:
	if player != gunner:
		return
	_cooldown -= delta
	if aim == Vector2.ZERO or not _play_on():
		_cooldown = maxf(_cooldown, 0.0)
		return
	aim = clamp_aim(aim)
	_angle = aim.angle()
	queue_redraw()
	if _cooldown <= 0.0:
		_cooldown = maxf(_cooldown + BraidTuning.TURRET_INTERVAL, 0.0)
		_shoot(aim)


## `aim` turned to the nearest direction within the turret's half circle
## (into the target lane, TURRET_EDGE_MARGIN short of the wall each side).
func clamp_aim(aim: Vector2) -> Vector2:
	var limit := PI / 2.0 - BraidTuning.TURRET_EDGE_MARGIN
	var off := clampf(facing.angle_to(aim), -limit, limit)
	return facing.rotated(off)


func _shoot(aim: Vector2) -> void:
	var along_wall := Vector2(-facing.y, facing.x)
	var half := BraidTuning.SEPARATOR / 2.0 + 2.0
	# Out through the slit: from the far face of the wall, where the aim
	# crosses it (kept inside the slit).
	var slide := aim.dot(along_wall) / maxf(aim.dot(facing), 0.05) * half
	var reach := BraidTuning.TURRET_PORT / 2.0 - 3.0
	var start := global_position + facing * half + along_wall * clampf(slide, -reach, reach)
	var shot := Projectile.new()
	shot.direction = aim.rotated(randf_range(-BraidTuning.TURRET_SPREAD, BraidTuning.TURRET_SPREAD) / 2.0)
	var scale_by: float = gunner.wave_enemy_health if "wave_enemy_health" in gunner else 1.0
	shot.damage = maxi(roundi(BraidTuning.TURRET_DAMAGE * scale_by), 1)
	shot.speed = BraidTuning.TURRET_SHOT_SPEED
	shot.lifetime = BraidTuning.TURRET_RANGE / BraidTuning.TURRET_SHOT_SPEED
	shot.size = BraidTuning.TURRET_SHOT_SIZE
	shot.knockback = BraidTuning.TURRET_KNOCKBACK
	shot.shooter = gunner
	shot.position = start  # before add_child
	gunner.get_parent().add_child(shot)
	var link: Variant = game.get("link") if game else null
	if link != null and is_instance_valid(link):
		link.report_shot(shot, "minigun")
	_sound.play()
	_flash = 0.05


func _draw() -> void:
	# The mount, in the port (turned from facing down to `facing`).
	draw_set_transform(Vector2.ZERO, facing.angle() - PI / 2.0)
	draw_texture(BASE_TEXTURE, -BASE_TEXTURE.get_size() / 2.0)
	# The gun, turned to its aim; flipped over when it points left, so its
	# light side stays up.
	var dir := Vector2.from_angle(_angle)
	draw_set_transform(Vector2.ZERO, _angle, Vector2(1.0, -1.0 if dir.x < 0.0 else 1.0))
	draw_texture(GUN_TEXTURE, -GUN_PIVOT)
	draw_set_transform(Vector2.ZERO)
	if _flash > 0.0:
		draw_circle(dir * (BARREL + 2.0), 3.0, FLASH)
	if gunner == null and _near != null:
		var at := to_local(seat())
		at += Vector2(0, 24) if facing == Vector2.UP else Vector2(0, -26)
		BraidPrompt.draw_button(self, at, _near.device == Global.KEYBOARD)
