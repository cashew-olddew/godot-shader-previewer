@tool
extends EditorPlugin

var dock: EditorDock = null
var dock_scene: ShaderLinePreviewerDock = null
var shader_code_editor: CodeEdit = null
var visual_shader_editor: GraphEdit = null
var code_editor_parent: TabContainer = null
var selected_node: Node = null
var selected_visual_node_id := ""

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

func _get_current_text() -> String:
	if shader_code_editor:
		return shader_code_editor.text
	if visual_shader_editor:
		return visual_shader_editor.get_meta("code_editor").text
	return ""

func _get_current_caret_line() -> int:
	if shader_code_editor:
		return shader_code_editor.get_caret_line()
	if visual_shader_editor and selected_visual_node_id:
		var text := _get_current_text()
		var lines := text.split("\n")
		for i in lines.size():
			if lines[i].contains("n_out%sp0 = " % [selected_visual_node_id]):
				return i
		for i in lines.size():
			for keys in ShaderLinePreviewerDock.BUILTINS:
				for key in keys:
					if lines[i].contains("%s = " % [key]):
						# special line number for "just use original shader"
						return -2
	return -1

func _process(delta):
	if not shader_code_editor and not visual_shader_editor:
		return
		
	var current_text = _get_current_text()
	var current_caret = _get_current_caret_line()
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
	shader.code = _get_current_text()
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
	var caret_line_index = _get_current_caret_line()
	var shader_text: String = _get_current_text()
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

	if not active_editor:
		return
	var as_visual := active_editor.get_class() == "VisualShaderEditor"
	var code_edits = active_editor.find_children("*", "CodeEdit", true, false)
	if code_edits.is_empty():
		return
		
	var ce = code_edits[0]
	var target_control = ce
	var target_control_local = shader_code_editor
	if as_visual:
		target_control = code_editor_parent.find_children("*", "GraphEdit", true, false)[0]
		target_control_local = visual_shader_editor
		target_control.set_meta("code_editor", ce)
	if target_control_local != target_control:
		if target_control_local:
			target_control_local.resized.disconnect(_on_shader_editor_resize)
		
		if as_visual:
			shader_code_editor = null
			visual_shader_editor = target_control
			visual_shader_editor.node_selected.connect(_on_visual_node_selected)
		else:
			shader_code_editor = target_control
			visual_shader_editor = null
		
		target_control.resized.connect(_on_shader_editor_resize)
		
		dock_scene.current_shader_code_editor = shader_code_editor
		dock_scene.current_visual_shader_editor = visual_shader_editor
		
		if not _is_floating: return
		
		if dock_scene.get_parent() == null:
			shader_code_editor.add_child(dock_scene)
		else:
			dock_scene.reparent(target_control)
		
		dock_scene.set_floating_mode(true)
		dock_scene.show()

func _on_shader_editor_resize() -> void:
	if not _is_floating: return
	
	dock_scene.resize_to_editor_shape()

func _on_visual_node_selected(node: GraphNode) -> void:
	selected_visual_node_id = node.name
	# the code is only updated when the preview text is viewed; so we have to force it
	visual_shader_editor.get_meta("code_editor").text = _get_selected_node_surface_material().shader.code

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
	var shader_editors = base_control.find_children("*", "ShaderEditor", true, false)
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

func _on_floating_requested() -> void:
	var new_parent: Node
	if not _is_floating:
		if shader_code_editor:
			new_parent = shader_code_editor
		elif visual_shader_editor:
			new_parent = visual_shader_editor
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
