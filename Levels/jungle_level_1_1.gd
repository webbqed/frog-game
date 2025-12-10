extends Node2D

@onready var player: CharacterBody2D = $player

func _on_killzone_player_fell(body: Node2D) -> void:
	if body == player:
		player.player_died()
