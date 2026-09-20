class_name HUD
extends CanvasLayer
var input_locked: bool = false
var fire_grace_until: int = 0
var _player: Player = null
var _weapon: Weapon = null
var _touch_shown: bool = false
@onready var _crosshair: ColorRect = $UI/Crosshair
@onready var _health_bar: ProgressBar = $UI/HealthBar
@onready var _ammo_label: Label = $UI/AmmoLabel
@onready var _objective_label: Label = $UI/ObjectiveLabel
@onready var _story_overlay: CenterContainer = $UI/StoryOverlay
@onready var _story_text: Label = $UI/StoryOverlay/Panel/Margin/VBox/StoryText
@onready var _death_screen: ColorRect = $UI/DeathScreen
@onready var _win_screen: ColorRect = $UI/WinScreen
@onready var _touch_controls: Control = $UI/TouchControls
func _ready() -> void:
	add_to_group("hud")
	layer = 10
	# Keep the HUD (and its buttons) responsive while the tree is paused on
	# the death / win screens.
	process_mode = Node.PROCESS_MODE_ALWAYS
	$UI/DeathScreen/Center/VBox/RestartButton.pressed.connect(_on_restart_pressed)
	$UI/WinScreen/Center/VBox/PlayAgainButton.pressed.connect(_on_restart_pressed)
	_build_touch_controls()
	if DisplayServer.is_touchscreen_available():
		_show_touch_controls()
func bind(p: Player, w: Weapon) -> void:
	_player = p
	_weapon = w
	if _player != null:
		_player.health_changed.connect(_on_health_changed)
	if _weapon != null:
		_weapon.ammo_changed.connect(_on_ammo_changed)
		_on_ammo_changed(_weapon.mag, _weapon.reserve)
func show_story(text: String) -> void:
	_story_text.text = text
	_story_overlay.visible = true
	input_locked = true
func show_death() -> void:
	input_locked = true
	_death_screen.visible = true
	_end_screen_shown()
func show_win() -> void:
	input_locked = true
	_win_screen.visible = true
	_end_screen_shown()
func _end_screen_shown() -> void:
	# Give the cursor back (it is captured during play) so RESTART / PLAY
	# AGAIN can actually be clicked, and freeze the world behind the overlay.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
func set_objective(t: String) -> void:
	_objective_label.text = t
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not _touch_shown:
		_show_touch_controls()
	if input_locked and _story_overlay.visible:
		var dismiss := false
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			dismiss = true
		elif event is InputEventScreenTouch and event.pressed:
			dismiss = true
		elif event.is_action_pressed("ui_accept"):
			dismiss = true
		if dismiss:
			_story_overlay.visible = false
			input_locked = false
			fire_grace_until = Time.get_ticks_msec() + 150
			get_viewport().set_input_as_handled()
			if event is InputEventMouseButton:
				# Desktop: the dismissing click also captures the mouse, so
				# the player does not need a second click to start looking.
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _on_health_changed(hp: float, max_hp: float) -> void:
	_health_bar.max_value = max_hp
	_health_bar.value = hp
func _on_ammo_changed(mag: int, reserve: int) -> void:
	var res_text: String = "∞" if reserve < 0 else str(reserve)
	_ammo_label.text = "%d / %s" % [mag, res_text]
func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
func _show_touch_controls() -> void:
	_touch_shown = true
	_touch_controls.visible = true
func _build_touch_controls() -> void:
	var joy := TouchJoystick.new()
	joy.name = "Joystick"
	joy.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy.output = func(v: Vector2) -> void:
		if input_locked:
			return
		if _player != null:
			_player.apply_touch_move(v)
	_touch_controls.add_child(joy)
	var look := TouchLookArea.new()
	look.name = "LookArea"
	look.set_anchors_preset(Control.PRESET_FULL_RECT)
	look.mouse_filter = Control.MOUSE_FILTER_IGNORE
	look.hud_ref = self
	look.stick_ref = joy
	_touch_controls.add_child(look)
	var fire := Button.new()
	fire.name = "FireButton"
	fire.text = "FIRE"
	fire.anchor_left = 1.0
	fire.anchor_top = 1.0
	fire.anchor_right = 1.0
	fire.anchor_bottom = 1.0
	fire.offset_left = -196.0
	fire.offset_top = -216.0
	fire.offset_right = -56.0
	fire.offset_bottom = -116.0
	_style_touch_button(fire)
	fire.button_down.connect(_on_touch_fire_down)
	fire.button_up.connect(_on_touch_fire_up)
	_touch_controls.add_child(fire)
	var reload_btn := Button.new()
	reload_btn.name = "ReloadButton"
	reload_btn.text = "RELOAD"
	reload_btn.anchor_left = 1.0
	reload_btn.anchor_top = 1.0
	reload_btn.anchor_right = 1.0
	reload_btn.anchor_bottom = 1.0
	reload_btn.offset_left = -196.0
	reload_btn.offset_top = -336.0
	reload_btn.offset_right = -56.0
	reload_btn.offset_bottom = -252.0
	_style_touch_button(reload_btn)
	reload_btn.pressed.connect(_on_touch_reload_pressed)
	_touch_controls.add_child(reload_btn)
	look.fire_button = fire
	look.reload_button = reload_btn
func _style_touch_button(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.06, 0.06, 0.85)
	normal.border_color = Color(0.62, 0.14, 0.1, 1.0)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.4, 0.09, 0.07, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.85, 1.0))
	b.add_theme_font_size_override("font_size", 22)
func _on_touch_fire_down() -> void:
	if input_locked:
		return
	if _player != null:
		_player.set_touch_firing(true)
	if _weapon != null:
		_weapon.set_firing(true)
func _on_touch_fire_up() -> void:
	if _player != null:
		_player.set_touch_firing(false)
	if _weapon != null:
		_weapon.set_firing(false)
func _on_touch_reload_pressed() -> void:
	if input_locked:
		return
	if _weapon != null:
		_weapon.start_reload()
class TouchJoystick extends Control:
	const MOVE_FRACTION: float = 0.5
	var radius: float = 105.0
	var knob_radius: float = 40.0
	var output: Callable = func(_v: Vector2) -> void: pass
	var _touch_index: int = -1
	var _base_pos: Vector2 = Vector2.ZERO
	var _knob_offset: Vector2 = Vector2.ZERO
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if event.pressed:
				if event.index == _touch_index:
					_reset_touch()
				if _touch_index == -1 and _is_move_touch(event.position):
					_touch_index = event.index
					_base_pos = event.position
					_knob_offset = Vector2.ZERO
					output.call(Vector2.ZERO)
					queue_redraw()
			elif event.index == _touch_index:
				_reset_touch()
		elif event is InputEventScreenDrag:
			if event.index == _touch_index:
				_update_knob(event.position)
	func get_touch_index() -> int:
		return _touch_index
	func _reset_touch() -> void:
		_touch_index = -1
		_knob_offset = Vector2.ZERO
		output.call(Vector2.ZERO)
		queue_redraw()
	func _is_move_touch(pos: Vector2) -> bool:
		return pos.x < get_viewport_rect().size.x * MOVE_FRACTION
	func _update_knob(pos: Vector2) -> void:
		var d: Vector2 = pos - _base_pos
		if d.length() > radius:
			d = d.normalized() * radius
		_knob_offset = d
		output.call(d / radius)
		queue_redraw()
	func _draw() -> void:
		if _touch_index == -1:
			var hint := Vector2(160.0, get_viewport_rect().size.y - 220.0)
			draw_circle(hint, radius, Color(1, 1, 1, 0.03))
			draw_arc(hint, radius, 0.0, TAU, 48, Color(0.9, 0.25, 0.15, 0.18), 3.0, true)
		else:
			draw_circle(_base_pos, radius, Color(1, 1, 1, 0.1))
			draw_arc(_base_pos, radius, 0.0, TAU, 48, Color(0.9, 0.25, 0.15, 0.55), 3.0, true)
			draw_circle(_base_pos + _knob_offset, knob_radius, Color(1, 1, 1, 0.22))
			draw_arc(_base_pos + _knob_offset, knob_radius, 0.0, TAU, 32, Color(0.9, 0.3, 0.2, 0.8), 2.0, true)
class TouchLookArea extends Control:
	var hud_ref: HUD = null
	var fire_button: Button = null
	var reload_button: Button = null
	var stick_ref: TouchJoystick = null
	const FIRE_LEAVE_MARGIN: float = 14.0
	const LOOK_TELEPORT_PX: float = 200.0
	var _touch_index: int = -1
	var _fire_touch_index: int = -1
	var _last_look_pos: Vector2 = Vector2.ZERO
	var _fire_last_pos: Vector2 = Vector2.ZERO
	var _teleport_strikes: int = 0
	func _input(event: InputEvent) -> void:
		if hud_ref == null or hud_ref._player == null:
			return
		if hud_ref.input_locked:
			_release_all()
			return
		if event is InputEventScreenTouch:
			if event.pressed:
				_on_touch_down(event.index, event.position)
			else:
				_on_touch_up(event.index)
		elif event is InputEventScreenDrag:
			_on_touch_drag(event.index, event.position, event.relative)
	func _release_all() -> void:
		_touch_index = -1
		_fire_touch_index = -1
		_teleport_strikes = 0
	func _on_touch_down(index: int, pos: Vector2) -> void:
		if index == _touch_index or index == _fire_touch_index:
			_release_all()
		if _touch_index == -1 and _is_look_touch(pos):
			_touch_index = index
			_last_look_pos = pos
			_teleport_strikes = 0
		elif _fire_touch_index == -1 and _is_fire_touch(pos):
			_fire_touch_index = index
			_fire_last_pos = pos
	func _on_touch_up(index: int) -> void:
		if index == _touch_index:
			_touch_index = -1
			_teleport_strikes = 0
		if index == _fire_touch_index:
			_fire_touch_index = -1
	func _on_touch_drag(index: int, pos: Vector2, _relative: Vector2) -> void:
		# InputEventScreenDrag.relative is deliberately ignored. Godot's web
		# platform computes it against the wrong finger when more than one
		# touch is down (its previous-position table is indexed by the slot
		# inside the touchmove event, not by the touch id), which spun the
		# camera whenever both thumbs were on the screen. The delta is derived
		# from the tracked positions instead, which are always correct.
		if stick_ref != null and index == stick_ref.get_touch_index():
			return
		if index == _touch_index:
			var delta: Vector2 = pos - _last_look_pos
			if delta.length() > LOOK_TELEPORT_PX:
				_teleport_strikes += 1
				_last_look_pos = pos
				if _teleport_strikes >= 2:
					_touch_index = -1
					_teleport_strikes = 0
				return
			_teleport_strikes = 0
			_last_look_pos = pos
			hud_ref._player.apply_touch_look(delta)
		elif index == _fire_touch_index and _touch_index == -1:
			if not _is_fire_touch(pos, FIRE_LEAVE_MARGIN):
				var delta: Vector2 = pos - _fire_last_pos
				_fire_touch_index = -1
				_touch_index = index
				_last_look_pos = pos
				_teleport_strikes = 0
				if delta.length() <= LOOK_TELEPORT_PX:
					hud_ref._player.apply_touch_look(delta)
			else:
				_fire_last_pos = pos
	func _is_fire_touch(pos: Vector2, margin: float = 0.0) -> bool:
		if fire_button == null:
			return false
		return fire_button.get_global_rect().grow(margin).has_point(pos)
	func _is_look_touch(pos: Vector2) -> bool:
		if pos.x < get_viewport_rect().size.x * TouchJoystick.MOVE_FRACTION:
			return false
		if _is_fire_touch(pos):
			return false
		if reload_button != null and reload_button.get_global_rect().has_point(pos):
			return false
		return true
