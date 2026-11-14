extends Node2D

enum Stage { ROOM, HALL, BASEMENT }

@export var stage: Stage
@export_file("*.tscn") var next_scene: String

@onready var original: CharacterBody2D = $Player
@onready var player = original
var apparition: CharacterBody2D
var apparition_sprite: Sprite2D
var apparition_rides := false
var riding_offset := Vector2.ZERO
const BODY_LAYER := 8
const SHELF_LAYER := 16
@onready var objects: Node2D = $Objects
@onready var status: Label = $HUD/Status
@onready var prompt: Label = $HUD/Prompt
@onready var dialogue: Label = $HUD/Dialogue
@onready var darkness: ColorRect = $HUD/Darkness

@onready var clock_audio := get_node_or_null("Ticking") as AudioStreamPlayer2D

func _find_clock_audio() -> AudioStreamPlayer2D:
	# First AudioStreamPlayer2D anywhere in this scene, whatever it's named or nested under.
	for node in find_children("*", "AudioStreamPlayer2D", true, false):
		return node as AudioStreamPlayer2D
	return null

var woke_up := true
var hallucinating := false
var lamp_on := false
var laptop_checked := false
var wardrobe_hint_shown := false
var front_door_checked := false
var has_key := false
var gate_open := false
var held_prop := ""
var held_side := 1.0
@onready var player_shape: CollisionPolygon2D = $Player/CollisionPolygon2D
@onready var player_sprite: Sprite2D = _find_player_sprite()

const BODY_TEXTURE := preload("res://Art/House/Character_big.png")
const APPARITION_TEXTURE := preload("res://Art/House/Character_glitched.png")
const CHAR_HEIGHT := 54.0  # on-screen height of the character in pixels
var moved_props: Dictionary = {}
var room_door_checked := false
var room_key := false
var bed_idle := 0.0
var bed_line := 0
var left_bed := false
var gate_wait := 0.0
var hints: Dictionary = {}

const MOVABLE := ["HallChair", "Cabinet", "CellarChair", "Ladder"]
const BED_LINES := [
	"Narrator: Still in bed? I can wait.",
	"Narrator: Fine. Lie there and rot.",
	"Narrator: Take your time. I’m not the one who needs to get to a hospital."
]
var climbed := false
var finished := false
var busy := false
var target := ""
var lines: Array[String] = []

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#222935"))
	# In the first room the hero starts lying face up; he stands after the intro dialogue.
	woke_up = stage != Stage.ROOM
	if woke_up:
		_show_avatar_texture()
	else:
		_lie_down()
	for prop in objects.get_children():
		var label := prop.get_node_or_null("Label") as Label
		if label:
			label.hide()
	original.collision_layer = BODY_LAYER
	_refresh_objects()
	if clock_audio:
		clock_audio.play()       
	match stage:
		Stage.ROOM:
			darkness.show()
			_say([
				"Narrator: Look who finally decided to wake up.",
				"Narrator: After everything that happened, I wasn’t sure you’d get up at all.",
				"Narrator: You said you’d get help yesterday, too."
			])
		Stage.HALL:
			_say([
				"Narrator: Why is your house such a mess?",
				"Narrator: Front door’s right there. Just cross the hall. Or whatever’s left of it. Looks like something out of a horror movie."
			])
		Stage.BASEMENT:
			_say([
				"Narrator: Looking at the rest of the house, I thought the basement would be scarier.",
				"Narrator: See that window over there? It’s probably your only way out of this dump."
			])

func _physics_process(_delta: float) -> void:
	if apparition_rides and not hallucinating:
		apparition.position = original.position + riding_offset

	player.can_jump = held_prop.is_empty()  # no jumping while holding an object
	_follow_player()
	
func _process(delta: float) -> void:
	if clock_audio and not clock_audio.playing:
		clock_audio.play()
	if woke_up:
		if not is_zero_approx(player.velocity.x):
			var sprite := apparition_sprite if player == apparition else player_sprite
			sprite.flip_h = player.velocity.x < 0.0
	if not dialogue.visible and not busy and not finished:
		_update_story(delta)
	_update_target()
	status.text = ""
	if lamp_on or stage != Stage.ROOM:
		status.text = "A/D: ruch   Spacja: skok"
	if room_door_checked or stage != Stage.ROOM:
		status.text += "   |   Q: przełącz postać (%s)" % ("wł." if hallucinating else "wył.")
	prompt.text = "" if target.is_empty() else "E  " + _action_label()
	if not held_prop.is_empty():
		prompt.text = "E  Odłóż   •   A/D  Przesuń"
	elif target.is_empty() and stage == Stage.ROOM and lamp_on and laptop_checked and not room_door_checked:
		prompt.text = "Podejdź do drzwi i sprawdź klamkę."
	if dialogue.visible:
		prompt.text = "E  Dalej"
	elif finished:
		prompt.text = "Koniec prototypu"

func _find_player_sprite() -> Sprite2D:
	# Hallway/basement have a HouseCharacter sprite; the room uses player.tscn's TextureRect,
	# so in that case create a Sprite2D here and hide the TextureRect.
	var sprite := player.get_node_or_null("HouseCharacter") as Sprite2D
	if sprite:
		return sprite
	sprite = Sprite2D.new()
	sprite.name = "HouseCharacter"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	player.add_child(sprite)
	var old_rect := player.get_node_or_null("TextureRect") as CanvasItem
	if old_rect:
		old_rect.hide()
	return sprite

func _show_avatar_texture() -> void:
	var tex := APPARITION_TEXTURE if player == apparition else BODY_TEXTURE
	var sprite := apparition_sprite if player == apparition else player_sprite
	sprite.texture = tex
	# The 10x art is much larger than the old 24x24 sprite, so scale it to a fixed height.
	sprite.scale = Vector2.ONE * (CHAR_HEIGHT / tex.get_height())

func _lie_down() -> void:
	_show_avatar_texture()
	player_sprite.rotation_degrees = -70.0  # lying on the other side
	player_sprite.position.y = 16.0

func _wake_up() -> void:
	woke_up = true
	player_sprite.rotation_degrees = 0.0
	player_sprite.position.y = 0.0
	_show_avatar_texture()

func _update_story(delta: float) -> void:
	match stage:
		Stage.ROOM:
			if lamp_on and (player.position.x < 42.0 or player.position.x > 258.0 or laptop_checked):
				left_bed = true
			if lamp_on and not left_bed and bed_line < BED_LINES.size():
				bed_idle += delta
				if bed_idle >= [8.0, 12.0, 16.0][bed_line]:
					bed_idle = 0.0
					_say([BED_LINES[bed_line]])
					bed_line += 1
		Stage.HALL:
			pass  # the wardrobe jump hint is handled on the Space key press (see _unhandled_key_input)
		Stage.BASEMENT:
			if player.position.x > 980.0 and player.velocity.y < 0.0 and not climbed:
				_hint("high_window", "Narrator: Bit high, isn’t it? Look around. There’s got to be something you can climb.")
			elif hallucinating and not has_key and player.position.x > 290.0 and player.position.x < 565.0 and player.position.y > 470.0:
				_hint("bench_chair", "Narrator: That chair looks familiar. Pull it up to the workbench.")
			if not dialogue.visible and hallucinating and not gate_open and not has_key and _near_gate():
				gate_wait += delta
				if gate_wait > 7.0:
					_hint("gate_wait", "Narrator: Have you checked the cabinets above the workbench?")
			else:
				gate_wait = 0.0

func _update_target() -> void:
	target = ""
	match stage:
		Stage.ROOM:
			if _near("RoomKey", 65.0) and hallucinating and room_door_checked and not room_key:
				target = "RoomKey"
			elif _near("Laptop") and lamp_on and not laptop_checked:
				target = "Laptop"
			elif _near("RoomDoor") and lamp_on and player == original:
				target = "RoomDoor"
		Stage.HALL:
			if _can_grab("HallChair"):
				target = "HallChair"
			elif _can_grab("Cabinet", 51.0):
				target = "Cabinet"
			elif hallucinating and front_door_checked and _near("CellarDoor"):
				target = "CellarDoor"
			elif _near("FrontDoor"):
				target = "FrontDoor"
		Stage.BASEMENT:
			if hallucinating and not has_key and _near("ToolCabinet", 76.0) and player.position.y < 465.0:
				target = "ToolCabinet"
			elif hallucinating and not gate_open and _near_gate():
				target = "Gate"
			elif hallucinating and _ladder_ready() and not climbed and absf(player.position.x - objects.get_node("Ladder").position.x) < 32.0 and _near("Ladder", 170.0):
				target = "Climb"
			elif _can_grab("Ladder", 148.0):
				target = "Ladder"
			elif _can_grab("CellarChair"):
				target = "CellarChair"
			elif _near("Window", 80.0) or player.position.x > 990.0:
				target = "Window"

func _near_gate() -> bool:
	return absf(player.position.x - objects.get_node("Gate").position.x) < 86.0

func _hint(id: String, line: String) -> void:
	if not hints.has(id):
		hints[id] = true
		_say([line])

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or busy or (finished and not dialogue.visible):
		return
	match event.physical_keycode:
		KEY_Q:
			if not dialogue.visible and held_prop.is_empty() and (stage != Stage.ROOM or room_door_checked):
				hallucinating = not hallucinating
				_switch_avatar()
				_refresh_objects()
				_reveal_dialogue()
		KEY_SPACE:
			if stage == Stage.HALL and not dialogue.visible:
				_wardrobe_jump_hint()
		KEY_E:
			if dialogue.visible:
				_advance_dialogue()
			elif not held_prop.is_empty():
				_drop_prop()
			else:
				_interact()

func _switch_avatar() -> void:
	if hallucinating:
		original.velocity = Vector2.ZERO
		original.set_physics_process(false)
		original.set_process_input(false)
		if apparition == null:
			apparition = preload("res://player.tscn").instantiate() as CharacterBody2D
			apparition.set("layer_switching_enabled", false)
			apparition.scale = original.scale
			add_child(apparition)
			apparition.get_node("TextureRect").hide()
			apparition_sprite = Sprite2D.new()
			apparition_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			apparition.add_child(apparition_sprite)
			apparition.position = original.position - Vector2(0, _player_half_size().y * 2.0 + 1.0)
		apparition_rides = false
		apparition.collision_layer = BODY_LAYER
		apparition.collision_mask = 1 | BODY_LAYER | SHELF_LAYER
		original.collision_mask = 1 | BODY_LAYER
		apparition.show()
		_set_active_avatar(apparition)
		_show_avatar_texture()
	else:
		var base_shape := original.get_node("CollisionPolygon2D") as CollisionPolygon2D
		var difference := player_shape.global_position - base_shape.global_position
		var half := _player_half_size()
		apparition_rides = absf(difference.x) < half.x * 2.0 and absf(difference.y + half.y * 2.0) < 3.0
		riding_offset = apparition.position - original.position
		apparition.velocity = Vector2.ZERO
		apparition.set_physics_process(false)
		apparition.set_process_input(false)
		apparition.collision_layer = 0
		apparition.collision_mask = 0
		apparition.hide()
		original.collision_mask = 1
		_set_active_avatar(original)

func _set_active_avatar(avatar: CharacterBody2D) -> void:
	player = avatar
	player_shape = avatar.get_node("CollisionPolygon2D") as CollisionPolygon2D
	avatar.set_process_input(true)
	avatar.set_physics_process(true)

func _wardrobe_jump_hint() -> void:
	if wardrobe_hint_shown or moved_props.has("HallChair"):
		return
	var wardrobe: Node2D = objects.get_node("Wardrobe")
	var half_width: float = wardrobe.get("size").x / 2.0
	var left: float = wardrobe.position.x - half_width
	# Pressing Space anywhere in the ~220 px in front of the wardrobe counts as trying to jump it.
	if player.position.x > left - 220.0 and player.position.x < left + half_width * 2.0:
		wardrobe_hint_shown = true
		_say(["Narrator: Yeah, you’re not jumping that. Try using that superpower of yours again. Maybe you’ll see something you can use."])

func _reveal_dialogue() -> void:
	if not hallucinating:
		return
	match stage:
		Stage.ROOM:
			if not room_key:
				_hint("room_key", "Narrator: There’s your key. Grab it before you bounce back to reality.")
		Stage.HALL:
			if front_door_checked:
				_hint("cellar_door", "Narrator: There it is. Who puts a cabinet in front of a door?")
			else:
				_hint("hall_chair", "Narrator: See that chair? Pull it up to the wardrobe. You can use it to climb over.")

func _interact() -> void:
	if target in MOVABLE:
		_grab_prop()
		return
	match target:
		"Laptop":
			laptop_checked = true
			$Objects/Desk/LaptopOff.hide()
			$Objects/Desk/LaptopOn.show()
			_say([
				"Narrator: Two kilometers. Take the bus. I don’t trust you to make it on foot.",
				"Narrator: Come on. Let’s just get you out of this room first."
			])
		"RoomDoor":
			if not laptop_checked:
				_say(["Hero: I should look up the hospital first."])
			elif room_key:
				_go_forward()
			elif not room_door_checked:
				room_door_checked = true
				_say([
					"Narrator: Locked. Huh. I don’t see a key anywhere.",
					"Narrator: Oh, right. The voice in your head isn’t your only symptom.",
					"Hero: (grunts)",
					"Narrator: Touchy. Fine. Your other superpower.",
					"Narrator: You see things I can’t. Take another look around. See if you can find the key."
				])
		"RoomKey":
			room_key = true
			_refresh_objects()
		"FrontDoor":
			if not front_door_checked:
				front_door_checked = true
				if hallucinating:
					hallucinating = false
					_switch_avatar()
				_refresh_objects()
				_say(["Hero: Locked.", "Narrator: Of course it is. What about the basement? Maybe there’s a way out?"])
		"CellarDoor":
			if _cabinet_blocks_door():
				_hint("blocked_door", "Narrator: Try sliding it aside. Same as the chair.")
			else:
				_go_forward()
		"ToolCabinet":
			has_key = true
			_refresh_objects()
		"Gate":
			if has_key:
				gate_open = true
				_refresh_objects()
			else:
				_hint("locked_gate", "Narrator: A ladder. Of course it’s locked up. Who exactly were you expecting to steal it?")
		"Climb":
			await _climb_ladder()
		"Window":
			if climbed and _near("Window", 80.0):
				finished = true
				player.set_physics_process(false)
			else:
				_hint("high_window", "Narrator: Bit high, isn’t it? Look around. There’s got to be something you can climb.")

func _can_grab(name: String, distance := 86.0) -> bool:
	var prop = objects.get_node(name)
	if not prop.visible or not _near(name, distance):
		return false
	if name == "Ladder":
		return gate_open
	return true

func _grab_prop() -> void:
	held_prop = target
	var prop = objects.get_node(held_prop)
	held_side = -1.0 if prop.position.x < player.position.x else 1.0
	if prop is StaticBody2D:
		prop.collision_layer = 0

func _follow_player() -> void:
	if held_prop.is_empty():
		return
	var prop = objects.get_node(held_prop)
	var query := _prop_query(prop)
	var half_width: float = query.shape.size.x / 2.0
	var offset := (half_width + _player_half_size().x + 5.0) * held_side
	var wanted: float = player.position.x + offset
	var destination := clampf(wanted, 24.0 + half_width, 1128.0 - half_width)
	var motion := Vector2(destination - prop.position.x, 0.0)
	query.motion = motion
	var safe_fraction := get_world_2d().direct_space_state.cast_motion(query)[0]
	prop.position.x += motion.x * safe_fraction
	# The box could not follow all the way (wall, object, room edge): stop the player too,
	# so he can't walk through the box he is holding.
	if absf(prop.position.x - wanted) > 0.5:
		var limit: float = prop.position.x - offset
		if absf(player.position.x - limit) < 24.0:  # small correction only, never a teleport
			player.position.x = limit

func _prop_query(prop: Node2D) -> PhysicsShapeQueryParameters2D:
	var size: Vector2 = prop.get("size") if prop is StaticBody2D else Vector2(46, 266)
	var shape := RectangleShape2D.new()
	shape.size = size - Vector2(0, 2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = prop.global_transform
	query.collision_mask = 1
	if held_prop == "Ladder":
		# The ladder rests against the window sill.
		query.exclude = [objects.get_node("Sill").get_rid()]
	return query

func _player_bounds() -> Rect2:
	# Bounding box of the collision polygon in global coordinates (follows scale/position).
	var xf := player_shape.global_transform
	var points := player_shape.polygon
	var bounds := Rect2(xf * points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(xf * point)
	return bounds

func _player_half_size() -> Vector2:
	return _player_bounds().size / 2.0

func _drop_prop() -> void:
	var prop: Node2D = objects.get_node(held_prop)
	var query := _prop_query(prop)
	var size: Vector2 = query.shape.size + Vector2(0, 2)
	var overlaps_player := Rect2(prop.global_position - size / 2.0, size).intersects(_player_bounds())
	if overlaps_player or not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		_say(["Tu nie ma miejsca. Przesuń przedmiot i spróbuj ponownie."])
		return
	moved_props[held_prop] = true
	if held_prop == "Ladder":
		climbed = false
	held_prop = ""
	_refresh_objects()

func _cabinet_blocks_door() -> bool:
	var cabinet = objects.get_node("Cabinet")
	var door = objects.get_node("CellarDoor")
	return absf(cabinet.position.x - door.position.x) < 65.0

func _ladder_ready() -> bool:
	return moved_props.has("Ladder") and absf(objects.get_node("Ladder").position.x - 1035.0) < 44.0


func _climb_ladder() -> void:
	busy = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(player, "position:x", objects.get_node("Ladder").position.x, 0.2)
	tween.tween_property(player, "position:y", 314.0, 0.9)
	await tween.finished
	climbed = true
	player.set_physics_process(true)
	busy = false

func _go_forward() -> void:
	busy = true
	var result := get_tree().change_scene_to_file(next_scene)
	if result != OK:
		busy = false
		_say(["Nie udało się wczytać następnej sceny."])

func _near(object_name: String, distance := 86.0) -> bool:
	return player.position.distance_to(objects.get_node(object_name).position) <= distance

func _say(text_lines: Array[String]) -> void:
	lines = text_lines.duplicate()
	dialogue.show()
	player.set_process_input(false)
	player.set_physics_process(false)
	_advance_dialogue()

func _turn_on_lamp() -> void:
	lamp_on = true
	$Objects/Nightstand/LampOff.hide()
	$Objects/Nightstand/LampOn.show()
	darkness.hide()
	_say([
		"Narrator: You can hear me. That’s reason enough to get help. Even if I’m trying to help you.",
		"Hero: Maybe I should listen to you this time.",
		"Narrator: Good. Your laptop’s on the desk. Look up the nearest hospital."
	])

func _advance_dialogue() -> void:
	if not lines.is_empty():
		dialogue.text = lines.pop_front()
		return
	if finished:
		dialogue.hide()
		return
	dialogue.hide()
	if not woke_up:
		if not lamp_on:
			_turn_on_lamp()
			return
		_wake_up()
	player.set_process_input(true)
	player.set_physics_process(true)

func _refresh_objects() -> void:
	match stage:
		Stage.ROOM:
			_show_prop("RoomKey", hallucinating and room_door_checked and not room_key)
			$Objects/HallucinationShelves.visible = hallucinating
		Stage.HALL:
			_show_prop("HallChair", hallucinating)
			_show_prop("Cabinet", hallucinating and front_door_checked)
			_show_prop("CellarDoor", hallucinating and front_door_checked)
		Stage.BASEMENT:
			_show_prop("CellarChair", hallucinating)
			_show_prop("Gate", not gate_open)
			_show_prop("Ladder", hallucinating)

func _show_prop(object_name: String, enabled: bool) -> void:
	var prop = objects.get_node(object_name)
	prop.visible = enabled
	if prop is StaticBody2D:
		prop.collision_layer = prop.layers if enabled and held_prop != object_name else 0

func _action_label() -> String:
	if target in MOVABLE:
		return "Chwyć"
	return {
		"Laptop": "Sprawdź laptopa", "RoomDoor": "Sprawdź drzwi",
		"RoomKey": "Podnieś klucz", "FrontDoor": "Sprawdź drzwi frontowe",
		"CellarDoor": "Sprawdź drzwi do piwnicy", "ToolCabinet": "Przeszukaj szafkę",
		"Gate": "Sprawdź kraty", "Climb": "Wespnij się po drabinie",
		"Window": "Sprawdź okno" if not climbed else "Wyjdź przez okno"
	}.get(target, "")
