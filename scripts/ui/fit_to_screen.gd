extends RefCounted
## Shrinks a full-screen menu evenly (never grows it) when its contents are
## bigger than the screen, e.g. four players' columns, so nothing runs off the
## edges. Used by the shop and the Class Mod picker.
##
## `content` is a full-rect container (a CenterContainer) whose first child
## holds everything. Call fit() again whenever the contents change size.

## Leave this share of the screen as a margin round the scaled contents.
const ROOM := 0.98


static func fit(content: Control) -> void:
	if not content.is_inside_tree() or content.get_child_count() == 0:
		return
	var box := content.get_child(0) as Control
	var needed := box.get_combined_minimum_size()
	var screen := content.get_viewport_rect().size
	var room := screen * ROOM
	var scale := minf(1.0, minf(room.x / maxf(needed.x, 1.0), room.y / maxf(needed.y, 1.0)))
	# `content` grows past the screen to hold everything, so scale from its
	# corner and centre the scaled result by hand. (Its size may not have
	# caught up with the contents yet, so work out the size it will have.)
	var full := Vector2(maxf(screen.x, needed.x), maxf(screen.y, needed.y))
	content.scale = Vector2(scale, scale)
	content.position = (screen - full * scale) / 2.0
