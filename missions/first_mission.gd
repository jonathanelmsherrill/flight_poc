class_name FirstMission
extends Node

signal mission_completed

@export var rock_tunnel: PlayerTriggerArea
@export var updraft: PlayerTriggerArea
@export var corvette_landing: PlayerTriggerArea

const OBJECTIVE_TEXT := [
	"Fly through the rock tunnel",
	"Enter the updraft on the far side",
	"Land on the moving corvette",
]

@onready var mission_title: Label = $CanvasLayer/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/Title
@onready var objective_labels: Array[Label] = [
	$CanvasLayer/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/RockTunnel,
	$CanvasLayer/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/Updraft,
	$CanvasLayer/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/CorvetteLanding,
]

var _current_objective := 0


func _ready() -> void:
	_connect_trigger(rock_tunnel, 0)
	_connect_trigger(updraft, 1)
	_connect_trigger(corvette_landing, 2)
	_update_objective_display()


func _connect_trigger(trigger: PlayerTriggerArea, objective_index: int) -> void:
	if not trigger:
		push_error("FirstMission is missing trigger %d." % objective_index)
		return
	trigger.player_entered.connect(_on_player_entered.bind(objective_index))


func _on_player_entered(_player: Player, objective_index: int) -> void:
	if objective_index != _current_objective:
		return

	_current_objective += 1
	_update_objective_display()
	if _current_objective == OBJECTIVE_TEXT.size():
		mission_completed.emit()


func _update_objective_display() -> void:
	var mission_is_complete := _current_objective == OBJECTIVE_TEXT.size()
	mission_title.text = "FIRST FLIGHT - COMPLETE" if mission_is_complete else "FIRST FLIGHT"
	mission_title.modulate = Color(0.55, 1.0, 0.65) if mission_is_complete else Color.WHITE

	for index in objective_labels.size():
		var label := objective_labels[index]
		if index < _current_objective:
			label.text = "[x] %s" % OBJECTIVE_TEXT[index]
			label.modulate = Color(0.55, 1.0, 0.65)
		elif index == _current_objective:
			label.text = ">  %s" % OBJECTIVE_TEXT[index]
			label.modulate = Color.WHITE
		else:
			label.text = "[ ] %s" % OBJECTIVE_TEXT[index]
			label.modulate = Color(0.62, 0.66, 0.72)

