extends CanvasLayer

const FILE := "user://house_settings.cfg"
const KEYS := {
	"house_left": KEY_A, "house_right": KEY_D, "house_jump": KEY_SPACE,
	"house_interact": KEY_E, "house_switch": KEY_Q,
}
const NAMES := {
	"house_left": "Move left", "house_right": "Move right", "house_jump": "Jump",
	"house_interact": "Interact / continue", "house_switch": "Hallucination",
}
const BUSES := ["Master", "Sound Effects", "Music", "Dialogue"]

var rooms: Dictionary = {}
var returning := false
var hallucination_in_transit := false
var learned_bounce_back := false
var config := ConfigFile.new()
var panel: CenterContainer
var content: VBoxContainer
var capture := ""
var buttons: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	config.load(FILE)
	for action in KEYS:
		InputMap.add_action(action)
		_bind(action, config.get_value("controls", action, KEYS[action]))
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		_volume(config.get_value("audio", bus, 100.0), bus, false)
	_display(config.get_value("display", "fullscreen", false), false)
	_build_menu()

func key_name(action: String) -> String:
	return OS.get_keycode_string(InputMap.action_get_events(action)[0].physical_keycode)

func _bind(action: String, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if not capture.is_empty():
			buttons[capture].text = key_name(capture)
			capture = ""
		else:
			panel.visible = not panel.visible
			get_tree().paused = panel.visible
	elif panel.visible and not capture.is_empty():
		get_viewport().set_input_as_handled()
		var key: Key = event.physical_keycode
		for action in KEYS:
			if action != capture and InputMap.action_get_events(action)[0].physical_keycode == key:
				buttons[capture].text = "Key in use. Try another."
				return
		_bind(capture, key)
		config.set_value("controls", capture, key)
		config.save(FILE)
		buttons[capture].text = key_name(capture)
		capture = ""

func _build_menu() -> void:
	panel = CenterContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.06, 0.09, 0.9)
	add_child(shade)
	move_child(shade, 0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.visibility_changed.connect(func(): shade.visible = panel.visible)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 420
	panel.add_child(card)
	var margin := MarginContainer.new()
	for side in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	card.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.y = 260
	content.add_child(tabs)
	var settings := VBoxContainer.new()
	settings.name = "Settings"
	tabs.add_child(settings)
	for bus in BUSES:
		var row := _row(settings, bus)
		var slider := HSlider.new()
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value = config.get_value("audio", bus, 100.0)
		row.add_child(slider)
		slider.value_changed.connect(_volume.bind(bus, true))
	var mode := CheckButton.new()
	mode.text = "Fullscreen"
	mode.button_pressed = config.get_value("display", "fullscreen", false)
	settings.add_child(mode)
	mode.toggled.connect(_display.bind(true))
	var controls := VBoxContainer.new()
	controls.name = "Controls"
	tabs.add_child(controls)
	for action in KEYS:
		var row := _row(controls, NAMES[action])
		var button := Button.new()
		button.text = key_name(action)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
		buttons[action] = button
		button.pressed.connect(_capture.bind(action))
	var resume := Button.new()
	resume.text = "Resume"
	content.add_child(resume)
	resume.pressed.connect(func():
		if not capture.is_empty():
			buttons[capture].text = key_name(capture)
			capture = ""
		panel.hide()
		get_tree().paused = false
	)
	panel.hide()

func _capture(action: String) -> void:
	if not capture.is_empty():
		buttons[capture].text = key_name(capture)
	capture = action
	buttons[action].text = "Press a key"

func _row(parent: Control, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 160
	row.add_child(label)
	parent.add_child(row)
	return row

func _volume(value: float, bus: String, save: bool) -> void:
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(index, value <= 0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value / 100.0, 0.001)))
	if save:
		config.set_value("audio", bus, value)
		config.save(FILE)

func _display(fullscreen: bool, save: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if save:
		config.set_value("display", "fullscreen", fullscreen)
		config.save(FILE)

const DOOR_COOLDOWN_MS := 750
var door_ready_at := 0
var door_effect: AudioStreamPlayer

func can_use_door() -> bool:
	return Time.get_ticks_msec() >= door_ready_at and (not is_instance_valid(door_effect) or not door_effect.playing)

func play_door_open() -> void:
	door_ready_at = Time.get_ticks_msec() + DOOR_COOLDOWN_MS
	if not is_instance_valid(door_effect):
		door_effect = AudioStreamPlayer.new()
		door_effect.stream = load("res://Audio/House/door_open.mp3")
		door_effect.bus = "Sound Effects"
		add_child(door_effect)
	door_effect.play()