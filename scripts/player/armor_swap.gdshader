shader_type canvas_item;
// Palette swap for the player art (any skin in scripts/player/player_skins.gd,
// pictures in assets/player/): the green armour becomes `armor_color`, keeping the art's light/dark shading. Everything else
// (outline, undersuit, visor) is left alone.
// Used by scripts/player/player_sprite.gd and the character select preview.

uniform vec4 armor_color : source_color = vec4(1.0);
// Hit / block / heal flash: the whole sprite is pushed toward flash_color.
uniform vec4 flash_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
// Below 1 dims the whole sprite (knocked out, locked in character select).
uniform float brightness : hint_range(0.0, 1.0) = 1.0;

// Green channel of the brightest armour green in the art (62, 154, 84).
// Shading is kept relative to it: the darker green (40, 123, 62) ends up as
// armor_color at ~80%.
const float ARMOR_LIGHT = 154.0 / 255.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// Only the armour is green-dominant (e.g. the Spartan's visor is orange
	// and undersuit grey/purple; the chicken's comb is red, feet orange). The smoothstep also catches filtered edge
	// pixels where green blends into the black outline.
	float greenness = c.g - max(c.r, c.b);
	vec3 armor = armor_color.rgb * (c.g / ARMOR_LIGHT);
	c.rgb = mix(c.rgb, armor, smoothstep(0.02, 0.12, greenness));
	c.rgb = mix(c.rgb, flash_color.rgb, flash_amount);
	c.rgb *= brightness;
	COLOR = c;
}
