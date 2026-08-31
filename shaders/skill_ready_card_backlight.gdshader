shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glow_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.8;
uniform float phase = 0.0;

float rounded_box_sdf(vec2 point, vec2 half_size, float radius) {
	vec2 q = abs(point) - half_size + radius;
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}

void fragment() {
	vec2 point = UV - vec2(0.5);
	float distance_to_card = rounded_box_sdf(point, vec2(0.372, 0.374), 0.055);
	float angle = atan(point.y, point.x);
	float radius = length(point);
	float pulse = 0.82 + 0.18 * sin(TIME * 1.85 + phase);
	float shimmer = 0.72 + 0.28 * sin(angle * 11.0 - TIME * 0.72 + phase);
	float halo = exp(-abs(distance_to_card) * 16.0);
	float edge = exp(-abs(distance_to_card) * 42.0);
	float outside = smoothstep(-0.015, 0.045, distance_to_card);
	float ray_band = smoothstep(0.30, 0.43, radius)
			* (1.0 - smoothstep(0.43, 0.70, radius));
	float rays = pow(max(0.0, shimmer), 3.0) * ray_band * outside;
	float alpha = (halo * 0.34 + edge * 0.62 + rays * 0.30)
			* intensity * pulse;
	float nearest_canvas_edge = min(
			min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	alpha *= smoothstep(0.0, 0.11, nearest_canvas_edge);
	vec3 hot_core = mix(glow_color.rgb, vec3(1.0), edge * 0.38);
	COLOR = vec4(hot_core * (0.88 + rays * 0.45), clamp(alpha, 0.0, 0.92));
}
