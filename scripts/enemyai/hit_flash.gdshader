shader_type canvas_item;
// Enemy hit flash (scripts/enemyai/chasesplayer.gd, flash_hit): the sprite is
// pushed toward flash_color, keeping its alpha, like the player's hit flash
// (scripts/player/armor_swap.gdshader). Modulate and self_modulate (slow
// tints, elite colours, Braid fades) still apply underneath.

uniform vec4 flash_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.rgb = mix(c.rgb, flash_color.rgb, flash_amount);
	COLOR = c;
}
