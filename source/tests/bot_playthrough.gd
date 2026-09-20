extends Node
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MAX_FRAMES: int = 30000
var _game: Game
var _player: Player
var _weapon: Weapon
var _hud: HUD
var _kills: int = 0
var _frames: int = 0
var _stall_frames: int = 0
var _last_enemy_pos := { }
var _waves_seen := { }
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	print("--- bot playthrough ---")
	Game.skip_title = true
	_game = MAIN_SCENE.instantiate() as Game
	get_tree().root.add_child(_game)
	await _wait_physics(10)
	_player = get_tree().get_first_node_in_group("player") as Player
	_hud = get_tree().get_first_node_in_group("hud") as HUD
	if _player != null:
		_weapon = _player.get_node_or_null("Head/Camera3D/WeaponMount/Weapon") as Weapon
	if _player == null or _hud == null or _weapon == null:
		print("SETUP FAIL")
		get_tree().quit(1)
		return
	_hud._input(_mk_tap(Vector2(400, 200)))
	await _wait_physics(5)
	var _last_alive := 0
	var result := "TIMEOUT"
	while _frames < MAX_FRAMES:
		await get_tree().physics_frame
		_frames += 1
		_player.hp = _player.max_hp
		if _hud.get_node("UI/WinScreen").visible:
			result = "WIN"
			break
		if _hud.get_node("UI/DeathScreen").visible:
			result = "DIED"
			break
		_tick()
		var alive_now := get_tree().get_nodes_in_group("enemies").filter(
				func(e: Node) -> bool: return not (e as Enemy)._dead).size()
		if alive_now < _last_alive:
			_kills += _last_alive - alive_now
		_last_alive = alive_now
		if _frames == 250 or _frames == 500 or _frames == 750:
			await _snap("bp_bot_%d" % _frames)
		if _frames % 600 == 0:
			_report_progress()
		_check_stalls()
	print("kills=%d frames=%d" % [_kills, _frames])
	print("RESULT: " + result)
	get_tree().quit(0 if result == "WIN" else 1)
func _tick() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies").filter(
			func(e: Node) -> bool: return not (e as Enemy)._dead)
	if not enemies.is_empty():
		var target := _nearest(enemies)
		_aim_at(target.global_position + Vector3(0, 1.2, 0))
		_weapon.set_firing(true)
		_player.set_touch_firing(true)
		var to: Vector3 = target.global_position - _player.global_position
		to.y = 0.0
		var dist := to.length()
		var want := Vector3.ZERO
		if dist > 6.0:
			want = to.normalized()
		elif dist < 3.0:
			want = -to.normalized()
		else:
			want = to.normalized().rotated(Vector3.UP, PI / 2.0)
		_set_move(want)
	else:
		_weapon.set_firing(false)
		_player.set_touch_firing(false)
		var dest: Vector3 = _game.bot_next_goal()
		var to: Vector3 = dest - _player.global_position
		to.y = 0.0
		if to.length() < 1.0:
			_set_move(Vector3.ZERO)
		else:
			_face(to.normalized())
			_set_move(Vector3(0, 0, -1))
func _nearest(enemies: Array) -> Enemy:
	var best: Enemy = null
	var best_d := 1000000000.0
	for e in enemies:
		var d: float = _player.global_position.distance_to((e as Enemy).global_position)
		if d < best_d:
			best_d = d
			best = e
	return best
func _aim_at(world_point: Vector3) -> void:
	var head: Node3D = _player.get_node("Head")
	var to: Vector3 = world_point - head.global_position
	var yaw := atan2(-to.x, -to.z)
	var flat := Vector2(to.x, to.z).length()
	var pitch := clampf(atan2(to.y, flat), deg_to_rad(-85.0), deg_to_rad(85.0))
	_player._yaw = yaw
	_player._pitch = pitch
	_player.rotation.y = yaw
	head.rotation.x = pitch
func _face(dir: Vector3) -> void:
	var yaw := atan2(-dir.x, -dir.z)
	_player._yaw = yaw
	_player.rotation.y = yaw
	_player._pitch = 0.0
	(_player.get_node("Head") as Node3D).rotation.x = 0.0
func _set_move(local_dir: Vector3) -> void:
	if local_dir.length() < 0.01:
		_player.apply_touch_move(Vector2.ZERO)
		return
	_player.apply_touch_move(Vector2(local_dir.x, local_dir.z).limit_length(1.0))
func _check_stalls() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en._dead:
			continue
		var p: Vector3 = en.global_position
		var key := en.get_instance_id()
		if _last_enemy_pos.has(key):
			var old: Vector3 = _last_enemy_pos[key]
			var d: float = Vector2(p.x - old.x, p.z - old.z).length()
			var pd: float = Vector2(
					p.x - _player.global_position.x,
					p.z - _player.global_position.z).length()
			if d < 0.05 and pd > 2.5:
				_stall_frames += 1
				if _stall_frames == 600:
					print("STALL? enemy id=%d pos=%s dist_to_player=%.1f (600f)" % [key, str(p), pd])
		_last_enemy_pos[key] = p
func _report_progress() -> void:
	var alive := get_tree().get_nodes_in_group("enemies").filter(
			func(e: Node) -> bool: return not (e as Enemy)._dead).size()
	print("t=%d alive=%d player=%s %s" % [
			_frames, alive, str(_player.global_position),
			_game.progress_text()])
func _wait_physics(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame
func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/home/hatch/workspace/your_files/" + name + ".png")
	print("snap: " + name)
func _mk_tap(pos: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.index = 0
	ev.position = pos
	return ev
