@tool
extends ColorRect
class_name PartialPreviewDock

@onready var label = $Label

func update_shader_preview(text: String, current_line_index: int, selected_material: ShaderMaterial) -> void:
	label.text = ""
	var generated_code = _generate_preview_shader(text, current_line_index)
	var shader_content := Shader.new()
	shader_content.code = generated_code
	
	# A new material is created to not overwrite the node's actual material
	var preview_material = ShaderMaterial.new()
	preview_material.shader = shader_content
	
	# TODO: Currently this 'registers' as selected for every node. Find a way to differenciate
	if not selected_material:
		label.text = "A node using the shader must be selected."
		material = null
		return
		
	# TODO: Find a way to call this whenever a parameter changes
	_sync_material_parameters(selected_material, preview_material)

	material = preview_material

# Helper function to copy uniform values
func _sync_material_parameters(source: ShaderMaterial, target: ShaderMaterial) -> void:
	if not source.shader:
		return
		
	# Get all uniforms defined in the original shader
	var params = source.shader.get_shader_uniform_list()
	for p in params:
		var param_name = p["name"]
		var param_value = source.get_shader_parameter(param_name)
		target.set_shader_parameter(param_name, param_value)

func _generate_preview_shader(original_code: String, line_index: int) -> String:
	var lines = original_code.split("\n")
	
	if line_index >= lines.size():
		label.text = "Something weird happened... Try restarting the plugin."
		return original_code

	var current_line_text = lines[line_index]
	
	# Search for variable assignment
	# TODO: Consider multi-line statements
	var var_regex = RegEx.new()
	var_regex.compile(r"(\w+)\s*([+\-*/%]?=)")
	var var_match = var_regex.search(current_line_text)
	
	if not var_match:
		label.text = "The selected line needs to be an assignment."
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
		_: 
			label.text = "Preview unavailable for current assignment.\nSupported types are: [b]float, vec2, vec3, vec4[/b]."
			return original_code
		
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
