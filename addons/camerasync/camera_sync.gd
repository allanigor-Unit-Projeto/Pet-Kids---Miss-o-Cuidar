@tool
extends EditorPlugin

func _enter_tree():
    get_editor_interface().get_selection().connect("selection_changed", Callable(self, "_on_selection_changed"))

func _exit_tree():
    get_editor_interface().get_selection().disconnect("selection_changed", Callable(self, "_on_selection_changed"))

func _on_selection_changed():
    var selected = get_editor_interface().get_selection().get_selected_nodes()
    if selected.size() == 0:
        return

    var camera := selected[0]
    if camera is Camera3D:
        var editor_viewport = get_editor_interface().get_editor_viewport()
        editor_viewport.set_camera_transform(camera.get_global_transform())
