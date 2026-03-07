shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture;

void fragment() {
	vec4 original_color = COLOR;
	vec3 background = texture(screen_texture, SCREEN_UV).rgb;
	
	// Note: constrast between 0.3 and 1.0 to prevent white background to remove nuance in icons
	vec3 contrast = clamp(vec3(1.0) - background, 0.3, 1.0);
	
	COLOR.rgb = original_color.rgb * contrast;
}
