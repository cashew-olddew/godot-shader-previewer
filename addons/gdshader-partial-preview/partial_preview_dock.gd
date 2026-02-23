@tool
extends ColorRect
class_name PartialPreviewDock

func update_shader_preview(text: String, current_line_index: int) -> void:
	var generated_code = _generate_preview_shader(text, current_line_index)
	
	var shader_content := Shader.new()
	shader_content.code = generated_code
	
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader_content
	
	material = shader_material

func _generate_preview_shader(original_code: String, line_index: int) -> String:
	var lines = original_code.split("\n")
	
	if line_index >= lines.size():
		return original_code

	var current_line_text = lines[line_index]
	
	# Search for variable assignment
	var var_regex = RegEx.new()
	var_regex.compile(r"(\w+)\s*([+\-*/%]?=)")
	var var_match = var_regex.search(current_line_text)
	
	if not var_match:
		return original_code
		
	var var_name = var_match.get_string(1)
	var type = _find_var_type(var_name, original_code, line_index)
	
	# All code before assignment stays as it was
	var truncated_lines = []
	for i in range(line_index + 1):
		truncated_lines.append(lines[i])
	
	# Inject COLOR preview
	var injection = ""
	match type:
		"float": injection = "COLOR = vec4(vec3(%s), 1.0);" % var_name
		"vec2":  injection = "COLOR = vec4(%s, 0.0, 1.0);" % var_name
		"vec3":  injection = "COLOR = vec4(%s, 1.0);" % var_name
		"vec4":  injection = "COLOR = %s;" % var_name
		_: return original_code
		
	truncated_lines.append(injection)
	
	# Close parantheses
	var full_truncated_text = "\n".join(truncated_lines)
	var open_braces = full_truncated_text.count("{")
	var closed_braces = full_truncated_text.count("}")
	var needed_closures = open_braces - closed_braces
	
	for i in range(needed_closures):
		full_truncated_text += "\n}"
		
	return full_truncated_text

func _find_var_type(var_name: String, full_code: String, line_index: int) -> String:
	var lines = full_code.split("\n")
	var type_regex = RegEx.new()
	type_regex.compile("(float|vec2|vec3|vec4|int|bool)\\s+" + var_name + "\\b")
	
	for i in range(line_index, -1, -1):
		var m = type_regex.search(lines[i])
		if m: return m.get_string(1)
			
	if var_name in ["UV", "SCREEN_UV"]: return "vec2"
	if var_name in ["COLOR", "MODULATE"]: return "vec4"
	if var_name == "TIME": return "float"
	return ""
