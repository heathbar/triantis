extends Enemy
## Bomber: when its target is within FUSE_RANGE it lights its fuse, slows
## down, swells and blinks, and FUSE_TIME later blows up. Killing it first
## also sets it off, straight away. The blast hurts players (blast_damage
## half hearts, if their armor doesn't block it) and every enemy in it
## (enemy_blast_damage, which grows with the wave), so a bomber shot in a
## crowd is a gift. Blowing itself up earns nobody anything; when a player
## kills it, they're credited with whatever the blast kills.
##
## Drawn as a puffball spore (the meadow's, the default): glowing purple
## (bomber-1), flickering between its red frames (bomber-fuse-1a/b) as the
## fuse burns, and bursting into a spore cloud (bomber-cloud-1a/b, blown up
## to the blast's size) instead of a fireball. Act-themed art is one image
## that flashes FUSE_TINT on a lit fuse and blows up in an ordinary blast.

const Blast := preload("res://scripts/equipment/blast.gd")
const ActTheme := preload("res://scripts/act_theme.gd")

## Played as it blows up (every act's bombers, and other squads' bombers
## blowing up on our map), at this volume (0-1, of the Effects volume).
const BLAST_SOUND := preload("res://assets/meadow/enemies/bomber.ogg")
const BLAST_VOLUME := 0.35
## Lights the fuse when its target is this close (centre to centre).
const FUSE_RANGE := 52.0
const FUSE_TIME := 0.9
## Speed (x normal) once the fuse is lit.
const FUSE_SPEED := 0.45
## Knockback of the blast on enemies, in pixels.
const BLAST_KNOCKBACK := 40.0
## A player's body counts as reaching this far from their centre.
const PLAYER_HALF := 12.0
## The default (meadow) art: unlit, the lit fuse's two frames, and its spore
## cloud's two frames. A lit fuse swells any look.
const LOOK := preload("res://assets/meadow/enemies/bomber-1.png")
const FUSE_FRAMES: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/bomber-fuse-1a.png"),
	preload("res://assets/meadow/enemies/bomber-fuse-1b.png"),
]
const CLOUD_FRAMES: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/bomber-cloud-1a.png"),
	preload("res://assets/meadow/enemies/bomber-cloud-1b.png"),
]
## The spore cloud: seconds on its first frame, then fading out on its second.
const CLOUD_BURST := 0.15
const CLOUD_FADE := 0.6
const WARNING_COLOR := Color(1.0, 0.4, 0.1, 0.5)
const FUSE_TINT := Color(1.0, 0.25, 0.2)

@export var blast_radius := 60.0
## Half hearts the blast costs a player caught in it.
@export var blast_damage := 2
## Damage to each enemy caught in the blast, x the wave's health multiplier.
@export var enemy_blast_damage := 15

## Seconds left on the fuse; < 0 while it isn't lit.
var _fuse := -1.0
var _blink := 0.0
var _sprite: Sprite2D
var _sprite_scale := Vector2.ONE
## Drawn with act-themed art (Braid act 2: a sea mine), not the default.
var _themed := false


func _ready() -> void:
	var look := ActTheme.enemy_look("bomber")
	_themed = look != null
	ActTheme.apply_look(self, look if look else LOOK)
	super()
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite:
		_sprite_scale = _sprite.scale


## Elites tint the sprite (there's no ColorRect for the base class to recolour).
## self_modulate, so it stacks with the Freeze Ray's modulate.
func make_elite(scaling: PlayerScaling) -> void:
	super(scaling)
	blast_damage = maxi(blast_damage, ELITE_DAMAGE)
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.self_modulate = elite_color


func _desired_velocity(target: Node2D, delta: float) -> Vector2:
	if _fuse < 0.0:
		if target and global_position.distance_to(target.global_position) <= FUSE_RANGE:
			_fuse = FUSE_TIME
			queue_redraw()
		return super(target, delta)
	_fuse -= delta
	if _fuse <= 0.0:
		_detonate.call_deferred()
		return Vector2.ZERO
	return super(target, delta) * FUSE_SPEED


## Blew itself up: no kill to credit, so no points or drops.
func _detonate() -> void:
	if is_dead():
		return
	points_value = 0
	resource_drops = 0
	_die(null)


func _on_death(killer: Node) -> void:
	_explode(global_position, killer)


func mirror_died(at: Vector2) -> void:
	_explode(at, null)


## The blast at `center`: hurts our players and our own enemies in it (not
## mirrors: each squad's game blows up its own side, see mirror_died).
func _explode(center: Vector2, killer: Node) -> void:
	Global.play_sfx(BLAST_SOUND, BLAST_VOLUME)
	var enemy_damage := maxi(roundi(enemy_blast_damage * health_scale), 1)
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or (enemy is Enemy and enemy.is_mirror) or not enemy.has_method("take_damage") \
				or enemy.is_dead():
			continue
		var reach: float = enemy.half_extent() if enemy.has_method("half_extent") else 12.0
		if center.distance_to(enemy.global_position) - reach <= blast_radius:
			var away := center.direction_to(enemy.global_position)
			if away == Vector2.ZERO:
				away = Vector2.RIGHT.rotated(randf() * TAU)
			enemy.take_damage(enemy_damage, killer, away * BLAST_KNOCKBACK)
	for player: Node2D in get_tree().get_nodes_in_group("players"):
		if player is Player and center.distance_to(player.global_position) - PLAYER_HALF <= blast_radius:
			player.hurt_by(blast_damage, center)
	var world := get_parent() as Node2D
	if world == null:
		return
	if not _themed:
		_spore_cloud(world, center)
		return
	var blast := Blast.new()
	blast.radius = blast_radius
	blast.position = world.to_local(center)  # before add_child
	world.add_child.call_deferred(blast)


## The puffball's burst: its spore cloud, blown up (whole pixels) to about
## the blast's size, puffing out then fading.
func _spore_cloud(world: Node2D, center: Vector2) -> void:
	var cloud := Sprite2D.new()
	cloud.texture = CLOUD_FRAMES[0]
	cloud.z_index = 20
	var size := float(CLOUD_FRAMES[1].get_width())
	cloud.scale = Vector2.ONE * maxf(roundf(blast_radius * 2.0 / size), 1.0)
	cloud.position = world.to_local(center)  # before add_child
	cloud.add_to_group("deployables")  # Cleared with the rest when the wave ends.
	world.add_child.call_deferred(cloud)
	# (The tree's tween, bound to the cloud: it isn't in the tree yet.)
	var tween := get_tree().create_tween().bind_node(cloud)
	tween.tween_interval(CLOUD_BURST)
	tween.tween_callback(cloud.set.bind("texture", CLOUD_FRAMES[1]))
	tween.tween_property(cloud, "modulate:a", 0.0, CLOUD_FADE)
	tween.tween_callback(cloud.queue_free)


func net_state() -> int:
	return 1 if _fuse >= 0.0 else 0


func mirror_state(state: int) -> void:
	if state == 1 and _fuse < 0.0:
		_fuse = FUSE_TIME
		queue_redraw()


func _process(delta: float) -> void:
	if is_mirror and _fuse >= 0.0:
		_fuse = maxf(_fuse - delta, 0.0)
	if _sprite == null:
		return
	# (Round, so it never turns.)
	var tint := elite_color if is_elite else Color.WHITE
	if _fuse < 0.0:
		_sprite.self_modulate = tint
		_sprite.scale = _sprite_scale
		if not _themed:
			_sprite.texture = LOOK
		return
	# Flashes (red, or between the puffball's red frames) faster and swells
	# as the fuse burns down.
	_blink += delta
	var lit := 1.0 - clampf(_fuse / FUSE_TIME, 0.0, 1.0)
	var flash := lerpf(0.12, 0.04, lit)
	var on := fmod(_blink, flash * 2.0) < flash
	if _themed:
		_sprite.self_modulate = FUSE_TINT if on else tint
	else:
		_sprite.texture = FUSE_FRAMES[0] if on else FUSE_FRAMES[1]
	_sprite.scale = _sprite_scale * (1.0 + 0.3 * lit)


## While the fuse burns: how far the blast will reach.
func _draw() -> void:
	if _fuse < 0.0:
		return
	var r := blast_radius / maxf(absf(scale.x), 0.01)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, WARNING_COLOR, 1.0)
