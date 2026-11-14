extends Node2D
# Builds the level and the player in code.
# Every solid object has one or more z-layers. The player only collides
# with objects that share the player's current z-layer.

const W := 1152.0
const H := 648.0
const WALL := 24.0
const FLOOR_H := 48.0
const ALL_LAYERS := [1, 2, 3]
const PlayerScript = preload("res://player.gd")

var objects: Array = []   # [{ "node": Node2D, "layers": Array }]
var z_label: Label

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.55, 0.75, 0.95))

	# Floor and walls exist on every z-layer
	make_box(Vector2(W / 2, H - FLOOR_H / 2), Vector2(W, FLOOR_H), Color(0.35, 0.25, 0.15), ALL_LAYERS)
	make_box(Vector2(WALL / 2, H / 2), Vector2(WALL, H), Color(0.3, 0.3, 0.35), ALL_LAYERS)
	make_box(Vector2(W - WALL / 2, H / 2), Vector2(WALL, H), Color(0.3, 0.3, 0.35), ALL_LAYERS)

	# Platforms, each on ONE specific z-layer
	make_box(Vector2(300, 538), Vector2(200, 16), Color(0.9, 0.7, 0.2), [1])
	make_box(Vector2(600, 538), Vector2(200, 16), Color(0.3, 0.8, 0.4), [2])
	make_box(Vector2(900, 538), Vector2(200, 16), Color(0.6, 0.4, 0.9), [3])

	# HUD
	var hud := CanvasLayer.new()
	z_label = Label.new()
	z_label.position = Vector2(40, 12)
	z_label.add_theme_font_size_override("font_size", 24)
	hud.add_child(z_label)
	add_child(hud)

	# Player
	var player = PlayerScript.new()   # untyped on purpose: it has custom members (z, z_changed)
	player.position = Vector2(W / 2, H - FLOOR_H - 30)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 48)
	shape.shape = rect
	player.add_child(shape)
	var body := ColorRect.new()
	body.size = Vector2(32, 48)
	body.position = -body.size / 2
	body.color = Color(0.9, 0.2, 0.2)
	player.add_child(body)
	player.z_changed.connect(_on_player_z_changed)
	add_child(player)
	_on_player_z_changed(player.z)

func make_box(center: Vector2, size: Vector2, color: Color, layers: Array) -> void:
	var body := StaticBody2D.new()
	body.position = center
	# Physics: sit on the collision layer(s) matching the z-layer(s)
	var bits := 0
	for l in layers:
		bits |= 1 << (l - 1)
	body.collision_layer = bits
	body.collision_mask = 0
	# Drawing: higher z-layers draw in front
	body.z_index = layers.min() * 2

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	var visual := ColorRect.new()
	visual.size = size
	visual.position = -size / 2
	visual.color = color
	body.add_child(visual)
	add_child(body)
	objects.append({"node": body, "layers": layers})

func _on_player_z_changed(z: int) -> void:
	z_label.text = "Z-index: %d   (W = forward, S = back)" % z
	# Fade objects the player can't collide with
	for o in objects:
		o["node"].modulate.a = 1.0 if z in o["layers"] else 0.3
