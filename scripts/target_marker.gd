extends RefCounted
## Where something is about to land from the sky: assets/misc/target.png (a
## crosshair ring, 64 px) drawn at the size of the spot it marks. Used by the
## bosses' shells and rocks (Lighthouse, Vault, Crusher), the Tyrants
## modifier's mortars, the Air Strike equipment and the Campaign's airstrike.
##
## The art is shrunk (never stretched) to each size once, smoothly, and kept:
## shrinking it on the fly would drop pixels from its 1-2 px lines.

const TEXTURE := preload("res://assets/misc/target.png")
## Width of the friendly airstrikes' aim marks (pixels), smaller than their
## blasts so a line of them doesn't overlap into a smear.
const AIM_SIZE := 24

## Diameter (pixels) -> the art at that size.
static var _sizes := {}


## The art at `size` pixels across.
static func texture(size: int) -> Texture2D:
	size = clampi(size, 4, TEXTURE.get_width())
	if size == TEXTURE.get_width():
		return TEXTURE
	if not _sizes.has(size):
		var image := TEXTURE.get_image()
		if image.is_compressed():
			image.decompress()
		image.generate_mipmaps()
		image.resize(size, size, Image.INTERPOLATE_TRILINEAR)
		_sizes[size] = ImageTexture.create_from_image(image)
	return _sizes[size]


## Draws the target centred on `at` (on `c`), `radius` pixels round, tinted
## `tint` (white: as drawn).
static func draw(c: CanvasItem, at: Vector2, radius: float, tint := Color.WHITE) -> void:
	var tex := texture(roundi(radius * 2.0))
	c.draw_texture(tex, (at - tex.get_size() / 2.0).round(), tint)
