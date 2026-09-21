class_name Weapon
extends Node3D
signal ammo_changed(mag: int, reserve: int)
signal fired
signal target_hit(headshot: bool)
signal weapon_changed(weapon_name: String)
# Two weapons share one node: a rifle and a shotgun with their own magazine
# and reserve. `mag`, `mag_size`, `reserve` etc. always describe the active
# weapon; the other one's state is parked in `_parked`.
const PROFILES: Dictionary = {
	"rifle": {"label": "RIFLE", "mag_size": 30, "fire_interval": 0.12, "damage": 25.0, "pellets": 1, "spread_deg": 0.0, "reload_time": 1.2, "start_reserve": 60, "sound": "shot", "sound_db": -6.0, "kick": 0.012},
	"shotgun": {"label": "SHOTGUN", "mag_size": 6, "fire_interval": 0.85, "damage": 12.0, "pellets": 8, "spread_deg": 5.0, "reload_time": 1.7, "start_reserve": 18, "sound": "shotgun", "sound_db": -3.0, "kick": 0.035},
}
const KINDS: Array[String] = ["rifle", "shotgun"]
const HEAD_MIN_Y: float = 1.45
const HEAD_HALF_WIDTH: float = 0.35
const HEADSHOT_MULT: float = 2.0
const DRY_FIRE_INTERVAL: float = 0.25
const POOL_SIZE: int = 16
@export var max_range: float = 100.0
var kind: String = "rifle"
var mag_size: int = 30
var fire_interval: float = 0.12
var damage: float = 25.0
var pellets: int = 1
var spread_deg: float = 0.0
var reload_time: float = 1.2
var mag: int = 30
var reserve: int = -1
var reloading: bool = false
var firing: bool = false
var _parked: Dictionary = {}
var _cooldown: float = 0.0
var _dry_cooldown: float = 0.0
var _camera: Camera3D = null
var _muzzle: Marker3D = null
var _flash: MeshInstance3D = null
var _flash_timer: Timer = null
var _reload_timer: Timer = null
var _barrel: MeshInstance3D = null
var _tracers: Array[MeshInstance3D] = []
var _impacts: Array[MeshInstance3D] = []
var _sparks: Array[GPUParticles3D] = []
var _fx_tweens: Dictionary = {}
var _key1_down: bool = false
var _key2_down: bool = false
func _ready() -> void:
	for k in KINDS:
		var p: Dictionary = PROFILES[k]
		_parked[k] = {"mag": int(p["mag_size"]), "reserve": int(p["start_reserve"])}
	_load_profile("rifle")
	_camera = _find_camera()
	_build_gun()
	_reload_timer = Timer.new()
	_reload_timer.one_shot = true
	_reload_timer.timeout.connect(_finish_reload)
	add_child(_reload_timer)
func _load_profile(k: String) -> void:
	var p: Dictionary = PROFILES[k]
	kind = k
	mag_size = int(p["mag_size"])
	fire_interval = float(p["fire_interval"])
	damage = float(p["damage"])
	pellets = int(p["pellets"])
	spread_deg = float(p["spread_deg"])
	reload_time = float(p["reload_time"])
	mag = int(_parked[k]["mag"])
	reserve = int(_parked[k]["reserve"])
func weapon_label() -> String:
	return String(PROFILES[kind]["label"])
func switch_weapon(k: String) -> void:
	if k == kind or not PROFILES.has(k):
		return
	if reloading:
		_reload_timer.stop()
		reloading = false
	_parked[kind] = {"mag": mag, "reserve": reserve}
	_load_profile(k)
	_cooldown = maxf(_cooldown, 0.25)
	if _barrel != null:
		_barrel.scale = Vector3(1.6, 1.3, 0.85) if kind == "shotgun" else Vector3.ONE
	_sfx("reload", -8.0, 1.3)
	weapon_changed.emit(weapon_label())
	ammo_changed.emit(mag, reserve)
func toggle_weapon() -> void:
	switch_weapon("shotgun" if kind == "rifle" else "rifle")
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
		if reserve == 0:
			_dry_fire()
		else:
			start_reload()
		return
	_cooldown = fire_interval
	mag -= 1
	ammo_changed.emit(mag, reserve)
	fired.emit()
	for i in range(pellets):
		_do_hitscan(i > 0)
	_play_muzzle_flash()
	var p: Dictionary = PROFILES[kind]
	_sfx(String(p["sound"]), float(p["sound_db"]), randf_range(0.95, 1.05))
	var player: Node = _find_player_collider()
	if player != null and player.has_method("kick"):
		player.kick(float(p["kick"]))
func _sfx(kind_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var sfx: Node = get_tree().get_first_node_in_group("sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play(kind_name, volume_db, pitch)
func start_reload() -> void:
	if reloading:
		return
	if mag >= mag_size:
		return
	if reserve == 0:
		_dry_fire()
		return
	reloading = true
	_reload_timer.start(reload_time)
	_sfx("reload", -4.0)
func _finish_reload() -> void:
	var need: int = mag_size - mag
	var take: int = need if reserve < 0 else mini(need, reserve)
	mag += take
	if reserve > 0:
		reserve -= take
	reloading = false
	ammo_changed.emit(mag, reserve)
func add_reserve(rounds: int) -> void:
	# Rifle ammo (the active weapon's counter updates if that is the rifle).
	_add_to("rifle", rounds)
func add_shells(shells: int) -> void:
	_add_to("shotgun", shells)
func _add_to(k: String, n: int) -> void:
	if k == kind:
		if reserve >= 0:
			reserve += n
	else:
		var r: int = int(_parked[k]["reserve"])
		if r >= 0:
			_parked[k]["reserve"] = r + n
	ammo_changed.emit(mag, reserve)
func ammo_snapshot() -> Dictionary:
	var snap: Dictionary = _parked.duplicate(true)
	snap[kind] = {"mag": mag, "reserve": reserve}
	snap["kind"] = kind
	return snap
func restore_ammo(snap: Dictionary) -> void:
	for k in KINDS:
		if snap.has(k):
			_parked[k] = {"mag": int(snap[k]["mag"]), "reserve": int(snap[k]["reserve"])}
	var k: String = String(snap.get("kind", "rifle"))
	_load_profile(k)
	if _barrel != null:
		_barrel.scale = Vector3(1.6, 1.3, 0.85) if kind == "shotgun" else Vector3.ONE
	weapon_changed.emit(weapon_label())
	ammo_changed.emit(mag, reserve)
func _dry_fire() -> void:
	if _dry_cooldown > 0.0:
		return
	_dry_cooldown = DRY_FIRE_INTERVAL
	_sfx("reload", -10.0, 1.7)
func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_dry_cooldown = maxf(0.0, _dry_cooldown - delta)
	if _controls_locked():
		return
	var k1 := Input.is_physical_key_pressed(KEY_1)
	var k2 := Input.is_physical_key_pressed(KEY_2)
	if k1 and not _key1_down:
		switch_weapon("rifle")
	if k2 and not _key2_down:
		switch_weapon("shotgun")
	_key1_down = k1
	_key2_down = k2
	if reloading:
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
func _do_hitscan(spread_only: bool) -> void:
	if _camera == null:
		_camera = _find_camera()
	if _camera == null:
		return
	var screen_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var origin: Vector3 = _camera.project_ray_origin(screen_center)
	var dir: Vector3 = _camera.project_ray_normal(screen_center)
	if spread_deg > 0.0 and (spread_only or pellets > 1):
		var basis: Basis = _camera.global_transform.basis
		var r := deg_to_rad(spread_deg) * sqrt(randf())
		var a := randf() * TAU
		dir = (dir + basis.x * (cos(a) * tan(r)) + basis.y * (sin(a) * tan(r))).normalized()
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
			var headshot := false
			if collider is Node3D:
				var local: Vector3 = (collider as Node3D).to_local(end_pos)
				if collider.has_method("is_headshot"):
					headshot = collider.call("is_headshot", local)
				else:
					headshot = local.y >= HEAD_MIN_Y and absf(local.x) <= HEAD_HALF_WIDTH
			collider.call("take_damage", damage * (HEADSHOT_MULT if headshot else 1.0), headshot)
			target_hit.emit(headshot)
		_spawn_impact(end_pos, hit.get("normal", Vector3.UP))
	_spawn_tracer(muzzle_pos, end_pos)
# --- pooled effects -----------------------------------------------------
func _fx_root() -> Node:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	return root
func _acquire(pool: Array, builder: Callable) -> Node3D:
	for n in pool:
		if is_instance_valid(n) and not n.visible:
			return n
	if pool.size() < POOL_SIZE:
		var made: Node3D = builder.call()
		pool.append(made)
		return made
	var oldest: Node3D = pool.pop_front()
	pool.append(oldest)
	return oldest
func _restart_fx_tween(n: Node3D) -> Tween:
	var old: Tween = _fx_tweens.get(n)
	if old != null and old.is_valid():
		old.kill()
	var tw := n.create_tween()
	_fx_tweens[n] = tw
	return tw
func _build_tracer() -> MeshInstance3D:
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.02, 1.0)
	tracer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	tracer.material_override = mat
	tracer.visible = false
	_fx_root().add_child(tracer)
	return tracer
func _build_impact() -> MeshInstance3D:
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
	impact.visible = false
	_fx_root().add_child(impact)
	return impact
func _build_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color = Color(1.0, 0.8, 0.35, 1.0)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	quad.material = mat
	p.draw_pass_1 = quad
	p.visible = false
	_fx_root().add_child(p)
	return p
func _spawn_tracer(from_pos: Vector3, to_pos: Vector3) -> void:
	var dist: float = from_pos.distance_to(to_pos)
	if dist < 0.1:
		return
	var tracer := _acquire(_tracers, _build_tracer) as MeshInstance3D
	var mat := tracer.material_override as StandardMaterial3D
	tracer.visible = true
	tracer.scale = Vector3.ONE
	tracer.global_position = (from_pos + to_pos) * 0.5
	var shot_dir: Vector3 = (to_pos - from_pos).normalized()
	var up: Vector3 = Vector3.UP
	if absf(shot_dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	tracer.look_at(to_pos, up)
	tracer.scale = Vector3(1.0, 1.0, dist)
	mat.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	var tw := _restart_fx_tween(tracer)
	tw.tween_property(mat, "albedo_color", Color(1.0, 0.85, 0.55, 0.0), 0.06)
	tw.tween_callback(func() -> void: tracer.visible = false)
func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var n: Vector3 = normal
	if n.length() < 0.01:
		n = Vector3.UP
	var impact := _acquire(_impacts, _build_impact) as MeshInstance3D
	var mat := impact.material_override as StandardMaterial3D
	impact.visible = true
	impact.scale = Vector3.ONE
	impact.global_position = pos + n.normalized() * 0.03
	mat.albedo_color = Color(1.0, 0.5, 0.2, 0.95)
	var tw := _restart_fx_tween(impact).set_parallel(true)
	tw.tween_property(impact, "scale", Vector3(3.0, 3.0, 3.0), 0.15)
	tw.tween_property(mat, "albedo_color", Color(1.0, 0.5, 0.2, 0.0), 0.15)
	tw.chain().tween_callback(func() -> void: impact.visible = false)
	var sparks := _acquire(_sparks, _build_sparks) as GPUParticles3D
	sparks.visible = true
	sparks.global_position = pos + n.normalized() * 0.05
	(sparks.process_material as ParticleProcessMaterial).direction = n.normalized()
	sparks.restart()
	var stw := _restart_fx_tween(sparks)
	stw.tween_interval(0.45)
	stw.tween_callback(func() -> void: sparks.visible = false)
func _play_muzzle_flash() -> void:
	if _flash == null or _flash_timer == null:
		return
	_flash.visible = true
	var s: float = randf_range(0.8, 1.4) * (1.6 if kind == "shotgun" else 1.0)
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
	_barrel = MeshInstance3D.new()
	var barrel_mesh := BoxMesh.new()
	barrel_mesh.size = Vector3(0.055, 0.07, 0.35)
	_barrel.mesh = barrel_mesh
	_barrel.material_override = dark
	_barrel.position = Vector3(0.19, -0.135, -0.68)
	add_child(_barrel)
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
