extends Node
## Autoload "Game": wlasciciel stanu gry. UI czyta Game.state i slucha Events.

var state: FarmState


func _ready() -> void:
	new_game()


func new_game() -> void:
	state = FarmState.from_start_config(GameData.balance().get("start", {}))
	Events.resources_changed.emit()
