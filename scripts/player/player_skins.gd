extends RefCounted
## The looks a player can pick on character select (Up / Down), independent of
## their class: the class still sets the colour, which armor_swap.gdshader
## paints over the art's green. Purely cosmetic: hitbox and gameplay are the
## same whichever is picked.
##
## To add one: drop a PNG in assets/player/ and add an entry below. The art
## should face right and use the same armour greens as the others
## (62, 154, 84) and (40, 123, 62); everything else keeps its own colours.
## Centring comes from the picture's opaque area, so any canvas size works.
## The art is drawn at its own pixel size in game (1 texture pixel = 1 world
## pixel), so draw it at the size it should appear (~25px tall).
##
## Picks are stored and sent over the network as indexes into SKINS, so add
## new ones at the end.

const SKINS := [
	{"name": "Spartan", "texture": preload("res://assets/player/master_chief.png")},
	{"name": "Princess", "texture": preload("res://assets/player/princess.png")},
	{"name": "Chicken", "texture": preload("res://assets/player/chicken.png")},
	{"name": "Mario", "texture": preload("res://assets/player/mario.png")},
	{"name": "Pickle", "texture": preload("res://assets/player/pickle.png")},
	{"name": "Minion", "texture": preload("res://assets/player/minion.png")},
]

## texture -> Rect2 of its opaque pixels (see art_rect()). 
static var _rects := {}
## index -> AtlasTexture (see cropped_texture()).
static var _cropped := {}


static func count() -> int:
	return SKINS.size()


## The skin at `index`, or the first one if it's out of range (e.g. a squad
## player on a build with more skins).
static func get_skin(index: int) -> Dictionary:
	return SKINS[index] if index >= 0 and index < SKINS.size() else SKINS[0]


static func texture(index: int) -> Texture2D:
	return get_skin(index)["texture"]


## The part of `index`'s picture the figure covers (the PNGs have empty
## margins), worked out once per picture.
static func art_rect(index: int) -> Rect2:
	var tex := texture(index)
	if not _rects.has(tex):
		var rect := Rect2(Vector2.ZERO, tex.get_size())
		var image := tex.get_image()
		if image:
			var used := image.get_used_rect()
			if used.has_area():
				rect = Rect2(used)
		_rects[tex] = rect
	return _rects[tex]


## The figure cropped out of its picture, for UI (character select), so every
## skin fills its preview the same way.
static func cropped_texture(index: int) -> Texture2D:
	if not _cropped.has(index):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture(index)
		atlas.region = art_rect(index)
		_cropped[index] = atlas
	return _cropped[index]
