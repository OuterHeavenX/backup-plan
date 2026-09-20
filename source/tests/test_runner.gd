extends Node
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const ZONE_ZS: Array[float] = [-16.0, -34.0, -52.0]
const GATE_Z: float = -64.5
const PLAYER_SPAWN := Vector3(0, 0.5, 0)
var _passed: int = 0
var _failed: int = 0
var _game: Game
var _player: Player
var _weapon: Weapon
var _hud: HUD
var _fired_count: int = 0
func _ready() -> void:
	_run_all.call_deferred()
func _run_all() -> void:
	print("--- FPS prototype headless tests ---")
	_game = MAIN_SCENE.instantiate() as Game
	get_tree().root.add_child(_game)
	await _wait_physics(10)
	_player = get_tree().get_first_node_in_group("player") as Player
	_hud = get_tree().get_first_node_in_group("hud") as HUD
	if _player != null:
		_weapon = _player.get_node_or_null("Head/Camera3D/WeaponMount/Weapon") as Weapon
	if _player == null or _hud == null or _weapon == null:
		_failed += 1
		print("FAIL: setup - could not resolve player/hud/weapon refs")
		print("RESULT: 0/1 passed")
		get_tree().quit(1)
		return
	for a in ["move_forward", "move_back", "move_left", "move_right", "fire", "reload", "jump"]:
		_release(a)
	await _test_story_dismiss()
	await _test_player_moves()
	await _test_shooting()
	await _test_reload()
	await _test_touch_move_direction()
	await _test_left_half_touch_never_looks()
	await _test_aim_while_firing()
	await _test_fire_jiggle_while_walking()
	await _test_touch_identifier_hardening()
	await _test_enemy_ai()
	await _test_win_path()
	await _test_lose_path()
	var total := _passed + _failed
	print("RESULT: %d/%d passed" % [_passed, total])
	get_tree().quit(0 if _failed == 0 else 1)
func _wait_physics(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame
func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)
func _release(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
func _verdict(test_name: String, ok: bool, reason: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS: " + test_name)
	else:
		_failed += 1
		print("FAIL: " + test_name + (" - " + reason if reason != "" else ""))
func _reset_player(pos: Vector3 = PLAYER_SPAWN) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	var head := _player.get_node_or_null("Head")
	if head != null:
		head.rotation.x = 0.0
func _heal() -> void:
	_player.hp = _player.max_hp
func _xz_dist(a: Vector3, b: Vector3) -> float:
	var d := a - b
	d.y = 0.0
	return d.length()
func _on_test_fired() -> void:
	_fired_count += 1
func _mk_touch(pressed: bool, index: int, pos: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.index = index
	ev.position = pos
	return ev
func _mk_drag(index: int, pos: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = relative
	return ev
func _test_story_dismiss() -> void:
	var overlay := _hud.get_node("UI/StoryOverlay") as Control
	if not (_hud.input_locked and overlay.visible):
		_verdict("story_dismiss", false,
				"story card not shown/locked at start (locked=%s, visible=%s)"
				% [str(_hud.input_locked), str(overlay.visible)])
		return
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	Input.parse_input_event(mb)
	await get_tree().physics_frame
	await get_tree().physics_frame
	mb.pressed = false
	Input.parse_input_event(mb)
	var ok := false
	for i in range(120):
		await get_tree().physics_frame
		if not _hud.input_locked and not overlay.visible:
			ok = true
			break
	if ok:
		_verdict("story_dismiss", true)
	else:
		_verdict("story_dismiss", false,
				"input still locked after click" if _hud.input_locked else "overlay still visible after click")
func _test_player_moves() -> void:
	_reset_player()
	await _wait_physics(5)
	var z0 := _player.global_position.z
	_press("move_forward")
	var moved := false
	for i in range(300):
		await get_tree().physics_frame
		if _player.global_position.z < z0 - 0.5:
			moved = true
			break
	_release("move_forward")
	var x0 := _player.global_position.x
	_press("move_right")
	var strafed := false
	for i in range(300):
		await get_tree().physics_frame
		if _player.global_position.x > x0 + 0.5:
			strafed = true
			break
	_release("move_right")
	if not moved:
		_verdict("player_moves", false,
				"z did not decrease (z0=%.2f, z=%.2f)" % [z0, _player.global_position.z])
	elif not strafed:
		_verdict("player_moves", false,
				"x did not increase while strafing (x0=%.2f, x=%.2f)" % [x0, _player.global_position.x])
	else:
		_verdict("player_moves", true)
func _test_shooting() -> void:
	_reset_player()
	_heal()
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.position = Vector3(0, 1.0, -6.0)
	_game.add_child(enemy)
	await _wait_physics(2)
	if not is_instance_valid(enemy):
		_verdict("shooting_fires_and_damages", false, "test enemy failed to instance")
		return
	var hp0: float = enemy.hp
	_fired_count = 0
	_weapon.fired.connect(_on_test_fired)
	_press("fire")
	var fired_ok := false
	var dmg_ok := false
	for i in range(600):
		await get_tree().physics_frame
		if _fired_count >= 3:
			fired_ok = true
		if is_instance_valid(enemy):
			if enemy.hp < hp0:
				dmg_ok = true
		else:
			dmg_ok = true
		if fired_ok and dmg_ok:
			break
	_release("fire")
	_weapon.fired.disconnect(_on_test_fired)
	if is_instance_valid(enemy):
		enemy.queue_free()
	await _wait_physics(5)
	if fired_ok and dmg_ok:
		_verdict("shooting_fires_and_damages", true)
	else:
		var hp_text := "dead" if not is_instance_valid(enemy) else "%.1f" % enemy.hp
		_verdict("shooting_fires_and_damages", false,
				"fired=%d (need >=3), enemy hp=%s (started %.1f)" % [_fired_count, hp_text, hp0])
func _test_reload() -> void:
	for i in range(120):
		if not _weapon.reloading:
			break
		await get_tree().physics_frame
	_weapon.mag = 5
	_weapon.start_reload()
	var ok := false
	for i in range(600):
		await get_tree().physics_frame
		if _weapon.mag == _weapon.mag_size and not _weapon.reloading:
			ok = true
			break
	if ok:
		_verdict("reload", true)
	else:
		_verdict("reload", false,
				"mag=%d (want %d), reloading=%s" % [_weapon.mag, _weapon.mag_size, str(_weapon.reloading)])
func _test_touch_move_direction() -> void:
	_reset_player()
	_heal()
	var joy := _hud.get_node("UI/TouchControls/Joystick")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var p := Vector2(vp.x * 0.25, vp.y * 0.6)
	joy._input(_mk_touch(true, 4, p))
	var up := p + Vector2(0, -60)
	joy._input(_mk_drag(4, up, Vector2(0, -60)))
	var z0 := _player.global_position.z
	var went_forward := false
	for i in range(300):
		await get_tree().physics_frame
		if _player.global_position.z < z0 - 0.5:
			went_forward = true
			break
	joy._input(_mk_touch(false, 4, up))
	_reset_player()
	joy._input(_mk_touch(true, 5, p))
	var down := p + Vector2(0, 60)
	joy._input(_mk_drag(5, down, Vector2(0, 60)))
	z0 = _player.global_position.z
	var went_back := false
	for i in range(300):
		await get_tree().physics_frame
		if _player.global_position.z > z0 + 0.5:
			went_back = true
			break
	joy._input(_mk_touch(false, 5, down))
	if not went_forward:
		_verdict("touch_move_direction", false, "push-up did not move player forward (-Z)")
	elif not went_back:
		_verdict("touch_move_direction", false, "push-down did not move player backward (+Z)")
	else:
		_verdict("touch_move_direction", true)
func _test_left_half_touch_never_looks() -> void:
	_reset_player()
	_heal()
	var look := _hud.get_node("UI/TouchControls/LookArea")
	var joy := _hud.get_node("UI/TouchControls/Joystick")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_player.rotation.y = 0.0
	_player._yaw = 0.0
	var yaw0: float = _player.rotation.y
	var p := Vector2(vp.x * 0.2, vp.y * 0.55)
	joy._input(_mk_touch(true, 7, p))
	look._input(_mk_touch(true, 7, p))
	var q := p
	for i in range(6):
		q += Vector2(25, -10)
		joy._input(_mk_drag(7, q, Vector2(25, -10)))
		look._input(_mk_drag(7, q, Vector2(25, -10)))
		await get_tree().physics_frame
	var yaw1: float = _player.rotation.y
	var moved: bool = _player.global_position.distance_to(Vector3(0, 0.5, 0)) > 0.3
	joy._input(_mk_touch(false, 7, q))
	look._input(_mk_touch(false, 7, q))
	if absf(yaw1 - yaw0) > 0.001:
		_verdict("left_half_touch_never_looks", false,
				"left-half drag spun the camera (dyaw=%.4f)" % (yaw1 - yaw0))
	elif not moved:
		_verdict("left_half_touch_never_looks", false,
				"left-half drag did not move the player")
	else:
		_verdict("left_half_touch_never_looks", true)
func _test_aim_while_firing() -> void:
	_reset_player()
	_heal()
	_hud.fire_grace_until = 0
	var look := _hud.get_node("UI/TouchControls/LookArea")
	var fire_btn := _hud.get_node("UI/TouchControls/FireButton") as Button
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var fire_center: Vector2 = fire_btn.get_global_rect().get_center()
	_player.rotation.y = 0.0
	_hud._on_touch_fire_down()
	var lp := Vector2(vp.x * 0.7, vp.y * 0.45)
	look._input(_mk_touch(true, 1, lp))
	for i in range(5):
		lp += Vector2(30, 0)
		look._input(_mk_drag(1, lp, Vector2(30, 0)))
		await get_tree().physics_frame
	var yaw_a: float = _player.rotation.y
	var firing_a: bool = _weapon.firing
	look._input(_mk_touch(false, 1, lp))
	_hud._on_touch_fire_up()
	var ok_a: bool = firing_a and absf(yaw_a) > 0.01
	_player.rotation.y = 0.0
	_hud._on_touch_fire_down()
	var sp := fire_center
	look._input(_mk_touch(true, 2, sp))
	for i in range(6):
		sp += Vector2(-40, -20)
		look._input(_mk_drag(2, sp, Vector2(-40, -20)))
		await get_tree().physics_frame
	var yaw_b: float = _player.rotation.y
	look._input(_mk_touch(false, 2, sp))
	_hud._on_touch_fire_up()
	_player.rotation.y = 0.0
	_hud._on_touch_fire_down()
	var mp := fire_center
	look._input(_mk_touch(true, 3, mp))
	for i in range(4):
		mp += Vector2(4, 3)
		look._input(_mk_drag(3, mp, Vector2(4, 3)))
		await get_tree().physics_frame
	var yaw_c: float = _player.rotation.y
	look._input(_mk_touch(false, 3, mp))
	_hud._on_touch_fire_up()
	_weapon.mag = _weapon.mag_size
	if not ok_a:
		_verdict("aim_while_firing", false,
				"look drag during fire failed (firing=%s, dyaw=%.4f)" % [str(firing_a), yaw_a])
	elif absf(yaw_b) < 0.01:
		_verdict("aim_while_firing", false, "slide-off-fire did not aim the camera")
	elif absf(yaw_c) > 0.001:
		_verdict("aim_while_firing", false,
				"micro-drift on FIRE moved the camera (dyaw=%.4f)" % yaw_c)
	else:
		_verdict("aim_while_firing", true)
func _test_fire_jiggle_while_walking() -> void:
	_reset_player()
	_heal()
	_hud.fire_grace_until = 0
	var look := _hud.get_node("UI/TouchControls/LookArea")
	var joy := _hud.get_node("UI/TouchControls/Joystick")
	var fire_btn := _hud.get_node("UI/TouchControls/FireButton") as Button
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var fire_center: Vector2 = fire_btn.get_global_rect().get_center()
	_player.rotation.y = 0.0
	_player._yaw = 0.0
	var jp := Vector2(vp.x * 0.25, vp.y * 0.6)
	joy._input(_mk_touch(true, 9, jp))
	look._input(_mk_touch(true, 9, jp))
	joy._input(_mk_drag(9, jp + Vector2(0, -60), Vector2(0, -60)))
	_hud._on_touch_fire_down()
	look._input(_mk_touch(true, 10, fire_center))
	var fp := fire_center
	var yaw0: float = _player.rotation.y
	for i in range(12):
		var off := Vector2(12, -10) if i % 2 == 0 else Vector2(-12, 10)
		fp = fire_center + off
		look._input(_mk_drag(10, fp, off))
		await get_tree().physics_frame
	var yaw1: float = _player.rotation.y
	var walked: bool = _player.global_position.z < -0.5
	look._input(_mk_touch(false, 10, fp))
	_hud._on_touch_fire_up()
	joy._input(_mk_touch(false, 9, jp))
	look._input(_mk_touch(false, 9, jp))
	_weapon.mag = _weapon.mag_size
	if absf(yaw1 - yaw0) > 0.001:
		_verdict("fire_jiggle_while_walking", false,
				"jiggling fire thumb while walking spun the camera (dyaw=%.4f)" % (yaw1 - yaw0))
	elif not walked:
		_verdict("fire_jiggle_while_walking", false,
				"player did not walk during the jiggle")
	else:
		_verdict("fire_jiggle_while_walking", true)
func _test_touch_identifier_hardening() -> void:
	_reset_player()
	_heal()
	_hud.fire_grace_until = 0
	var look := _hud.get_node("UI/TouchControls/LookArea")
	var joy := _hud.get_node("UI/TouchControls/Joystick")
	var fire_btn := _hud.get_node("UI/TouchControls/FireButton") as Button
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var fire_center: Vector2 = fire_btn.get_global_rect().get_center()
	_player.rotation.y = 0.0
	_player._yaw = 0.0
	var rp := Vector2(vp.x * 0.75, vp.y * 0.5)
	look._input(_mk_touch(true, 20, rp))
	look._input(_mk_drag(20, rp + Vector2(10, 5), Vector2(10, 5)))
	var yaw_after_real: float = _player.rotation.y
	look._input(_mk_drag(20, Vector2(50, 300), Vector2(-1000, 500)))
	var yaw_after_tp1: float = _player.rotation.y
	look._input(_mk_drag(20, Vector2(900, 100), Vector2(850, -200)))
	var yaw_after_tp2: float = _player.rotation.y
	look._input(_mk_drag(20, Vector2(700, 500), Vector2(10, 10)))
	var yaw_after_tp3: float = _player.rotation.y
	var ok_a: bool = absf(yaw_after_real) > 0.0001 \
		and absf(yaw_after_tp1 - yaw_after_real) < 0.0001 \
		and absf(yaw_after_tp2 - yaw_after_real) < 0.0001 \
		and absf(yaw_after_tp3 - yaw_after_real) < 0.0001 \
		and look._touch_index == -1
	look._input(_mk_touch(false, 20, rp))
	var lp := Vector2(vp.x * 0.25, vp.y * 0.6)
	joy._input(_mk_touch(true, 21, lp))
	look._touch_index = 21
	look._last_look_pos = Vector2(vp.x * 0.8, vp.y * 0.4)
	look._input(_mk_drag(21, lp + Vector2(30, -40), Vector2(30, -40)))
	var ok_b: bool = absf(_player.rotation.y - yaw_after_real) < 0.0001
	joy._input(_mk_touch(false, 21, lp))
	look._touch_index = -1
	look._touch_index = 22
	look._fire_touch_index = -1
	look._input(_mk_touch(true, 22, fire_center))
	var ok_c: bool = look._touch_index == -1 and look._fire_touch_index == 22
	look._input(_mk_touch(false, 22, fire_center))
	if not ok_a:
		_verdict("touch_identifier_hardening", false,
				"teleporting look drags moved the camera or did not release the touch")
	elif not ok_b:
		_verdict("touch_identifier_hardening", false,
				"a drag on the joystick's touch index steered the camera")
	elif not ok_c:
		_verdict("touch_identifier_hardening", false,
				"touch-down with a reused index did not reset stale look tracking")
	else:
		_verdict("touch_identifier_hardening", true)
func _test_enemy_ai() -> void:
	_reset_player()
	_heal()
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.position = Vector3(0, 1.0, -12.0)
	_game.add_child(enemy)
	await _wait_physics(5)
	if not is_instance_valid(enemy):
		_verdict("enemy_ai_engages", false, "test enemy failed to instance")
		return
	var d0 := _xz_dist(enemy.global_position, _player.global_position)
	var shrank := false
	for i in range(600):
		await get_tree().physics_frame
		if not is_instance_valid(enemy):
			break
		if _xz_dist(enemy.global_position, _player.global_position) < d0 - 1.0:
			shrank = true
			break
	var hp_before: float = _player.hp
	var attacked := false
	for i in range(900):
		await get_tree().physics_frame
		if _player.hp < hp_before:
			attacked = true
			break
	if is_instance_valid(enemy):
		enemy.queue_free()
	await _wait_physics(5)
	if not shrank:
		_verdict("enemy_ai_engages", false,
				"enemy did not approach the player (dist stayed ~%.1f)" % d0)
	elif not attacked:
		_verdict("enemy_ai_engages", false, "enemy approached but never damaged the player")
	else:
		_verdict("enemy_ai_engages", true)
func _test_win_path() -> void:
	_heal()
	var zone_names := ["WaveZone1", "WaveZone2", "WaveZone3"]
	for zi in range(ZONE_ZS.size()):
		_player.global_position = Vector3(0, 1.0, ZONE_ZS[zi])
		_player.velocity = Vector3.ZERO
		await _wait_physics(10)
		var spawned := false
		for i in range(300):
			await get_tree().physics_frame
			if get_tree().get_nodes_in_group("enemies").size() > 0:
				spawned = true
				break
		if not spawned:
			_verdict("win_path", false, "%s spawned no enemies" % zone_names[zi])
			return
		for e in get_tree().get_nodes_in_group("enemies"):
			(e as Enemy).take_damage(9999.0)
		var cleared := false
		for i in range(300):
			await get_tree().physics_frame
			if get_tree().get_nodes_in_group("enemies").is_empty():
				cleared = true
				break
		if not cleared:
			_verdict("win_path", false, "%s wave did not clear" % zone_names[zi])
			return
		_heal()
	_player.global_position = Vector3(0, 1.0, GATE_Z)
	_player.velocity = Vector3.ZERO
	var win_screen := _hud.get_node("UI/WinScreen") as Control
	var won := false
	for i in range(300):
		await get_tree().physics_frame
		if win_screen.visible:
			won = true
			break
	if won:
		_verdict("win_path", true)
	else:
		_verdict("win_path", false, "WinScreen never became visible after entering the exit gate")
func _test_lose_path() -> void:
	_game._game_over = false
	_player._dead = false
	_player.hp = _player.max_hp
	_player.take_damage(9999.0)
	var death_screen := _hud.get_node("UI/DeathScreen") as Control
	var shown := false
	for i in range(300):
		await get_tree().physics_frame
		if death_screen.visible:
			shown = true
			break
	if shown:
		_verdict("lose_path", true)
	else:
		_verdict("lose_path", false, "DeathScreen never became visible after lethal damage")
