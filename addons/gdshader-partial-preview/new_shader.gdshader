shader_type canvas_item;

void fragment() {
	vec2 uv;
	uv = UV;
	mat2 test = mat2(uv, uv);
	uv = fract(uv * 10.);
	uv *= fract(TIME);
}
