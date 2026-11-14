extends CharacterBody2D

signal z_changed(new_z)

const SPEED := 300.0
const JUMP_VELOCITY := -520.0
const GRAVITY := 1400.0
const SIZE := Vector2(32, 48)
const MIN_Z := 1
const MAX_Z := 3
const COYOTE_TIME := 0.05   # seconds you can still jump after leaving a platform
const STEP_HEIGHT := 14.0   # biggest ledge he walks onto without jumping (pixels)

@export var layer_switching_enabled := true

var z := 1   # current z-index (default 1)
var coyote_timer := 0.0
var can_jump := true   # the level turns this off while the hero is holding an object

func _ready() -> void:
	floor_snap_length = STEP_HEIGHT + 4.0   # keeps him glued to the ground after a step
	_apply_z(1)

func _apply_z(new_z: int) -> void:
	z = new_z
	collision_layer = 0
	collision_mask = 1 << (z - 1)
	z_index = z * 2 + 1
	z_changed.emit(z)

func _input(event: InputEvent) -> void:
	if not layer_switching_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_W: _try_change_z(z + 1)
			KEY_S: _try_change_z(z - 1)

func _try_change_z(new_z: int) -> void:
	new_z = clampi(new_z, MIN_Z, MAX_Z)
	if new_z == z:
		return
	# Don't switch if it would put the player inside a solid object
	var query := PhysicsShapeQueryParameters2D.new()
	var s := RectangleShape2D.new()
	s.size = SIZE - Vector2(2, 2)
	query.shape = s
	query.transform = global_transform
	query.collision_mask = 1 << (new_z - 1)
	if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		_apply_z(new_z)

func _physics_process(delta: float) -> void:
	# Gravity, plus the coyote-time timer
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		velocity.y += GRAVITY * delta
		coyote_timer -= delta

	var dir := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir += 1.0
	velocity.x = dir * SPEED

	# Jump with Space (W / S now change the z-index)
	if can_jump and Input.is_physical_key_pressed(KEY_SPACE) and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0

	_try_step_up(delta)
	move_and_slide()

func _try_step_up(delta: float) -> void:
	# Only while walking on the ground, not while jumping or falling
	if not is_on_floor() or velocity.y < 0.0 or is_zero_approx(velocity.x):
		return
	var motion := Vector2(velocity.x * delta, 0.0)
	if not test_move(global_transform, motion):
		return                                   # nothing in the way
	var up := Vector2(0.0, -STEP_HEIGHT)
	if test_move(global_transform, up):
		return                                   # no room above (ceiling)
	if test_move(global_transform.translated(up), motion):
		return                                   # still blocked when raised: a wall, not a step
	global_position.y -= STEP_HEIGHT
