class_name Weapon
extends Node3D
signal ammo_changed(mag: int, reserve: int)
signal fired
@export var mag_size: int = 30
@export var fire_interval: float = 0.12
@export var damage: float = 25.0
@export var max_range: float = 100.0
@export var reload_time: float = 1.2
var mag: int = 30
var reserve: int = -1
var reloading: bool = false
var firing: bool = false
var _cooldown: float = 0.0
var _camera: Camera3D = null
var _muzzle: Marker3D = null
var _flash: MeshInstance3D = null
var _flash_timer: Timer = null
var _reload_timer: Timer = null
func _ready() -> void:
	_camera = _find_camera()
	_build_gun()
	# Reload runs on a child Timer (not an awaited SceneTreeTimer) so it is
	# freed together with the weapon on scene restart and pauses with it.
	_reload_timer = Timer.new()
	_reload_timer.one_shot = true
	_reload_timer.timeout.connect(_finish_reload)
	add_child(_reload_timer)
func set_firing(pressed: bool) -> void:
	firing = pressed
func try_fire() -> void:
	if reloading:
		return
	if _cooldown > 0.0:
		return
	if _controls_locked():
		return
	if mag <= 0:
		start_reload()
		return
	_cooldown = fire_interval
	mag -= 1
	ammo_changed.emit(mag, reserve)
	fired.emit()
	_do_hitscan()
	_play_muzzle_flash()
func start_reload() -> void:
	if reloading:
		return
	if mag >= mag_size:
		return
	reloading = true
	_reload_timer.start(reload_time)
func _finish_reload() -> void:
	mag = mag_size
	reloading = false
	ammo_changed.emit(mag, reserve)
func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if reloading:
		return
	if _controls_locked():
		return
	if Input.is_action_just_pressed("reload"):
		start_reload()
		return
	var want_fire: bool = Input.is_action_pressed("fire") or firing
	if want_fire and _cooldown <= 0.0:
		try_fire()
func _controls_locked() -> bool:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return false
	if bool(hud.get("input_locked")):
		return true
	var grace_until: int = int(hud.get("fire_grace_until"))
	return Time.get_ticks_msec() < grace_until
func _find_camera() -> Camera3D:
	var n: Node = get_parent()
	while n != null:
		if n is Camera3D:
			return n
		if n.has_node("Camera3D"):
			var c: Node = n.get_node("Camera3D")
			if c is Camera3D:
				return c
		n = n.get_parent()
	var vp_cam: Camera3D = get_viewport().get_camera_3d()
	return vp_cam
func _find_player_collider() -> CollisionObject3D:
	var n: Node = self
	while n != null:
		if n.is_in_group("player") and n is CollisionObject3D:
			return n
		n = n.get_parent()
	return null
func _do_hitscan() -> void:
	if _camera == null:
		_camera = _find_camera()
	if _camera == null:
		return
	var screen_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var origin: Vector3 = _camera.project_ray_origin(screen_center)
	var dir: Vector3 = _camera.project_ray_normal(screen_center)
	var target: Vector3 = origin + dir * max_range
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	var player_col := _find_player_collider()
	if player_col != null:
		query.exclude.append(player_col.get_rid())
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(query)
	var muzzle_pos: Vector3 = _muzzle.global_position if _muzzle != null else origin
	var end_pos: Vector3 = target
	if not hit.is_empty():
		end_pos = hit["position"]
		var collider: Object = hit["collider"]
		if collider is Node and (collider as Node).is_in_group("enemies") and collider.has_method("take_damage"):
			collider.call("take_damage", damage)
		_spawn_impact(end_pos, hit.get("normal", Vector3.UP))
	_spawn_tracer(muzzle_pos, end_pos)
func _spawn_tracer(from_pos: Vector3, to_pos: Vector3) -> void:
	var dist: float = from_pos.distance_to(to_pos)
	if dist < 0.1:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.02, dist)
	tracer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	tracer.material_override = mat
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	root.add_child(tracer)
	tracer.global_position = (from_pos + to_pos) * 0.5
	var shot_dir: Vector3 = (to_pos - from_pos).normalized()
	var up: Vector3 = Vector3.UP
	if absf(shot_dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	tracer.look_at(to_pos, up)
	var tw := tracer.create_tween()
	tw.tween_property(mat, "albedo_color", Color(1.0, 0.85, 0.55, 0.0), 0.06)
	tw.tween_callback(tracer.queue_free)
func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var n: Vector3 = normal
	if n.length() < 0.01:
		n = Vector3.UP
	var impact := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	impact.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.5, 0.2, 0.95)
	impact.material_override = mat
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	root.add_child(impact)
	impact.global_position = pos + n.normalized() * 0.03
	var tw := impact.create_tween().set_parallel(true)
	tw.tween_property(impact, "scale", Vector3(3.0, 3.0, 3.0), 0.15)
	tw.tween_property(mat, "albedo_color", Color(1.0, 0.5, 0.2, 0.0), 0.15)
	tw.chain().tween_callback(impact.queue_free)
func _play_muzzle_flash() -> void:
	if _flash == null or _flash_timer == null:
		return
	_flash.visible = true
	var s: float = randf_range(0.8, 1.4)
	_flash.scale = Vector3(s, s, s)
	_flash_timer.start()
func _build_gun() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.07, 0.09)
	dark.metallic = 0.5
	dark.roughness = 0.55
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.4, 0.05, 0.05)
	accent.emission_enabled = true
	accent.emission = Color(0.9, 0.15, 0.1)
	accent.emission_energy_multiplier = 1.5
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.09, 0.15, 0.45)
	body.mesh = body_mesh
	body.material_override = dark
	body.position = Vector3(0.19, -0.17, -0.35)
	add_child(body)
	var grip := MeshInstance3D.new()
	var grip_mesh := BoxMesh.new()
	grip_mesh.size = Vector3(0.08, 0.18, 0.1)
	grip.mesh = grip_mesh
	grip.material_override = dark
	grip.position = Vector3(0.19, -0.3, -0.22)
	grip.rotation_degrees.x = 12.0
	add_child(grip)
	var barrel := MeshInstance3D.new()
	var barrel_mesh := BoxMesh.new()
	barrel_mesh.size = Vector3(0.055, 0.07, 0.35)
	barrel.mesh = barrel_mesh
	barrel.material_override = dark
	barrel.position = Vector3(0.19, -0.135, -0.68)
	add_child(barrel)
	var sight := MeshInstance3D.new()
	var sight_mesh := BoxMesh.new()
	sight_mesh.size = Vector3(0.02, 0.03, 0.02)
	sight.mesh = sight_mesh
	sight.material_override = accent
	sight.position = Vector3(0.19, -0.085, -0.55)
	add_child(sight)
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.19, -0.135, -0.88)
	add_child(_muzzle)
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 0.75, 0.3)
	_flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.07
	flash_mesh.height = 0.14
	_flash.mesh = flash_mesh
	_flash.material_override = flash_mat
	_flash.visible = false
	_muzzle.add_child(_flash)
	_flash_timer = Timer.new()
	_flash_timer.one_shot = true
	_flash_timer.wait_time = 0.05
	_flash_timer.timeout.connect(func() -> void: _flash.visible = false)
	add_child(_flash_timer)
