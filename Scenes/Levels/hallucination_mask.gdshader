shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint : source_color = vec4(0.580392, 0.278431, 0.458824, 1.0);

float grain_at(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(1.0, 0.88);
	float breath = sin(TIME * 1.55);
	float edge = smoothstep(0.24, 0.63, length(centered) + breath * 0.018);
	float haze = sin(UV.y * 9.0 + UV.x * 5.0 - TIME * 0.8);
	float grain = grain_at(floor(FRAGCOORD.xy / 3.0)) - 0.5;
	vec3 shadow = tint.rgb * vec3(0.24, 0.17, 0.33);
	vec3 color = mix(tint.rgb, shadow, edge * 0.92);
	float opacity = 0.29 + edge * 0.43 + breath * 0.025 + haze * 0.018 + grain * 0.036;
	COLOR = vec4(color, clamp(opacity, 0.0, 1.0));
}
