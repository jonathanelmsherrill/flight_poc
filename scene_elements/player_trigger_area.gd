class_name PlayerTriggerArea
extends Area3D

signal player_entered(player: Player)

## When enabled, entering the volume is not enough: the player must also be
## standing on a floor. Players who enter while airborne are checked until
## they land or leave the volume.
@export var must_land := false

var _players_inside: Array[Player] = []
var _triggered_players: Array[Player] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if not must_land:
		return

	for player in _players_inside:
		_try_trigger(player)


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if not player or not player.is_in_group(&"player"):
		return

	if not _players_inside.has(player):
		_players_inside.append(player)
	_try_trigger(player)


func _on_body_exited(body: Node3D) -> void:
	var player := body as Player
	if player:
		_players_inside.erase(player)
		_triggered_players.erase(player)


func _try_trigger(player: Player) -> void:
	if _triggered_players.has(player) or (must_land and not player.is_on_floor()):
		return

	_triggered_players.append(player)
	player_entered.emit(player)
