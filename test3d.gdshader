shader_type spatial;
render_mode blend_add, depth_draw_never;

uniform vec4 fresnel_color: source_color = vec4(0.0, 0.9, 0.9, 1.0);
uniform float fresnel_intensity: hint_range(0.0, 10.0) = 1.0;
uniform float fresnel_power: hint_range(0.5, 8.0) = 6.0;

void fragment() {
	float fresnel = 1.0 - dot(normalize(NORMAL), normalize(VIEW));
	fresnel = pow(fresnel, fresnel_power);
	EMISSION += (fresnel * fresnel_color.rgb * fresnel_intensity);
	ALBEDO = clamp(vec3(UV, 0.0) + EMISSION, vec3(0.0), vec3(1.0));
}