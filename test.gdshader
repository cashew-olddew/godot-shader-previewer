shader_type canvas_item;

// Uniforms for the user to play with in the Inspector
uniform float time_speed : hint_range(0.1, 5.0) = 1.0;
uniform float scale : hint_range(1.0, 20.0) = 10.0;
uniform vec4 custom_color : source_color = vec4(0.2, 0.5, 0.8, 1.0);
uniform bool brighten = true;

void fragment() {
	float gradient = UV.x;
	vec2 st = UV;
	int grid_cells = int(UV.x * scale);
	bool is_left_side = UV.x < 0.5;
	vec3 animated_rgb = vec3(
		0.5 + 0.5 * cos(TIME * time_speed + float(grid_cells) + vec3(0, 2, 4))
	);
	vec4 final_pixel = vec4(animated_rgb, 1.0) * custom_color;
	if (brighten) {
		final_pixel.rgb += 0.5;
	}
	
	COLOR = final_pixel;
}