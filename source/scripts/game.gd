class_name Game
extends Node3D
# Story-driven level built from a JSON level file (res://levels/*.json): a
# corridor of named areas, each with its own geometry, story caption,
# objective and encounter. Doors between areas lift when the area is done.
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const LEVELS: Array = [
		{"id": "ash_valley", "path": "res://levels/ash_valley.json", "title": "ASH VALLEY"},
		{"id": "the_deep", "path": "res://levels/the_deep.json", "title": "THE DEEP"},
	]
const DIFFICULTIES: Array = [
		{"title": "EASY", "hp": 0.75, "damage": 0.7, "ammo_drop": 0.6, "health_drop": 0.25},
		{"title": "NORMAL", "hp": 1.0, "damage": 1.0, "ammo_drop": 0.4, "health_drop": 0.15},
		{"title": "HARD", "hp": 1.3, "damage": 1.4, "ammo_drop": 0.25, "health_drop": 0.08},
	]
const KILL_PLANE_Y: float = -15.0
const AMMO_PICKUP_ROUNDS: int = 30
const AMMO_PICKUP_SHELLS: int = 6
const AMMO_DROP_ROUNDS: int = 15
const HEALTH_PICKUP_AMOUNT: float = 40.0
const FLOOR_HALF_WIDTH: float = 8.5
const WALL_HEIGHT: float = 6.0
const DOOR_HEIGHT: float = 4.2
const OBJECTIVE_GATE := "Reach the exit gate"
# Session state that survives scene reloads.
static var story_shown: bool = false
static var skip_title: bool = false
static var level_index: int = 0
static var difficulty: int = 1
static var resume_area: int = -1
static var checkpoint: Dictionary = {}
var level: Dictionary = {}
var areas: Array = []
var gate_z: float = -120.0
var _player: Player = null
var _weapon: Weapon = null
var _hud: HUD = null
var _alive: Array[Enemy] = []
var _current_area: int = -1
var _area_done: Array[bool] = []
var _area_pending: Array[int] = []
var _area_entered: Array[bool] = []
var _doors: Dictionary = {}
var _key: Node3D = null
var _key_taken: bool = false
var _current_objective: String = ""
var _game_over: bool = false
var _playing: bool = false
var _run_start_area: int = 0
var _portal_mat: StandardMaterial3D = null
var _torch_lights: Array[OmniLight3D] = []
var _time: float = 0.0
var _stats: Dictionary = {"time": 0.0, "kills": 0, "headshots": 0, "shots": 0, "hits": 0, "damage_taken": 0.0}
var _last_hp: float = 100.0
func _ready() -> void:
	if not skip_title and not story_shown and resume_area < 0:
		_load_saved_prefs()
	level_index = clampi(level_index, 0, LEVELS.size() - 1)
	difficulty = clampi(difficulty, 0, DIFFICULTIES.size() - 1)
	_load_level(level_index)
	for i in range(areas.size()):
		_area_done.append(false)
		_area_pending.append(0)
		_area_entered.append(false)
	_build_environment()
	_build_sfx()
	_build_level()
	_spawn_player_and_hud()
	_build_triggers()
	_build_gate()
	_build_navigation()
	_build_pickups()
	_hud.play_pressed.connect(_after_title)
	_hud.story_dismissed.connect(_start_run)
	_hud.restart_requested.connect(_restart)
	_hud.retry_requested.connect(_retry_checkpoint)
	_hud.next_level_requested.connect(_next_level)
	_hud.quit_to_title_requested.connect(_quit_to_title)
	_hud.set_level_info(String(level["name"]), DIFFICULTIES[difficulty]["title"])
	if resume_area > 0 and resume_area < areas.size():
		var idx := resume_area
		resume_area = -1
		_start_run_from(idx)
	elif skip_title:
		_after_title()
	else:
		_hud.show_title()
# ---------------------------------------------------------------- level data
func _load_level(idx: int) -> void:
	var path: String = LEVELS[idx]["path"]
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Game: could not parse level " + path)
		parsed = {"name": "Broken", "story": "", "gate_z": -20, "areas": []}
	level = parsed
	gate_z = float(level.get("gate_z", -120.0))
	areas = []
	for raw in level.get("areas", []):
		areas.append(_parse_area(raw))
func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
func _parse_area(raw: Dictionary) -> Dictionary:
	var a := {
		"name": String(raw.get("name", "Area")),
		"z0": float(raw.get("z0", 0.0)),
		"z1": float(raw.get("z1", -20.0)),
		"hw": float(raw.get("hw", 4.0)),
		"story": String(raw.get("story", "")),
		"objective": String(raw.get("objective", "")),
		"kind": String(raw.get("kind", "clear")),
		"late_delay": float(raw.get("late_delay", 0.0)),
		"door": bool(raw.get("door", false)),
		"spawns": [], "late_spawns": [], "ammo": [], "health": [], "rubble": [], "torches": [],
	}
	for s in raw.get("spawns", []):
		a["spawns"].append([String(s[0]), _v3(s[1])])
	for s in raw.get("late_spawns", []):
		a["late_spawns"].append([String(s[0]), _v3(s[1])])
	for p in raw.get("ammo", []):
		a["ammo"].append(_v3(p))
	for p in raw.get("health", []):
		a["health"].append(_v3(p))
	for r in raw.get("rubble", []):
		a["rubble"].append([_v3(r[0]), _v3(r[1])])
	for t in raw.get("torches", []):
		a["torches"].append([_v3(t[0]), float(t[1])])
	if raw.has("key"):
		a["key"] = _v3(raw["key"])
	return a
# ---------------------------------------------------------------- run flow
func _after_title() -> void:
	if story_shown:
		_start_run()
	else:
		story_shown = true
		_hud.show_story(String(level["story"]))
func _start_run() -> void:
	if _playing:
		return
	_playing = true
	_run_start_area = 0
	_hud.set_playing(true)
	_start_ambience()
	_enter_area(0)
func _start_run_from(idx: int) -> void:
	_playing = true
	_run_start_area = idx
	_hud.set_playing(true)
	_start_ambience()
	for i in range(idx):
		_area_done[i] = true
		_area_entered[i] = true
		if _doors.has(i):
			_doors[i].open(true)
	if areas[idx - 1].has("key"):
		_key_taken = true
		if _key != null:
			_key.queue_free()
			_key = null
	if _weapon != null and checkpoint.has("ammo"):
		_weapon.restore_ammo(checkpoint["ammo"])
	_player.global_position = area_entry_position(idx) + Vector3(0, 0.5, 0.5)
	_player.velocity = Vector3.ZERO
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_enter_area(idx)
func _start_ambience() -> void:
	var sfx: Node = get_tree().get_first_node_in_group("sfx")
	if sfx != null and sfx.has_method("start_ambience"):
		sfx.start_ambience()
func _restart() -> void:
	skip_title = true
	resume_area = -1
	get_tree().paused = false
	get_tree().reload_current_scene()
func _retry_checkpoint() -> void:
	skip_title = true
	resume_area = int(checkpoint.get("area", 0))
	get_tree().paused = false
	get_tree().reload_current_scene()
func _next_level() -> void:
	level_index = (level_index + 1) % LEVELS.size()
	story_shown = false
	skip_title = true
	resume_area = -1
	get_tree().paused = false
	get_tree().reload_current_scene()
func _load_saved_prefs() -> void:
	# First boot of the session: pick up the last chosen level / difficulty.
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return
	level_index = int(cfg.get_value("game", "level", level_index))
	difficulty = int(cfg.get_value("game", "difficulty", difficulty))
func _quit_to_title() -> void:
	skip_title = false
	resume_area = -1
	get_tree().paused = false
	get_tree().reload_current_scene()
func _process(delta: float) -> void:
	_time += delta
	if _playing and not _game_over:
		_stats["time"] += delta
	if not _game_over and _player != null and _player.global_position.y < KILL_PLANE_Y:
		_player.take_damage(9999.0)
	for i in range(_torch_lights.size()):
		var l := _torch_lights[i]
		l.light_energy = 1.6 \
			+ sin(_time * 11.0 + float(i) * 2.1) * 0.18 \
			+ sin(_time * 23.0 + float(i) * 4.7) * 0.1
# ---------------------------------------------------------------- building
func _build_sfx() -> void:
	var sfx_script: Script = load("res://scripts/sfx.gd")
	if sfx_script == null:
		push_error("Game: missing res://scripts/sfx.gd")
		return
	var sfx: Node = sfx_script.new()
	sfx.name = "Sfx"
	add_child(sfx)
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
func _particle_quad(color: Color, size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	quad.material = mat
	return quad
func _build_ash() -> void:
	# Drifting ash around the player, sized to the fog distance.
	var p := GPUParticles3D.new()
	p.name = "Ash"
	p.amount = 260
	p.lifetime = 7.0
	p.preprocess = 4.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 30, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10.0, 3.5, 16.0)
	pm.direction = Vector3(0.15, -1.0, 0.0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, -0.25, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color = Color(0.75, 0.72, 0.7, 0.45)
	p.process_material = pm
	p.draw_pass_1 = _particle_quad(Color(0.8, 0.78, 0.75, 0.5), 0.045)
	p.position = Vector3(0, 2.5, -4)
	_player.add_child(p)
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
	var z_start: float = 8.0
	var z_end: float = float(areas[areas.size() - 1]["z1"])
	var length: float = z_start - z_end
	_add_box(Vector3(FLOOR_HALF_WIDTH * 2.0, 0.5, length), Vector3(0, -0.25, (z_start + z_end) * 0.5), floor_mat, "Floor")
	_add_box(Vector3(FLOOR_HALF_WIDTH * 2.0 + 1.6, WALL_HEIGHT, 0.8), Vector3(0, WALL_HEIGHT * 0.5, z_start + 0.4), wall_mat, "WallStart")
	_add_box(Vector3(FLOOR_HALF_WIDTH * 2.0 + 1.6, WALL_HEIGHT, 0.8), Vector3(0, WALL_HEIGHT * 0.5, z_end + 0.4), wall_mat, "WallEnd")
	for i in range(areas.size()):
		var a: Dictionary = areas[i]
		var hw: float = a["hw"]
		var z0: float = a["z0"]
		var z1: float = a["z1"]
		var seg_len: float = z0 - z1
		var zc: float = (z0 + z1) * 0.5
		var wall_size := Vector3(0.8, WALL_HEIGHT, seg_len)
		if i == 0:
			wall_size.z += z_start - z0
			zc = (z_start + z1) * 0.5
		_add_box(wall_size, Vector3(-(hw + 0.4), WALL_HEIGHT * 0.5, zc), wall_mat, "WallL%d" % i)
		_add_box(wall_size, Vector3(hw + 0.4, WALL_HEIGHT * 0.5, zc), wall_mat, "WallR%d" % i)
		if i > 0:
			var prev_hw: float = areas[i - 1]["hw"]
			if not is_equal_approx(prev_hw, hw):
				var lo: float = minf(prev_hw, hw)
				var hi: float = maxf(prev_hw, hw) + 0.8
				var piece := Vector3(hi - lo, WALL_HEIGHT, 0.8)
				_add_box(piece, Vector3(-(lo + hi) * 0.5, WALL_HEIGHT * 0.5, z0), wall_mat, "StepL%d" % i)
				_add_box(piece, Vector3((lo + hi) * 0.5, WALL_HEIGHT * 0.5, z0), wall_mat, "StepR%d" % i)
		var ri := 0
		for r in a["rubble"]:
			_add_box(r[0], r[1], rock_mat, "Rock%d_%d" % [i, ri])
			ri += 1
		_build_torches(a["torches"], i)
		if a["door"]:
			var door_hw: float = minf(hw, float(areas[i + 1]["hw"])) if i + 1 < areas.size() else hw
			_build_door(z1, door_hw, i)
		if a.has("key"):
			_build_key(a["key"])
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
func _build_torches(torches: Array, area_idx: int) -> void:
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1, 0.5, 0.15)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1, 0.45, 0.12)
	flame_mat.emission_energy_multiplier = 3.0
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var bracket_mat := StandardMaterial3D.new()
	bracket_mat.albedo_color = Color(0.05, 0.04, 0.04)
	for i in range(torches.size()):
		var pos: Vector3 = torches[i][0]
		var rot_y: float = torches[i][1]
		_add_box(Vector3(0.12, 0.5, 0.12), pos + Vector3(0, -0.45, 0), bracket_mat, "TorchBracket%d_%d" % [area_idx, i])
		var flame := MeshInstance3D.new()
		flame.name = "TorchFlame%d_%d" % [area_idx, i]
		var quad := PlaneMesh.new()
		quad.orientation = PlaneMesh.FACE_Z
		quad.size = Vector2(0.4, 0.55)
		quad.material = flame_mat
		flame.mesh = quad
		flame.position = pos
		flame.rotation.y = rot_y
		add_child(flame)
		var embers := GPUParticles3D.new()
		embers.name = "TorchEmbers%d_%d" % [area_idx, i]
		embers.amount = 22
		embers.lifetime = 0.9
		embers.preprocess = 1.0
		embers.local_coords = false
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.12, 0.05, 0.12)
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 18.0
		pm.initial_velocity_min = 0.7
		pm.initial_velocity_max = 1.5
		pm.gravity = Vector3(0, 0.4, 0)
		pm.scale_min = 0.4
		pm.scale_max = 1.0
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
		ramp.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
		ramp.add_point(0.4, Color(1.0, 0.45, 0.1, 0.9))
		var ramp_tex := GradientTexture1D.new()
		ramp_tex.gradient = ramp
		pm.color_ramp = ramp_tex
		embers.process_material = pm
		embers.draw_pass_1 = _particle_quad(Color(1.0, 0.6, 0.2, 1.0), 0.09)
		embers.position = pos + Vector3(0, -0.15, 0)
		add_child(embers)
		var light := OmniLight3D.new()
		light.name = "TorchLight%d_%d" % [area_idx, i]
		light.light_color = Color(1.0, 0.55, 0.22)
		light.light_energy = 1.6
		light.omni_range = 8.0
		light.shadow_enabled = false
		var side := signf(pos.x)
		light.position = pos + Vector3(-side * 0.6, 0.1, 0)
		add_child(light)
		_torch_lights.append(light)
func _build_door(z: float, hw: float, area_idx: int) -> void:
	var door := Door.new()
	door.name = "Door%d" % area_idx
	door.setup(hw * 2.0, DOOR_HEIGHT)
	door.position = Vector3(0, DOOR_HEIGHT * 0.5, z)
	add_child(door)
	_doors[area_idx] = door
func _build_key(pos: Vector3) -> void:
	var key := KeyPickup.new()
	key.name = "GateKey"
	key.position = pos
	key.collected.connect(_on_key_collected)
	add_child(key)
	_key = key
func _spawn_player_and_hud() -> void:
	var player_scene: PackedScene = load("res://scenes/player.tscn")
	if player_scene == null:
		push_error("Game: missing res://scenes/player.tscn")
		return
	_player = player_scene.instantiate() as Player
	_player.name = "Player"
	_player.position = Vector3(0, 0.5, 0)
	add_child(_player)
	_build_ash()
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
	_player.health_changed.connect(_on_player_health_changed)
	_last_hp = _player.hp
	if _weapon != null:
		_weapon.fired.connect(func() -> void: _stats["shots"] += 1)
		_weapon.target_hit.connect(_on_weapon_hit)
func _build_triggers() -> void:
	for i in range(1, areas.size()):
		var a: Dictionary = areas[i]
		var area := Area3D.new()
		area.name = "AreaTrigger%d" % i
		area.position = Vector3(0, 2, float(a["z0"]) - 1.5)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(float(a["hw"]) * 2.0, 4, 2.5)
		cs.shape = shape
		area.add_child(cs)
		add_child(area)
		area.body_entered.connect(_on_trigger_body_entered.bind(i))
func _build_gate() -> void:
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.13, 0.12, 0.15)
	pillar_mat.roughness = 1.0
	_add_box(Vector3(1.2, 5, 1.2), Vector3(-2.4, 2.5, gate_z), pillar_mat, "GatePillarL")
	_add_box(Vector3(1.2, 5, 1.2), Vector3(2.4, 2.5, gate_z), pillar_mat, "GatePillarR")
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
	portal.position = Vector3(0, 2.5, gate_z)
	add_child(portal)
	var area := Area3D.new()
	area.name = "ExitGate"
	area.position = Vector3(0, 2, gate_z + 1.5)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5, 4, 3)
	cs.shape = shape
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_gate_body_entered)
func _build_pickups() -> void:
	for a in areas:
		for pos in a["ammo"]:
			_spawn_ammo(pos, AMMO_PICKUP_ROUNDS, AMMO_PICKUP_SHELLS)
		for pos in a["health"]:
			_spawn_health(pos, HEALTH_PICKUP_AMOUNT)
func _spawn_ammo(pos: Vector3, rounds: int, shells: int = 0) -> void:
	var pickup := AmmoPickup.new()
	pickup.rounds = rounds
	pickup.shells = shells
	pickup.position = pos
	add_child(pickup)
func _spawn_health(pos: Vector3, amount: float) -> void:
	var pickup := HealthPickup.new()
	pickup.amount = amount
	pickup.position = pos
	add_child(pickup)
func _build_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nm.geometry_source_group_name = "nav_source"
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
# ---------------------------------------------------------------- progression
func _on_trigger_body_entered(body: Node3D, area_idx: int) -> void:
	if not _playing or _game_over:
		return
	if not is_instance_valid(body) or not body.is_in_group("player"):
		return
	if _area_entered[area_idx]:
		return
	if _current_area >= 0 and areas[_current_area]["kind"] == "reach":
		_area_done[_current_area] = true
	_enter_area(area_idx)
func _enter_area(idx: int) -> void:
	_area_entered[idx] = true
	_current_area = idx
	var a: Dictionary = areas[idx]
	if String(a["story"]) != "":
		_hud.show_caption(a["story"])
	_set_objective(a["objective"])
	_hud.set_area_name(a["name"])
	# Checkpoint: death offers a retry from the start of this area with the
	# ammo you had on entry.
	checkpoint = {"area": idx, "ammo": _weapon.ammo_snapshot() if _weapon != null else {}}
	_hud.set_checkpoint_available(idx > 0)
	for s in a["spawns"]:
		_spawn_enemy(s[0], s[1], idx)
	if a["kind"] == "clear" and not a["late_spawns"].is_empty():
		_area_pending[idx] = a["late_spawns"].size()
		_schedule_late_spawns(idx, float(a["late_delay"]))
	if a["kind"] == "clear":
		_check_area_clear(idx)
func _schedule_late_spawns(idx: int, delay: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = maxf(delay, 0.05)
	t.timeout.connect(_do_late_spawns.bind(idx))
	add_child(t)
	t.start()
func _do_late_spawns(idx: int) -> void:
	if _game_over:
		return
	for s in areas[idx]["late_spawns"]:
		_spawn_enemy(s[0], s[1], idx)
	_area_pending[idx] = 0
	if areas[idx]["kind"] == "clear":
		_check_area_clear(idx)
func _spawn_enemy(kind: String, pos: Vector3, area_idx: int) -> void:
	var enemy: Enemy = ENEMY_SCENE.instantiate() as Enemy
	enemy.variant = kind
	enemy.hp_scale = float(DIFFICULTIES[difficulty]["hp"])
	enemy.damage_scale = float(DIFFICULTIES[difficulty]["damage"])
	enemy.position = pos
	enemy.set_meta("area", area_idx)
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	_alive.append(enemy)
func _alive_in_area(idx: int) -> int:
	var n := 0
	for e in _alive:
		if is_instance_valid(e) and int(e.get_meta("area", -1)) == idx:
			n += 1
	return n
func _check_area_clear(idx: int) -> void:
	if _area_done[idx]:
		return
	if _area_pending[idx] > 0 or _alive_in_area(idx) > 0:
		return
	_complete_area(idx)
func _complete_area(idx: int) -> void:
	if _area_done[idx]:
		return
	_area_done[idx] = true
	var a: Dictionary = areas[idx]
	if a["door"] and _doors.has(idx):
		_doors[idx].open()
	if idx == areas.size() - 1:
		_set_objective(OBJECTIVE_GATE)
		_open_gate()
		_hud.show_caption("The way is clear. Go.")
	elif a["kind"] == "clear":
		_set_objective("Area clear — move on")
	elif a["kind"] == "collect":
		_set_objective("Key found — get to the next door")
func _on_key_collected() -> void:
	_key_taken = true
	_hud.show_caption("The ash stirs behind you. Move!")
	var idx := -1
	for i in range(areas.size()):
		if areas[i].has("key"):
			idx = i
	if idx < 0:
		return
	for s in areas[idx]["late_spawns"]:
		_spawn_enemy(s[0], s[1], idx)
	_complete_area(idx)
func _on_enemy_died(enemy: Enemy) -> void:
	_alive.erase(enemy)
	if _game_over:
		return
	_stats["kills"] += 1
	if DisplayServer.is_touchscreen_available():
		Input.vibrate_handheld(20)
	if is_instance_valid(enemy):
		var drop_pos: Vector3 = enemy.global_position
		drop_pos.y = 0.35
		var roll := randf()
		if roll < float(DIFFICULTIES[difficulty]["ammo_drop"]):
			_spawn_ammo(drop_pos, AMMO_DROP_ROUNDS, 2)
		elif roll < float(DIFFICULTIES[difficulty]["ammo_drop"]) + float(DIFFICULTIES[difficulty]["health_drop"]):
			_spawn_health(drop_pos, 25.0)
	var idx := int(enemy.get_meta("area", -1))
	if idx >= 0 and areas[idx]["kind"] == "clear":
		_check_area_clear(idx)
func _all_done() -> bool:
	for d in _area_done:
		if not d:
			return false
	return true
func _open_gate() -> void:
	if _portal_mat != null:
		_portal_mat.emission_energy_multiplier = 2.5
func _on_gate_body_entered(body: Node3D) -> void:
	if _game_over or not _playing:
		return
	if not body.is_in_group("player"):
		return
	if _all_done():
		_game_over = true
		_hud.show_win(_stats, _run_start_area == 0, level_index + 1 < LEVELS.size())
	else:
		_flash_hint("The gate is sealed — hold the area first!")
func _flash_hint(text: String) -> void:
	_hud.set_objective(text)
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(_hud):
		_hud.set_objective(_current_objective)
func _set_objective(text: String) -> void:
	_current_objective = text
	if _hud != null:
		_hud.set_objective(text)
func _on_weapon_hit(headshot: bool) -> void:
	_stats["hits"] += 1
	if headshot:
		_stats["headshots"] += 1
		if DisplayServer.is_touchscreen_available():
			Input.vibrate_handheld(15)
func _on_player_health_changed(hp: float, _max_hp: float) -> void:
	if hp < _last_hp:
		_stats["damage_taken"] += _last_hp - hp
	_last_hp = hp
func _on_player_died() -> void:
	if _game_over:
		return
	_game_over = true
	_hud.show_death(_stats)
# ---------------------------------------------------------------- bot / test API
func get_area_count() -> int:
	return areas.size()
func get_current_area() -> int:
	return _current_area
func is_area_done(idx: int) -> bool:
	return _area_done[idx]
func area_kind(idx: int) -> String:
	return areas[idx]["kind"]
func area_entry_position(idx: int) -> Vector3:
	return Vector3(0, 0, float(areas[idx]["z0"]) - 1.5)
func area_center_position(idx: int) -> Vector3:
	return Vector3(0, 0, (float(areas[idx]["z0"]) + float(areas[idx]["z1"])) * 0.5)
func key_position() -> Vector3:
	if _key != null and is_instance_valid(_key):
		return _key.global_position
	return Vector3.ZERO
func gate_position() -> Vector3:
	return Vector3(0, 0, gate_z + 1.5)
func progress_text() -> String:
	return "level=%s area=%d done=%s" % [LEVELS[level_index]["id"], _current_area, str(_area_done)]
func bot_next_goal() -> Vector3:
	if _current_area < 0:
		return area_entry_position(0)
	var a: Dictionary = areas[_current_area]
	if not _area_done[_current_area]:
		if a["kind"] == "collect" and not _key_taken:
			return key_position()
		if a["kind"] == "reach":
			return area_entry_position(_current_area + 1)
		return area_center_position(_current_area)
	if _current_area + 1 < areas.size():
		return area_entry_position(_current_area + 1)
	return gate_position()
# ---------------------------------------------------------------- helpers
class Door extends StaticBody3D:
	var _shape: CollisionShape3D = null
	var _opened: bool = false
	var _height: float = 4.0
	func setup(width: float, height: float) -> void:
		_height = height
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width, height, 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.13, 0.12)
		mat.metallic = 0.4
		mat.roughness = 0.7
		bm.material = mat
		mi.mesh = bm
		add_child(mi)
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(width * 0.9, 0.18, 0.56)
		var bar_mat := StandardMaterial3D.new()
		bar_mat.albedo_color = Color(0.45, 0.08, 0.06)
		bar_mat.emission_enabled = true
		bar_mat.emission = Color(1.0, 0.15, 0.1)
		bar_mat.emission_energy_multiplier = 1.2
		bar_mesh.material = bar_mat
		bar.mesh = bar_mesh
		bar.position = Vector3(0, height * 0.15, 0)
		add_child(bar)
		_shape = CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(width, height, 0.5)
		_shape.shape = sh
		add_child(_shape)
	func open(instant: bool = false) -> void:
		if _opened:
			return
		_opened = true
		if instant:
			position.y += _height + 0.4
			_shape.disabled = true
			return
		var sfx: Node = get_tree().get_first_node_in_group("sfx")
		if sfx != null and sfx.has_method("play_at"):
			sfx.play_at("growl", global_position, -6.0, 0.35)
		var tw := create_tween()
		tw.tween_property(self, "position:y", position.y + _height + 0.4, 1.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func() -> void: _shape.disabled = true)
class Pickup extends Area3D:
	var _mesh: MeshInstance3D = null
	var _t: float = 0.0
	var _spin: float = 1.5
	func _make(size: Vector3, albedo: Color, emission: Color, energy: float, radius: float) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = albedo
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
		bm.material = mat
		mi.mesh = bm
		add_child(mi)
		_mesh = mi
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = radius
		cs.shape = sh
		add_child(cs)
		body_entered.connect(_on_body_entered)
	func _process(delta: float) -> void:
		_t += delta
		rotate_y(_spin * delta)
		_mesh.position.y = 0.06 * sin(_t * 3.0)
	func _on_body_entered(body: Node3D) -> void:
		if not body.is_in_group("player"):
			return
		if _apply(body):
			set_deferred("monitoring", false)
			queue_free()
	func _apply(_body: Node3D) -> bool:
		return false
	func _play(kind: String, volume_db: float, pitch: float) -> void:
		var sfx: Node = get_tree().get_first_node_in_group("sfx")
		if sfx != null and sfx.has_method("play"):
			sfx.play(kind, volume_db, pitch)
class AmmoPickup extends Pickup:
	var rounds: int = 30
	var shells: int = 0
	func _ready() -> void:
		_make(Vector3(0.35, 0.22, 0.35), Color(0.9, 0.7, 0.2), Color(1.0, 0.75, 0.2), 1.2, 0.9)
	func _apply(body: Node3D) -> bool:
		var weapon: Node = body.get_node_or_null("Head/Camera3D/WeaponMount/Weapon")
		if weapon == null or not weapon.has_method("add_reserve"):
			return false
		weapon.add_reserve(rounds)
		if shells > 0 and weapon.has_method("add_shells"):
			weapon.add_shells(shells)
		_play("pickup", -8.0, 1.0)
		return true
class HealthPickup extends Pickup:
	var amount: float = 40.0
	func _ready() -> void:
		_make(Vector3(0.3, 0.3, 0.3), Color(0.95, 0.95, 0.9), Color(0.3, 1.0, 0.45), 1.6, 0.9)
		var cross := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.34, 0.1, 0.1)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.1, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.15, 0.1)
		mat.emission_energy_multiplier = 1.5
		bm.material = mat
		cross.mesh = bm
		_mesh.add_child(cross)
		var cross2 := cross.duplicate()
		cross2.rotation.z = PI * 0.5
		_mesh.add_child(cross2)
	func _apply(body: Node3D) -> bool:
		if not body.has_method("heal"):
			return false
		if body.get("hp") != null and float(body.get("hp")) >= float(body.get("max_hp")):
			return false
		body.heal(amount)
		_play("pickup", -6.0, 1.25)
		return true
class KeyPickup extends Pickup:
	signal collected
	func _ready() -> void:
		_spin = 2.0
		_make(Vector3(0.18, 0.5, 0.18), Color(0.3, 0.9, 1.0), Color(0.4, 0.9, 1.0), 2.5, 1.0)
		var light := OmniLight3D.new()
		light.light_color = Color(0.4, 0.85, 1.0)
		light.light_energy = 1.2
		light.omni_range = 5.0
		light.shadow_enabled = false
		add_child(light)
	func _apply(_body: Node3D) -> bool:
		_play("pickup", -4.0, 1.5)
		collected.emit()
		return true
