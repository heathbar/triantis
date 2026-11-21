extends RefCounted
## Controller button icons (res://assets/ui/controls/) inside menu text.
## Write {A}, {B}, {X}, {Y}, {LB}, {RB}, {LT}, {LEFT}, {RIGHT}, {UP} or {DOWN} (D-pad) in a prompt and show it with label() /
## set_text() (or put bbcode() into any RichTextLabel): each token becomes
## that button's icon, sized to the text. Other text is shown as-is.
##
## Prompts only name controller buttons; keyboard / mouse players work it out.

const ICONS := {
	"A": "res://assets/ui/controls/A.svg",
	"B": "res://assets/ui/controls/B.svg",
	"X": "res://assets/ui/controls/X.svg",
	"Y": "res://assets/ui/controls/Y.svg",
	"LB": "res://assets/ui/controls/Left_Bumper.svg",
	"RB": "res://assets/ui/controls/Right_Bumper.svg",
	"LT": "res://assets/ui/controls/Left_Trigger.svg",
	"LEFT": "res://assets/ui/controls/DPad_Left.svg",
	"RIGHT": "res://assets/ui/controls/DPad_Right.svg",
	"UP": "res://assets/ui/controls/DPad_Up.svg",
	"DOWN": "res://assets/ui/controls/DPad_Down.svg",
}
## Icon size relative to the font size.
const ICON_SCALE := 1.3


static func icon(button: String) -> Texture2D:
	return load(ICONS[button])


## `text` as BBCode for a RichTextLabel with `font_size` text: tokens become
## icons (tinted `color`), and any "[" in the text shows as itself.
static func bbcode(text: String, font_size: int, color := Color.WHITE) -> String:
	text = text.replace("[", "[lb]")
	var size := roundi(font_size * ICON_SCALE)
	for key in ICONS:
		text = text.replace("{%s}" % key, "[img width=%d height=%d color=#%s]%s[/img]"
			% [size, size, color.to_html(), ICONS[key]])
	return text


## A one-line, centred label showing `text` (with icons) that sizes itself to
## fit. `outline` is the black outline's width.
static func label(text: String, color: Color, font_size: int, outline := 0) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.autowrap_mode = TextServer.AUTOWRAP_OFF
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rich.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rich.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rich.add_theme_font_size_override("normal_font_size", font_size)
	rich.add_theme_color_override("default_color", color)
	rich.add_theme_color_override("font_outline_color", Color.BLACK)
	rich.add_theme_constant_override("outline_size", outline)
	rich.set_meta("prompt_font_size", font_size)
	set_text(rich, text)
	return rich


## Change the text of a label() (or any RichTextLabel with bbcode_enabled).
static func set_text(rich: RichTextLabel, text: String) -> void:
	var font_size: int = rich.get_meta("prompt_font_size",
		rich.get_theme_font_size("normal_font_size"))
	rich.text = bbcode(text, font_size, rich.get_theme_color("default_color"))
