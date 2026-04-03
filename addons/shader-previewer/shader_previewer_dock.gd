@tool
extends PanelContainer
class_name ShaderLinePreviewerDock

signal floating_requested

var generator := ShaderPreviewGenerator.new()

@onready var preview: TextureRect = %Preview

@onready var controls_container: Control = %ControlsContainer

@export var viewport_texture: ViewportTexture
@export var preview_mesh: MeshInstance3D
@export var label: RichTextLabel

@onready var top_left_separator: Control = %TopLeftSeparator
@export var move_view_button: Button
@export var floating_button: Button
@onready var _button_material: ShaderMaterial = floating_button.material

#region 3D Related
@export_category("3D Related")
@onready var sub_viewport: SubViewport = %SubViewport

@onready var mesh_instance_3d: MeshInstance3D = %MeshInstance3D
@onready var vertical_anchor: Node3D = %VerticalAnchor
@onready var lateral_anchor: Node3D = %LateralAnchor

@export var material_for_3d: ShaderMaterial

@onready var _3d_controls_container: Control = %"3dControlsContainer"

@onready var directional_light_3d_1: DirectionalLight3D = %DirectionalLight3D1
@onready var directional_light_3d_2: DirectionalLight3D = %DirectionalLight3D2

# Buttons to switch to different shapes
@export var sphere_shape_button: Button
@export var cube_shape_button: Button
@export var quad_shape_button: Button

# Buttons to turn on/off lights
@export var light_1_button: Button # Front right light
@export var light_2_button: Button # Bottom light

# Will limit rotation to defined boundaries
var current_shape_has_v_limit: bool = true
var current_shape_v_limit := Vector2(-PI / 2.0, PI / 2.0)

var current_shape_has_h_limit: bool = false
var current_shape_h_limit := Vector2(-PI / 2.0, PI / 2.0)

# Define the rotation limit for each shape horizontaly and verticaly
const sphere_rotation_limit := Vector2(0.0, PI / 2.0)
const cube_rotation_limit := Vector2(0.0, PI / 2.0)
const quad_rotation_limit := Vector2(PI / 2.2, PI / 2.2)

# Define the start rotation for each shape horizontaly and verticaly
const sphere_start_rotation := Vector2(-0.5, 0.32)
const cube_start_rotation := Vector2(-0.5, 0.32)
const quad_start_rotation := Vector2.ZERO

#endregion

var _initial_texture: Texture2D = null
var _mode_3d := false

var _is_floating: bool = false
var current_shader_code_editor: CodeEdit
var _should_hide_buttons: bool = false # Used to prevent hiding during resize/move

func _ready():
	_initialize_theme_color()
	
	_initial_texture = preview.texture
	
	controls_container.hide()
	_3d_controls_container.hide()
	_set_sphere_shape() # Initialize preview 3d rotations
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	move_view_button.button_down.connect(_on_move_button_down)
	move_view_button.button_up.connect(_on_move_button_up)
	
	floating_button.pressed.connect(func(): floating_requested.emit())
	
	sphere_shape_button.pressed.connect(_set_sphere_shape)
	cube_shape_button.pressed.connect(_set_cube_shape)
	quad_shape_button.pressed.connect(_set_quad_shape)
	
	light_1_button.pressed.connect(_switch_light_1)
	light_2_button.pressed.connect(_switch_light_2)
	
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
		move_view_button.show()
		size = _last_floating_panel_size
		sub_viewport.size = _last_floating_panel_size
		set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 20)
		
		# Note: These 2 await allow us to wait for the code editor to get its true size
		#       and prevent wrong positioning due to local cords. If a better way to find
		#       if the CodeEditor finished positioning in the layers can be found it replace
		#       this fix
		var old_visible_state: bool = visible
		visible = false # Fix the ghosting effect on CodeEditor switch caused by the frame awaiting
		await get_tree().process_frame
		await get_tree().process_frame
		visible = old_visible_state
		
		if _last_floating_panel_pos.x >= 0.0:
			position = _last_floating_panel_pos
		
		# This prevent the preview to keep a now outside old size/pos
		if current_shader_code_editor: resize_to_editor_shape()
	else:
		move_view_button.hide()

func _on_mouse_entered() -> void:
	controls_container.show()
	_should_hide_buttons = false

func _on_mouse_exited() -> void:
	if _in_resize or _in_move:
		_should_hide_buttons = true
		return
	
	controls_container.hide()

#region 3D Controls
func _init_shape_rotation_and_limits(initial_rotation: Vector2, limit: Vector2) -> void:
	lateral_anchor.rotation.y = initial_rotation.x
	vertical_anchor.rotation.x = initial_rotation.y
	
	current_shape_has_h_limit = limit.x != 0.0
	current_shape_h_limit = Vector2(-limit.x, limit.x)
	
	current_shape_has_v_limit = limit.y != 0.0
	current_shape_v_limit = Vector2(-limit.y, limit.y)

func _set_sphere_shape() -> void:
	sphere_shape_button.button_pressed = true
	cube_shape_button.button_pressed = false
	quad_shape_button.button_pressed = false
	
	mesh_instance_3d.mesh = SphereMesh.new()
	
	_init_shape_rotation_and_limits(sphere_start_rotation, sphere_rotation_limit)

func _set_cube_shape() -> void:
	sphere_shape_button.button_pressed = false
	cube_shape_button.button_pressed = true
	quad_shape_button.button_pressed = false
	
	var new_box_mesh := BoxMesh.new()
	new_box_mesh.size = Vector3.ONE * 0.75
	mesh_instance_3d.mesh = new_box_mesh
	
	_init_shape_rotation_and_limits(cube_start_rotation, cube_rotation_limit)

func _set_quad_shape() -> void:
	sphere_shape_button.button_pressed = false
	cube_shape_button.button_pressed = false
	quad_shape_button.button_pressed = true
	
	mesh_instance_3d.mesh = QuadMesh.new()
	
	_init_shape_rotation_and_limits(quad_start_rotation, quad_rotation_limit)

func _clamp_3d_preview_rotation() -> void:
	if current_shape_has_v_limit: vertical_anchor.rotation.x = clamp(vertical_anchor.rotation.x, current_shape_v_limit.x, current_shape_v_limit.y)
	if current_shape_has_h_limit: lateral_anchor.rotation.y = clamp(lateral_anchor.rotation.y, current_shape_h_limit.x, current_shape_h_limit.y)

func _switch_light_1() -> void:
	directional_light_3d_1.visible = not directional_light_3d_1.visible

func _switch_light_2() -> void:
	directional_light_3d_2.visible = not directional_light_3d_2.visible
#endregion

#region Resize, Move and Rotation

# Rotation properties
var _last_mouse_position: Vector2

# Floating Resize and Move properties
const MIN_SIZE := Vector2(150.0, 150.0)

var _in_resize: bool = false
var _in_move: bool = false

var _current_resize_mode: ResizeMode

var _initial_mouse_position: Vector2
var _initial_panel_size: Vector2
var _initial_panel_position: Vector2

var _last_floating_panel_size: Vector2
var _last_floating_panel_pos := Vector2(-1, -1)

func _on_move_button_down() -> void:
	if not _is_floating: return
	
	_in_move = true
	_initial_mouse_position = get_global_mouse_position()
	_initial_panel_position = position

func _on_move_button_up() -> void:
	if not _is_floating: return
	
	_in_move = false
	if _should_hide_buttons:
		controls_container.hide()
		_should_hide_buttons = false

# Resize Mode BitMask
enum ResizeMode {
	None = 0,
	Left = 1,
	Right = 2,
	Top = 4,
	Bot = 8
}

const border_resize_margin: float = 16
func _get_mouse_resize_mode(mouse_pos: Vector2) -> ResizeMode:
	var on_left: bool   = mouse_pos.x <= border_resize_margin
	var on_right: bool  = mouse_pos.x >= size.x - border_resize_margin
	var on_top: bool    = mouse_pos.y <= border_resize_margin
	var on_bottom: bool = mouse_pos.y >= size.y - border_resize_margin
	
	var mode_mask: ResizeMode = ResizeMode.None
	if on_left: mode_mask |= ResizeMode.Left
	if on_right: mode_mask |= ResizeMode.Right
	if on_top: mode_mask |= ResizeMode.Top
	if on_bottom: mode_mask |= ResizeMode.Bot
	
	return mode_mask

func _update_resize_cursor(mode: int) -> void:
	match mode:
		ResizeMode.Left, ResizeMode.Right:
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		
		ResizeMode.Top, ResizeMode.Bot:
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		
		ResizeMode.Left | ResizeMode.Top, ResizeMode.Right | ResizeMode.Bot:
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		
		ResizeMode.Right | ResizeMode.Top, ResizeMode.Left | ResizeMode.Bot:
			mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
		
		_:
			mouse_default_cursor_shape = Control.CURSOR_ARROW

func _gui_input(event: InputEvent) -> void:
	## Gather events
	var mouse_button := event as InputEventMouseButton
	var mouse_move := event as InputEventMouseMotion
	
	## Floating section
	if _is_floating:
		if mouse_button and mouse_button.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			if not mouse_button.pressed:
				if _in_resize:
					_in_resize = false
					if _should_hide_buttons:
						controls_container.hide()
						_should_hide_buttons = false
			else:
				if get_viewport().gui_get_hovered_control() != self:
					return
				
				var resize_mode: ResizeMode = _get_mouse_resize_mode(mouse_button.position)
				if resize_mode != ResizeMode.None:
					_in_resize = true
					_current_resize_mode = resize_mode
					_initial_mouse_position = mouse_button.global_position
					_initial_panel_size = size
					_initial_panel_position = position
		
		if mouse_move:
			if not (_in_resize or _in_move):
				# Prevent changing cursor if we are hovering another UI element
				if get_viewport().gui_get_hovered_control() != self:
					mouse_default_cursor_shape = Control.CURSOR_ARROW
				else:
					var local_mouse_pos: Vector2 = mouse_move.position
					var resize_mode: ResizeMode = _get_mouse_resize_mode(local_mouse_pos)
					_update_resize_cursor(resize_mode)
			
			else:
				var delta_mouse_position: Vector2 = _initial_mouse_position - mouse_move.global_position
				if _in_resize:
					var new_size: Vector2 = _initial_panel_size
					var new_pos: Vector2 = _initial_panel_position
					
					# Horizontal
					if _current_resize_mode & ResizeMode.Left:
						new_size.x = maxf(_initial_panel_size.x + delta_mouse_position.x, MIN_SIZE.x)
						new_pos.x = _initial_panel_position.x - (new_size.x - _initial_panel_size.x)
					elif _current_resize_mode & ResizeMode.Right:
						new_size.x = maxf(_initial_panel_size.x - delta_mouse_position.x, MIN_SIZE.x)
					
					# Vertical
					if _current_resize_mode & ResizeMode.Top:
						new_size.y = maxf(_initial_panel_size.y + delta_mouse_position.y, MIN_SIZE.y)
						new_pos.y = _initial_panel_position.y - (new_size.y - _initial_panel_size.y)
					elif _current_resize_mode & ResizeMode.Bot:
						new_size.y = maxf(_initial_panel_size.y - delta_mouse_position.y, MIN_SIZE.y)
					
					## Bounds (Min is 0)
					var max_pos: Vector2 = _get_current_max_pos()
					
					# Clamp minimal position to 0 and resize according to the difference
					new_size += new_pos.min(Vector2.ZERO)
					new_pos = new_pos.max(Vector2.ZERO)
					
					# Clamp maximal size to max_pos - the new preview pos to respect shader editor edges
					new_size = new_size.min(max_pos - new_pos)
					
					sub_viewport.size = new_size
					size = new_size
					position = new_pos
					
					_last_floating_panel_size = size
					_last_floating_panel_pos = position
				
				elif _in_move:
					var moved_pos: Vector2 = _initial_panel_position - delta_mouse_position
					
					if current_shader_code_editor:
						moved_pos = moved_pos.clamp(Vector2.ZERO, _get_current_max_pos() - size)
					
					position = moved_pos
					
					_last_floating_panel_pos = position
				return
	
	## Common 3D section
	if not _mode_3d: return
	
	# Detect mouse pressions and initiate preview motion
	if mouse_button:
		if mouse_button.button_index != MouseButton.MOUSE_BUTTON_LEFT: return
		
		if mouse_button.pressed: _last_mouse_position = get_global_mouse_position()
		
		return
	
	# Handle preview motion
	if mouse_move and mouse_move.button_mask == MouseButtonMask.MOUSE_BUTTON_MASK_LEFT:
		var new_mouse_pos: Vector2 = get_global_mouse_position()
		var scaled_mouse_diff: Vector2 = 0.01 * (new_mouse_pos - _last_mouse_position)
		_last_mouse_position = new_mouse_pos
		
		lateral_anchor.rotation.y += scaled_mouse_diff.x
		vertical_anchor.rotation.x += scaled_mouse_diff.y
		_clamp_3d_preview_rotation()

func _get_current_max_size() -> Vector2:
	return current_shader_code_editor.size - Vector2(
		current_shader_code_editor.get_v_scroll_bar().size.x,
		current_shader_code_editor.get_h_scroll_bar().size.y
	)

func _get_current_max_pos() -> Vector2:
	return current_shader_code_editor.size - Vector2(
		current_shader_code_editor.get_v_scroll_bar().size.x,
		current_shader_code_editor.get_h_scroll_bar().size.y
	)

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
	
	var max_pos: Vector2 = _get_current_max_pos() - size
	position = position.clamp(Vector2.ZERO, max_pos)
#endregion

#region Shader Preview Core
func _show_error(message: String) -> void:
	label.text = message
	_activate_2d_mode()

func _activate_2d_mode() -> void:
	_mode_3d = false
	preview.material = null
	preview.texture = _initial_texture
	
	_button_material.set_shader_parameter("contrast_mode", true)
	_3d_controls_container.hide()
	top_left_separator.hide()

func _activate_3d_mode() -> void:
	_mode_3d = true
	preview.material = material_for_3d
	
	_button_material.set_shader_parameter("contrast_mode", false)
	_3d_controls_container.show()
	top_left_separator.show()

func update_shader_preview(original_code: String, current_line_index: int, selected_material: ShaderMaterial) -> void:
	label.text = ""
	
	var generated_preview_result: Dictionary = generator.generate(original_code, current_line_index, selected_material)
	if not generated_preview_result["success"]:
		_show_error(generated_preview_result["error"])
		return
	
	var preview_material: ShaderMaterial = generated_preview_result["generated_material"]
	
	if generated_preview_result["mode_3d"]:
		_activate_3d_mode()
		preview_mesh.set_surface_override_material(0, preview_material)
	else:
		_activate_2d_mode()
		preview.material = preview_material

func update_texture(node: Node) -> void:
	if node and "texture" in node and node.texture:
		preview.texture = node.texture
	else:
		preview.texture = _initial_texture
#endregion
