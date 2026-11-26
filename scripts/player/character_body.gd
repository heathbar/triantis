class_name Player
extends CharacterBody2D
## A player. `device` is the joypad id it listens to, or Global.KEYBOARD.
##
## The keyboard player's keys and mouse buttons are InputMap actions (set up
## in Global._setup_controller_ui_input): "fire", "melee", "use_equipment",
## "drop" and the keypad's "code_a" / "code_b" / "code_x" / "code_y".
## Controllers use their sticks, triggers and face buttons directly.

## Health (in half hearts) went up or down.
signal health_changed(health: int)
signal died(hit_position: Vector2)
signal points_changed(points: int)
signal resources_changed(resources: int)
## Brought back after being knocked out (between waves).
signal revived
## An attribute changed (see change_attribute).
signal attributes_changed(attributes: Dictionary)
## This player just fired `shot` (already in the world). A gun with several
## pellets fires once per pellet.
signal shot_fired(shot: Node)
## The player swung their melee weapon.
signal melee_swung
## The player swapped guns (see equip_gun).
signal gun_changed(gun: Dictionary)
## The player swapped melee weapons (see equip_melee).
signal melee_changed(weapon: Dictionary)
## The player's equipment changed (see equip_equipment); {} = none.
signal equipment_changed(equipment: Dictionary)
## The player used their equipment; `deployed` is what it put in the world.
signal equipment_used(deployed: Node)
## Something (a Healing Bubble) started or stopped healing this player.
signal healing_changed(healing: bool)

const SPEED = 100
const STICK_DEADZONE = 0.2
## How far the right trigger must be pulled (0..1) to swing the melee weapon.
const MELEE_TRIGGER_THRESHOLD = 0.5
## How far the left trigger must be pulled (0..1) to use the equipment, and
## below what it counts as let go.
const EQUIPMENT_TRIGGER_THRESHOLD := 0.5
const EQUIPMENT_TRIGGER_RELEASE := 0.3
## Keypad codes (the Vault): which action gives which face button.
const CODE_ACTIONS := {&"code_a": "A", &"code_b": "B", &"code_x": "X", &"code_y": "Y"}
## Seconds a dash keeps the player safe after it ends.
const DASH_GRACE := 0.15

## Health, in half hearts, before the class is applied. Touching an enemy
## costs its contact_damage (half a heart for most; a full heart for
## Brutes, Chargers and elites).
## (The real cap is max_health: the "lives" attribute, in hearts, x2.)
const MAX_HEALTH := CharacterClasses.LIVES_DEFAULT * CharacterClasses.HALVES_PER_HEART
## Seconds of invulnerability after a hit (or a hit armor ignored), so a
## touching enemy doesn't drain health, or reroll the armor chance, every
## physics frame.
const HIT_COOLDOWN := 1.0
const FLASH_COLOR := Color(1, 0, 0)
## Flash when armor ignores a hit.
const BLOCK_FLASH_COLOR := Color(0.75, 0.85, 1.0)
## Flash when a heart is healed back.
const HEAL_FLASH_COLOR := Color(0.45, 1.0, 0.55)
const FLASH_HOLD := 0.1
## Played when the player loses health (one at random) and when armor
## deflects a hit (the white flash), at these volumes (0-1, of the Effects
## volume).
const HURT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/player/hurt-1.ogg"),
	preload("res://assets/player/hurt-2.ogg"),
	preload("res://assets/player/hurt-3.ogg"),
	preload("res://assets/player/hurt-4.ogg"),
]
const HURT_VOLUME := 0.5
const DODGE_SOUND := preload("res://assets/player/dodge.ogg")
const DODGE_VOLUME := 1.0
const FLASH_FADE := 0.2
const DeathMarker := preload("res://scripts/death_marker.gd")
const Projectile := preload("res://scripts/projectile.gd")
const CharacterClasses := preload("res://scripts/character_classes.gd")
const Guns := preload("res://scripts/guns.gd")
const Melee := preload("res://scripts/melee.gd")
const MeleeSwing := preload("res://scripts/melee_swing.gd")
const Equipment := preload("res://scripts/equipment.gd")
const Items := preload("res://scripts/items.gd")

## How far in front of the player's centre projectiles appear.
const MUZZLE_DISTANCE := 17.0
## Melee swing sounds, one picked at random per swing: QUICK ones for swings
## at least every QUICK_SWING_INTERVAL seconds (knife, machete, chainsaw, or
## any weapon sped up that far by tier, tune-ups and fire rate), SLOW ones
## for heavier swings (wrench, katana, spiked bat, sledgehammer).
const QUICK_SWING_SOUNDS: Array[AudioStream] = [
	preload("res://assets/weapons/melee/melee-whoosh-01.ogg"),
	preload("res://assets/weapons/melee/melee-whoosh-02.ogg"),
	preload("res://assets/weapons/melee/melee-whoosh-03.ogg"),
	preload("res://assets/weapons/melee/melee-whoosh-04.ogg"),
	preload("res://assets/weapons/melee/melee-whoosh-05.ogg"),
]
const SLOW_SWING_SOUNDS: Array[AudioStream] = [
	preload("res://assets/weapons/melee/melee-whoosh-06.ogg"),
	preload("res://assets/weapons/melee/melee-whoosh-07.ogg"),
	preload("res://assets/weapons/melee/melee-whoosh-08.ogg"),
	preload("res://assets/weapons/melee/melee-whoosh-09.ogg"),
	preload("res://assets/weapons/melee/melee-whoosh-10.ogg"),
]
const QUICK_SWING_INTERVAL := 0.55
## Swing sounds play at this fraction of the Effects volume (like gun shots,
## player_gun.gd SOUND_VOLUME).
const SWING_VOLUME := 0.2
## Overlapping swing sounds allowed (a chainsaw swings every 0.12s).
const SWING_POLYPHONY := 3
## Speed (x normal) while carrying something (a Hot Potato).
const CARRY_SPEED := 0.55
## Seconds a gun's recoil push (Guns "recoil") takes to fade out after a shot.
const RECOIL_FADE := 0.2
## Guns that overheat (Guns "overheat"): seconds for a full heat bar to drain
## once the trigger is let go, and the default lockout once overheated.
const HEAT_COOL_TIME := 1.5
const HEAT_LOCKOUT := 2.0
## The heat bar under the player: size, and how far below their centre.
const HEAT_BAR_SIZE := Vector2(20, 2)
const HEAT_BAR_Y := 16.0
## The gun's tint at full heat.
const HOT_GUN_COLOR := Color(1.0, 0.35, 0.25)

## The game scene (scripts/game_base.gd). Set before the player enters the
## tree; null when the player is used outside a game.
var game: GameBase
var player_index := 0
## Name typed on character select ("" if none). See display_name().
var player_name := ""
var device := Global.KEYBOARD
var color := Color.WHITE
## The look picked on character select (index into scripts/player/player_skins.gd).
## Cosmetic only.
var skin := 0
## Current health in half hearts (2 = one heart).
var health := MAX_HEALTH
## Score earned by this player (from eliminating enemies).
var points := 0
## Enemies this player has finished off.
var kills := 0
## Kills towards the next Vampire Fangs heal (see record_kill).
var _fang_kills := 0
## Resources this player holds. Every pickup gives each player their own copy.
var resources := 0
## World-space area the player's square must stay inside (set by game.gd from
## the grass background). An empty Rect2 means no limit.
var move_bounds := Rect2()

## Attribute id -> value, from the character's class. "lives" is a heart
## count; the rest are -100 .. +100.
## Set before the player enters the tree; change later with change_attribute().
## See scripts/character_classes.gd.
var attributes := {}
## The character's class id (scripts/character_classes.gd), e.g. "engineer".
var class_id := ""
## Id of the gun this player holds (scripts/guns.gd). Set before the player
## enters the tree; swap later with equip_gun().
var gun_id := ""
## The held gun's entry from Guns.LIST.
var gun: Dictionary = Guns.get_gun("")
## Tune-ups bought for the held gun (0 .. Guns.MAX_LEVEL); see tune_gun().
var gun_level := 0
## Id of the melee weapon this player holds (scripts/melee.gd). Set before the
## player enters the tree; swap later with equip_melee().
var melee_id := ""
## The held melee weapon's entry from Melee.LIST.
var melee: Dictionary = Melee.get_weapon("")
## Tune-ups bought for the held melee weapon (0 .. Melee.MAX_LEVEL); see
## tune_melee().
var melee_level := 0
## Id of the equipment this player holds (scripts/equipment.gd), "" for none.
## Set before the player enters the tree; swap later with equip_equipment().
var equipment_id := ""
## The held equipment's entry from Equipment.LIST, or {} for none.
var equipment: Dictionary = {}
## Seconds until the equipment can be used again (0 = ready).
var equipment_cooldown := 0.0
## The wave's enemy health multiplier (in the shop: the next wave's). Some
## equipment stats grow with it (Equipment.WAVE_SCALING). Set by game.gd.
var wave_enemy_health := 1.0
## Retunes this player's equipment (see Equipment.stats for the format);
## {} = as listed. Braid sets it (BraidTuning.EQUIPMENT_TUNING).
var equipment_tuning := {}
## True when this player's gun and melee weapon can't be changed: the shop
## never offers them weapons (Braid mode, scripts/braid/braid_game.gd).
var weapons_locked := false
## Braid Class Mods picked so far: {branch id: stage reached (1..3)}
## (scripts/braid/braid_class_mod.gd).
var class_mod_picks := {}
## The full length of the current cooldown (for the HUD's pie chart).
var equipment_cooldown_total := 0.0

# Effective stats, rebuilt by _recalculate_stats() from the attributes.
# Don't set directly; change attributes instead.
var max_health := MAX_HEALTH
var move_speed := float(SPEED)
var fire_interval := 0.5
## Damage per projectile; a gun can fire several (shot_pellets) at once.
var damage := Projectile.DAMAGE
var shot_lifetime := Projectile.LIFETIME
## How far a shot flies, in pixels.
var shot_range := Projectile.LIFETIME * Projectile.SPEED
var shot_pellets := 1
var shot_spread := 0.0  # radians
var shot_speed := Projectile.SPEED
var shot_size := Projectile.SIZE
## The held gun's shots carry leftover damage through kills (Guns "overkill").
var shot_overkill := false
## Pixels each projectile shoves the enemy it hits.
var shot_knockback := 0.0
## Recoil push per shot (pixels/second) and seconds of fire to overheat
## (0 = never), with the lockout once overheated; see Guns.
var shot_recoil := 0.0
var overheat_time := 0.0
var overheat_lockout := HEAT_LOCKOUT
## The gun's heat, 0..1 (only guns that overheat), and whether it overheated
## and is locked until it cools to 0.
var heat := 0.0
var overheated := false
var hit_cooldown := HIT_COOLDOWN
## Chance (0..1) that an enemy hit is ignored, from the armor attribute.
var block_chance := CharacterClasses.BLOCK_CHANCE_AVERAGE
## Melee swing: damage per enemy hit, seconds between swings, reach past the
## edge of the player's square (pixels) and arc (radians).
var melee_damage := 1
var melee_interval := 0.5
var melee_range := 0.0
var melee_arc := 0.0
var melee_knockback := 0.0
## Resources gained per pickup (fractions carry over between pickups).
var harvest_rate := 1.0

var _harvest_carry := 0.0
## Temporary attribute bonuses (an Adrenaline Shot): source instance id ->
## {attribute id -> change}. They add to `attributes` in the effective stats
## only; see add_boost().
var _boosts := {}
## Ids of shop items bought, in order (scripts/items.gd).
var items: Array[String] = []
## Item ids saved in the shop for the next wave (scripts/items.gd).
var banked_items: Array[String] = []
## Banked item id -> the waves-done its price was locked at when it was first
## banked, so a banked item doesn't get dearer from wave to wave (see shop.gd).
var banked_price_waves := {}

var _hit_cooldown := 0.0
var _fire_cooldown := 0.0
## The melee swing in progress (freed when it ends); see melee_busy().
var _active_swing: Node
var _melee_cooldown := 0.0
## Players for the QUICK_SWING_SOUNDS and SLOW_SWING_SOUNDS (each picks one
## at random per play, so overlapping swings don't cut each other off).
var _quick_swing_sound: AudioStreamPlayer
var _slow_swing_sound: AudioStreamPlayer
## Physics layers while up (a knocked-out player is on none).
var _live_collision_layer := PhysicsLayers.PLAYERS
## True while the left trigger is held (see _poll_equipment_trigger).
var _equipment_trigger_down := false
## The current recoil push (fades over RECOIL_FADE).
var _recoil_velocity := Vector2.ZERO
## Draws the heat bar (guns that overheat).
var _heat_bar: Node2D
## Which way the next swing sweeps; flips every swing.
var _swing_clockwise := true
var _death_marker: Node2D
## Instance ids of whatever is healing this player right now.
var _healing_sources := {}
## A dash going on (start_dash): its velocity and seconds left.
var _dash_velocity := Vector2.ZERO
var _dash_left := 0.0
## Instance ids of whatever stops enemies hurting this player by touch (a
## Riot Shield, scripts/equipment/riot_shield.gd). Bosses still do.
var _contact_shields := {}
## Optional: func(amount, hit_position) -> bool. An enemy attack it returns
## true for is blocked (like armor does). Unset in the arena game; Braid
## Class Mods use it.
var hit_filter := Callable()
## Objective waves: what this player is carrying (a Hot Potato,
## scripts/objectives/hot_potato.gd), or null. Carrying slows them and stops
## them shooting, swinging and using equipment; B (Q on the keyboard) drops
## it, which calls its player_dropped(player).
var carrying: Node = null
## Boss waves: the keypad this player stands at (the Vault,
## scripts/bosses/vault.gd), or null. While set, the face buttons (I/J/K/L on
## the keyboard) go to it as code presses: keypad.code_press(player, button)
## with "A", "B", "X" or "Y". It also stops them using their equipment.
var keypad: Node = null
## A fixed gun this player is manning (Braid's mounted turrets,
## scripts/braid/braid_turret.gd), or null. While set they can't move, their
## own gun, melee and equipment stay idle, and each physics frame their aim
## (right stick, or the mouse while firing) goes to mount.mounted_aim(self,
## aim, delta). Set it with set_mount().
var mount: Node = null
## A dummy squad's stand-in player (scripts/net/dummy_squad.gd, set before it
## joins the tree): nothing hurts it, and walls and enemies don't stop it (so
## the Campaign's tide can always push it along).
var dummy := false

## The player's square: invisible now, but it still sets the size and its
## rotation is the facing direction.
@onready var body: ColorRect = $ColorRect
## The character art, palette-swapped to the player's colour.
@onready var sprite: Sprite2D = $Sprite
## The gun, drawn over the character and pointing along the aim.
@onready var gun_sprite: Sprite2D = $Gun
@onready var hurtbox: Area2D = $Hurtbox


func _ready() -> void:
	# Top-down: no floors, so a player never "stands on" an enemy (or another
	# player) and gets carried along by it.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("players")
	if dummy:
		collision_mask = 0
	_quick_swing_sound = _swing_player(QUICK_SWING_SOUNDS)
	_slow_swing_sound = _swing_player(SLOW_SWING_SOUNDS)
	# Unlike "players", knocked-out players stay in this one.
	add_to_group("all_players")
	if attributes.is_empty():
		attributes = CharacterClasses.starting_attributes("")
	gun = Guns.get_gun(gun_id)
	gun_id = gun["id"]
	gun_sprite.show_gun(gun["type"])
	melee = Melee.get_weapon(melee_id)
	melee_id = melee["id"]
	equipment = Equipment.find(equipment_id)
	_recalculate_stats()
	health = max_health
	body.color = color
	sprite.armor_color = color
	sprite.skin = skin
	# Rotate the square around the player's origin (not the rect's top-left).
	body.pivot_offset = -body.position
	_heat_bar = Node2D.new()
	_heat_bar.z_index = 1
	_heat_bar.draw.connect(_draw_heat_bar)
	add_child(_heat_bar)


func is_dead() -> bool:
	return health <= 0


func _physics_process(delta: float) -> void:
	if is_dead():
		return

	_hit_cooldown = maxf(_hit_cooldown - delta, 0.0)
	if _hit_cooldown == 0.0:
		var enemy := _touching_enemy()
		if enemy:
			# The hit lands where the two squares meet.
			hurt_by(_contact_damage(enemy), global_position.lerp(enemy.global_position, 0.5))
			if is_dead():
				return

	var mounted := is_mounted()
	var direction := Vector2.ZERO if mounted else _read_direction()
	if direction:
		velocity = direction * move_speed * (CARRY_SPEED if is_carrying() else 1.0)
	else:
		velocity = Vector2.ZERO  # No sliding: players stop dead.
	if _dash_left > 0.0:
		velocity = _dash_velocity
		_dash_left -= delta
		if _dash_left <= 0.0:
			_end_dash()
	velocity += _recoil_velocity

	var before_move := global_position
	move_and_slide()
	stay_in_bounds()
	_stay_on_screen(before_move)
	velocity -= _recoil_velocity
	if shot_recoil > 0.0:
		_recoil_velocity = _recoil_velocity.move_toward(Vector2.ZERO,
			shot_recoil / RECOIL_FADE * delta)
	else:
		_recoil_velocity = Vector2.ZERO

	# Cooldowns carry their overshoot into the next shot (see _shoot), so a
	# gun fires at its stated rate, not rounded up to whole physics frames.
	# Not while idle: the trigger can't bank shots.
	_fire_cooldown -= delta
	var aim := _read_aim()
	# Melee and shooting don't mix: the gun is quiet while the melee button
	# is held or a swing is still going (aiming still turns the player, so
	# swings go where they aim).
	var firing := aim and not is_carrying() and not overheated and not mounted and not melee_busy()
	if mounted:
		mount.mounted_aim(self, aim, delta)
	if not firing:
		_fire_cooldown = maxf(_fire_cooldown, 0.0)
	if aim:
		body.rotation = aim.angle()
		sprite.face(body.rotation)
		gun_sprite.aim(body.rotation)
		if _fire_cooldown <= 0.0 and firing:
			_shoot(aim)
	elif direction:
		# Not shooting: face the way they're walking.
		body.rotation = direction.angle()
		sprite.face(body.rotation)
		gun_sprite.aim(body.rotation)

	_melee_cooldown -= delta
	var swinging := _melee_held() and not is_carrying() and not mounted
	if not swinging:
		_melee_cooldown = maxf(_melee_cooldown, 0.0)
	elif _melee_cooldown <= 0.0:
		_try_melee()

	equipment_cooldown = maxf(equipment_cooldown - delta, 0.0)
	_poll_equipment_trigger()
	_update_heat(delta, firing)


## Guns that overheat: cools the gun while it isn't firing (slower once it
## has overheated, see overheat_lockout) and updates the heat bar and tint.
## Heat itself is added per shot, in _shoot().
func _update_heat(delta: float, firing: bool) -> void:
	var was := heat
	if overheat_time <= 0.0:
		heat = 0.0
		overheated = false
	elif overheated:
		heat = maxf(heat - delta / maxf(overheat_lockout, 0.01), 0.0)
		overheated = heat > 0.0
	elif not firing:
		heat = maxf(heat - delta / HEAT_COOL_TIME, 0.0)
	if heat != was or overheated:
		_heat_bar.queue_redraw()
		gun_sprite.self_modulate = Color.WHITE.lerp(HOT_GUN_COLOR, heat)


func _draw_heat_bar() -> void:
	if heat <= 0.0:
		return
	var origin := Vector2(-HEAT_BAR_SIZE.x / 2.0, HEAT_BAR_Y)
	_heat_bar.draw_rect(Rect2(origin - Vector2.ONE, HEAT_BAR_SIZE + Vector2(2, 2)),
		Color(0, 0, 0, 0.6))
	var fill := Color(1.0, 0.85, 0.2).lerp(Color(1.0, 0.2, 0.1), heat)
	if overheated:
		# Blinks while locked out.
		fill = Color(1.0, 0.2, 0.1) if fmod(Time.get_ticks_msec() / 1000.0, 0.3) < 0.15 \
			else Color(1.0, 0.9, 0.8)
	_heat_bar.draw_rect(Rect2(origin, Vector2(HEAT_BAR_SIZE.x * heat, HEAT_BAR_SIZE.y)), fill)


## "use_equipment" (F) uses the keyboard player's equipment (controllers use
## the left trigger: see _poll_equipment_trigger). "drop" (Q, or B on a
## controller) drops what they carry.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if is_carrying() and _is_my_press(event, &"drop"):
		carrying.player_dropped(self)
		get_viewport().set_input_as_handled()
		return
	if keypad != null and is_instance_valid(keypad) and not is_dead():
		var button := _code_button(event)
		if not button.is_empty():
			keypad.code_press(self, button)
			get_viewport().set_input_as_handled()
			return
	if device == Global.KEYBOARD and _is_my_press(event, &"use_equipment") and use_equipment():
		get_viewport().set_input_as_handled()


## True if `event` presses `action` on this player's own input: the keyboard
## and mouse for the keyboard player (and a pressed InputEventAction, as tests
## send), their own controller otherwise.
func _is_my_press(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action):
		return false
	if device == Global.KEYBOARD:
		return event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventAction
	return event is InputEventJoypadButton and event.device == device


## Controllers: pulling the left trigger uses the equipment, once per pull
## (it has to come back past EQUIPMENT_TRIGGER_RELEASE before it fires again).
func _poll_equipment_trigger() -> void:
	if device == Global.KEYBOARD:
		return
	var pull := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
	if _equipment_trigger_down:
		_equipment_trigger_down = pull > EQUIPMENT_TRIGGER_RELEASE
	elif pull > EQUIPMENT_TRIGGER_THRESHOLD:
		_equipment_trigger_down = true
		use_equipment()


## Keypad codes: the face button `event` presses on this player's controller
## ("A", "B", "X" or "Y"), or "". The keyboard player's keys are laid out the
## same way (CODE_ACTIONS): I (Y) on top, J (X) left, L (B) right, K (A) below.
func _code_button(event: InputEvent) -> String:
	for action: StringName in CODE_ACTIONS:
		if _is_my_press(event, action):
			return CODE_ACTIONS[action]
	return ""


## True while this player holds their interact button: X on their
## controller, E on the keyboard (Braid's airstrike pads and turrets).
func interact_held() -> bool:
	if device == Global.KEYBOARD:
		return Input.is_action_pressed(&"interact")
	return Input.is_joy_button_pressed(device, JOY_BUTTON_X)


## True while this player holds their "drop" button: B on their controller,
## Q on the keyboard (also how they get off a Braid turret).
func drop_held() -> bool:
	if device == Global.KEYBOARD:
		return Input.is_action_pressed(&"drop")
	return Input.is_joy_button_pressed(device, JOY_BUTTON_B)


## Mans fixed gun `node` (null to let go): see `mount`. Their own gun is
## hidden while they're on it.
func set_mount(node: Node) -> void:
	mount = node
	gun_sprite.visible = node == null
	if node != null:
		_recoil_velocity = Vector2.ZERO


func is_mounted() -> bool:
	if mount != null and not is_instance_valid(mount):
		set_mount(null)
	return mount != null


## True while this player is pushing to move.
func wants_to_move() -> bool:
	return _read_direction() != Vector2.ZERO


func is_carrying() -> bool:
	return carrying != null and is_instance_valid(carrying)


func has_equipment() -> bool:
	return not equipment.is_empty()


## Swaps the held equipment for another (scripts/equipment.gd; "" = none).
## Anything the old one put in the world stays until it runs out.
func equip_equipment(id: String) -> void:
	equipment = Equipment.find(id)
	equipment_id = equipment.get("id", "")
	equipment_cooldown = 0.0
	equipment_changed.emit(equipment)


## The held equipment's numbers in this player's hands (Equipment.stats()),
## or {} with none.
func equipment_stats() -> Dictionary:
	if equipment.is_empty():
		return {}
	return Equipment.stats(equipment, get_attribute("engineering"), wave_enemy_health,
		equipment_tuning)


## Makes the equipment usable right away (at the start of every wave).
func recharge_equipment() -> void:
	equipment_cooldown = 0.0


## Uses the held equipment, if it's charged and the player is up: puts its
## deployable down where they stand and starts the cooldown. Anything already
## out stays (equipment is never used up). Returns true if it was used.
func use_equipment() -> bool:
	if equipment.is_empty() or is_dead() or not is_inside_tree() \
			or is_carrying() or (keypad != null and is_instance_valid(keypad)) or is_mounted():
		return false
	if _pack_up_deployable():
		return true
	if equipment_cooldown > 0.0:
		return false
	var stats := equipment_stats()
	var deployed := Equipment.create(equipment, self, stats)
	deployed.position = global_position  # before add_child
	var world := get_parent()
	world.add_child(deployed)
	# Drawn under the players (and the enemies, which come later in the tree).
	world.move_child(deployed, 0)
	equipment_cooldown = stats["cooldown"]
	equipment_cooldown_total = equipment_cooldown
	equipment_used.emit(deployed)
	return true


## Packs away the nearest of our own deployables within reach that can be
## picked up (Deployable.can_pick_up), taking what's left of its time off
## the cooldown. False if there's none.
func _pack_up_deployable() -> bool:
	var best: Deployable = null
	var best_dist := INF
	for deployed in get_tree().get_nodes_in_group("deployables"):
		if not deployed is Deployable or deployed.owner_player != self \
				or not deployed.owner_can_pack_up():
			continue
		var d := global_position.distance_to(deployed.global_position)
		if d < best_dist:
			best_dist = d
			best = deployed
	if best == null:
		return false
	var refund: float = best.pick_up() * equipment_cooldown_total
	equipment_cooldown = maxf(equipment_cooldown - refund, 0.0)
	return true


## Moves the player at `dash_velocity` for `seconds`, whatever the stick says
## (a Dash Pack, scripts/equipment/dash_pack.gd): straight through enemies,
## and enemies can't hurt them until DASH_GRACE after it ends.
func start_dash(dash_velocity: Vector2, seconds: float) -> void:
	_dash_velocity = dash_velocity
	_dash_left = seconds
	_hit_cooldown = maxf(_hit_cooldown, seconds + DASH_GRACE)
	collision_mask &= ~PhysicsLayers.ENEMIES


func is_dashing() -> bool:
	return _dash_left > 0.0


func _end_dash() -> void:
	_dash_left = 0.0
	velocity = _dash_velocity.normalized() * move_speed
	if not dummy:
		collision_mask |= PhysicsLayers.ENEMIES


## Something (`source`, a Riot Shield) starts or stops keeping enemies from
## hurting this player by touch.
func set_contact_shield(source: Object, on: bool) -> void:
	if on:
		_contact_shields[source.get_instance_id()] = true
	else:
		_contact_shields.erase(source.get_instance_id())


## A healing source (`source`, e.g. a Healing Bubble) starts or stops healing
## this player. healing_changed fires when that changes whether anything is.
func set_healing(source: Object, healing: bool) -> void:
	var was := is_healing()
	if healing:
		_healing_sources[source.get_instance_id()] = true
	else:
		_healing_sources.erase(source.get_instance_id())
	if is_healing() != was:
		healing_changed.emit(is_healing())


func is_healing() -> bool:
	return not _healing_sources.is_empty()


## Gives back `amount` half hearts (not past max_health) to a player who's up.
func heal(amount: int = 1) -> void:
	if is_dead() or health >= max_health:
		return
	health = mini(health + amount, max_health)
	health_changed.emit(health)
	_flash(HEAL_FLASH_COLOR)


## Keeps the player's whole square inside move_bounds (bosses call this after
## shoving a player).
func stay_in_bounds() -> void:
	if not move_bounds.has_area():
		return
	# Keep the whole square (not just its centre) inside the bounds.
	var lo := move_bounds.position - body.position
	var hi := move_bounds.end - (body.position + body.size)
	var clamped := global_position.clamp(lo, hi)
	if clamped.x != global_position.x:
		velocity.x = 0.0
	if clamped.y != global_position.y:
		velocity.y = 0.0
	global_position = clamped


## Keeps this player close enough to the other living players that the
## camera (game.gd) can show them all: no further than max_player_spread()
## from the furthest of them on each axis. A player already further out (put
## there, or thrown) isn't pulled in, but can't go further than `from` (where
## they were before this move).
func _stay_on_screen(from: Vector2) -> void:
	if game == null:
		return
	var others := Rect2()
	var any := false
	for other: Node2D in get_tree().get_nodes_in_group("players"):
		if other == self:
			continue
		if any:
			others = others.expand(other.global_position)
		else:
			others = Rect2(other.global_position, Vector2.ZERO)
			any = true
	if not any:
		return
	var spread := game.max_player_spread()
	# If the others are already spread further than that, stay within them.
	var lo := (others.end - spread).min(others.position).min(from)
	var hi := (others.position + spread).max(others.end).max(from)
	var clamped := global_position.clamp(lo, hi)
	if clamped.x != global_position.x:
		velocity.x = 0.0
	if clamped.y != global_position.y:
		velocity.y = 0.0
	global_position = clamped


## Returns a unit vector to face/shoot along, or Vector2.ZERO when not shooting.
## Keyboard players shoot toward the mouse while it's held.
func _read_aim() -> Vector2:
	if device == Global.KEYBOARD:
		# The world is drawn in the game's pixel-art view (game_base.gd), so ask it.
		var mouse := game.world_mouse_position() if game else get_global_mouse_position()
		var to_mouse := mouse - global_position
		if Input.is_action_pressed(&"fire") and to_mouse.length() > 1.0:
			return to_mouse.normalized()
		return Vector2.ZERO

	var stick := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	if stick.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return stick.normalized()


func _shoot(aim: Vector2) -> void:
	# At most one shot per physics frame, however fast the gun.
	_fire_cooldown = maxf(_fire_cooldown + fire_interval, 0.0)
	if shot_recoil > 0.0:
		_recoil_velocity = -aim * shot_recoil
	if overheat_time > 0.0:
		# Firing non-stop for overheat_time fills the bar, at any fire rate.
		heat = minf(heat + fire_interval / overheat_time, 1.0)
		overheated = heat >= 0.999  # float sums fall just short of 1
	gun_sprite.play_shot()
	for i in shot_pellets:
		# Pellets fan out evenly across the spread; a lone shot strays randomly
		# within it.
		var angle := 0.0
		if shot_pellets > 1:
			angle = lerpf(-shot_spread / 2.0, shot_spread / 2.0, i / float(shot_pellets - 1))
		elif shot_spread > 0.0:
			angle = randf_range(-shot_spread / 2.0, shot_spread / 2.0)
		var direction := aim.rotated(angle)
		var shot := Projectile.new()
		shot.direction = direction
		shot.damage = damage
		shot.lifetime = shot_lifetime
		shot.speed = shot_speed
		shot.size = shot_size
		shot.knockback = shot_knockback
		shot.overkill = shot_overkill
		shot.shooter = self
		shot.position = global_position + direction * MUZZLE_DISTANCE  # before add_child
		get_parent().add_child(shot)
		shot_fired.emit(shot)


## True while this player holds their melee button: the right trigger on
## their controller (the "melee" action, Space or the right mouse button, for
## the keyboard player). Holding it swings again each time the weapon is
## ready, so tapping can't swing any faster.
func _melee_held() -> bool:
	if device == Global.KEYBOARD:
		return Input.is_action_pressed(&"melee")
	return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > MELEE_TRIGGER_THRESHOLD


## True while the melee button is held (when a swing could happen) or a
## swing is still sweeping: no shooting then.
func melee_busy() -> bool:
	if is_instance_valid(_active_swing):
		return true
	return _melee_held() and not is_carrying() and not is_mounted() and not is_dead()


## Swings the melee weapon where the player faces. The swing hits enemies
## as the weapon passes through them (scripts/melee_swing.gd), within the
## weapon's arc (centred on where they face) and reach. A swing that hits
## nothing still uses up the weapon's interval.
func _try_melee() -> void:
	var player_half := (body.size.x + body.size.y) / 4.0
	_melee_cooldown = maxf(_melee_cooldown + melee_interval, 0.0)
	melee_swung.emit()
	_play_swing_sound()
	var swing := MeleeSwing.new()
	swing.reach = player_half + melee_range
	swing.inner = player_half
	swing.arc = melee_arc
	swing.interval = melee_interval
	swing.weapon_type = melee.get("type", "")
	swing.clockwise = _swing_clockwise
	_swing_clockwise = not _swing_clockwise
	swing.rotation = body.rotation
	swing.attacker = self
	swing.damage = melee_damage
	swing.knockback = melee_knockback
	add_child(swing)
	_active_swing = swing


## A random whoosh, quick or slow to match how fast this player swings.
func _play_swing_sound() -> void:
	if melee_interval < QUICK_SWING_INTERVAL:
		_quick_swing_sound.play()
	else:
		_slow_swing_sound.play()


## A sound player (child of this player) that plays one of `sounds` at
## random each time.
func _swing_player(sounds: Array[AudioStream]) -> AudioStreamPlayer:
	var randomizer := AudioStreamRandomizer.new()
	randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	randomizer.random_pitch = 1.0
	for sound in sounds:
		randomizer.add_stream(-1, sound)
	var sound_player := AudioStreamPlayer.new()
	sound_player.stream = randomizer
	sound_player.bus = Global.SFX_BUS
	sound_player.volume_linear = SWING_VOLUME
	sound_player.max_polyphony = SWING_POLYPHONY
	add_child(sound_player)
	return sound_player


## Swaps the held melee weapon for another (scripts/melee.gd); the old one is
## gone, and so are its tune-ups.
func equip_melee(id: String) -> void:
	melee = Melee.get_weapon(id)
	melee_id = melee["id"]
	melee_level = 0
	_recalculate_stats()
	melee_changed.emit(melee)


## One more tune-up for the held melee weapon (see Melee UPGRADE KITS). No
## charge here.
func tune_melee() -> void:
	melee_level = mini(melee_level + 1, Melee.MAX_LEVEL)
	_recalculate_stats()
	melee_changed.emit(melee)


## The held melee weapon's name, with its tune-up level.
func melee_name() -> String:
	return Melee.display_name(melee, melee_level)


## What `weapon` (from Melee.LIST), tuned up `level` times, would do in this
## player's hands: {damage, interval, range, arc (radians), knockback}. Melee
## damage scales the damage, fire rate scales the swing speed and the
## knockback attribute scales knockback; reach isn't affected by the range
## attribute (only by tune-ups). Class perks (CharacterClasses "perks") then
## change the swing interval and reach.
func melee_stats(weapon: Dictionary, level: int = 0) -> Dictionary:
	return {
		"damage": maxi(Melee.upgraded_damage(weapon["damage"] * _stat_mult("melee_damage"), level), 1),
		"interval": weapon["interval"] / (_stat_mult("fire_rate") * Melee.level_mult("fire_rate", level))
			* CharacterClasses.perk(class_id, "melee_interval_mult", 1.0),
		"range": float(weapon["range"]) * Melee.level_mult("range", level)
			+ CharacterClasses.perk(class_id, "melee_reach_bonus", 0.0),
		"arc": deg_to_rad(weapon["arc"]),
		"knockback": weapon.get("knockback", 0) * _stat_mult("knockback"),
	}


## Swaps the held gun for another (scripts/guns.gd); the old one is gone,
## and so are its tune-ups.
func equip_gun(id: String) -> void:
	gun = Guns.get_gun(id)
	gun_id = gun["id"]
	gun_level = 0
	_recalculate_stats()
	heat = 0.0
	overheated = false
	if is_node_ready():
		gun_sprite.self_modulate = Color.WHITE
		gun_sprite.show_gun(gun["type"])
		_heat_bar.queue_redraw()
	gun_changed.emit(gun)


## One more tune-up for the held gun (see Guns UPGRADE KITS). No charge here.
func tune_gun() -> void:
	gun_level = mini(gun_level + 1, Guns.MAX_LEVEL)
	_recalculate_stats()
	gun_changed.emit(gun)


## The held gun's name, with its tune-up level.
func gun_name() -> String:
	return Guns.display_name(gun, gun_level)


## What `of_gun`, tuned up `level` times, would do in this player's hands,
## after their range, ranged damage, fire rate and knockback attributes:
## {damage, pellets, interval, range, lifetime, speed, size, spread
## (radians), knockback (per pellet), recoil, overheat, lockout, overkill
## (see Guns)}.
func gun_stats(of_gun: Dictionary, level: int = 0) -> Dictionary:
	var speed: float = of_gun.get("speed", Projectile.SPEED)
	var range_px: float = of_gun["range"] * _stat_mult("range") * Guns.level_mult("range", level)
	return {
		"damage": maxi(Guns.upgraded_damage(of_gun["damage"] * _stat_mult("ranged_damage"), level), 1),
		"pellets": int(of_gun.get("pellets", 1)),
		"interval": of_gun["interval"] / (_stat_mult("fire_rate") * Guns.level_mult("fire_rate", level)),
		"range": range_px,
		"lifetime": range_px / speed,
		"speed": speed,
		"size": of_gun.get("size", Projectile.SIZE),
		"spread": deg_to_rad(of_gun.get("spread", 0.0)),
		"knockback": of_gun.get("knockback", 0) * _stat_mult("knockback"),
		"recoil": float(of_gun.get("recoil", 0.0)),
		"overheat": float(of_gun.get("overheat", 0.0)),
		"lockout": float(of_gun.get("lockout", HEAT_LOCKOUT)),
		"overkill": bool(of_gun.get("overkill", false)),
	}


## Every point this player earns is multiplied by this (the Campaign's
## modifiers raise it: scripts/braid/braid_modifiers.gd).
var score_multiplier := 1.0


func add_points(amount: int) -> void:
	points += roundi(amount * score_multiplier)
	points_changed.emit(points)


func record_kill(points_value: int) -> void:
	kills += 1
	add_points(points_value)
	# Vampire Fangs (Items): half a heart every Items.fang_kills() kills,
	# fewer the more pairs owned (wasted at full health or while knocked out).
	var fangs := Items.owned(self, "vampire_fangs")
	if fangs > 0:
		_fang_kills += 1
		if _fang_kills >= Items.fang_kills(fangs):
			_fang_kills = 0
			heal(1)


func add_resources(amount: int) -> void:
	resources += amount
	resources_changed.emit(resources)


## Collects a resource pickup worth `amount`, scaled by the harvesting attribute.
func harvest(amount: int) -> void:
	_harvest_carry += amount * harvest_rate
	var whole := int(_harvest_carry)
	_harvest_carry -= whole
	if whole > 0:
		add_resources(whole)


func spend_resources(amount: int) -> void:
	resources = maxi(resources - amount, 0)
	resources_changed.emit(resources)


func get_attribute(id: String) -> int:
	return attributes.get(id, CharacterClasses.default_value(id))


## Raises (or lowers, with a negative delta) an attribute, kept in its range
## (see CharacterClasses.clamp_attribute), and updates the stats that depend on it.
func change_attribute(id: String, delta: int) -> void:
	set_attribute(id, get_attribute(id) + delta)


func set_attribute(id: String, value: int) -> void:
	attributes[id] = CharacterClasses.clamp_attribute(id, value)
	_recalculate_stats()
	health_changed.emit(health)
	attributes_changed.emit(attributes)


## Rebuilds the effective stats from the attributes.
## (Engineering isn't cached here: it's read when equipment is used, see
## equipment_stats().)
func _recalculate_stats() -> void:
	var old_max := max_health
	max_health = get_attribute("lives") * CharacterClasses.HALVES_PER_HEART
	# Gaining hearts heals that much; losing them caps current health.
	if is_inside_tree() and not is_dead():
		health = clampi(health + maxi(max_health - old_max, 0), 0, max_health)

	move_speed = SPEED * _stat_mult("speed")
	hit_cooldown = CharacterClasses.perk(class_id, "hit_cooldown", HIT_COOLDOWN)
	var stats := gun_stats(gun, gun_level)
	damage = stats["damage"]
	fire_interval = stats["interval"]
	shot_range = stats["range"]
	shot_lifetime = stats["lifetime"]
	shot_pellets = stats["pellets"]
	shot_spread = stats["spread"]
	shot_speed = stats["speed"]
	shot_size = stats["size"]
	shot_knockback = stats["knockback"]
	shot_overkill = stats["overkill"]
	shot_recoil = stats["recoil"]
	overheat_time = stats["overheat"]
	overheat_lockout = stats["lockout"]
	var melee_now := melee_stats(melee, melee_level)
	melee_damage = melee_now["damage"]
	melee_interval = melee_now["interval"]
	melee_range = melee_now["range"]
	melee_arc = melee_now["arc"]
	melee_knockback = melee_now["knockback"]
	harvest_rate = _stat_mult("harvesting")
	block_chance = CharacterClasses.block_chance(boosted_attribute("armor"))


func _stat_mult(attribute_id: String) -> float:
	return CharacterClasses.stat_multiplier(boosted_attribute(attribute_id), attribute_id)


## The attribute with any temporary boosts on top (kept in its range). The
## effective stats use this; get_attribute() is the lasting value.
func boosted_attribute(id: String) -> int:
	var value := get_attribute(id)
	for effects: Dictionary in _boosts.values():
		value += int(effects.get(id, 0))
	return CharacterClasses.clamp_attribute(id, value)


## Adds temporary attribute changes from `source` (replacing any it already
## gave) until remove_boost(source). Not for "lives".
func add_boost(source: Object, effects: Dictionary) -> void:
	_boosts[source.get_instance_id()] = effects
	_recalculate_stats()


func remove_boost(source: Object) -> void:
	if _boosts.erase(source.get_instance_id()):
		_recalculate_stats()


func is_boosted() -> bool:
	return not _boosts.is_empty()


## The melee weapon is ready to swing again right away.
func reset_melee_cooldown() -> void:
	_melee_cooldown = 0.0


## Can't be hurt for at least the next `seconds`.
func extend_invulnerability(seconds: float) -> void:
	_hit_cooldown = maxf(_hit_cooldown, seconds)


## Refills every heart (between waves), reviving the player if knocked out.
func restore_all_lives() -> void:
	if is_dead():
		revive(max_health)
		return
	health = max_health
	health_changed.emit(health)


## Brings a knocked-out player back with `with_health` half hearts.
func revive(with_health: int = CharacterClasses.HALVES_PER_HEART) -> void:
	if not is_dead():
		return
	if is_dashing():
		_end_dash()  # Knocked out mid-dash: don't carry it on.
	health = clampi(with_health, 1, max_health)
	_hit_cooldown = hit_cooldown
	add_to_group("players")
	collision_layer = _live_collision_layer
	sprite.clear_flash()
	sprite.dimmed = false
	gun_sprite.set_dimmed(false)
	if is_instance_valid(_death_marker):
		_death_marker.queue_free()
	_death_marker = null
	health_changed.emit(health)
	revived.emit()


## Takes `amount` half hearts of damage (at least 1), then is briefly
## invulnerable.
func take_hit(amount: int = 1, hit_position: Vector2 = global_position) -> void:
	if is_dead() or dummy:
		return
	health = maxi(health - maxi(amount, 1), 0)
	_hit_cooldown = hit_cooldown
	health_changed.emit(health)
	_flash()
	Global.play_sfx(HURT_SOUNDS.pick_random(), HURT_VOLUME)
	if is_dead():
		_die(hit_position)


## An enemy attack (a touch, a blast) worth `amount` half hearts: ignored
## while still invulnerable from the last hit, and armor may block it.
func hurt_by(amount: int, hit_position: Vector2 = global_position) -> void:
	if is_dead() or dummy or _hit_cooldown > 0.0:
		return
	if hit_filter.is_valid() and hit_filter.call(amount, hit_position):
		_block_hit()
	elif randf() < block_chance:
		_block_hit()
	else:
		take_hit(amount, hit_position)


## Half hearts a touching enemy takes per hit (its contact_damage).
static func _contact_damage(enemy: Node) -> int:
	var amount: Variant = enemy.get("contact_damage")
	return int(amount) if amount != null else 1


## Armor ignored an enemy hit: no health lost, but the same invulnerability.
func _block_hit() -> void:
	_hit_cooldown = hit_cooldown
	_flash(BLOCK_FLASH_COLOR)
	Global.play_sfx(DODGE_SOUND, DODGE_VOLUME)


func _touching_enemy() -> Node2D:
	for other in hurtbox.get_overlapping_bodies():
		# Objective structures (nests) are shot like enemies but don't hurt.
		if not other.is_in_group("enemies") or other.is_in_group("objective_structures"):
			continue
		# Harmless for now (contact_damage 0: e.g. a Braid splitter's fresh
		# pieces), or held off by a Riot Shield (which bosses ignore).
		var amount: Variant = other.get("contact_damage")
		if amount != null and int(amount) <= 0:
			continue
		if not _contact_shields.is_empty() and other is CharacterBody2D:
			continue
		return other
	return null


func _flash(flash_color: Color = FLASH_COLOR) -> void:
	sprite.flash(flash_color, FLASH_HOLD, FLASH_FADE)


func _die(hit_position: Vector2) -> void:
	# Out of health: the character is frozen in place for the rest of the game
	# (_physics_process returns early once is_dead() is true).
	velocity = Vector2.ZERO
	remove_from_group("players")  # enemies stop chasing, camera stops tracking
	# Nothing bumps into a knocked-out player (they'd block a keypad, a doorway...).
	_live_collision_layer = collision_layer
	collision_layer = 0
	# Knocked-out players are drawn as a dim version of themselves.
	sprite.dimmed = true
	gun_sprite.set_dimmed(true)

	_death_marker = DeathMarker.new()
	_death_marker.color = color
	get_parent().add_child(_death_marker)
	# Centre the X on the knocked-out player (not where the hit landed).
	_death_marker.global_position = global_position

	died.emit(hit_position)


func _read_direction() -> Vector2:
	if device == Global.KEYBOARD:
		return Input.get_vector("left", "right", "up", "down")

	var stick := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	if stick.length() < STICK_DEADZONE:
		stick = Vector2.ZERO
	var dpad := Vector2(
		float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT))
			- float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT)),
		float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN))
			- float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP)))
	return (stick + dpad).limit_length(1.0)


## The player's name, or "P1".."P4" if they didn't enter one.
func display_name() -> String:
	return Global.player_label(player_index, player_name)
