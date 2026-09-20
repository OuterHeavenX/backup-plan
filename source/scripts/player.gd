class_name Player
extends CharacterBody3D
signal health_changed(hp: float, max_hp: float)
signal died
@export var max_hp: float = 100.0
var hp: float = 100.0
@export var walk_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var look_sens: float = 0.0025
# Thumb drags cover far fewer pixels than a mouse, so touch look gets its
# own, higher sensitivity.
@export var touch_look_sens: float = 0.005
# Touch aim assist: while the FIRE button is held, pull the view gently
# toward the nearest enemy inside a narrow cone.
@export var aim_assist_enabled: bool = true
@export var aim_assist_cone_deg: float = 7.0
@export var aim_assist_speed: float = 6.0
@export var aim_assist_max_rate_deg: float = 90.0
var touch_move: Vector2 = Vector2.ZERO
var touch_firing: bool = false
const GRAVITY: float = 20.0
const PITCH_LIMIT: float = 85.0
var _dead: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
func _ready() -> void:
	add_to_group("player")
	# Slide along walls even when walking into them almost head-on; the
	# default 15 degree threshold makes rubble and walls feel sticky.
	wall_min_slide_angle = 0.0
func take_damage(amount: float) -> void:
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	health_changed.emit(hp, max_hp)
	var sfx: Node = get_tree().get_first_node_in_group("sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("hurt", -6.0, randf_range(0.9, 1.1))
	if hp <= 0.0:
		_dead = true
		died.emit()
func is_dead() -> bool:
	return _dead
func apply_touch_move(vec: Vector2) -> void:
	touch_move = vec.limit_length(1.0)
func apply_touch_look(delta: Vector2) -> void:
	_apply_look(delta, touch_look_sens)
func _apply_look(delta: Vector2, sens: float) -> void:
	_yaw -= delta.x * sens
	_pitch = clampf(_pitch - delta.y * sens, deg_to_rad(-PITCH_LIMIT), deg_to_rad(PITCH_LIMIT))
	rotation.y = _yaw
	head.rotation.x = _pitch
func set_touch_firing(pressed: bool) -> void:
	touch_firing = pressed
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Never re-capture the mouse while dead or while a HUD overlay
			# (story card, death/win screen) is up - the player needs the
			# cursor to press the buttons.
			if _dead or _hud_input_locked():
				return
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mm := event as InputEventMouseMotion
			_apply_look(mm.relative, look_sens)
func _hud_input_locked() -> bool:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	return hud != null and bool(hud.get("input_locked"))
func _apply_aim_assist(delta: float) -> void:
	var cam_pos: Vector3 = head.global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var cone := deg_to_rad(aim_assist_cone_deg)
	var best_dir := Vector3.ZERO
	var best_angle := cone
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D):
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		var to: Vector3 = (e as Node3D).global_position + Vector3(0, 1.2, 0) - cam_pos
		if to.length() < 0.5:
			continue
		var d := to.normalized()
		var ang := acos(clampf(forward.dot(d), -1.0, 1.0))
		if ang < best_angle:
			best_angle = ang
			best_dir = d
	if best_dir == Vector3.ZERO:
		return
	var want_yaw := atan2(-best_dir.x, -best_dir.z)
	var want_pitch := asin(clampf(best_dir.y, -1.0, 1.0))
	var max_step := deg_to_rad(aim_assist_max_rate_deg) * delta
	var dyaw := clampf(angle_difference(_yaw, want_yaw) * aim_assist_speed * delta, -max_step, max_step)
	var dpitch := clampf((want_pitch - _pitch) * aim_assist_speed * delta, -max_step, max_step)
	_yaw += dyaw
	_pitch = clampf(_pitch + dpitch, deg_to_rad(-PITCH_LIMIT), deg_to_rad(PITCH_LIMIT))
	rotation.y = _yaw
	head.rotation.x = _pitch
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	if not _dead and not _hud_input_locked():
		if touch_firing and aim_assist_enabled:
			_apply_aim_assist(delta)
		var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		input_vec += touch_move
		input_vec = input_vec.limit_length(1.0)
		var dir := Vector3.ZERO
		if input_vec.length() > 0.001:
			dir = (transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)).normalized()
		velocity.x = dir.x * walk_speed
		velocity.z = dir.z * walk_speed
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
