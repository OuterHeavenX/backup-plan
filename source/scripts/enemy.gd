class_name Enemy
extends CharacterBody3D
signal died(enemy: Enemy)
@export var hp: float = 75.0
@export var speed: float = 3.0
@export var attack_range: float = 1.3
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0
# Attack telegraph: wind up (eyes flare, head swells, spikes flick out)
# before striking; the strike only lands if the player is still in reach.
@export var windup_time: float = 0.35
@export var strike_reach_bonus: float = 0.5
# "grunt" (default), "runner" (fast, fragile, small) or "brute" (slow,
# huge, slams the ground).
@export var variant: String = "grunt"
# Difficulty scaling applied on ready.
@export var hp_scale: float = 1.0
@export var damage_scale: float = 1.0
const GRAVITY: float = 20.0
const NAV_TARGET_INTERVAL: float = 0.15
const TELEGRAPH_EYE_BOOST: float = 3.0
const TELEGRAPH_HEAD_SCALE: float = 1.35
const STUCK_SPEED_FRACTION: float = 0.3
const UNSTICK_TIME: float = 0.5
var _dead: bool = false
var _cooldown: float = 0.0
var _windup: float = 0.0
var _mats: Array[StandardMaterial3D] = []
var _orig_emission: Array = []
var _eye_mats: Array[StandardMaterial3D] = []
var _flash_tween: Tween = null
var _lunge_tween: Tween = null
var _telegraph_tween: Tween = null
var _stagger_tween: Tween = null
var _flash_energy: float = 2.0
var _head: MeshInstance3D = null
var _body: MeshInstance3D = null
var _spike_l: MeshInstance3D = null
var _spike_r: MeshInstance3D = null
var _body_base_y: float = 0.9
var _head_base_y: float = 1.68
var _head_min_y: float = 1.45
var _head_half_width: float = 0.35
var _mesh_scale: float = 1.0
var _anim_t: float = 0.0
var _agent: NavigationAgent3D = null
var _nav_timer: float = 0.0
var _unstick_dir: Vector3 = Vector3.ZERO
var _unstick_time: float = 0.0
var _stuck_strikes: int = 0
var _free_time: float = 0.0
func _ready() -> void:
	add_to_group("enemies")
	wall_min_slide_angle = 0.0
	_cooldown = randf() * 0.4
	_collect_materials()
	_apply_variant()
	hp *= hp_scale
	attack_damage *= damage_scale
	_agent = NavigationAgent3D.new()
	_agent.name = "NavAgent"
	_agent.radius = 0.5 * _mesh_scale
	_agent.height = 1.95 * _mesh_scale
	_agent.path_desired_distance = 0.5
	_agent.target_desired_distance = 0.5
	_agent.path_max_distance = 3.0
	add_child(_agent)
func _collect_materials() -> void:
	_mats.clear()
	_orig_emission.clear()
	_eye_mats.clear()
	_head = get_node_or_null("Head") as MeshInstance3D
	_body = get_node_or_null("Body") as MeshInstance3D
	_spike_l = get_node_or_null("SpikeL") as MeshInstance3D
	_spike_r = get_node_or_null("SpikeR") as MeshInstance3D
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
		if mi.name.begins_with("Eye"):
			_eye_mats.append(m)
func _apply_variant() -> void:
	var k := 1.0
	var body_color := Color(0.07, 0.07, 0.09)
	var eye_color := Color(1.0, 0.08, 0.06)
	match variant:
		"runner":
			speed = 5.5
			hp = 30.0
			attack_damage = 6.0
			attack_cooldown = 0.7
			windup_time = 0.25
			k = 0.8
			body_color = Color(0.22, 0.06, 0.05)
			eye_color = Color(1.0, 0.45, 0.05)
		"brute":
			speed = 2.0
			hp = 200.0
			attack_damage = 25.0
			attack_cooldown = 1.6
			attack_range = 2.0
			windup_time = 0.7
			strike_reach_bonus = 1.2
			k = 1.35
			body_color = Color(0.09, 0.1, 0.13)
			eye_color = Color(0.75, 0.9, 1.0)
	_mesh_scale = k
	_head_min_y = 1.45 * k
	_head_half_width = 0.35 * k
	if k != 1.0:
		for child in get_children():
			var mi := child as MeshInstance3D
			if mi != null:
				mi.position *= k
				mi.scale *= k
		var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs != null and cs.shape is BoxShape3D:
			var box := (cs.shape as BoxShape3D).duplicate() as BoxShape3D
			box.size *= k
			cs.shape = box
			cs.position *= k
	if _body != null:
		_body_base_y = _body.position.y
	if _head != null:
		_head_base_y = _head.position.y
	if variant == "grunt":
		return
	for i in range(_mats.size()):
		var m: StandardMaterial3D = _mats[i]
		if _eye_mats.has(m):
			m.emission = eye_color
			_orig_emission[i][1] = m.emission
		else:
			m.albedo_color = body_color
func is_headshot(local_pos: Vector3) -> bool:
	return local_pos.y >= _head_min_y and absf(local_pos.x) <= _head_half_width
func is_dead() -> bool:
	return _dead
func take_damage(amount: float, headshot: bool = false) -> void:
	if _dead:
		return
	hp -= amount
	_flash_hit(4.0 if headshot else 2.0)
	if headshot:
		_sfx_at("hit", 0.0, randf_range(1.3, 1.5))
		_stagger()
	else:
		_sfx_at("hit", -3.0, randf_range(0.9, 1.1))
	if hp <= 0.0:
		_die()
func _sfx_at(kind: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var sfx: Node = get_tree().get_first_node_in_group("sfx")
	if sfx != null and sfx.has_method("play_at"):
		sfx.play_at(kind, global_position + Vector3(0, 1.2 * _mesh_scale, 0), volume_db, pitch)
func _flash_hit(energy: float = 2.0) -> void:
	if _mats.is_empty():
		return
	_flash_energy = energy
	for m in _mats:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.9, 0.85)
		m.emission_energy_multiplier = energy
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(_apply_flash_blend, 0.0, 1.0, 0.22)
func _apply_flash_blend(t: float) -> void:
	for i in range(_mats.size()):
		var m: StandardMaterial3D = _mats[i]
		var o: Array = _orig_emission[i]
		m.emission = Color(1.0, 0.9, 0.85).lerp(o[1] as Color, t)
		var base_energy: float = float(o[2])
		if _windup > 0.0 and _eye_mats.has(m):
			base_energy *= TELEGRAPH_EYE_BOOST
		m.emission_energy_multiplier = lerpf(_flash_energy, base_energy, t)
		if t >= 1.0:
			m.emission_enabled = bool(o[0])
func _stagger() -> void:
	if _head == null:
		return
	if _stagger_tween != null and _stagger_tween.is_valid():
		_stagger_tween.kill()
	_stagger_tween = create_tween()
	_stagger_tween.tween_property(_head, "rotation:x", -0.55, 0.06)
	_stagger_tween.tween_property(_head, "rotation:x", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Knocked back a step.
	var back: Vector3 = global_transform.basis.z
	back.y = 0.0
	velocity += back.normalized() * 2.5
func _set_telegraph(on: bool) -> void:
	for i in range(_mats.size()):
		var m: StandardMaterial3D = _mats[i]
		if not _eye_mats.has(m):
			continue
		var o: Array = _orig_emission[i]
		m.emission_energy_multiplier = float(o[2]) * (TELEGRAPH_EYE_BOOST if on else 1.0)
	if _head == null:
		return
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	_telegraph_tween = create_tween()
	var target_scale := Vector3.ONE * _mesh_scale * (TELEGRAPH_HEAD_SCALE if on else 1.0)
	if on:
		_telegraph_tween.tween_property(_head, "scale", target_scale, windup_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		_telegraph_tween.tween_property(_head, "scale", target_scale, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
func _die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	_sfx_at("growl", 0.0, 0.6 if variant != "brute" else 0.4)
	for tw in [_flash_tween, _lunge_tween, _telegraph_tween, _stagger_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
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
	tw.tween_property(self, "global_position:y", global_position.y - 1.0 * _mesh_scale, 0.6) \
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
		velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 8.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		_animate(delta)
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > 0.05:
		var target_yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, 10.0 * delta))
	var wants_move := false
	if _windup > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 8.0 * delta)
		_windup -= delta
		if _windup <= 0.0:
			_strike(player, dist)
	elif dist > attack_range:
		wants_move = true
		var dir := _chase_direction(player, to_player / dist, delta)
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
			_windup = windup_time
			_set_telegraph(true)
			_sfx_at("growl", -2.0 if variant != "brute" else 2.0, randf_range(0.9, 1.15) if variant != "brute" else 0.55)
	_apply_gravity(delta)
	move_and_slide()
	if wants_move:
		_update_stuck_state(to_player, delta)
	_animate(delta)
func _strike(player: Node3D, dist: float) -> void:
	_set_telegraph(false)
	_lunge()
	var landed := dist <= attack_range + strike_reach_bonus
	if variant == "brute":
		_sfx_at("slam", 2.0)
		if player.has_method("shake") and dist < 7.0:
			player.shake(0.6 if landed else 0.35)
	if landed and player.has_method("take_damage"):
		player.take_damage(attack_damage)
func _animate(delta: float) -> void:
	var moving: float = clampf(Vector2(velocity.x, velocity.z).length() / maxf(speed, 0.01), 0.0, 1.0)
	_anim_t += delta * (2.0 + 8.0 * moving)
	if _body != null:
		_body.position.y = _body_base_y + sin(_anim_t) * 0.045 * _mesh_scale * moving
		_body.rotation.x = lerpf(_body.rotation.x, -0.14 * moving, minf(1.0, 8.0 * delta))
	if _head != null:
		_head.position.y = _head_base_y + sin(_anim_t + 0.6) * 0.03 * _mesh_scale * moving
	var spike_out: float = 0.12 + (0.9 if _windup > 0.0 else 0.0)
	if _spike_l != null:
		_spike_l.rotation.z = lerpf(_spike_l.rotation.z, spike_out, minf(1.0, 14.0 * delta))
	if _spike_r != null:
		_spike_r.rotation.z = lerpf(_spike_r.rotation.z, -spike_out, minf(1.0, 14.0 * delta))
func _chase_direction(player: Node3D, direct: Vector3, delta: float) -> Vector3:
	if _agent == null:
		return direct
	var map: RID = get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return direct
	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_timer = NAV_TARGET_INTERVAL
		_agent.target_position = player.global_position
	if _agent.is_navigation_finished():
		return direct
	var next: Vector3 = _agent.get_next_path_position()
	var d := next - global_position
	d.y = 0.0
	if d.length() < 0.05:
		return direct
	return d.normalized()
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
		velocity.y -= GRAVITY * delta
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
	_lunge_tween.tween_property(self, "global_position", base + fwd * 0.35 * _mesh_scale, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_tween.tween_property(self, "global_position", base, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
