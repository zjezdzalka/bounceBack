extends CharacterBody2D

signal z_changed(new_z)

const SPEED := 300.0
const JUMP_VELOCITY := -520.0
const GRAVITY := 1400.0
const SIZE := Vector2(32, 48)
const MIN_Z := 1
const MAX_Z := 3

var z := 1   # current z-index (default 1)

func _ready() -> void:
	_apply_z(1)

func _apply_z(new_z: int) -> void:
	z = new_z
	collision_layer = 0                 # nothing needs to collide with the player
	collision_mask = 1 << (z - 1)       # only collide with objects on the same z
	z_index = z * 2 + 1                 # draw in front of objects on the same z
	z_changed.emit(z)

func _input(event: InputEvent) -> void:
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
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var dir := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir += 1.0
	velocity.x = dir * SPEED

	# Jump with Space (W / S now change the z-index)
	var jump := Input.is_physical_key_pressed(KEY_SPACE) \
		or Input.is_physical_key_pressed(KEY_UP) \
		or Input.is_physical_key_pressed(KEY_K)
	if jump and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()
