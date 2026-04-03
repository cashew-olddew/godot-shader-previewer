shader_type canvas_item;
render_mode world_vertex_coords;

uniform sampler2D shape_texture;

uniform vec3 light_square_color: source_color = vec3(0.576, 0.588, 0.604);
uniform vec3 dark_square_color: source_color = vec3(0.302, 0.318, 0.341);
uniform float square_size = 16.0;

varying vec2 pos;
void vertex() {
	pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 centered_scaled_screen_uv = (SCREEN_UV / SCREEN_PIXEL_SIZE - pos);
	vec2 fract_part = mod(floor(centered_scaled_screen_uv / square_size), 2.0);
	
	vec3 background_color = vec3(mix(light_square_color, dark_square_color, mod(fract_part.x + fract_part.y, 2.0)));
	
	vec4 shape_color = texture(shape_texture, UV);
	
	COLOR = vec4(mix(background_color, shape_color.rgb, shape_color.a), 1.0);
}
