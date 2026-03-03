@tool
extends TextureRect
class_name ShaderLinePreviewerDock

const BUILTINS := {
	[
		"NORMAL_MAP_DEPTH",
		"DEPTH",
		"ALPHA",
		"ALPHA_SCISSOR_THRESHOLD",
		"ALPHA_HASH_SCALE",
		"ALPHA_ANTIALIASING_EDGE",
		"PREMUL_ALPHA_FACTOR",
		"METALLIC",
		"SPECULAR",
		"ROUGHNESS",
		"RIM",
		"RIM_TINT",
		"CLEARCOAT",
		"CLEARCOAT_GLOSS",
		"ANISOTROPY",
		"SSS_STRENGTH",
		"SSS_TRANSMITTANCE_DEPTH",
		"SSS_TRANSMITTANCE_BOOST",
		"AO",
		"AO_LIGHT_AFFECT",
	]: "float",

	[
		"VERTEX",
		"SHADOW_VERTEX",
		"ALPHA_TEXTURE_COORDINATE",
		"ANISOTROPY_FLOW",
	]: "vec2",

	[
		"NORMAL",
		"NORMAL_MAP",
		"LIGHT_VERTEX",
		"TANGENT",
		"BINORMAL",
		"ALBEDO",
		"BACKLIGHT",
		"EMISSION",
	]: "vec3",

	[
		"COLOR",
		"FOG",
		"RADIANCE",
		"IRRADIANCE",
		"SSS_TRANSMITTANCE_COLOR",
	]: "vec4"
}

const SPATIAL_ASSIGNMENTS := {
	"bool": "ALBEDO = vec3(float(%s)); ALPHA = 1.0;",
	"int": "ALBEDO = vec3(float(%s)); ALPHA = 1.0;",
	"float": "ALBEDO = vec3(%s); ALPHA = 1.0;",
	"vec2": "ALBEDO = vec3(%s.rg, 0.0); ALPHA = 1.0;",
	"vec3": "ALBEDO = %s; ALPHA = 1.0;",
	"vec4": "vec4 __injected_outbound = %s; ALBEDO = __injected_outbound.rgb; ALPHA = __injected_outbound.a;"
}

const CANVAS_ASSIGNMENTS := {
	"bool": "COLOR = vec4(vec3(float(%s)), 1.0);",
	"int": "COLOR = vec4(vec3(float(%s)), 1.0);",
	"float": "COLOR = vec4(vec3(%s), 1.0);",
	"vec2": "COLOR = vec4(%s, 0.0, 1.0);",
	"vec3": "COLOR = vec4(%s, 1.0);",
	"vec4": "COLOR = %s;",
}

@export var viewport_texture: ViewportTexture
@export var preview_mesh: MeshInstance3D
@export var label: RichTextLabel
@export var camera_3d: Camera3D


var _initial_texture: Texture2D = null
var _mode_3d := false:
	set(v):
		_mode_3d = v

func _ready():
	_initial_texture = texture

func _show_error(message: String) -> void:
	label.text = message
	material = null
	texture = _initial_texture

func update_shader_preview(text: String, current_line_index: int, selected_material: ShaderMaterial) -> void:
	label.text = ""
	var generated_code = _generate_preview_shader(text, current_line_index)
	var shader_content := Shader.new()
	shader_content.code = generated_code

	# A new material is created to not overwrite the node's actual material
	var preview_material = ShaderMaterial.new()
	preview_material.shader = shader_content

	if not selected_material or not _match_uniforms(selected_material, preview_material):
		_show_error("A node using the shader must be selected.")
		return
		
	_sync_material_parameters(selected_material, preview_material)

	if _mode_3d:
		material = null
		texture = viewport_texture
		preview_mesh.set_surface_override_material(0, preview_material)
	else:
		material = preview_material
	
func update_texture(node: Node) -> void:
	if node and "texture" in node and node.texture:
		texture = node.texture
	else:
		texture = _initial_texture

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
	var_regex.compile(r"([\w.]+)\s*([+\-*/%]?=)(?!=)")
	
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
		
	var full_captured_path = var_match.get_string(1) # e.g. "my_vec.xy"
	var base_var_name = full_captured_path.split(".")[0] # e.g. "my_vec"
	
	return {
		"var_name": base_var_name,
		"start": stmt_start,
		"end": stmt_end,
	}

func _get_enclosing_function(lines: PackedStringArray, line_index: int) -> String:
	var brace_stack = 0
	var func_regex = RegEx.new()
	func_regex.compile(r"void\s+(\w+)\s*\(")

	for i in range(line_index, -1, -1):
		# 1. Strip comments AND trailing whitespace
		var clean_line = lines[i].split("//")[0].strip_edges()
		if clean_line.is_empty():
			continue

		brace_stack += clean_line.count("}")
		brace_stack -= clean_line.count("{")

		if brace_stack < 0:
			var m = func_regex.search(clean_line)
			if m:
				return m.get_string(1)
			
			# If we exited a block but didn't find a function head on this line,
			# the user might have put the '{' on its own line. 
			# We keep looking back for the function signature.
			brace_stack = 0 
				
	return "" # Global scope

func _get_shader_type(code: String) -> String:
	var regex := RegEx.create_from_string(r"shader_type\s+(canvas_item|spatial)")
	var result := regex.search(code)
	return "error" if result == null else result.get_string(1)

func _generate_preview_shader(original_code: String, line_index: int) -> String:
	var shader_type := _get_shader_type(original_code)
	if shader_type == "error":
		_show_error("No [b]shader_type[/b] statement found on shader")
		return original_code
	if shader_type.is_empty():
		_show_error("Preview only supports [b]canvas_item[/b] and [b]spatial[/b] shaders")
		return original_code
	_mode_3d = shader_type == "spatial"
	
	var lines = original_code.split("\n")
	var enclosing_function = _get_enclosing_function(lines, line_index)
	
	if enclosing_function != "fragment":
		_show_error("Preview only supports assignments in the [b]fragment()[/b] function")
		return original_code
	
	if line_index >= lines.size():
		_show_error("Something weird happened... Try restarting the plugin.")
		return original_code
		
	var stmt = _find_statement(lines, line_index)
	
	if stmt.is_empty():
		_show_error("The selected line needs to be an assignment.")
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
	var assignments: Dictionary = SPATIAL_ASSIGNMENTS if _mode_3d else CANVAS_ASSIGNMENTS
	if not assignments.has(type):
		_show_error("Preview unavailable for current assignment.\nSupported types are: [b]bool, int, float, vec2, vec3, vec4[/b].")
		return original_code
	
	injection = assignments[type] % var_name
	
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
			
	# Built-in Godot Shader Variables (CanvasItem & Spatial)
	for builtin_collection: Array in BUILTINS.keys():
		if var_name in builtin_collection:
			return BUILTINS[builtin_collection]
	
	return ""
