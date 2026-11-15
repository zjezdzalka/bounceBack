extends CanvasLayer

signal solved
signal cancelled

const SIZE := 6
const COLORS := [
	Color("#ff777f"), Color("#79c9ff"), Color("#ffe177"),
	Color("#92e4a2"), Color("#d5a2ff"), Color("#ffad70")
]

const SYMBOLS := ["●", "▲", "■", "◆", "✚", "★"]

var endpoints: Dictionary = {}
var paths: Dictionary = {}
var cells: Dictionary = {}
var active := -1
var completed := false
var message: Label

func _ready() -> void:
	layer = 10
	_generate()
	_build_board()
	_redraw()

func _generate() -> void:
	var walk: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			walk.append(Vector2i(x if y % 2 == 0 else SIZE - 1 - x, y))
	# Reconnect adjacent cells at one end to shuffle the walk without losing coverage.
	for step in 90:
		if randf() < 0.5:
			walk.reverse()
		var neighbors: Array[int] = []
		for index in range(2, walk.size()):
			if _adjacent(walk[0], walk[index]):
				neighbors.append(index)
		if not neighbors.is_empty():
			var end: int = neighbors.pick_random()
			var prefix := walk.slice(0, end)
			prefix.reverse()
			walk = prefix + walk.slice(end)
	var offset := 0
	for color in COLORS.size():
		var remaining := walk.size() - offset
		var later := COLORS.size() - color - 1
		var length := remaining if later == 0 else randi_range(4, mini(8, remaining - later * 4))
		endpoints[walk[offset]] = color
		endpoints[walk[offset + length - 1]] = color
		offset += length

func _build_board() -> void:
	var shade := ColorRect.new()
	shade.color = Color("#171320")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	var title := Label.new()
	title.text = "Reconnect the wires"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	message = Label.new()
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(message)
	var grid := GridContainer.new()
	grid.columns = SIZE
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(grid)
	for y in SIZE:
		for x in SIZE:
			var location := Vector2i(x, y)
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(58, 58)
			cell.focus_mode = Control.FOCUS_NONE
			cell.add_theme_font_size_override("font_size", 24)
			cell.button_down.connect(_pick.bind(location))
			grid.add_child(cell)
			cells[location] = cell
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	var reset := Button.new()
	reset.text = "Reset paths"
	reset.pressed.connect(func():
		paths.clear()
		active = -1
		_redraw()
	)
	buttons.add_child(reset)
	var close := Button.new()
	close.text = "Back"
	close.pressed.connect(func(): cancelled.emit())
	buttons.add_child(close)

func _input(event: InputEvent) -> void:
	if completed or active < 0 or not event is InputEventMouseMotion:
		return
	if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		return
	for location in cells:
		if cells[location].get_global_rect().has_point(event.position):
			_extend(location)
			return

func _pick(location: Vector2i) -> void:
	if completed:
		return
	if active >= 0 and _extend(location):
		return
	if endpoints.has(location):
		active = endpoints[location]
		paths[active] = [location]
		_redraw()
		_check_completion()

func _extend(location: Vector2i) -> bool:
	var path: Array = paths[active]
	var last: Vector2i = path.back()
	if not _adjacent(last, location):
		return false
	var previous := path.find(location)
	if previous >= 0:
		path.resize(previous + 1)
		_redraw()
		_check_completion()
		return true
	if _owner(location) != -1 or (endpoints.has(location) and endpoints[location] != active):
		return false
	path.append(location)
	if endpoints.has(location):
		active = -1
	_redraw()
	_check_completion()
	return true

func _check_completion() -> void:
	if not completed and _complete():
		completed = true
		solved.emit()

func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	var difference := (a - b).abs()
	return difference.x + difference.y == 1

func _owner(location: Vector2i) -> int:
	for color in paths:
		if location in paths[color]:
			return color
	return -1

func _complete() -> bool:
	return _connected_pairs() == COLORS.size() and _covered_tiles() == SIZE * SIZE

func _connected_pairs() -> int:
	var total := 0
	for color in COLORS.size():
		var path: Array = paths.get(color, [])
		if _reaches_end(color, path):
			total += 1
	return total

func _covered_tiles() -> int:
	var total := 0
	for color in paths:
		var path: Array = paths[color]
		total += path.size()
		if _reaches_end(color, path) and (path.size() == 1 or not endpoints.has(path.back())):
			total += 1
	return total

func _reaches_end(color: int, path: Array) -> bool:
	if path.is_empty():
		return false
	for location: Vector2i in endpoints:
		if endpoints[location] == color and location != path.front():
			return location == path.back() or _adjacent(location, path.back())
	return false

func _redraw() -> void:
	for location in cells:
		var cell: Button = cells[location]
		var owner := _owner(location)
		var color: int = endpoints.get(location, owner)
		if owner < 0 and color >= 0 and _reaches_end(color, paths.get(color, [])):
			owner = color
		cell.text = SYMBOLS[color] if color >= 0 else ""
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#332d40") if owner < 0 else COLORS[color]
		style.set_border_width_all(2)
		style.border_color = COLORS[color] if endpoints.has(location) else Color("#171320")
		if owner >= 0 and owner == active:
			style.border_color = Color.WHITE
		for state in ["normal", "hover", "pressed"]:
			cell.add_theme_stylebox_override(state, style)
		for font in ["font_color", "font_hover_color", "font_pressed_color"]:
			cell.add_theme_color_override(font, Color("#21192d") if owner >= 0 else (COLORS[color] if color >= 0 else Color.WHITE))
	message.text = "Match symbols and fill every tile  •  Tiles %d/%d  •  Pairs %d/%d" % [
		_covered_tiles(), SIZE * SIZE, _connected_pairs(), COLORS.size()
	]
