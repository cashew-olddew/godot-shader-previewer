@tool
extends EditorPlugin

var dock: EditorDock = null
var dock_scene: PartialPreviewDock = null
var shader_code_editor: CodeEdit = null
var code_editor_parent: TabContainer = null
var selected_node: Node = null

func _enable_plugin():
	pass

func _disable_plugin():
	pass

func _enter_tree():
	dock_scene = preload("res://addons/gdshader-partial-preview/partial_preview_dock.tscn").instantiate()
	
	# Add new dock
	dock = EditorDock.new()
	dock.add_child(dock_scene)
	dock.title = "Shader Preview"
	dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	add_dock(dock)
	
	initialize_shader_code_edit()
		
	EditorInterface.get_selection().selection_changed.connect(_on_node_selection_changed)
	# A node might already be selected when plugin enters tree
	_on_node_selection_changed()
	
func _on_preview_try() -> void:
	if not shader_code_editor:
		return

	var caret_line_index = shader_code_editor.get_caret_line()
	var shader_text: String = shader_code_editor.text
	var selected_material = null
	if selected_node and "material" in selected_node:
		selected_material = selected_node.material as ShaderMaterial
	dock_scene.update_shader_preview(shader_text, caret_line_index, selected_material)

func _on_node_selection_changed() -> void:
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	selected_node = selected_nodes[0] if not selected_nodes.is_empty() else null
	
	# Update preview on node swap.
	_on_preview_try()

func _update_code_editor_signals(new_code_editor: CodeEdit) -> void:
	if shader_code_editor and shader_code_editor.caret_changed.is_connected(_on_preview_try):
		shader_code_editor.caret_changed.disconnect(_on_preview_try)
	new_code_editor.caret_changed.connect(_on_preview_try)

func _disconnect_old_editor() -> void:
	if shader_code_editor and is_instance_valid(shader_code_editor):
		if shader_code_editor.caret_changed.is_connected(_on_preview_try):
			shader_code_editor.caret_changed.disconnect(_on_preview_try)
	shader_code_editor = null

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
			_disconnect_old_editor()
			
			shader_code_editor = ce
			shader_code_editor.caret_changed.connect(_on_preview_try)
				
	_on_preview_try()

func update_shader_editor_reference(_tab: int) -> void:
	if not code_editor_parent:
		initialize_shader_code_edit()
	_update_active_shader_editor()
	_on_preview_try()

func initialize_shader_code_edit() -> void:
	# Currently there's no public API for getting the Shader Editor,
	# so I get the internal ShaderEditor class to find it.
	var base_control = EditorInterface.get_base_control()
	var shader_editors = base_control.find_children("*", "TextShaderEditor", true, false)
	if shader_editors.size() == 0:
		return
	
	# The parent of the ShaderEditors is a TabContainer.
	# We need it to track signals emitted by tab switches or clicks
	var parent = shader_editors[0].get_parent()
	
	if parent is TabContainer:
		code_editor_parent = parent
		if not parent.tab_selected.is_connected(update_shader_editor_reference):
			parent.tab_selected.connect(update_shader_editor_reference)

	_update_active_shader_editor()

func _exit_tree():
	remove_dock(dock)
	dock.queue_free()
