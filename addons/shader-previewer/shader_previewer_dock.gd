@tool
extends PanelContainer
class_name ShaderLinePreviewerDock

signal floating_requested

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

@onready var preview: TextureRect = $Preview
@onready var sub_viewport: SubViewport = $SubViewport
@onready var top_button_container: HBoxContainer = $Preview/TopButtonContainer

@export var viewport_texture: ViewportTexture
@export var preview_mesh: MeshInstance3D
@export var label: RichTextLabel
@export var camera_3d: Camera3D

@export var resize_view_button: Button
@export var move_view_button: Button
@export var floating_button: Button

var _initial_texture: Texture2D = null
var _mode_3d := false

var _is_floating: bool = false
var current_shader_code_editor: CodeEdit
var _should_hide_buttons: bool = false # Used to prevent hiding during resize/move

func _ready():
	_initialize_theme_color()
	
	_initial_texture = preview.texture
	
	top_button_container.hide()
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	resize_view_button.button_down.connect(_on_resize_button_down)
	resize_view_button.button_up.connect(_on_resize_button_up)
	
	move_view_button.button_down.connect(_on_move_button_down)
	move_view_button.button_up.connect(_on_move_button_up)
	
	floating_button.pressed.connect(func(): floating_requested.emit())
	
	_last_floating_panel_size = size

func _initialize_theme_color() -> void:
	var style_box: StyleBoxFlat = get_theme_stylebox("panel")
	
	var root := EditorInterface.get_base_control()
	var base_color = root.get_theme_color("base_color", "Editor")
	
	style_box.bg_color = base_color
	style_box.border_color = base_color
	(preview.texture as GradientTexture1D).gradient.set_color(0, base_color)

func set_floating_mode(floating: bool) -> void:
	_is_floating = floating
	if floating:
		resize_view_button.show()
		move_view_button.show()
		size = _last_floating_panel_size
		sub_viewport.size = _last_floating_panel_size
		set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 20)
		
		# Note: These 2 await allow us to wait for the code editor to get its true size
		#       and prevent wrong positioning due to local cords. If a better way to find
		#       if the CodeEditor finished positioning in the layers can be found it replace
		#       this fix
		await get_tree().process_frame
		await get_tree().process_frame
		
		if _last_floating_panel_pos.x >= 0.0:
			position = _last_floating_panel_pos
		
		# This prevent the preview to keep a now outside old size/pos
		if current_shader_code_editor: resize_to_editor_shape()
	else:
		resize_view_button.hide()
		move_view_button.hide()

func _on_mouse_entered() -> void:
	top_button_container.show()
	_should_hide_buttons = false

func _on_mouse_exited() -> void:
	if _in_resize or _in_move:
		_should_hide_buttons = true
		return
	
	top_button_container.hide()

#region Resize and Move
const MIN_SIZE := Vector2(150.0, 150.0)

var _in_resize: bool = false
var _in_move: bool = false

var _initial_mouse_position: Vector2
var _initial_panel_size: Vector2
var _initial_panel_position: Vector2

var _last_floating_panel_size: Vector2
var _last_floating_panel_pos := Vector2(-1, -1)

func _on_resize_button_down() -> void:
	if not _is_floating: return
	
	_in_resize = true
	_initial_mouse_position = get_global_mouse_position()
	_initial_panel_size = size
	_initial_panel_position = position

func _on_resize_button_up() -> void:
	if not _is_floating: return
	_in_resize = false
	if _should_hide_buttons:
		top_button_container.hide()
		_should_hide_buttons = false

func _on_move_button_down() -> void:
	if not _is_floating: return
	
	_in_move = true
	_initial_mouse_position = get_global_mouse_position()
	_initial_panel_position = position

func _on_move_button_up() -> void:
	if not _is_floating: return
	
	_in_move = false
	if _should_hide_buttons:
		top_button_container.hide()
		_should_hide_buttons = false

func _gui_input(event: InputEvent) -> void:
	if not _is_floating: return
	
	if not _in_resize and not _in_move: return
	
	var mouse_move := event as InputEventMouseMotion
	if not mouse_move: return
	
	var delta_mouse_position: Vector2 = _initial_mouse_position - mouse_move.global_position
	
	if _in_resize:
		var resized_size: Vector2 = _initial_panel_size + delta_mouse_position
		resized_size = resized_size.max(MIN_SIZE)
		
		var resized_pos: Vector2 = _initial_panel_position - (resized_size - _initial_panel_size)
		
		var code_edit: CodeEdit = get_parent() as CodeEdit
		if code_edit:
			if resized_pos.x < 0.0:
				resized_size.x += resized_pos.x
				resized_pos.x = 0.0
			if resized_pos.y < 0.0:
				resized_size.y += resized_pos.y
				resized_pos.y = 0.0
		
		sub_viewport.size = resized_size
		
		size = resized_size
		position = _initial_panel_position - (resized_size - _initial_panel_size)
		
		_last_floating_panel_size = size
		_last_floating_panel_pos = position
	
	elif _in_move:
		var moved_pos: Vector2 = _initial_panel_position - delta_mouse_position
		
		if current_shader_code_editor:
			moved_pos = moved_pos.clamp(Vector2.ZERO, _get_current_max_pos())
		
		position = moved_pos
		
		_last_floating_panel_pos = position

func _get_current_max_size() -> Vector2:
	return current_shader_code_editor.size - Vector2(
			current_shader_code_editor.get_v_scroll_bar().size.x,
			current_shader_code_editor.get_h_scroll_bar().size.y
	)

func _get_current_max_pos() -> Vector2:
	return current_shader_code_editor.size - (
		size + Vector2(
			current_shader_code_editor.get_v_scroll_bar().size.x,
			current_shader_code_editor.get_h_scroll_bar().size.y
	))

func resize_to_editor_shape() -> void:
	var max_size: Vector2 = _get_current_max_size()
	if max_size.x <= 0.0: return
	
	if max_size < MIN_SIZE:
		#TODO: Add a collapsing feature if the remaining space in the shader code editor is too small
		pass
	
	var new_size: Vector2 = size.clamp(MIN_SIZE, max_size)
	if size != new_size:
		sub_viewport.size = new_size
		size = new_size
	
	var max_pos: Vector2 = _get_current_max_pos()
	position = position.clamp(Vector2.ZERO, max_pos)
#endregion

#region Shader Preview Core
func _show_error(message: String) -> void:
	label.text = message
	preview.material = null
	preview.texture = _initial_texture

func update_shader_preview(text: String, current_line_index: int, selected_material: ShaderMaterial) -> void:
	label.text = ""
	var generated_preview_result: Dictionary = _generate_preview_shader(text, current_line_index)
	if not generated_preview_result["success"]:
		return
	
	var shader_content := Shader.new()
	shader_content.code = generated_preview_result["generated_code"]

	# A new material is created to not overwrite the node's actual material
	var preview_material = ShaderMaterial.new()
	preview_material.shader = shader_content

	if not selected_material or not _match_uniforms(selected_material, preview_material):
		_show_error("A node using the shader must be selected.")
		return
		
	_sync_material_parameters(selected_material, preview_material)

	if _mode_3d:
		preview.material = null
		preview.texture = viewport_texture
		preview_mesh.set_surface_override_material(0, preview_material)
	else:
		preview.material = preview_material
	
func update_texture(node: Node) -> void:
	if node and "texture" in node and node.texture:
		preview.texture = node.texture
	else:
		preview.texture = _initial_texture

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

func _generate_preview_shader(original_code: String, line_index: int) -> Dictionary:
	var result: Dictionary = {"success": false, "generated_code": ""}
	
	var shader_type := _get_shader_type(original_code)
	if shader_type == "error":
		_show_error("No [b]shader_type[/b] statement found on shader")
		return result
	if shader_type.is_empty():
		_show_error("Preview only supports [b]canvas_item[/b] and [b]spatial[/b] shaders")
		return result
	_mode_3d = shader_type == "spatial"
	
	var lines = original_code.split("\n")
	var enclosing_function = _get_enclosing_function(lines, line_index)
	
	if enclosing_function != "fragment":
		_show_error("Preview only supports assignments in the [b]fragment()[/b] function")
		return result
	
	if line_index >= lines.size():
		_show_error("Something weird happened... Try restarting the plugin.")
		return result
		
	var stmt = _find_statement(lines, line_index)
	
	if stmt.is_empty():
		_show_error("The selected line needs to be an assignment.")
		return result
		
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
		return result
	
	injection = assignments[type] % var_name
	
	truncated_lines.append(injection)
	
	# Close parantheses
	var full_truncated_text = "\n".join(truncated_lines)
	var open_braces = full_truncated_text.count("{")
	var closed_braces = full_truncated_text.count("}")
	var needed_closures = open_braces - closed_braces
	
	for i in range(needed_closures):
		full_truncated_text += "\n}"
	
	result["success"] = true
	result["generated_code"] = full_truncated_text
	return result

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
#endregion
