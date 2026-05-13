@tool
extends EditorPlugin

func _enter_tree():
	get_editor_interface().get_selection().connect("selection_changed", Callable(self, "_on_selection_changed"))

func _exit_tree():
	get_editor_interface().get_selection().disconnect("selection_changed", Callable(self, "_on_selection_changed"))

func _on_selection_changed():
	var selection = get_editor_interface().get_selection()
	var nodes = selection.get_selected_nodes()
	if nodes.size() == 0:
		return

	var camera = nodes[0]
	if camera is Camera3D:
		var editor_viewport = get_editor_interface().get_editor_viewport()
		# Alinha posição e rotação da câmera do editor
		editor_viewport.set_camera_transform(camera.get_global_transform())

		# Sincroniza FOV da câmera do editor com a Camera3D selecionada
		editor_viewport.fov = camera.fov
