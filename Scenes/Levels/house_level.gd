extends Node2D

enum Stage { ROOM, HALL, BASEMENT, LIGHTS }

@export var stage: Stage
@export_file("*.tscn") var next_scene: String

@onready var original: CharacterBody2D = $Player
@onready var player = original
var apparition: CharacterBody2D
var apparition_sprite: Sprite2D
var apparition_rides := false
var riding_offset := Vector2.ZERO
var bed_spawn := Vector2.ZERO
var apparition_entry := ""
var back_door: Node2D
var learned_hints: Dictionary = {}
const PREVIOUS_ROOMS := {Stage.HALL: "room", Stage.LIGHTS: "hallway", Stage.BASEMENT: "hallway"}
var wardrobe_raised := false
const SAVED_FIELDS := ["wardrobe_raised", "lamp_on", "laptop_checked", "wardrobe_hint_shown", "front_door_checked", "room_door_checked", "room_key", "lights_fixed", "has_key", "gate_open", "moved_props", "hints", "learned_hints", "learned_move", "learned_jump", "left_bed", "bed_line"]
const AVATAR_ART_SCALE := 1.25
const BODY_LAYER := 8
const SHELF_LAYER := 16
const LIFTED_WARDROBE_Y := 155.0
const BACKGROUND_PROP_LAYER := 32
@onready var objects: Node2D = $Objects
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
var moved_props: Dictionary = {}
var room_door_checked := false
var room_key := false
var lights_fixed := false
var learned_move := false
var learned_jump := false
var floating_hint: Label
var continue_hint: Label
var bed_idle := 0.0
var bed_line := 0
var left_bed := false
var gate_wait := 0.0
var hints: Dictionary = {}
var queued_narrator_hints: Array[String] = []

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
	_create_hallucination_effect()
	var keep_hallucination: bool = HouseSession.hallucination_in_transit
	HouseSession.hallucination_in_transit = false
	_fit_avatar_hitbox(original, Vector2(43, 118))
	bed_spawn = original.position
	_create_back_door()
	if back_door and stage != Stage.LIGHTS:
		apparition_entry = "BackDoor"
	var visited: bool = _restore_progress()
	_create_floating_hint()
	_create_continue_hint()
	RenderingServer.set_default_clear_color(Color("#222935"))
	# In the first room the hero starts lying face up; he stands after the intro dialogue.
	woke_up = stage != Stage.ROOM or visited
	if woke_up:
		_show_avatar_texture()
	else:
		_lie_down()
	for prop in objects.get_children():
		var label := prop.get_node_or_null("Label") as Label
		if label:
			label.hide()
	_create_head_platform()
	_refresh_objects()
	if clock_audio:
		clock_audio.bus = "Sound Effects"
		clock_audio.play()
	if keep_hallucination or stage == Stage.LIGHTS:
		hallucinating = true
		hallucination_tint.show()
		_switch_avatar()
	if stage == Stage.LIGHTS:
		apparition.position = Vector2(480, 348)
		apparition.position.y += 375.9 - _player_bounds().end.y
		original.hide()
		original.get_node("HeadPlatform").collision_layer = 0
	_refresh_objects()
	if visited:
		return
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
		Stage.LIGHTS:
			if not lights_fixed:
				_say(["Narrator: Find a way to get the lights working before you go down there. I’d hate for you to break your neck on the stairs."])
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
	if continue_hint.visible:
		continue_hint.text = _press("house_interact", "continue")
	if clock_audio and not clock_audio.playing:
		clock_audio.play()
	if woke_up:
		if not is_zero_approx(player.velocity.x):
			var sprite := apparition_sprite if player == apparition else player_sprite
			sprite.flip_h = player.velocity.x < 0.0
	if not dialogue.visible and not busy and not finished:
		_update_story(delta)
		if not dialogue.visible and _can_show_narrator_hint() and not queued_narrator_hints.is_empty():
			_say([queued_narrator_hints.pop_front()])
	_update_target()
	_update_floating_hint()

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
	sprite.scale = Vector2.ONE * AVATAR_ART_SCALE / sprite.get_parent().global_scale
	var shape := (player_shape as CollisionPolygon2D)
	var foot_y := _collision_bounds(shape).end.y
	sprite.global_position.y = foot_y - tex.get_height() * AVATAR_ART_SCALE / 2.0

func _lie_down() -> void:
	_show_avatar_texture()
	player_sprite.rotation_degrees = -70.0  # lying on the other side
	player_sprite.position.y = 16.0

func _wake_up() -> void:
	woke_up = true
	player_sprite.rotation_degrees = 0.0
	_show_avatar_texture()

func _update_story(delta: float) -> void:
	match stage:
		Stage.ROOM:
			if hallucinating and not room_key and _near("RoomKey", 35.0):
				_hint("room_key", "Narrator: There’s your key. Grab it before you bounce back to reality.")
			if lamp_on and (player.position.x < 42.0 or player.position.x > 258.0 or laptop_checked):
				left_bed = true
			if lamp_on and not left_bed and bed_line < BED_LINES.size():
				bed_idle += delta
				if bed_idle >= [8.0, 12.0, 16.0][bed_line]:
					bed_idle = 0.0
					_say([BED_LINES[bed_line]])
					bed_line += 1
		Stage.HALL:
			_wardrobe_approach_hint()
		Stage.LIGHTS:
			if $Objects/Wires.visible and _near("Wires", 105.0):
				_hint("wires", "Narrator: See those wires? Try connecting them. Maybe that’ll get the lights working.")
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
	if back_door and (player == original or stage == Stage.LIGHTS) and _near("BackDoor", 74.0):
		target = "BackDoor"
		return
	match stage:
		Stage.ROOM:
			if _near("RoomKey", 65.0) and hallucinating and room_door_checked and not room_key:
				target = "RoomKey"
			elif _near("Laptop") and lamp_on and not laptop_checked:
				target = "Laptop"
			elif player == original and _near("RoomDoor") and lamp_on:
				target = "RoomDoor"
		Stage.HALL:
			if hallucinating and wardrobe_raised and front_door_checked and _near("WardrobePassage", 64.0):
				target = "WardrobePassage"
			elif _can_grab("Cabinet", 65.0):
				target = "Cabinet"
			elif _can_grab("HallChair"):
				target = "HallChair"
			elif player == original and _near("CellarDoor"):
				target = "CellarDoor"
			elif player == original and _near("FrontDoor"):
				target = "FrontDoor"
		Stage.LIGHTS:
			if $Objects/Wires.visible and _near("Wires", 65.0):
				target = "Wires"
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
		queued_narrator_hints.append(line)

func _can_show_narrator_hint() -> bool:
	return player.is_on_floor() and player.velocity.y >= -1.0

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or busy or (finished and not dialogue.visible):
		return
	match true:
		true when event.is_action_pressed("house_switch"):
			if not dialogue.visible and held_prop.is_empty() and stage != Stage.LIGHTS and (stage != Stage.ROOM or room_door_checked):
				hallucinating = not hallucinating
				if not hallucinating:
					HouseSession.learned_bounce_back = true
				_switch_avatar()
				_refresh_objects()
				_reveal_dialogue()
		true when event.is_action_pressed("house_interact"):
			if dialogue.visible:
				_advance_dialogue()
			elif not held_prop.is_empty():
				_drop_prop()
			else:
				_interact()

func _switch_avatar() -> void:
	if hallucinating:
		original.velocity = Vector2.ZERO
		original.set("controls_enabled", false)
		original.set_process_input(false)
		if apparition == null:
			apparition = preload("res://player.tscn").instantiate() as CharacterBody2D
			apparition.set("layer_switching_enabled", false)
			apparition.scale = original.scale * float(APPARITION_TEXTURE.get_height()) / BODY_TEXTURE.get_height()
			add_child(apparition)
			_fit_avatar_hitbox(apparition, Vector2(10, 29))
			apparition.get_node("TextureRect").hide()
			apparition.z_index = original.z_index + 1
			apparition_sprite = Sprite2D.new()
			apparition_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			apparition.add_child(apparition_sprite)
			apparition.position = bed_spawn if stage == Stage.ROOM else original.position
			var ghost_shape := apparition.get_node("CollisionPolygon2D") as CollisionPolygon2D
			if not apparition_entry.is_empty():
				var entry := objects.get_node(apparition_entry) as Node2D
				var floor_node := $Objects/Floor as Node2D
				var floor_size: Vector2 = floor_node.get("size")
				var floor_y := floor_node.to_global(Vector2(0, -floor_size.y / 2.0)).y
				apparition.global_position.x = entry.global_position.x
				apparition.global_position.y += floor_y - _collision_bounds(ghost_shape).end.y - 0.1
			elif stage == Stage.ROOM:
				_spawn_apparition_on_bed(ghost_shape)
		if apparition_rides:
			apparition.position = original.position + riding_offset
		apparition_rides = false
		apparition.collision_layer = 0
		apparition.collision_mask = 1 | BODY_LAYER | SHELF_LAYER | BACKGROUND_PROP_LAYER
		apparition.show()
		_set_active_avatar(apparition)
		_show_avatar_texture()
	else:
		var base_shape := original.get_node("CollisionPolygon2D") as CollisionPolygon2D
		var base_bounds := _collision_bounds(base_shape)
		var ghost_bounds := _player_bounds()
		var overlaps_x := ghost_bounds.position.x < base_bounds.end.x and ghost_bounds.end.x > base_bounds.position.x
		apparition_rides = overlaps_x and absf(ghost_bounds.end.y - base_bounds.position.y) < 3.0
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
	avatar.set("controls_enabled", true)
	avatar.set_process_input(true)
	avatar.set_physics_process(true)

func _wardrobe_approach_hint() -> void:
	if player != original or wardrobe_raised or wardrobe_hint_shown or not _can_show_narrator_hint():
		return
	var wardrobe: Node2D = objects.get_node("Wardrobe")
	var half_width: float = wardrobe.get("size").x / 2.0
	if absf(original.position.x - wardrobe.position.x) <= half_width + 88.0:
		wardrobe_hint_shown = true
		_hint("wardrobe_jump", "Narrator: Yeah, you’re not jumping that. Try using that superpower of yours again. Maybe you’ll see something you can use.")

func _reveal_dialogue() -> void:
	if not hallucinating:
		return
	match stage:
		Stage.ROOM:
			if not room_key:
				_hint("first_shrink", "Narrator: I didn’t expect you to shrink that much. Might come in handy. You can squeeze into tighter spaces now.")
		Stage.HALL:
			if not wardrobe_raised:
				_hint("cabinet_plate", "Narrator: Use the chair to reach those ledges. The cabinet on the other side goes on the pressure plate.")

func _interact() -> void:
	if target.is_empty():
		return
	if player != original and (target in ["RoomDoor", "FrontDoor", "CellarDoor"] or (target == "BackDoor" and stage != Stage.LIGHTS)):
		return
	if target != "Wires":
		learned_hints[_interaction_hint_id()] = true
	if target in MOVABLE:
		_grab_prop()
		return
	match target:
		"BackDoor":
			if stage == Stage.LIGHTS and HouseSession.can_use_door():
				var corridor: Dictionary = HouseSession.rooms.get("res://Scenes/Levels/hallway.tscn", {})
				if not corridor.is_empty():
					corridor["returning_from_niche"] = true
			_change_room("res://Scenes/Levels/%s.tscn" % PREVIOUS_ROOMS[stage], true)
		"Laptop":
			laptop_checked = true
			$Objects/Desk/LaptopOff.hide()
			$Objects/Desk/LaptopOn.show()
			_say([
				"Narrator: Ten kilometers. Take the bus. I don’t trust you to make it on foot.",
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
				_refresh_objects()
				_say(["Hero: Locked.", "Narrator: Of course it is. What about the basement? Maybe there’s a way out?"])
		"WardrobePassage":
			if player == apparition and hallucinating and wardrobe_raised and front_door_checked:
				_change_room("res://Scenes/Levels/lights.tscn", false)
		"CellarDoor":
			if absf($Objects/Cabinet.position.x - $Objects/CellarDoor.position.x) < 64.0:
				_hint("blocked_door", "Narrator: Slide that cabinet onto the pressure plate.")
			elif lights_fixed:
				_go_forward()
			else:
				_hint("dark_stairs", "Narrator: Find a way to get the lights working before you go down there. I’d hate for you to break your neck on the stairs.")
		"Wires":
			_open_wire_puzzle()
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
				_say([
					"Narrator: You managed to get out of your house without dying. I’m flabbergasted.",
					"Narrator: As they say, ‘One small step for man, one giant leap for a schizophrenic.’ Or something along those lines.",
					"Narrator: Anyway, don’t celebrate just yet. You’ve still got a long way to go before you can bounce back to reality for good."
				])
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
	return _collision_bounds(player_shape)

func _collision_bounds(collision: CollisionPolygon2D) -> Rect2:
	# Bounding box of the collision polygon in global coordinates (follows scale/position).
	var xf := collision.global_transform
	var points := collision.polygon
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
	if stage == Stage.HALL and held_prop == "Cabinet" and not wardrobe_raised:
		if absf(prop.position.x - $Objects/PressurePlate.position.x) <= 27.0:
			_raise_wardrobe()
	learned_hints["drop"] = true
	if held_prop == "Ladder":
		climbed = false
	held_prop = ""
	_refresh_objects()

func _raise_wardrobe() -> void:
	wardrobe_raised = true
	var wardrobe := $Objects/Wardrobe as StaticBody2D
	wardrobe.collision_layer = 0
	create_tween().tween_property(wardrobe, "position:y", LIFTED_WARDROBE_Y, 0.45)
	$Objects/PressurePlate/Surface.color = Color("#67b178")

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
	_change_room(next_scene, false)

func _change_room(path: String, backwards: bool) -> void:
	if busy or not HouseSession.can_use_door():
		return
	_save_progress()
	HouseSession.returning = backwards
	HouseSession.hallucination_in_transit = hallucinating
	busy = true
	var result := get_tree().change_scene_to_file(path)
	if result == OK:
		HouseSession.play_door_open()
	else:
		busy = false
		HouseSession.returning = false
		HouseSession.hallucination_in_transit = false
		_say(["Nie udało się wczytać następnej sceny."])

func _near(object_name: String, distance := 86.0) -> bool:
	return player.position.distance_to(objects.get_node(object_name).position) <= distance

func _say(text_lines: Array[String]) -> void:
	lines = text_lines.duplicate()
	dialogue.show()
	continue_hint.text = _press("house_interact", "continue")
	continue_hint.show()
	player.set_process_input(false)
	player.set_physics_process(false)
	_advance_dialogue()

func _turn_on_lamp() -> void:
	lamp_on = true
	$Objects/Nightstand/LampOff.hide()
	$Objects/Nightstand/LampOn.show()
	darkness.hide()
	_say([
		"Hero: Why would I need help?",
		"Narrator: You can hear me. That’s reason enough to get help. Even if I’m trying to help you.",
		"Hero: Maybe I should listen to you this time.",
		"Narrator: Good. Your laptop’s on the desk. Look up the nearest hospital."
	])

func _advance_dialogue() -> void:
	if not lines.is_empty():
		dialogue.text = lines.pop_front()
		return
	dialogue.hide()
	continue_hint.hide()
	if finished:
		return
	if not woke_up:
		if not lamp_on:
			_turn_on_lamp()
			return
		_wake_up()
	player.jump_blocked_until_release = Input.is_action_pressed("house_jump")
	player.set_process_input(true)
	player.set_physics_process(true)

func _refresh_objects() -> void:
	_update_hallucination_effect()
	match stage:
		Stage.ROOM:
			_show_prop("RoomKey", hallucinating and room_door_checked and not room_key)
			$Objects/HallucinationShelves.visible = hallucinating
		Stage.HALL:
			_show_prop("HallChair", hallucinating)
			_show_prop("WardrobeParkour", hallucinating and not wardrobe_raised)
			_show_prop("Cabinet", hallucinating)
			$Objects/CellarDoor.modulate = Color.WHITE if lights_fixed else Color(0.58, 0.58, 0.64)
			_show_prop("PressurePlate", hallucinating)
			_show_prop("WardrobePassage", hallucinating and wardrobe_raised and front_door_checked)
		Stage.LIGHTS:
			_show_prop("Wires", hallucinating and not lights_fixed)
		Stage.BASEMENT:
			_show_prop("CellarChair", hallucinating)
			_show_prop("Gate", not gate_open)
			_show_prop("Ladder", hallucinating)

func _show_prop(object_name: String, enabled: bool) -> void:
	var prop = objects.get_node(object_name)
	prop.visible = enabled
	if prop is StaticBody2D:
		prop.collision_layer = prop.layers if enabled and held_prop != object_name else 0

func _create_floating_hint() -> void:
	floating_hint = Label.new()
	floating_hint.name = "FloatingControlHint"
	floating_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floating_hint.add_theme_font_size_override("font_size", 19)
	floating_hint.add_theme_color_override("font_color", Color("#fff0bf"))
	floating_hint.add_theme_color_override("font_outline_color", Color("#161922"))
	floating_hint.add_theme_constant_override("outline_size", 6)
	floating_hint.hide()
	$HUD.add_child(floating_hint)

func _update_floating_hint() -> void:
	if not woke_up or dialogue.visible or busy or finished:
		floating_hint.hide()
		return
	learned_move = learned_move or absf(player.get_real_velocity().x) > 1.0
	learned_jump = learned_jump or player.velocity.y < -1.0
	var text := _floating_control_text()
	if text.is_empty():
		floating_hint.hide()
		return
	floating_hint.text = text
	floating_hint.reset_size()
	var bounds := _player_bounds()
	var x := bounds.end.x + 14.0
	if x + floating_hint.size.x > 1136.0:
		x = bounds.position.x - floating_hint.size.x - 14.0
	floating_hint.position = Vector2(maxf(x, 16.0), clampf(bounds.get_center().y - 14.0, 16.0, 590.0))
	floating_hint.show()

func _floating_control_text() -> String:
	if not held_prop.is_empty():
		return "" if learned_hints.has("drop") else _press("house_interact", "put it down")
	if target in ["RoomDoor", "FrontDoor", "CellarDoor"] or (target == "BackDoor" and stage != Stage.LIGHTS):
		var door_hint := _press("house_interact", "open the door")
		if target == "RoomDoor" and room_door_checked and not room_key and apparition == null:
			door_hint += "\n" + _press("house_switch", "enter the hallucination")
		return door_hint
	if stage == Stage.ROOM:
		if not learned_move:
			return "Press %s / %s to move" % [HouseSession.key_name("house_left"), HouseSession.key_name("house_right")]
		if room_door_checked and not room_key and apparition == null:
			return _press("house_switch", "enter the hallucination")
	if target in MOVABLE and not learned_hints.has(target):
		return _press("house_interact", "grab")
	if stage == Stage.ROOM and not learned_jump and target.is_empty():
		return _press("house_jump", "jump")
	var action: String = {
		"BackDoor": "return to the previous room",
		"Laptop": "check the laptop",
		"RoomKey": "pick up the key",
		"WardrobePassage": "enter the passage",
		"Wires": "connect the wires",
		"ToolCabinet": "search the cabinet",
		"Gate": "unlock the gate" if has_key else "check the gate",
		"Climb": "climb the ladder",
		"Window": "climb out the window" if climbed else "check the window",
	}.get(target, "")
	if not action.is_empty() and not learned_hints.has(_interaction_hint_id()):
		return _press("house_interact", action)
	if hallucinating and stage != Stage.LIGHTS and not HouseSession.learned_bounce_back:
		return _press("house_switch", "bounce back to reality")
	return ""

func _create_continue_hint() -> void:
	continue_hint = Label.new()
	continue_hint.name = "ContinueHint"
	continue_hint.text = _press("house_interact", "continue")
	continue_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	continue_hint.add_theme_font_size_override("font_size", 16)
	continue_hint.add_theme_color_override("font_color", Color("#fff0bf"))
	continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var panel := $HUD/TextBackground as Control
	panel.add_child(continue_hint)
	continue_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	continue_hint.offset_right = -24.0
	continue_hint.offset_left = -260.0
	continue_hint.offset_bottom = -12.0
	continue_hint.offset_top = -36.0
	continue_hint.hide()

func _press(action: String, verb: String) -> String:
	return "Press %s to %s" % [HouseSession.key_name(action), verb]

func _interaction_hint_id() -> String:
	match target:
		"RoomDoor": return "UnlockRoomDoor" if room_key else target
		"CellarDoor": return "EnterBasement" if lights_fixed else target
		"Gate": return "UnlockGate" if has_key else target
		"Window": return "EscapeWindow" if climbed else target
	return target

func _create_back_door() -> void:
	if stage == Stage.ROOM:
		return
	back_door = Node2D.new()
	back_door.name = "BackDoor"
	objects.add_child(back_door)
	back_door.position = Vector2(original.position.x, original.position.y - 24.0)
	if stage == Stage.LIGHTS:
		back_door.position = Vector2(450, 355)
		var opening := ColorRect.new()
		opening.position = Vector2(-12, -20)
		opening.size = Vector2(24, 40)
		opening.color = Color("#385965")
		opening.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back_door.add_child(opening)
		return
	var sprite := Sprite2D.new()
	sprite.texture = preload("res://Art/House/Door_big.png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	back_door.add_child(sprite)

func _save_progress() -> void:
	var record := {}
	for field in SAVED_FIELDS:
		record[field] = get(field)
	var positions := {}
	for name in MOVABLE:
		if objects.has_node(name):
			positions[name] = objects.get_node(name).position
	record["positions"] = positions
	record["original_position"] = original.position
	HouseSession.rooms[scene_file_path] = record.duplicate(true)

func _restore_progress() -> bool:
	var backwards: bool = HouseSession.returning
	HouseSession.returning = false
	if not HouseSession.rooms.has(scene_file_path):
		return false
	var record: Dictionary = HouseSession.rooms[scene_file_path].duplicate(true)
	for field in SAVED_FIELDS:
		set(field, record[field])
	for name in record["positions"]:
		objects.get_node(name).position = record["positions"][name]
	if stage == Stage.ROOM and lamp_on:
		$Objects/Nightstand/LampOff.hide()
		$Objects/Nightstand/LampOn.show()
		$Objects/Desk/LaptopOff.visible = not laptop_checked
		$Objects/Desk/LaptopOn.visible = laptop_checked
		darkness.hide()
	if stage == Stage.HALL and wardrobe_raised:
		$Objects/Wardrobe.position.y = LIFTED_WARDROBE_Y
		$Objects/Wardrobe.collision_layer = 0
		$Objects/PressurePlate/Surface.color = Color("#67b178")
	if record.get("returning_from_niche", false):
		original.position = record["original_position"]
		apparition_entry = "WardrobePassage"
		HouseSession.rooms[scene_file_path].erase("returning_from_niche")
	elif backwards:
		var exit_name: String = {Stage.ROOM: "RoomDoor", Stage.HALL: "CellarDoor"}[stage]
		apparition_entry = exit_name
		original.position.x = objects.get_node(exit_name).position.x
		original.position.y = 600.0 - _player_half_size().y - 6.0
	return true

func _fit_avatar_hitbox(avatar: CharacterBody2D, body_size: Vector2) -> void:
	var hitbox := avatar.get_node("CollisionPolygon2D") as CollisionPolygon2D
	var sole_y := _collision_bounds(hitbox).end.y
	var center_x := avatar.global_position.x
	var half_width := body_size.x / 2.0
	var top_y := sole_y - body_size.y
	hitbox.polygon = PackedVector2Array([
		hitbox.to_local(Vector2(center_x - half_width, top_y)),
		hitbox.to_local(Vector2(center_x + half_width, top_y)),
		hitbox.to_local(Vector2(center_x + half_width, sole_y)),
		hitbox.to_local(Vector2(center_x - half_width, sole_y)),
	])

func _spawn_apparition_on_bed(hitbox: CollisionPolygon2D) -> void:
	var bed := $Objects/Bed as Node2D
	var x := bed.global_position.x + (52.0 if original.global_position.x <= bed.global_position.x else -52.0)
	var ray := PhysicsRayQueryParameters2D.create(Vector2(x, bed.global_position.y - 140.0), Vector2(x, bed.global_position.y + 40.0), 1)
	var surface := get_world_2d().direct_space_state.intersect_ray(ray)
	if surface.get("collider") == bed:
		apparition.global_position.x = x
		var top: Vector2 = surface["position"]
		apparition.global_position.y += top.y - _collision_bounds(hitbox).end.y - 0.1

func _create_head_platform() -> void:
	var bounds := _collision_bounds(player_shape)
	var head := StaticBody2D.new()
	head.name = "HeadPlatform"
	head.collision_layer = BODY_LAYER
	head.collision_mask = 0
	original.add_child(head)
	head.global_position = Vector2(bounds.get_center().x, bounds.position.y + 1.0)
	var surface := RectangleShape2D.new()
	surface.size = Vector2(bounds.size.x, 2.0) / original.global_scale.abs()
	var shape := CollisionShape2D.new()
	shape.shape = surface
	shape.one_way_collision = true
	head.add_child(shape)

const EYE_FRAMES := [
	preload("res://Art/House/eye_closed.png"),
	preload("res://Art/House/eye_open.png"),
	preload("res://Art/House/eye_spiral.png")
]

var hallucination_tint: ColorRect
var hallucination_eye: TextureRect
var eye_animation: Tween

func _create_hallucination_effect() -> void:
	var tint_layer := CanvasLayer.new()
	tint_layer.layer = 1
	add_child(tint_layer)
	hallucination_tint = ColorRect.new()
	var mask_material := ShaderMaterial.new()
	mask_material.shader = preload("res://Scenes/Levels/hallucination_mask.gdshader")
	hallucination_tint.material = mask_material
	hallucination_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint_layer.add_child(hallucination_tint)
	hallucination_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hallucination_tint.hide()
	$HUD.layer = 2
	var eye_layer := CanvasLayer.new()
	eye_layer.layer = 3
	add_child(eye_layer)
	hallucination_eye = TextureRect.new()
	hallucination_eye.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hallucination_eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hallucination_eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eye_layer.add_child(hallucination_eye)
	hallucination_eye.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hallucination_eye.offset_left = -96
	hallucination_eye.offset_top = -96
	hallucination_eye.offset_right = 96
	hallucination_eye.offset_bottom = 96
	hallucination_eye.hide()

func _update_hallucination_effect() -> void:
	if hallucination_tint.visible == hallucinating:
		return
	hallucination_tint.visible = hallucinating
	if eye_animation and eye_animation.is_running():
		eye_animation.kill()
	var first := 0 if hallucinating else 2
	var last := 2 - first
	hallucination_eye.texture = EYE_FRAMES[first]
	hallucination_eye.show()
	eye_animation = create_tween()
	eye_animation.tween_callback(hallucination_eye.set_texture.bind(EYE_FRAMES[1])).set_delay(0.30)
	eye_animation.tween_callback(hallucination_eye.set_texture.bind(EYE_FRAMES[last])).set_delay(0.10)
	eye_animation.tween_callback(hallucination_eye.hide).set_delay(0.15)

func _open_wire_puzzle() -> void:
	if lights_fixed or busy:
		return
	busy = true
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	var puzzle := preload("res://Scenes/Levels/wire_puzzle.gd").new()
	add_child(puzzle)
	puzzle.cancelled.connect(_close_wire_puzzle.bind(puzzle, false))
	puzzle.solved.connect(_close_wire_puzzle.bind(puzzle, true))

func _close_wire_puzzle(puzzle: CanvasLayer, solved: bool) -> void:
	puzzle.queue_free()
	busy = false
	player.jump_blocked_until_release = Input.is_action_pressed("house_jump")
	player.set_physics_process(true)
	if solved:
		learned_hints["Wires"] = true
		lights_fixed = true
		var corridor: Dictionary = HouseSession.rooms.get("res://Scenes/Levels/hallway.tscn", {})
		if not corridor.is_empty():
			corridor["lights_fixed"] = true
		_refresh_objects()
