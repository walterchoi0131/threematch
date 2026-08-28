shader_type canvas_item;

uniform float fade_start = 0.8;
uniform float edge_fade = 0.2;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float top_alpha = smoothstep(0.0, edge_fade, UV.y);
	float bottom_alpha = 1.0 - smoothstep(fade_start, 1.0, UV.y);
	COLOR = vec4(tex_color.rgb, tex_color.a * top_alpha * bottom_alpha);
}
