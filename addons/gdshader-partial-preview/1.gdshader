shader_type canvas_item;

uniform float i : hint_range(0.0, 1.0, 0.1);

void fragment() {
	vec3 col1 = vec3(i, 0.0, 0.0);
	vec2 uv_s = fract(UV * 10.);
}
