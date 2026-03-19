@tool
extends EditorPlugin

var dock: EditorDock = null
var dock_scene: ShaderLinePreviewerDock = null
var shader_code_editor: CodeEdit = null
var code_editor_parent: TabContainer = null
var selected_node: Node = null
var bottom_panel : Node = null

var _is_floating: bool = false

var _last_text: String = ""
var _last_caret: int = -1
var _last_material_params: Dictionary = {}

# When engine starts, the plugin enters tree before the TextShaderEditor.
# For this reason we try a few times to link them
var _try_load_timer: Timer = null
var _load_tries_left: int = 60 # Try for 2 minutes (60 times. One try takes 2 seconds.)

var icon_tex = preload("res://addons/shader-previewer/assets/shader.svg")

func _enter_tree():
	dock_scene = preload("res://addons/shader-previewer/shader_previewer_dock.tscn").instantiate()
	dock_scene.floating_requested.connect(_on_floating_requested)
	
	# Floating by default
	#_is_floating = true
	#dock_scene.set_floating_mode(true)
	
	# Dock by default
	dock = _create_dock()
	dock.add_child(dock_scene)
	
	dock_scene.set_floating_mode(_is_floating)
	
	_try_load_timer = Timer.new()
	add_child(_try_load_timer)
	
	_try_load_timer.one_shot = true
	_try_load_timer.timeout.connect(initialize_shader_code_edit)
	
	initialize_shader_code_edit()
		
	EditorInterface.get_selection().selection_changed.connect(_on_node_selection_changed)
	# A node might already be selected when plugin enters tree
	_on_node_selection_changed()

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

func _create_dock() -> EditorDock:
	var new_dock: EditorDock = EditorDock.new()
	new_dock.title = "Shader Preview"
	new_dock.dock_icon = icon_tex
	new_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	add_dock(new_dock)
	
	new_dock.resized.connect(_on_dock_resized)
	
	return new_dock

func _get_selected_node_surface_material() -> ShaderMaterial:
	if not "mesh" in selected_node:
		return null
	
	var surface_count: int = selected_node.mesh.get_surface_count()
	
	var shader: Shader = Shader.new()
	shader.code = shader_code_editor.text
	var code_uniforms := shader.get_shader_uniform_list()
	
	for i in surface_count:
		var surface_material := selected_node.get_active_material(i) as ShaderMaterial
		if not surface_material:
			continue
		var surface_uniforms := surface_material.shader.get_shader_uniform_list()
		if surface_uniforms == code_uniforms:
			return surface_material
	return null

func _snapshot_material_params() -> Dictionary:
	if not selected_node or (not "material" in selected_node and not selected_node.has_method("get_active_material")):
		return {}
	var mat = selected_node.material as ShaderMaterial if "material" in selected_node else _get_selected_node_surface_material()
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
	if selected_node and ("material" in selected_node or selected_node.has_method("get_active_material")):
		selected_material = (selected_node.material if "material" in selected_node else _get_selected_node_surface_material()) as ShaderMaterial
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
			if shader_code_editor:
				shader_code_editor.resized.disconnect(_on_shader_editor_resize)
			
			shader_code_editor = ce
			shader_code_editor.resized.connect(_on_shader_editor_resize)
			
			dock_scene.current_shader_code_editor = shader_code_editor
			
			if not _is_floating: return
			
			if dock_scene.get_parent() == null:
				shader_code_editor.add_child(dock_scene)
			else:
				dock_scene.reparent(shader_code_editor)
			
			dock_scene.set_floating_mode(true)
			dock_scene.show()

func _on_shader_editor_resize() -> void:
	if not _is_floating: return
	
	dock_scene.resize_to_editor_shape()

func _on_dock_resized() -> void:
	dock_scene.sub_viewport.size = dock.size

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

#region Auto Dock Expand/Collapse
func _initialize_bottom_panel_tab_bar(base_control : Control) -> void:
	var bottom_panels = base_control.find_children("*", "EditorBottomPanel", true, false)
	if bottom_panels.is_empty():
		return
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
	if tab == -1:
		dock.close()
		return
	
	var current_tab = bottom_panel.get_child(tab)
	if current_tab and current_tab.get_class() == "EditorDock" and "Shader" in current_tab.name:
		dock.make_visible()
	else:
		dock.close()
#endregion
func _on_floating_requested() -> void:
	var new_parent: Node
	if not _is_floating:
		if shader_code_editor:
			new_parent = shader_code_editor
		else:
			new_parent = get_editor_interface().get_base_control()
			dock_scene.hide()
	
	else:
		dock = _create_dock()
		new_parent = dock
	
	if dock_scene.get_parent():
		dock_scene.reparent(new_parent)
	else:
		new_parent.add_child(dock_scene)
	
	_is_floating = not _is_floating
	
	if _is_floating and dock:
		remove_dock(dock)
		dock.queue_free()
		dock = null
	
	dock_scene.set_floating_mode(_is_floating)

func _exit_tree():
	dock_scene.queue_free()
	if dock:
		remove_dock(dock)
		dock.queue_free()
	if _try_load_timer:
		_try_load_timer.queue_free()
