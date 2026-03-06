@tool
extends EditorPlugin

var dock: EditorDock = null
var dock_scene: ShaderLinePreviewerDock = null
var shader_code_editor: CodeEdit = null
var code_editor_parent: TabContainer = null
var selected_node: Node = null

var bottom_panel : Node = null
var _floating_preview: Control = null
var _current_mode: String = ""

var _last_text: String = ""
var _last_caret: int = -1
var _last_material_params: Dictionary = {}

# When engine starts, the plugin enters tree before the TextShaderEditor.
# For this reason we try a few times to link them
var _try_load_timer: Timer = null
var _load_tries_left: int = 60 # Try for 2 minutes (60 times. One try takes 2 seconds.)

func _enter_tree():
	dock_scene = preload("res://addons/shader-previewer/shader_previewer_dock.tscn").instantiate()
	# Add new dock
	var icon_tex = preload("res://addons/shader-previewer/assets/shader.svg")
	
	dock = EditorDock.new()
	dock.add_child(dock_scene)
	dock.title = "Shader Preview"
	dock.dock_icon = icon_tex
	dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	add_dock(dock)
	
	_try_load_timer = Timer.new()
	add_child(_try_load_timer)
	
	_try_load_timer.one_shot = true
	_try_load_timer.timeout.connect(initialize_shader_code_edit)
	
	initialize_shader_code_edit()
		
	EditorInterface.get_selection().selection_changed.connect(_on_node_selection_changed)
	# A node might already be selected when plugin enters tree
	_on_node_selection_changed()
	
	var base = get_editor_interface().get_base_control()
	base.child_entered_tree.connect(_on_tree_changed)
	base.child_exiting_tree.connect(_on_tree_changed)
	_on_tree_changed(base)

func _process(delta):
	if not shader_code_editor:
		return
		
	var current_text = shader_code_editor.text
	var current_caret = shader_code_editor.get_caret_line()
	var current_params = _snapshot_material_params()
	
	# Only update when something actually changed
	if current_text == _last_text and current_caret == _last_caret and current_params == _last_material_params:
		return
	
	_last_text = current_text
	_last_caret = current_caret
	_last_material_params = current_params
	_on_preview_try()

func _snapshot_material_params() -> Dictionary:
	if not selected_node or not "material" in selected_node:
		return {}
	var mat = selected_node.material as ShaderMaterial
	if not mat or not mat.shader:
		return {}
	var result := {}
	for p in mat.shader.get_shader_uniform_list():
		var val = mat.get_shader_parameter(p["name"])
		result[p["name"]] = val
	return result
	
func _on_preview_try() -> void:
	var caret_line_index = shader_code_editor.get_caret_line()
	var shader_text: String = shader_code_editor.text
	var selected_material = null
	if selected_node and "material" in selected_node:
		selected_material = selected_node.material as ShaderMaterial
	dock_scene.update_shader_preview(shader_text, caret_line_index, selected_material)

func _on_node_selection_changed() -> void:
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	selected_node = selected_nodes[0] if not selected_nodes.is_empty() else null
	_last_material_params = {} # Force update on selection change
	if dock_scene:
		dock_scene.update_texture(selected_node)

func _update_active_shader_editor() -> void:
	if not code_editor_parent:
		return

	var current_tab_index = code_editor_parent.current_tab
	var active_editor = code_editor_parent.get_tab_control(current_tab_index)

	if active_editor and active_editor.get_class() == "TextShaderEditor":
		var code_edits = active_editor.find_children("*", "CodeEdit", true, false)
		if code_edits.is_empty():
			return
			
		var ce = code_edits[0]
		if shader_code_editor != ce:
			shader_code_editor = ce

func update_shader_editor_reference(_tab: int) -> void:
	if not code_editor_parent:
		initialize_shader_code_edit()
	_update_active_shader_editor()

func initialize_shader_code_edit() -> void:
	# Currently there's no public API for getting the Shader Editor,
	# so I get the internal ShaderEditor class to find it.
	var base_control = EditorInterface.get_base_control()
	_initialize_bottom_panel_tab_bar(base_control)
	var shader_editors = base_control.find_children("*", "TextShaderEditor", true, false)
	if shader_editors.size() == 0:
		if _load_tries_left > 0:
			_try_load_timer.start(2)
			_load_tries_left -= 1
		return
	
	# The parent of the ShaderEditors is a TabContainer.
	# We need it to track signals emitted by tab switches or clicks
	var parent = shader_editors[0].get_parent()
	
	if parent is TabContainer:
		code_editor_parent = parent
		if not parent.tab_selected.is_connected(update_shader_editor_reference):
			parent.tab_selected.connect(update_shader_editor_reference)

	_update_active_shader_editor()

#region Auto Dock Expand/Collapse And Floating Preview
func _initialize_bottom_panel_tab_bar(base_control : Control) -> void:
	var bottom_panels = base_control.find_children("*", "EditorBottomPanel", true, false)
	if bottom_panels.is_empty():
		return # don't need to do the retry strategy because initialize_shader_code_edit already handles it

	bottom_panel = bottom_panels[0]
	var tab_bars = bottom_panel.find_children("*", "TabBar", false, false)
	if tab_bars.is_empty():
		return
	var tab_bar = tab_bars[0] as TabBar
	
	if not tab_bar.tab_selected.is_connected(_on_bottom_tab_selected):
		tab_bar.tab_selected.connect(_on_bottom_tab_selected)
	
	_on_bottom_tab_selected(tab_bar.current_tab)

func _on_bottom_tab_selected(tab: int) -> void:
	if not bottom_panel or not dock:
		return
	var current_tab = bottom_panel.get_child(tab)
	if current_tab and current_tab.get_class() == "EditorDock" and "Shader" in current_tab.name:
		dock.make_visible()
	else:
		dock.close()

func get_shader_editor_mode() -> String:
	var base = get_editor_interface().get_base_control()
	var editors = base.find_children("Shader Editor", "", true, false)
	if editors.is_empty():
		return "not_found"
	
	var path = str(editors[0].get_path())
	
	if "WindowWrapper" in path:
		return "floating"
	elif "EditorBottomPanel" in path:
		return "docked"
	else:
		return "unknown"

func _on_tree_changed(_node: Node):
	await get_tree().process_frame
	var mode = get_shader_editor_mode()
	if mode == _current_mode:
		return
	_current_mode = mode
	_apply_mode(mode)
	print("Shader editor mode: ", mode)

func _apply_mode(mode: String) -> void:
	match mode:
		"floating":
			dock.close()
			_inject_floating_preview()
		"docked":
			_remove_floating_preview()
		_:
			dock.close()
			_remove_floating_preview()

func _inject_floating_preview() -> void:
	_remove_floating_preview()

	var base = get_editor_interface().get_base_control()
	var editors = base.find_children("*", "TextShaderEditor", true, false)
	if editors.is_empty():
		return
	var code_edits = editors[0].find_children("*", "CodeEdit", true, false)
	if code_edits.is_empty():
		return
	var code_edit = code_edits[0]
	
	code_edit.clip_contents = true

	_floating_preview = preload("res://addons/shader-previewer/shader_previewer_floating.tscn").instantiate()
	_floating_preview.inject_dock(dock_scene)
	code_edit.add_child(_floating_preview)

func _remove_floating_preview() -> void:
	if _floating_preview and is_instance_valid(_floating_preview):
		_floating_preview.eject_dock(dock_scene, dock)
		_floating_preview.queue_free()
	_floating_preview = null
#endregion

func _exit_tree():
	remove_dock(dock)
	if dock:
		dock.queue_free()
	if _try_load_timer:
		_try_load_timer.queue_free()
	
