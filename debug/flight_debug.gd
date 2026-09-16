class_name FlightDebug
extends RefCounted

## Creates and updates text readouts in a shared debug container. Handles map
## to label node names, so any caller can introduce a new readout on demand.
var container: Container
var labels: Dictionary[StringName, Label] = {}


func _init(debug_container: Container) -> void:
	container = debug_container


func submit(handle: StringName, text: String) -> void:
	var label := labels.get(handle) as Label
	if not label:
		label = container.get_node_or_null(NodePath(String(handle))) as Label
		if not label:
			label = Label.new()
			label.name = String(handle)
			container.add_child(label)
		labels[handle] = label
	label.text = text
