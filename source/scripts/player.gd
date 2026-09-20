class_name Player
extends CharacterBody3D
signal health_changed(hp: float, max_hp: float)
signal died
@export var max_hp: float = 100.0
var hp: float = 100.0
@export var walk_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var look_sens: float = 0.0025
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
func take_damage(amount: float) -> void:
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	health_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_dead = true
		died.emit()
func is_dead() -> bool:
	return _dead
func apply_touch_move(vec: Vector2) -> void:
	touch_move = vec.limit_length(1.0)
func apply_touch_look(delta: Vector2) -> void:
	_yaw -= delta.x * look_sens
	_pitch = clampf(_pitch - delta.y * look_sens, deg_to_rad(-PITCH_LIMIT), deg_to_rad(PITCH_LIMIT))
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
			apply_touch_look(mm.relative)
func _hud_input_locked() -> bool:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	return hud != null and bool(hud.get("input_locked"))
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	if not _dead:
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
