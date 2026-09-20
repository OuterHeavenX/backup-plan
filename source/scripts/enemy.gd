class_name Enemy
extends CharacterBody3D
signal died(enemy: Enemy)
@export var hp: float = 75.0
@export var speed: float = 3.0
@export var attack_range: float = 1.3
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0
var gravity: float = 20.0
var _dead: bool = false
var _cooldown: float = 0.0
var _mats: Array[StandardMaterial3D] = []
var _orig_emission: Array = []
var _flash_tween: Tween = null
var _lunge_tween: Tween = null
# Obstacle recovery: when a straight line to the player is blocked by rubble,
# sidestep (alternating sides, backing off slightly) instead of pushing into it.
const STUCK_SPEED_FRACTION: float = 0.3
const UNSTICK_TIME: float = 0.5
var _unstick_dir: Vector3 = Vector3.ZERO
var _unstick_time: float = 0.0
var _stuck_strikes: int = 0
var _free_time: float = 0.0
func _ready() -> void:
	add_to_group("enemies")
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 20.0))
	_cooldown = randf() * 0.4
	_collect_materials()
func _collect_materials() -> void:
	_mats.clear()
	_orig_emission.clear()
	for child in get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var src: StandardMaterial3D = mi.get_surface_override_material(0) as StandardMaterial3D
		if src == null and mi.mesh != null:
			src = mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src == null:
			continue
		var m := src.duplicate() as StandardMaterial3D
		mi.set_surface_override_material(0, m)
		_mats.append(m)
		_orig_emission.append([m.emission_enabled, m.emission, m.emission_energy_multiplier])
func take_damage(amount: float) -> void:
	if _dead:
		return
	hp -= amount
	_flash_hit()
	if hp <= 0.0:
		_die()
func _flash_hit() -> void:
	if _mats.is_empty():
		return
	for m in _mats:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.9, 0.85)
		m.emission_energy_multiplier = 2.0
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(_apply_flash_blend, 0.0, 1.0, 0.22)
func _apply_flash_blend(t: float) -> void:
	for i in range(_mats.size()):
		var m: StandardMaterial3D = _mats[i]
		var o: Array = _orig_emission[i]
		m.emission = Color(1.0, 0.9, 0.85).lerp(o[1] as Color, t)
		m.emission_energy_multiplier = lerpf(2.0, float(o[2]), t)
		if t >= 1.0:
			m.emission_enabled = bool(o[0])
func _die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	set_physics_process(false)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null:
		cs.set_deferred("disabled", true)
	for m in _mats:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position:y", global_position.y - 1.0, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(_apply_fade, 1.0, 0.0, 0.6)
	tw.set_parallel(false)
	tw.tween_callback(queue_free)
func _apply_fade(v: float) -> void:
	for m in _mats:
		var c := m.albedo_color
		c.a = v
		m.albedo_color = c
func _physics_process(delta: float) -> void:
	if _dead:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		_apply_gravity(delta)
		move_and_slide()
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if player.has_method("is_dead") and player.is_dead():
		# Nothing left to fight: stand still instead of lunging at a corpse.
		velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 8.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > 0.05:
		var target_yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, 10.0 * delta))
	var wants_move := false
	if dist > attack_range:
		wants_move = true
		var dir := to_player / dist
		if _unstick_time > 0.0:
			_unstick_time -= delta
			dir = _unstick_dir
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 8.0 * delta)
		if _cooldown <= 0.0:
			_cooldown = attack_cooldown
			if player.has_method("take_damage"):
				player.take_damage(attack_damage)
			_lunge()
	_apply_gravity(delta)
	move_and_slide()
	if wants_move:
		_update_stuck_state(to_player, delta)
func _update_stuck_state(to_player: Vector3, delta: float) -> void:
	if _unstick_time > 0.0:
		return
	var real := get_real_velocity()
	var moving := Vector2(real.x, real.z).length() >= speed * STUCK_SPEED_FRACTION
	if moving or not is_on_wall():
		_free_time += delta
		if _free_time > 1.5:
			_stuck_strikes = 0
		return
	_free_time = 0.0
	_stuck_strikes += 1
	var side := Vector3(-to_player.z, 0.0, to_player.x).normalized()
	if _stuck_strikes % 2 == 0:
		side = -side
	var back := -to_player.normalized() * (0.6 if _stuck_strikes > 2 else 0.25)
	_unstick_dir = (side + back).normalized()
	_unstick_time = UNSTICK_TIME
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
func _lunge() -> void:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	var base := global_position
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(self, "global_position", base + fwd * 0.35, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_tween.tween_property(self, "global_position", base, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
