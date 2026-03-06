@tool
extends Panel
class_name FloatingPreviewPanel

@export var resize_handle : TextureRect
@export var dock_container: Control

var _resize_drag: bool = false
var _resize_start_mouse: Vector2
var _resize_start_size: Vector2

const MIN_PREVIEW_SIZE = Vector2(120, 120)
const MAX_PREVIEW_SIZE = MIN_PREVIEW_SIZE * 4
const EDITOR_MARGIN	 = 18.0

var _move_drag: bool = false
var _move_start_mouse: Vector2
var _move_start_position: Vector2

func _ready() -> void:
	resize_handle.modulate = Color.WHITE
	resize_handle.gui_input.connect(_on_resize_handle_input.bind(self))

func inject_dock(dock_scene: Control) -> void:
	if dock_scene.get_parent():
		dock_scene.get_parent().remove_child(dock_scene)
	dock_container.add_child(dock_scene)
	dock_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func eject_dock(dock_scene: Control, target: Control) -> void:
	if dock_scene.get_parent() == dock_container:
		dock_container.remove_child(dock_scene)
		target.add_child(dock_scene)
		dock_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _on_resize_handle_input(event: InputEvent, panel: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resize_drag = event.pressed
		if _resize_drag:
			_resize_start_mouse = panel.get_global_mouse_position()
			_resize_start_size = Vector2(
				abs(panel.offset_right - panel.offset_left),
				abs(panel.offset_bottom - panel.offset_top)
			)

	if event is InputEventMouseMotion and _resize_drag:
		var delta = panel.get_global_mouse_position() - _resize_start_mouse
		# Can be a editor parameter
		# --- Non uniform resize ---
		#var new_size = (_resize_start_size - delta).max(MIN_PREVIEW_SIZE)
		# --- Uniform resize ---
		var avg_delta = (delta.x + delta.y) / 2.0
		var new_size = _resize_start_size - Vector2(avg_delta, avg_delta)
		new_size = clamp(new_size, MIN_PREVIEW_SIZE, MAX_PREVIEW_SIZE)
		panel.offset_left = panel.offset_right - new_size.x
		panel.offset_top = panel.offset_bottom - new_size.y

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_move_drag = true
			_move_start_mouse = get_global_mouse_position()
			_move_start_position = position
		else:
			_move_drag = false

	if event is InputEventMouseMotion and _move_drag:
		var delta = _move_start_mouse - get_global_mouse_position()
		var new_pos = _move_start_position - delta

		var parent_size = get_parent_control().size if get_parent_control() else get_viewport_rect().size
		new_pos = new_pos.clamp(
			Vector2(EDITOR_MARGIN, EDITOR_MARGIN),
			parent_size - size - Vector2(EDITOR_MARGIN, EDITOR_MARGIN)
		)

		position = new_pos
