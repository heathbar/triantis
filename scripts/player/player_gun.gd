extends Sprite2D
## The player's gun, drawn over the character art and pointing along the aim.
## Flipped when aiming left so it's never upside down. Used by the player
## scene (scenenodethings/player.tscn) and remote squad players
## (scripts/net/remote_player.gd).
##
## Each gun type (scripts/guns.gd TYPES) has its own image in
## assets/weapons/guns/, drawn at its own pixel size (no scaling), facing
## right with the grip at the left end.

const Guns := preload("res://scripts/guns.gd")

## Gun type id -> its image. Types missing here use DEFAULT_TYPE's.
const TEXTURES := {
	"pistol": preload("res://assets/weapons/guns/pistol.png"),
	"smg": preload("res://assets/weapons/guns/smg.png"),
	"rivet_gun": preload("res://assets/weapons/guns/rivet.png"),
	"revolver": preload("res://assets/weapons/guns/revolver.png"),
	"shotgun": preload("res://assets/weapons/guns/shotgun.png"),
	"hand_cannon": preload("res://assets/weapons/guns/hand_cannon.png"),
	"assault_rifle": preload("res://assets/weapons/guns/assault_riffle.png"),
	"sniper_rifle": preload("res://assets/weapons/guns/sniper.png"),
	"minigun": preload("res://assets/weapons/guns/minigun.png"),
}
const DEFAULT_TYPE := "pistol"
## The sound every gun makes when fired.
const SHOT_SOUND := preload("res://assets/weapons/guns/minigun.ogg")
## Overlapping shot sounds allowed at once (fast guns cut off the oldest).
const SOUND_POLYPHONY := 4
## Gun shots play at this fraction of the Effects volume (0.2 = a fifth as
## loud as the files).
const SOUND_VOLUME := 0.2
## How far along the aim the gun's back end (the grip) sits from the
## shoulder. Longer guns reach further out; shots still appear at
## character_body.gd's MUZZLE_DISTANCE.
const BACK := -3.0
## Where the gun pivots, relative to the player's centre (about chest height
## on the character art).
const SHOULDER := Vector2(0, 2)


var _sound := AudioStreamPlayer.new()


func _init() -> void:
	_sound.max_polyphony = SOUND_POLYPHONY
	_sound.bus = Global.SFX_BUS
	_sound.volume_linear = SOUND_VOLUME
	_sound.stream = SHOT_SOUND
	add_child(_sound)
	centered = false
	position = SHOULDER
	show_gun(DEFAULT_TYPE)
	aim(0.0)


## Shows gun type `type_id` (a TYPES id, e.g. "shotgun").
func show_gun(type_id: String) -> void:
	texture = TEXTURES.get(type_id, TEXTURES[DEFAULT_TYPE])
	# Uncentred, at a whole-pixel offset, so odd heights don't land on half
	# pixels.
	offset = Vector2(BACK, -floorf(texture.get_height() / 2.0))


## Shows the gun with id `gun_id` (any tier, e.g. "scrap_pistol").
func show_gun_id(gun_id: String) -> void:
	show_gun(Guns.get_gun(gun_id).get("type", DEFAULT_TYPE))


## Plays the firing sound (once per trigger pull, however many pellets the
## gun fires).
func play_shot() -> void:
	_sound.play()


## Darkens the gun to match a knocked-out player's dimmed art.
func set_dimmed(dimmed: bool) -> void:
	modulate = Color(0.3, 0.3, 0.3) if dimmed else Color.WHITE


## Points the gun along `angle` (radians, like the player square's rotation).
func aim(angle: float) -> void:
	rotation = angle
	# Same left/right split as the character art (player_sprite.gd's face()).
	flip_v = cos(angle) < -0.01
