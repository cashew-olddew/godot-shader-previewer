shader_type spatial;

void fragment() {
	float x_normal = NORMAL.x;
	x_normal = step(0.25, x_normal);
	
	ALBEDO = vec3(x_normal, 0.0, 1.0 - x_normal);
	ALPHA = x_normal;
}
