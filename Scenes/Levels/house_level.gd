extends Node2D

enum Stage { ROOM, HALL, BASEMENT }

@export var stage: Stage
@export_file("*.tscn") var next_scene: String

@onready var player = $Player
@onready var objects: Node2D = $Objects
@onready var status: Label = $HUD/Status
@onready var prompt: Label = $HUD/Prompt
@onready var dialogue: Label = $HUD/Dialogue
@onready var darkness: ColorRect = $HUD/Darkness

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
@onready var player_shape: CollisionShape2D = $Player/CollisionShape2D
@onready var player_sprite: Sprite2D = $Player/HouseCharacter

const CHAR_IDLE_PATH := "res://characaterx10.png"  # default standing pose
const CHAR_RIGHT_PATH := "res://char_right10x.png"
const CHAR_LEFT_PATH := "res://char_left10x.png"
const CHAR_HEIGHT := 54.0  # on-screen height of the character in pixels
var char_idle: Texture2D
var char_right: Texture2D
var char_left: Texture2D
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
	char_idle = load(CHAR_IDLE_PATH) as Texture2D
	char_right = load(CHAR_RIGHT_PATH) as Texture2D
	char_left = load(CHAR_LEFT_PATH) as Texture2D
	# In the first room the hero starts lying face up; he stands after the intro dialogue.
	woke_up = stage != Stage.ROOM
	if woke_up:
		_show_texture(char_idle)
	else:
		_lie_down()
	for prop in objects.get_children():
		var label := prop.get_node_or_null("Label") as Label
		if label:
			label.hide()
	_refresh_objects()
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
	_follow_player()

func _process(delta: float) -> void:
	if woke_up:
		var moving := not is_zero_approx(player.velocity.x) and not dialogue.visible and not busy
		if moving:
			_show_texture(char_right if player.velocity.x > 0.0 else char_left)
		else:
			_show_texture(char_idle)
	if not dialogue.visible and not busy and not finished:
		_update_story(delta)
	_update_target()
	status.text = ""
	if lamp_on or stage != Stage.ROOM:
		status.text = "A/D: ruch   Spacja: skok"
	if room_door_checked or stage != Stage.ROOM:
		status.text += "   |   Q: halucynacja (%s)" % ("wł." if hallucinating else "wył.")
	prompt.text = "" if target.is_empty() else "E  " + _action_label()
	if not held_prop.is_empty():
		prompt.text = "E  Odłóż   •   A/D  Przesuń"
	elif target.is_empty() and stage == Stage.ROOM and lamp_on and laptop_checked and not room_door_checked:
		prompt.text = "Podejdź do drzwi i sprawdź klamkę."
	if dialogue.visible:
		prompt.text = "E  Dalej"
	elif finished:
		prompt.text = "Koniec prototypu"

func _show_texture(tex: Texture2D) -> void:
	if tex == null:
		return
	player_sprite.texture = tex
	# The 10x art is much larger than the old 24x24 sprite, so scale it to a fixed height.
	player_sprite.scale = Vector2.ONE * (CHAR_HEIGHT / tex.get_height())

func _lie_down() -> void:
	_show_texture(char_right if char_right != null else char_idle)  # walking-right sprite
	player_sprite.rotation_degrees = -70.0  # lying on the other side
	player_sprite.position.y = 20.0

func _wake_up() -> void:
	woke_up = true
	player_sprite.rotation_degrees = 0.0
	player_sprite.position.y = 0.0
	_show_texture(char_idle)

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
			if not wardrobe_hint_shown and not moved_props.has("HallChair"):
				if player.position.x > 410.0 and player.position.x < 530.0 and player.velocity.y < 0.0:
					wardrobe_hint_shown = true
					_say(["Narrator: Yeah, you’re not jumping that. Try using that superpower of yours again. Maybe you’ll see something you can use."])
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
			if _near("Lamp", 112.0) and not lamp_on:
				target = "Lamp"
			elif _near("RoomKey", 65.0) and hallucinating and room_door_checked and not room_key:
				target = "RoomKey"
			elif _near("Laptop") and lamp_on and not laptop_checked:
				target = "Laptop"
			elif _near("RoomDoor") and lamp_on:
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
			elif _ladder_ready() and not climbed and absf(player.position.x - objects.get_node("Ladder").position.x) < 32.0 and _near("Ladder", 170.0):
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
				_refresh_objects()
				_reveal_dialogue()
		KEY_E:
			if dialogue.visible:
				_advance_dialogue()
			elif not held_prop.is_empty():
				_drop_prop()
			else:
				_interact()

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
		"Lamp":
			lamp_on = true
			$Objects/Nightstand/LampOff.hide()
			$Objects/Nightstand/LampOn.show()
			darkness.hide()
			_say([
				"Narrator: You can hear me. That’s reason enough to get help. Even if I’m trying to help you.",
				"Hero: Maybe I should listen to you this time.",
				"Narrator: Good. Your laptop’s on the desk. Look up the nearest hospital."
			])
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
				hallucinating = false
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
	var destination := clampf(player.position.x + offset, 24.0 + half_width, 1128.0 - half_width)
	var motion := Vector2(destination - prop.position.x, 0.0)
	query.motion = motion
	var safe_fraction := get_world_2d().direct_space_state.cast_motion(query)[0]
	prop.position.x += motion.x * safe_fraction

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

func _player_half_size() -> Vector2:
	var shape := player_shape.shape as RectangleShape2D
	return shape.size * player_shape.global_scale.abs() / 2.0

func _drop_prop() -> void:
	var prop: Node2D = objects.get_node(held_prop)
	var query := _prop_query(prop)
	var size: Vector2 = query.shape.size + Vector2(0, 2)
	var half_player := _player_half_size()
	var overlaps_player := Rect2(prop.global_position - size / 2.0, size).intersects(
		Rect2(player_shape.global_position - half_player, half_player * 2.0)
	)
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

func _advance_dialogue() -> void:
	if not lines.is_empty():
		dialogue.text = lines.pop_front()
		return
	if finished:
		dialogue.hide()
		return
	dialogue.hide()
	if not woke_up:
		_wake_up()  # the 3rd press of E ends the intro dialogue
	player.set_process_input(true)
	player.set_physics_process(true)

func _refresh_objects() -> void:
	match stage:
		Stage.ROOM:
			_show_prop("RoomKey", hallucinating and room_door_checked and not room_key)
		Stage.HALL:
			_show_prop("HallChair", hallucinating or moved_props.has("HallChair"))
			_show_prop("Cabinet", (hallucinating and front_door_checked) or moved_props.has("Cabinet"))
			_show_prop("CellarDoor", hallucinating and front_door_checked)
		Stage.BASEMENT:
			_show_prop("CellarChair", hallucinating or moved_props.has("CellarChair"))
			_show_prop("Gate", not gate_open)
			_show_prop("Ladder", hallucinating or moved_props.has("Ladder"))

func _show_prop(object_name: String, enabled: bool) -> void:
	var prop = objects.get_node(object_name)
	prop.visible = enabled
	if prop is StaticBody2D:
		prop.collision_layer = prop.layers if enabled and held_prop != object_name else 0

func _action_label() -> String:
	if target in MOVABLE:
		return "Chwyć"
	return {
		"Lamp": "Włącz lampkę", "Laptop": "Sprawdź laptopa", "RoomDoor": "Sprawdź drzwi",
		"RoomKey": "Podnieś klucz", "FrontDoor": "Sprawdź drzwi frontowe",
		"CellarDoor": "Sprawdź drzwi do piwnicy", "ToolCabinet": "Przeszukaj szafkę",
		"Gate": "Sprawdź kraty", "Climb": "Wespnij się po drabinie",
		"Window": "Sprawdź okno" if not climbed else "Wyjdź przez okno"
	}.get(target, "")
