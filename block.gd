@tool
extends StaticBody2D
# A solid rectangle you can place and edit in the Godot editor.
# Set Size, Color and Layers (which z-indexes it exists on) in the Inspector.

@export var size := Vector2(200, 16):
	set(value):
		size = value
		_refresh()

@export var color := Color(0.5, 0.5, 0.5):
	set(value):
		color = value
		queue_redraw()

# Tick the z-layers this block exists on (Layer 1 = z-index 1, etc.)
@export_flags("Layer 1", "Layer 2", "Layer 3") var layers := 1:
	set(value):
		layers = value
		_refresh()

func _ready() -> void:
	add_to_group("blocks")
	_refresh()

func _refresh() -> void:
	queue_redraw()
	collision_layer = layers   # collision layer bit n == z-index n+1
	collision_mask = 0
	# draw order: blocks on higher z-layers appear in front
	for i in 3:
		if layers & (1 << i):
			z_index = (i + 1) * 2
			break
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs and cs.shape is RectangleShape2D:
		cs.shape.size = size

@export var show_placeholder := true:
	set(value):
		show_placeholder = value
		queue_redraw()

func _draw() -> void:
	if not show_placeholder:
		return
	draw_rect(Rect2(-size / 2, size), color)

# Called by the game: fade blocks that aren't on the player's z-layer
func show_for_layer(z: int) -> void:
	modulate.a = 1.0 if (layers & (1 << (z - 1))) != 0 else 0.3
