extends Node
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
var _hud: HUD
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var game: Game = MAIN_SCENE.instantiate()
	get_tree().root.add_child(game)
	await _wait(10)
	_hud = get_tree().get_first_node_in_group("hud") as HUD
	_hud._input(_mk(true, 0, Vector2(640, 360)))
	await _wait(5)
	var joy = _hud.get_node("UI/TouchControls/Joystick")
	var look = _hud.get_node("UI/TouchControls/LookArea")
	var p := Vector2(300, 500)
	joy._input(_mk(true, 1, p))
	look._input(_mk(true, 1, p))
	for i in range(4):
		p += Vector2(0, -25)
		joy._input(_mkd(1, p, Vector2(0, -25)))
		look._input(_mkd(1, p, Vector2(0, -25)))
		await get_tree().physics_frame
	await _snap("bp_floatstick")
	joy._input(_mk(false, 1, p))
	look._input(_mk(false, 1, p))
	print("done")
	get_tree().quit(0)
func _wait(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame
func _snap(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
			"/home/hatch/workspace/your_files/" + n + ".png")
func _mk(pressed: bool, idx: int, pos: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.index = idx
	ev.position = pos
	return ev
func _mkd(idx: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	ev.relative = rel
	return ev
