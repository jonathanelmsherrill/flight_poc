class_name DebugContainer
extends VBoxContainer

var labels: Dictionary[StringName, Label] = {}

## Show Debug message
## handle - title of readout
## text - value of readout
func submit(handle: StringName, text: String) -> void:
	var label := labels.get(handle) as Label
	if not label:
		label = Label.new()
		label.name = String(handle)
		add_child(label)
		labels[handle] = label
	label.text = handle + ": " + text 