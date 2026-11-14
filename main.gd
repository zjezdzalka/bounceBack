extends Node2D
# The level is built in the editor (see main.tscn). This script only
# updates the HUD and fades blocks that aren't on the player's z-layer.

@onready var player = $Player
@onready var z_label: Label = $HUD/ZLabel

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.55, 0.75, 0.95))
	player.z_changed.connect(_on_player_z_changed)
	_on_player_z_changed(player.z)

func _on_player_z_changed(z: int) -> void:
	z_label.text = "Z-index: %d   (W = forward, S = back)" % z
	get_tree().call_group("blocks", "show_for_layer", z)
