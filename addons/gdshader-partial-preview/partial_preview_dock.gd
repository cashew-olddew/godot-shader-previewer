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

	if not selected_material or not _match_uniforms(selected_material, preview_material):
		label.text = "A node using the shader must be selected."
		material = null
		return
		
	_sync_material_parameters(selected_material, preview_material)

	material = preview_material

# Helper function to check if two shaders correspond
# Kind of hacky, as it just matches uniforms, but good enough for now
func _match_uniforms(source: ShaderMaterial, target: ShaderMaterial) -> bool:
	if not source.shader or not target.shader:
		return false
	
	var source_params = source.shader.get_shader_uniform_list()
	var target_params = target.shader.get_shader_uniform_list()
	
	if source_params.size() != target_params.size():
		return false
	
	# get_shader_uniform_list returns a dictionary and I'm not sure how all
	# values inside it are set. Because of that I'm comparing only name and type
	var target_set = {}
	for p in target_params:
		target_set[p.name + str(p.type)] = true
	
	for p in source_params:
		var key = p.name + str(p.type)
		if not target_set.has(key):
			return false
			
	return true
	
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

func _find_statement(lines: PackedStringArray, line_index: int) -> Dictionary:
	var var_regex = RegEx.new()
	var_regex.compile(r"(\w+)\s*([+\-*/%]?=)(?!=)")
	
	# Walk backward from the caret to find the line with the assignment operator
	var stmt_start = line_index
	var var_match = var_regex.search(lines[stmt_start])
	while not var_match and stmt_start > 0:
		var current_line = lines[stmt_start].strip_edges()
		
		if stmt_start < line_index and (current_line.is_empty() or current_line.ends_with(";") or current_line.ends_with("{") or current_line.ends_with("}")):
			return {}
			
		stmt_start -= 1
		var_match = var_regex.search(lines[stmt_start])
	
	if not var_match:
		return {}
	
	# Flow control selection can't be previewed
	var flow_regex = RegEx.new()
	flow_regex.compile(r"^(else\s+)?(if|while|for)\b")
	if flow_regex.search(lines[stmt_start].strip_edges()):
		return {}
	
	var stmt_end = stmt_start
	var max_scan = min(stmt_start + 20, lines.size() - 1)
	while stmt_end < max_scan and not lines[stmt_end].strip_edges().ends_with(";"):
		stmt_end += 1
	
	if not lines[stmt_end].strip_edges().ends_with(";"):
		return {}
	
	if line_index > stmt_end:
		return {}
	
	return {
		"var_name": var_match.get_string(1),
		"start": stmt_start,
		"end": stmt_end,
	}

func _generate_preview_shader(original_code: String, line_index: int) -> String:
	var lines = original_code.split("\n")
	
	if line_index >= lines.size():
		label.text = "Something weird happened... Try restarting the plugin."
		material = null
		return original_code
		
	var stmt = _find_statement(lines, line_index)
	
	if stmt.is_empty():
		label.text = "The selected line needs to be an assignment."
		material = null
		return original_code
		
	var var_name: String = stmt["var_name"]
	var last_line: int = stmt["end"]
	var type = _find_var_type(var_name, original_code, last_line)
	
	# All code before assignment stays as it was
	var truncated_lines = []
	for i in range(last_line + 1):
		truncated_lines.append(lines[i])
	
	# Inject COLOR preview
	var injection = ""
	match type:
		"bool":  injection = "COLOR = vec4(vec3(float(%s)), 1.0);" % var_name
		"int":   injection = "COLOR = vec4(vec3(float(%s)), 1.0);" % var_name
		"float": injection = "COLOR = vec4(vec3(%s), 1.0);" % var_name
		"vec2":  injection = "COLOR = vec4(%s, 0.0, 1.0);" % var_name
		"vec3":  injection = "COLOR = vec4(%s, 1.0);" % var_name
		"vec4":  injection = "COLOR = %s;" % var_name
		_: 
			label.text = "Preview unavailable for current assignment.\nSupported types are: [b]bool, int, float, vec2, vec3, vec4[/b]."
			material = null
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
	
	# Matches a type keyword, followed by anything EXCEPT a semicolon, then the variable name.
	# This safely handles: "float my_var;" AND "float a, b, my_var;"
	type_regex.compile(r"\b(float|vec2|vec3|vec4|int|bool|sampler2D)\b[^;]*\b" + var_name + r"\b")
	
	# Walk backwards from the end of the assignment statement
	for i in range(line_index, -1, -1):
		# Strip out comments before checking so we don't catch commented-out declarations
		var clean_line = lines[i].split("//")[0]
		
		var m = type_regex.search(clean_line)
		if m: 
			return m.get_string(1)
			
	# Built-in Godot Shader Variables (CanvasItem & common Spatial)
	if var_name in ["UV", "SCREEN_UV", "POINT_COORD"]: 
		return "vec2"
	if var_name in ["COLOR", "MODULATE"]: 
		return "vec4"
	if var_name in ["TIME", "PI", "TAU"]: 
		return "float"
	if var_name in ["VERTEX", "NORMAL"]: 
		return "vec2" 
	
	return ""
