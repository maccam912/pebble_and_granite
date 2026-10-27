class_name CurlModalFocus
extends RefCounted
## Keep Tab/Enter inside an in-game modal while its mouse backdrop is active.
var saved: Array = []
var previous_focus: WeakRef
var panel_mode := Control.FOCUS_BEHAVIOR_INHERITED

func open(panel: Control) -> void:
	if not saved.is_empty(): return
	var focused := panel.get_viewport().gui_get_focus_owner()
	previous_focus = weakref(focused) if focused != null else null
	panel_mode = panel.focus_behavior_recursive
	for child in panel.get_parent().get_children():
		if child is Control and child != panel:
			saved.append({"node": weakref(child), "mode": child.focus_behavior_recursive})
			child.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	panel.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	call_deferred("focus_first", weakref(panel))

func focus_first(reference: WeakRef) -> void:
	var panel = reference.get_ref()
	if not is_instance_valid(panel) or not panel.is_visible_in_tree(): return
	for child in panel.find_children("*", "Control", true, false):
		if child.is_visible_in_tree() and child.get_focus_mode_with_override() != Control.FOCUS_NONE:
			child.grab_focus()
			return

func close(panel: Control) -> void:
	for entry in saved:
		var control = entry.node.get_ref()
		if is_instance_valid(control): control.focus_behavior_recursive = entry.mode
	saved.clear()
	panel.focus_behavior_recursive = panel_mode
	if previous_focus != null:
		var focused = previous_focus.get_ref()
		if is_instance_valid(focused) and focused.is_inside_tree() and focused.is_visible_in_tree(): focused.grab_focus()
	previous_focus = null
