shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glow_color : source_color = vec4(0.05, 0.72, 1.0, 0.82);
uniform float glow_strength : hint_range(0.0, 1.5) = 0.0;
uniform float glow_radius : hint_range(1.0, 32.0) = 12.0;
uniform float glow_softness : hint_range(0.25, 2.0) = 0.72;
uniform float pulse_speed : hint_range(0.0, 12.0) = 4.0;
uniform float halo_gain : hint_range(0.25, 8.0) = 3.0;
uniform vec2 padding_uv = vec2(0.08);
uniform sampler2D source_texture : source_color, filter_linear, repeat_disable;
uniform vec2 source_texel_size = vec2(0.01);


float alpha_at(vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(source_texture, uv).a;
}


void fragment() {
	vec2 content_scale = vec2(1.0) - padding_uv * 2.0;
	vec2 source_uv = (UV - padding_uv) / content_scale;
	vec2 texel = source_texel_size * glow_radius;
	float source_alpha = alpha_at(source_uv);
	float soft_alpha = source_alpha * 2.0;
	float total_weight = 2.0;
	const int SAMPLE_COUNT = 24;
	for (int index = 0; index < SAMPLE_COUNT; index++) {
		float angle = float(index) * TAU / float(SAMPLE_COUNT);
		vec2 direction = vec2(cos(angle), sin(angle));
		float inner = alpha_at(source_uv + direction * texel * 0.28);
		float middle = alpha_at(source_uv + direction * texel * 0.58);
		float outer = alpha_at(source_uv + direction * texel);
		soft_alpha += inner * 0.48 + middle * 0.32 + outer * 0.20;
		total_weight += 1.0;
	}
	soft_alpha /= total_weight;
	float halo = max(soft_alpha - source_alpha * 0.58, 0.0);
	halo = pow(clamp(halo, 0.0, 1.0), glow_softness);
	halo *= 1.0 - smoothstep(0.0, 0.08, source_alpha);
	float pulse = 0.90 + sin(TIME * pulse_speed) * 0.10;
	float final_alpha = clamp(
			halo * glow_color.a * glow_strength * halo_gain * pulse, 0.0, 1.0);
	COLOR = vec4(glow_color.rgb * final_alpha, final_alpha);
}
