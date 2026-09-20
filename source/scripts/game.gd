class_name Game
extends Node3D
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const STORY_TEXT := "The wall has fallen. Ash chokes the valley — and the gate ahead is the only way through."
const OBJECTIVE_FIGHT := "Fight through to the exit gate"
const OBJECTIVE_GATE_OPEN := "Gate open — reach the exit"
const ZONE_POSITIONS: Array = [
		Vector3(0, 2, -16),
		Vector3(0, 2, -34),
		Vector3(0, 2, -52),
	]
const ZONE_SIZE := Vector3(8, 4, 5)
const KILL_PLANE_Y: float = -15.0
# Finite ammo: fixed floor pickups along the corridor plus a chance of a
# smaller pack dropping from each kill.
const AMMO_PICKUPS: Array = [
		Vector3(0, 0.35, -9),
		Vector3(0, 0.35, -28.5),
		Vector3(0, 0.35, -46),
	]
const AMMO_PICKUP_ROUNDS: int = 30
const AMMO_DROP_ROUNDS: int = 15
const AMMO_DROP_CHANCE: float = 0.4
const WAVE_SPAWNS: Array = [
		[Vector3(-2.0, 0.0, -21.0), Vector3(2.0, 0.0, -21.0), Vector3(0.0, 0.0, -25.0)],
		[Vector3(-2.5, 0.0, -39.0), Vector3(2.5, 0.0, -39.0), Vector3(-1.0, 0.0, -43.0), Vector3(1.0, 0.0, -43.0)],
		[Vector3(-2.5, 0.0, -57.0), Vector3(2.5, 0.0, -57.0), Vector3(0.0, 0.0, -59.0), Vector3(-1.5, 0.0, -62.0), Vector3(1.5, 0.0, -62.0)],
	]
var _player: Player = null
var _weapon: Weapon = null
var _hud: HUD = null
var _waves_triggered: Array[bool] = [false, false, false]
var _alive: Array[Enemy] = []
var _current_objective: String = OBJECTIVE_FIGHT
var _game_over: bool = false
var _portal_mat: StandardMaterial3D = null
var _torch_lights: Array[OmniLight3D] = []
var _time: float = 0.0
# Persists across scene reloads (script-level state), so the story card is
# only shown the first time the level starts in a session.
static var story_shown: bool = false
func _ready() -> void:
	_build_environment()
	_build_sfx()
	_build_level()
	_spawn_player_and_hud()
	_build_zones()
	_build_gate()
	_build_navigation()
	_build_ammo_pickups()
	if not story_shown:
		story_shown = true
		_hud.show_story(STORY_TEXT)
	_set_objective(OBJECTIVE_FIGHT)
func _build_sfx() -> void:
	var sfx_script: Script = load("res://scripts/sfx.gd")
	if sfx_script == null:
		push_error("Game: missing res://scripts/sfx.gd")
		return
	var sfx: Node = sfx_script.new()
	sfx.name = "Sfx"
	add_child(sfx)
func _build_ammo_pickups() -> void:
	for pos in AMMO_PICKUPS:
		_spawn_ammo(pos, AMMO_PICKUP_ROUNDS)
func _spawn_ammo(pos: Vector3, rounds: int) -> void:
	var pickup := AmmoPickup.new()
	pickup.rounds = rounds
	pickup.position = pos
	add_child(pickup)
func _build_navigation() -> void:
	# Bake a navmesh from the level's static colliders so enemies path around
	# rubble and pillars instead of steering in a straight line.
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nm.geometry_source_group_name = "nav_source"
	# Agent values are kept at exact multiples of the voxel size so the baker
	# does not round them (it warns otherwise).
	nm.cell_size = 0.25
	nm.cell_height = 0.2
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.2
	nm.agent_max_slope = 45.0
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	region.navigation_mesh = nm
	add_child(region)
	region.bake_navigation_mesh(false)
	var polys: int = nm.get_polygon_count()
	print("Game: navmesh baked with %d polygons" % polys)
	if polys == 0:
		push_warning("Game: navmesh is empty - enemies fall back to direct chase")
func _process(delta: float) -> void:
	_time += delta
	if not _game_over and _player != null and _player.global_position.y < KILL_PLANE_Y:
		# Safety net: anything that falls out of the level dies instead of
		# falling forever.
		_player.take_damage(9999.0)
	for i in range(_torch_lights.size()):
		var l := _torch_lights[i]
		l.light_energy = 1.6 \
			+ sin(_time * 11.0 + float(i) * 2.1) * 0.18 \
			+ sin(_time * 23.0 + float(i) * 4.7) * 0.1
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.008, 0.016)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.19, 0.27)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.02, 0.02, 0.04)
	env.fog_depth_begin = 12.0
	env.fog_depth_end = 58.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color(0.55, 0.68, 1.0)
	moon.light_energy = 0.35
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-50, -30, 0)
	add_child(moon)
func _build_level() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.085, 0.085, 0.105)
	floor_mat.roughness = 1.0
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.11, 0.105, 0.13)
	wall_mat.roughness = 1.0
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.14, 0.135, 0.15)
	rock_mat.roughness = 1.0
	_add_box(Vector3(9, 0.5, 78), Vector3(0, -0.25, -31), floor_mat, "Floor")
	_add_box(Vector3(0.8, 6, 78), Vector3(-4.4, 3, -31), wall_mat, "WallL")
	_add_box(Vector3(0.8, 6, 78), Vector3(4.4, 3, -31), wall_mat, "WallR")
	_add_box(Vector3(9.6, 6, 0.8), Vector3(0, 3, -69.6), wall_mat, "WallEnd")
	_add_box(Vector3(9.6, 6, 0.8), Vector3(0, 3, 8.4), wall_mat, "WallStart")
	_add_box(Vector3(1.6, 1.5, 1.6), Vector3(2.3, 0.75, -14), rock_mat, "Rubble1")
	_add_box(Vector3(1.2, 1.0, 1.2), Vector3(-2.4, 0.5, -25), rock_mat, "Rubble2")
	_add_box(Vector3(2.0, 2.2, 1.0), Vector3(-1.8, 1.1, -33), rock_mat, "Rubble3")
	_add_box(Vector3(1.4, 1.3, 1.4), Vector3(2.6, 0.65, -47), rock_mat, "Rubble4")
	_add_box(Vector3(1.0, 0.8, 2.2), Vector3(-2.2, 0.4, -54.5), rock_mat, "Rubble5")
	_add_box(Vector3(1.2, 5.0, 1.2), Vector3(-3.2, 2.5, -8), rock_mat, "Pillar1")
	_add_box(Vector3(1.2, 5.0, 1.2), Vector3(3.2, 2.5, -49), rock_mat, "Pillar2")
	_build_torches()
func _add_box(size: Vector3, pos: Vector3, mat: Material, box_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = box_name + "Body"
	body.position = pos
	body.add_to_group("nav_source")
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return mi
func _build_torches() -> void:
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1, 0.5, 0.15)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1, 0.45, 0.12)
	flame_mat.emission_energy_multiplier = 3.0
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Billboard so the flame sprite always faces the player instead of being
	# seen edge-on from down the corridor.
	flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var bracket_mat := StandardMaterial3D.new()
	bracket_mat.albedo_color = Color(0.05, 0.04, 0.04)
	var torches := [
			[Vector3(-3.9, 2.6, -12), PI / 2.0],
			[Vector3(3.9, 2.6, -32), -PI / 2.0],
			[Vector3(-3.9, 2.6, -52), PI / 2.0],
		]
	for i in range(torches.size()):
		var pos: Vector3 = torches[i][0]
		var rot_y: float = torches[i][1]
		_add_box(Vector3(0.12, 0.5, 0.12), pos + Vector3(0, -0.45, 0), bracket_mat, "TorchBracket%d" % i)
		var flame := MeshInstance3D.new()
		flame.name = "TorchFlame%d" % i
		var quad := PlaneMesh.new()
		# PlaneMesh lies flat (faces +Y) by default; stand it upright so the
		# billboard material has a camera-facing quad to work with.
		quad.orientation = PlaneMesh.FACE_Z
		quad.size = Vector2(0.55, 0.8)
		quad.material = flame_mat
		flame.mesh = quad
		flame.position = pos
		flame.rotation.y = rot_y
		add_child(flame)
		var light := OmniLight3D.new()
		light.name = "TorchLight%d" % i
		light.light_color = Color(1.0, 0.55, 0.22)
		light.light_energy = 1.6
		light.omni_range = 8.0
		light.shadow_enabled = false
		var side := signf(pos.x)
		light.position = pos + Vector3(-side * 0.6, 0.1, 0)
		add_child(light)
		_torch_lights.append(light)
func _spawn_player_and_hud() -> void:
	var player_scene: PackedScene = load("res://scenes/player.tscn")
	if player_scene == null:
		push_error("Game: missing res://scenes/player.tscn")
		return
	_player = player_scene.instantiate() as Player
	_player.name = "Player"
	_player.position = Vector3(0, 0.5, 0)
	add_child(_player)
	var weapon_script: Script = load("res://scripts/weapon.gd")
	if weapon_script != null:
		var mount := _player.get_node_or_null("Head/Camera3D/WeaponMount")
		if mount != null:
			_weapon = weapon_script.new() as Weapon
			_weapon.name = "Weapon"
			mount.add_child(_weapon)
		else:
			push_error("Game: player missing Head/Camera3D/WeaponMount")
	else:
		push_error("Game: missing res://scripts/weapon.gd")
	var hud_scene: PackedScene = load("res://scenes/hud.tscn")
	if hud_scene == null:
		push_error("Game: missing res://scenes/hud.tscn")
		return
	_hud = hud_scene.instantiate() as HUD
	_hud.name = "HUD"
	add_child(_hud)
	_hud.bind(_player, _weapon)
	_player.died.connect(_on_player_died)
func _build_zones() -> void:
	for i in range(ZONE_POSITIONS.size()):
		var area := Area3D.new()
		area.name = "WaveZone%d" % (i + 1)
		area.position = ZONE_POSITIONS[i]
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = ZONE_SIZE
		cs.shape = shape
		area.add_child(cs)
		add_child(area)
		area.body_entered.connect(_on_zone_body_entered.bind(i))
func _on_zone_body_entered(body: Node3D, zone_idx: int) -> void:
	if zone_idx < 0 or zone_idx >= _waves_triggered.size():
		return
	if _waves_triggered[zone_idx]:
		return
	if not is_instance_valid(body) or not body.is_in_group("player"):
		return
	_waves_triggered[zone_idx] = true
	var area := get_node_or_null("WaveZone%d" % (zone_idx + 1)) as Area3D
	if area != null:
		area.set_deferred("monitoring", false)
	_spawn_wave(zone_idx)
func _spawn_wave(zone_idx: int) -> void:
	var spawns: Array = WAVE_SPAWNS[zone_idx] as Array
	for pos in spawns:
		var enemy: Enemy = ENEMY_SCENE.instantiate() as Enemy
		enemy.position = pos
		enemy.died.connect(_on_enemy_died)
		add_child(enemy)
		_alive.append(enemy)
	_set_objective("Wave %d/3 — destroy the creatures" % (zone_idx + 1))
func _on_enemy_died(enemy: Enemy) -> void:
	_alive.erase(enemy)
	if _game_over:
		return
	if randf() < AMMO_DROP_CHANCE and is_instance_valid(enemy):
		var drop_pos: Vector3 = enemy.global_position
		drop_pos.y = 0.35
		_spawn_ammo(drop_pos, AMMO_DROP_ROUNDS)
	if _all_waves_cleared():
		_set_objective(OBJECTIVE_GATE_OPEN)
		_open_gate()
	elif _alive.is_empty():
		_set_objective(OBJECTIVE_FIGHT)
func _all_waves_cleared() -> bool:
	if not _alive.is_empty():
		return false
	for t in _waves_triggered:
		if not t:
			return false
	return true
func _build_gate() -> void:
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.13, 0.12, 0.15)
	pillar_mat.roughness = 1.0
	_add_box(Vector3(1.2, 5, 1.2), Vector3(-2.4, 2.5, -66), pillar_mat, "GatePillarL")
	_add_box(Vector3(1.2, 5, 1.2), Vector3(2.4, 2.5, -66), pillar_mat, "GatePillarR")
	_portal_mat = StandardMaterial3D.new()
	_portal_mat.albedo_color = Color(0.2, 0.02, 0.03)
	_portal_mat.emission_enabled = true
	_portal_mat.emission = Color(1, 0.08, 0.1)
	_portal_mat.emission_energy_multiplier = 0.6
	_portal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var portal := MeshInstance3D.new()
	portal.name = "ExitPortal"
	var slab := BoxMesh.new()
	slab.size = Vector3(3.6, 4.4, 0.25)
	slab.material = _portal_mat
	portal.mesh = slab
	portal.position = Vector3(0, 2.5, -66)
	add_child(portal)
	var area := Area3D.new()
	area.name = "ExitGate"
	area.position = Vector3(0, 2, -64.5)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5, 4, 3)
	cs.shape = shape
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_gate_body_entered)
func _open_gate() -> void:
	if _portal_mat != null:
		_portal_mat.emission_energy_multiplier = 2.5
func _on_gate_body_entered(body: Node3D) -> void:
	if _game_over:
		return
	if not body.is_in_group("player"):
		return
	if _all_waves_cleared():
		_game_over = true
		_hud.show_win()
	else:
		_flash_hint("Clear the creatures first!")
func _flash_hint(text: String) -> void:
	_hud.set_objective(text)
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(_hud):
		_hud.set_objective(_current_objective)
func _set_objective(text: String) -> void:
	_current_objective = text
	if _hud != null:
		_hud.set_objective(text)
func _on_player_died() -> void:
	if _game_over:
		return
	_game_over = true
	_hud.show_death()
class AmmoPickup extends Area3D:
	var rounds: int = 30
	var _mesh: MeshInstance3D = null
	var _bob_t: float = 0.0
	func _ready() -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 0.22, 0.35)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.7, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.75, 0.2)
		mat.emission_energy_multiplier = 1.2
		bm.material = mat
		mi.mesh = bm
		add_child(mi)
		_mesh = mi
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.9
		cs.shape = sh
		add_child(cs)
		body_entered.connect(_on_body_entered)
	func _process(delta: float) -> void:
		_bob_t += delta
		rotate_y(1.5 * delta)
		_mesh.position.y = 0.06 * sin(_bob_t * 3.0)
	func _on_body_entered(body: Node3D) -> void:
		if not body.is_in_group("player"):
			return
		var weapon: Node = body.get_node_or_null("Head/Camera3D/WeaponMount/Weapon")
		if weapon == null or not weapon.has_method("add_reserve"):
			return
		weapon.add_reserve(rounds)
		var sfx: Node = get_tree().get_first_node_in_group("sfx")
		if sfx != null and sfx.has_method("play"):
			sfx.play("reload", -6.0, 1.4)
		set_deferred("monitoring", false)
		queue_free()
