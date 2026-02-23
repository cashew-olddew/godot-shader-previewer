shader_type canvas_item;

void fragment() {
	vec2 uv;
	uv = UV;
	uv = fract(uv * 10.);
	uv *= fract(TIME);
}
