@tool
extends EditorPlugin

var dock: EditorDock = null
var shader_code_editor: CodeEdit = null

func _enable_plugin():
	pass


func _disable_plugin():
	# Remove autoloads here.
	pass


func _enter_tree():
	var dock_scene = preload("res://addons/gdshader-partial-preview/partial_preview_dock.tscn").instantiate()
	
	# Add new dock
	dock = EditorDock.new()
	
	dock.add_child(dock_scene)
	dock.title = "Shader Preview"
	dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	
	add_dock(dock)
	
	get_shader_code_edit()
	# TODO: find a way to update the shader_code_editor when new shader added or shader changed
		
func get_shader_code_edit() -> void:
	# Currently there's no public API for getting the Shader Editor,
	# so I get the internal ShaderEditor class to find it.
	var base_control = EditorInterface.get_base_control()
	var shader_editors = base_control.find_children("*", "ShaderEditor", true, false)
	
	for editor in shader_editors:
		if editor:
			var code_edits = editor.find_children("*", "CodeEdit", true, false)
			for ce in code_edits:
				if ce.is_visible_in_tree():
					shader_code_editor = ce
	shader_code_editor = null

func _exit_tree():
	remove_dock(dock)
	dock.queue_free()
