class_name HUD
extends CanvasLayer
signal play_pressed
signal story_dismissed
signal restart_requested
signal retry_requested
signal next_level_requested
signal quit_to_title_requested
const SETTINGS_PATH := "user://settings.cfg"
const AMMO_COLOR_NORMAL := Color(1.0, 0.85, 0.6, 1.0)
const AMMO_COLOR_LOW := Color(1.0, 0.55, 0.2, 1.0)
const AMMO_COLOR_EMPTY := Color(1.0, 0.2, 0.15, 1.0)
const FONT_COLOR := Color(1.0, 0.85, 0.6, 1.0)
var input_locked: bool = false
var fire_grace_until: int = 0
var paused: bool = false
var _player: Player = null
var _weapon: Weapon = null
var _touch_shown: bool = false
var _hitmarker_tween: Tween = null
var _caption_tween: Tween = null
var _vignette_tween: Tween = null
var _playing: bool = false
var _ended: bool = false
var _checkpoint_available: bool = false
var _low_hp: bool = false
var _pulse_t: float = 0.0
var _weapon_label: String = "RIFLE"
var _level_name: String = ""
var _title_screen: Control = null
var _pause_screen: Control = null
var _caption: Label = null
var _area_label: Label = null
var _pause_button: Button = null
var _dash_button: Button = null
var _swap_button: Button = null
var _win_stats: Label = null
var _death_stats: Label = null
var _retry_button: Button = null
var _next_level_button: Button = null
var _level_button: Button = null
var _difficulty_button: Button = null
var _mouse_slider: HSlider = null
var _touch_slider: HSlider = null
var _vignette: ColorRect = null
var _joystick: Control = null
var _fire_button: Button = null
var _reload_button: Button = null
var _safe: Dictionary = {"left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0}
@onready var _ui: Control = $UI
@onready var _crosshair: ColorRect = $UI/Crosshair
@onready var _health_bar: ProgressBar = $UI/HealthBar
@onready var _ammo_label: Label = $UI/AmmoLabel
@onready var _objective_label: Label = $UI/ObjectiveLabel
@onready var _story_overlay: CenterContainer = $UI/StoryOverlay
@onready var _story_text: Label = $UI/StoryOverlay/Panel/Margin/VBox/StoryText
@onready var _death_screen: ColorRect = $UI/DeathScreen
@onready var _win_screen: ColorRect = $UI/WinScreen
@onready var _touch_controls: Control = $UI/TouchControls
func _ready() -> void:
	add_to_group("hud")
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	$UI/DeathScreen/Center/VBox/RestartButton.pressed.connect(_on_restart_pressed)
	$UI/WinScreen/Center/VBox/PlayAgainButton.pressed.connect(_on_restart_pressed)
	_ammo_label.offset_left = -440.0
	_build_vignette()
	_build_stats_labels()
	_build_caption()
	_build_title_screen()
	_build_pause_screen()
	_build_touch_controls()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	if DisplayServer.is_touchscreen_available():
		_show_touch_controls()
func bind(p: Player, w: Weapon) -> void:
	_player = p
	_weapon = w
	_load_settings()
	if _player != null:
		_player.health_changed.connect(_on_health_changed)
	if _weapon != null:
		_weapon.ammo_changed.connect(_on_ammo_changed)
		_weapon.target_hit.connect(_on_weapon_hit)
		_weapon.weapon_changed.connect(_on_weapon_changed)
		_weapon_label = _weapon.weapon_label()
		_on_ammo_changed(_weapon.mag, _weapon.reserve)
func set_playing(v: bool) -> void:
	_playing = v
func set_level_info(level_name: String, difficulty_title: String) -> void:
	_level_name = level_name
	if _level_button != null:
		_level_button.text = "LEVEL:  %s" % level_name.to_upper()
	if _difficulty_button != null:
		_difficulty_button.text = "DIFFICULTY:  %s" % difficulty_title
func set_checkpoint_available(v: bool) -> void:
	_checkpoint_available = v
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _playing and not _ended and not paused and not _story_overlay.visible:
			pause()
# ---------------------------------------------------------------- screens
func show_title() -> void:
	input_locked = true
	_title_screen.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_title_screen.find_child("PlayButton", true, false) as Button).grab_focus()
func _on_play_pressed() -> void:
	_title_screen.visible = false
	input_locked = false
	play_pressed.emit()
func _on_level_pressed() -> void:
	Game.level_index = (Game.level_index + 1) % Game.LEVELS.size()
	Game.story_shown = false
	Game.resume_area = -1
	_save_settings()
	get_tree().reload_current_scene()
func _on_difficulty_pressed() -> void:
	Game.difficulty = (Game.difficulty + 1) % Game.DIFFICULTIES.size()
	_save_settings()
	set_level_info(_level_name, Game.DIFFICULTIES[Game.difficulty]["title"])
func show_story(text: String) -> void:
	_story_text.text = text
	_story_overlay.visible = true
	input_locked = true
func _dismiss_story(event: InputEvent) -> void:
	_story_overlay.visible = false
	input_locked = false
	fire_grace_until = Time.get_ticks_msec() + 150
	get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	story_dismissed.emit()
func show_death(stats: Dictionary = {}) -> void:
	input_locked = true
	_ended = true
	_death_stats.text = _format_stats(stats, false, false)
	_retry_button.visible = _checkpoint_available
	_death_screen.visible = true
	_end_screen_shown()
	if _checkpoint_available:
		_retry_button.grab_focus()
	else:
		$UI/DeathScreen/Center/VBox/RestartButton.grab_focus()
func show_win(stats: Dictionary = {}, allow_best: bool = true, has_next_level: bool = false) -> void:
	input_locked = true
	_ended = true
	_win_stats.text = _format_stats(stats, true, allow_best)
	_next_level_button.visible = has_next_level
	_win_screen.visible = true
	_end_screen_shown()
	if has_next_level:
		_next_level_button.grab_focus()
	else:
		$UI/WinScreen/Center/VBox/PlayAgainButton.grab_focus()
func _end_screen_shown() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
func set_objective(t: String) -> void:
	_objective_label.text = t
func set_area_name(name_text: String) -> void:
	_area_label.text = name_text.to_upper()
	_area_label.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_area_label, "modulate", Color(1, 1, 1, 1), 0.4)
	tw.tween_interval(2.5)
	tw.tween_property(_area_label, "modulate", Color(1, 1, 1, 0), 0.8)
func show_caption(text: String, duration: float = 4.0) -> void:
	_caption.text = text
	if _caption_tween != null and _caption_tween.is_valid():
		_caption_tween.kill()
	_caption.modulate = Color(1, 1, 1, 0)
	_caption_tween = create_tween()
	_caption_tween.tween_property(_caption, "modulate", Color(1, 1, 1, 1), 0.3)
	_caption_tween.tween_interval(duration)
	_caption_tween.tween_property(_caption, "modulate", Color(1, 1, 1, 0), 0.6)
# ---------------------------------------------------------------- pause
func toggle_pause() -> void:
	if paused:
		resume()
	else:
		pause()
func pause() -> void:
	if paused or _ended or _title_screen.visible or _story_overlay.visible:
		return
	paused = true
	input_locked = true
	_pause_screen.visible = true
	_mouse_slider.set_value_no_signal(_player.look_sens if _player != null else 0.0025)
	_touch_slider.set_value_no_signal(_player.touch_look_sens if _player != null else 0.005)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	(_pause_screen.find_child("ResumeButton", true, false) as Button).grab_focus()
	if _player != null:
		_player.set_touch_firing(false)
	if _weapon != null:
		_weapon.set_firing(false)
func resume() -> void:
	if not paused:
		return
	paused = false
	input_locked = false
	_pause_screen.visible = false
	get_tree().paused = false
	fire_grace_until = Time.get_ticks_msec() + 200
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _on_restart_pressed() -> void:
	restart_requested.emit()
func _on_retry_pressed() -> void:
	retry_requested.emit()
func _on_next_level_pressed() -> void:
	next_level_requested.emit()
func _on_quit_pressed() -> void:
	quit_to_title_requested.emit()
# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not _touch_shown:
		_show_touch_controls()
	if event.is_action_pressed("ui_cancel") and not _ended and not _title_screen.visible:
		if _story_overlay.visible:
			return
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if input_locked and _story_overlay.visible:
		var dismiss := false
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			dismiss = true
		elif event is InputEventScreenTouch and event.pressed:
			dismiss = true
		elif event.is_action_pressed("ui_accept"):
			dismiss = true
		if dismiss:
			_dismiss_story(event)
func _process(delta: float) -> void:
	if _low_hp and not _ended and not paused:
		_pulse_t += delta * 5.0
		var a := 0.12 + 0.1 * (0.5 + 0.5 * sin(_pulse_t))
		if _vignette_tween == null or not _vignette_tween.is_valid():
			_vignette.color = Color(0.6, 0.0, 0.0, a)
		var fill := _health_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill != null:
			fill.bg_color = Color(0.65, 0.1, 0.08).lerp(Color(1.0, 0.25, 0.15), 0.5 + 0.5 * sin(_pulse_t))
func _on_health_changed(hp: float, max_hp: float) -> void:
	var dropped: bool = hp < _health_bar.value
	_health_bar.max_value = max_hp
	_health_bar.value = hp
	var was_low := _low_hp
	_low_hp = hp > 0.0 and hp <= max_hp * 0.3
	if dropped:
		_flash_vignette()
	if was_low and not _low_hp:
		_vignette.color = Color(0.6, 0.0, 0.0, 0.0)
		var fill := _health_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill != null:
			fill.bg_color = Color(0.65, 0.1, 0.08)
func _flash_vignette() -> void:
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette.color = Color(0.7, 0.0, 0.0, 0.42)
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_vignette, "color", Color(0.6, 0.0, 0.0, 0.12 if _low_hp else 0.0), 0.45)
func _on_weapon_changed(label: String) -> void:
	_weapon_label = label
	if _weapon != null:
		_on_ammo_changed(_weapon.mag, _weapon.reserve)
func _on_ammo_changed(mag: int, reserve: int) -> void:
	var res_text: String = "∞" if reserve < 0 else str(reserve)
	_ammo_label.text = "%s   %d / %s" % [_weapon_label, mag, res_text]
	var color := AMMO_COLOR_NORMAL
	if mag == 0 and reserve == 0:
		color = AMMO_COLOR_EMPTY
	elif mag <= 5 or reserve == 0:
		color = AMMO_COLOR_LOW
	_ammo_label.add_theme_color_override("font_color", color)
func _on_weapon_hit(headshot: bool) -> void:
	_crosshair.pivot_offset = _crosshair.size * 0.5
	if _hitmarker_tween != null and _hitmarker_tween.is_valid():
		_hitmarker_tween.kill()
	_crosshair.scale = Vector2(2.4, 2.4) if headshot else Vector2(1.8, 1.8)
	_crosshair.color = Color(1.0, 0.15, 0.1, 1.0) if headshot else Color(1.0, 0.85, 0.3, 1.0)
	_hitmarker_tween = create_tween().set_parallel(true)
	_hitmarker_tween.tween_property(_crosshair, "scale", Vector2.ONE, 0.18)
	_hitmarker_tween.tween_property(_crosshair, "color", Color(1.0, 1.0, 1.0, 0.7), 0.25)
# ---------------------------------------------------------------- stats / settings
func _format_time(sec: float) -> String:
	var s := int(round(sec))
	return "%d:%02d" % [s / 60, s % 60]
func _format_stats(stats: Dictionary, won: bool, allow_best: bool) -> String:
	if stats.is_empty():
		return ""
	var shots: int = int(stats.get("shots", 0))
	var hits: int = int(stats.get("hits", 0))
	var acc: int = int(round(100.0 * float(hits) / float(shots))) if shots > 0 else 0
	var t: float = float(stats.get("time", 0.0))
	var lines: Array[String] = []
	lines.append("Time %s   Kills %d   Headshots %d" % [_format_time(t), int(stats.get("kills", 0)), int(stats.get("headshots", 0))])
	lines.append("Accuracy %d%%   Damage taken %d" % [acc, int(round(float(stats.get("damage_taken", 0.0))))])
	if won:
		var key := "best_time_%d_%d" % [Game.level_index, Game.difficulty]
		var best: float = _load_record(key)
		if not allow_best:
			lines.append("Checkpoint run — best time %s" % (_format_time(best) if best > 0.0 else "not set"))
		elif best <= 0.0 or t < best:
			_save_record(key, t)
			lines.append("NEW BEST TIME" if best > 0.0 else "First clear — best time set")
		else:
			lines.append("Best time %s" % _format_time(best))
	return "\n".join(lines)
func _load_record(key: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return 0.0
	return float(cfg.get_value("records", key, 0.0))
func _save_record(key: String, t: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("records", key, t)
	cfg.save(SETTINGS_PATH)
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK or _player == null:
		return
	_player.look_sens = float(cfg.get_value("look", "mouse", _player.look_sens))
	_player.touch_look_sens = float(cfg.get_value("look", "touch", _player.touch_look_sens))
func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	if _player != null:
		cfg.set_value("look", "mouse", _player.look_sens)
		cfg.set_value("look", "touch", _player.touch_look_sens)
	cfg.set_value("game", "level", Game.level_index)
	cfg.set_value("game", "difficulty", Game.difficulty)
	cfg.save(SETTINGS_PATH)
# ---------------------------------------------------------------- builders
func _make_label(text: String, size: int, color: Color = FONT_COLOR) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
func _make_button(text: String, cb: Callable, width: float = 300.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 56)
	_style_touch_button(b)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	return b
func _make_overlay(overlay_name: String, bg: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = overlay_name
	rect.color = bg
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.visible = false
	_ui.add_child(rect)
	return rect
func _make_center_vbox(parent: Control, separation: int) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", separation)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)
	return vbox
func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.name = "Vignette"
	_vignette.color = Color(0.6, 0.0, 0.0, 0.0)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_vignette)
	_ui.move_child(_vignette, 0)
func _build_stats_labels() -> void:
	_win_stats = _make_label("", 20, Color(0.92, 0.88, 0.82, 1.0))
	var win_vbox: VBoxContainer = $UI/WinScreen/Center/VBox
	win_vbox.add_child(_win_stats)
	win_vbox.move_child(_win_stats, 1)
	_next_level_button = _make_button("NEXT LEVEL", _on_next_level_pressed)
	_next_level_button.name = "NextLevelButton"
	win_vbox.add_child(_next_level_button)
	win_vbox.move_child(_next_level_button, 2)
	win_vbox.add_child(_make_button("QUIT TO TITLE", _on_quit_pressed))
	_death_stats = _make_label("", 20, Color(0.92, 0.88, 0.82, 1.0))
	var death_vbox: VBoxContainer = $UI/DeathScreen/Center/VBox
	death_vbox.add_child(_death_stats)
	death_vbox.move_child(_death_stats, 1)
	_retry_button = _make_button("RETRY FROM CHECKPOINT", _on_retry_pressed)
	_retry_button.name = "RetryButton"
	death_vbox.add_child(_retry_button)
	death_vbox.move_child(_retry_button, 2)
	death_vbox.add_child(_make_button("QUIT TO TITLE", _on_quit_pressed))
func _build_caption() -> void:
	_caption = _make_label("", 22, Color(0.95, 0.9, 0.82, 1.0))
	_caption.name = "Caption"
	_caption.anchor_left = 0.5
	_caption.anchor_right = 0.5
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = -400
	_caption.offset_right = 400
	_caption.offset_top = -150
	_caption.offset_bottom = -110
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.modulate = Color(1, 1, 1, 0)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_caption)
	_area_label = _make_label("", 34, Color(1.0, 0.78, 0.35, 1.0))
	_area_label.name = "AreaName"
	_area_label.anchor_left = 0.5
	_area_label.anchor_right = 0.5
	_area_label.offset_left = -400
	_area_label.offset_right = 400
	_area_label.offset_top = 60
	_area_label.offset_bottom = 110
	_area_label.add_theme_color_override("font_outline_color", Color(0.3, 0.08, 0.04, 1.0))
	_area_label.add_theme_constant_override("outline_size", 6)
	_area_label.modulate = Color(1, 1, 1, 0)
	_area_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_area_label)
func _build_title_screen() -> void:
	_title_screen = _make_overlay("TitleScreen", Color(0.02, 0.015, 0.03, 0.92))
	var vbox := _make_center_vbox(_title_screen, 14)
	var title := _make_label("BACKUP PLAN", 72, Color(1.0, 0.78, 0.35, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.08, 0.04, 1.0))
	title.add_theme_constant_override("outline_size", 8)
	vbox.add_child(title)
	vbox.add_child(_make_label("Ash chokes the valley. Get to the gate.", 22, Color(0.92, 0.88, 0.82, 1.0)))
	var play := _make_button("PLAY", _on_play_pressed, 340.0)
	play.name = "PlayButton"
	play.add_theme_font_size_override("font_size", 26)
	vbox.add_child(play)
	_level_button = _make_button("LEVEL", _on_level_pressed, 340.0)
	_level_button.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_level_button)
	_difficulty_button = _make_button("DIFFICULTY", _on_difficulty_pressed, 340.0)
	_difficulty_button.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_difficulty_button)
	var hint := "WASD move  ·  Shift dash  ·  Mouse look  ·  Click fire  ·  R reload  ·  1 / 2 weapons  ·  ESC pause"
	if DisplayServer.is_touchscreen_available():
		hint = "Left thumb: move (double-tap to dash)  ·  Right thumb: look  ·  FIRE / RELOAD / SWAP buttons"
	vbox.add_child(_make_label(hint, 15, Color(1.0, 0.75, 0.4, 0.9)))
	set_level_info(_level_name, Game.DIFFICULTIES[Game.difficulty]["title"])
func _build_pause_screen() -> void:
	_pause_screen = _make_overlay("PauseScreen", Color(0.0, 0.0, 0.0, 0.8))
	var vbox := _make_center_vbox(_pause_screen, 12)
	vbox.add_child(_make_label("PAUSED", 52, Color(1.0, 0.78, 0.35, 1.0)))
	var resume_btn := _make_button("RESUME", resume)
	resume_btn.name = "ResumeButton"
	vbox.add_child(resume_btn)
	vbox.add_child(_make_button("RESTART", _on_restart_pressed))
	vbox.add_child(_make_button("QUIT TO TITLE", _on_quit_pressed))
	vbox.add_child(_make_label("Mouse look sensitivity", 15))
	_mouse_slider = _make_slider(0.0008, 0.008, 0.0001, func(v: float) -> void:
		if _player != null:
			_player.look_sens = v
		_save_settings())
	vbox.add_child(_mouse_slider)
	vbox.add_child(_make_label("Touch look sensitivity", 15))
	_touch_slider = _make_slider(0.002, 0.014, 0.0002, func(v: float) -> void:
		if _player != null:
			_player.touch_look_sens = v
		_save_settings())
	vbox.add_child(_touch_slider)
	_pause_button = Button.new()
	_pause_button.name = "PauseButton"
	_pause_button.text = "PAUSE"
	_pause_button.anchor_left = 1.0
	_pause_button.anchor_right = 1.0
	_pause_button.offset_left = -120
	_pause_button.offset_top = 14
	_pause_button.offset_right = -20
	_pause_button.offset_bottom = 54
	_style_touch_button(_pause_button)
	_pause_button.add_theme_font_size_override("font_size", 16)
	_pause_button.pressed.connect(pause)
	_pause_button.visible = false
	_ui.add_child(_pause_button)
func _make_slider(min_v: float, max_v: float, step: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.custom_minimum_size = Vector2(300, 24)
	s.value_changed.connect(cb)
	return s
func _show_touch_controls() -> void:
	_touch_shown = true
	_touch_controls.visible = true
	if _pause_button != null:
		_pause_button.visible = true
func _apply_safe_area() -> void:
	# Keep touch buttons clear of notches / home indicators on phones. The
	# safe rect is in window pixels; convert to canvas units.
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var canvas := get_viewport().get_visible_rect().size
	if win.x <= 0.0 or win.y <= 0.0:
		return
	var sx := canvas.x / win.x
	var sy := canvas.y / win.y
	_safe["left"] = maxf(0.0, float(safe.position.x)) * sx
	_safe["top"] = maxf(0.0, float(safe.position.y)) * sy
	_safe["right"] = maxf(0.0, win.x - float(safe.position.x + safe.size.x)) * sx
	_safe["bottom"] = maxf(0.0, win.y - float(safe.position.y + safe.size.y)) * sy
	var r: float = _safe["right"]
	var b: float = _safe["bottom"]
	if _fire_button != null:
		_place_bottom_right(_fire_button, 196.0 + r, 216.0 + b, 140.0, 100.0)
	if _reload_button != null:
		_place_bottom_right(_reload_button, 196.0 + r, 336.0 + b, 140.0, 84.0)
	if _swap_button != null:
		_place_bottom_right(_swap_button, 356.0 + r, 216.0 + b, 140.0, 84.0)
	if _dash_button != null:
		_place_bottom_right(_dash_button, 356.0 + r, 320.0 + b, 140.0, 84.0)
	if _pause_button != null:
		_pause_button.offset_left = -120 - r
		_pause_button.offset_right = -20 - r
		_pause_button.offset_top = 14 + _safe["top"]
		_pause_button.offset_bottom = 54 + _safe["top"]
	if _joystick != null:
		_joystick.safe_left = _safe["left"]
		_joystick.safe_bottom = b
		_joystick.queue_redraw()
func _place_bottom_right(b: Button, from_right: float, from_bottom: float, w: float, h: float) -> void:
	b.anchor_left = 1.0
	b.anchor_top = 1.0
	b.anchor_right = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = -from_right
	b.offset_top = -from_bottom
	b.offset_right = -from_right + w
	b.offset_bottom = -from_bottom + h
func _build_touch_controls() -> void:
	var joy := TouchJoystick.new()
	joy.name = "Joystick"
	joy.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy.output = func(v: Vector2) -> void:
		if input_locked:
			return
		if _player != null:
			_player.apply_touch_move(v)
	joy.dash_callback = _on_touch_dash
	_touch_controls.add_child(joy)
	_joystick = joy
	var look := TouchLookArea.new()
	look.name = "LookArea"
	look.set_anchors_preset(Control.PRESET_FULL_RECT)
	look.mouse_filter = Control.MOUSE_FILTER_IGNORE
	look.hud_ref = self
	look.stick_ref = joy
	_touch_controls.add_child(look)
	_fire_button = Button.new()
	_fire_button.name = "FireButton"
	_fire_button.text = "FIRE"
	_place_bottom_right(_fire_button, 196.0, 216.0, 140.0, 100.0)
	_style_touch_button(_fire_button)
	_fire_button.button_down.connect(_on_touch_fire_down)
	_fire_button.button_up.connect(_on_touch_fire_up)
	_touch_controls.add_child(_fire_button)
	_reload_button = Button.new()
	_reload_button.name = "ReloadButton"
	_reload_button.text = "RELOAD"
	_place_bottom_right(_reload_button, 196.0, 336.0, 140.0, 84.0)
	_style_touch_button(_reload_button)
	_reload_button.pressed.connect(_on_touch_reload_pressed)
	_touch_controls.add_child(_reload_button)
	_swap_button = Button.new()
	_swap_button.name = "SwapButton"
	_swap_button.text = "SWAP"
	_place_bottom_right(_swap_button, 356.0, 216.0, 140.0, 84.0)
	_style_touch_button(_swap_button)
	_swap_button.add_theme_font_size_override("font_size", 18)
	_swap_button.pressed.connect(_on_touch_swap_pressed)
	_touch_controls.add_child(_swap_button)
	_dash_button = Button.new()
	_dash_button.name = "DashButton"
	_dash_button.text = "DASH"
	_place_bottom_right(_dash_button, 356.0, 320.0, 140.0, 84.0)
	_style_touch_button(_dash_button)
	_dash_button.add_theme_font_size_override("font_size", 18)
	_dash_button.pressed.connect(_on_touch_dash)
	_touch_controls.add_child(_dash_button)
	look.fire_button = _fire_button
	look.reload_button = _reload_button
	look.extra_buttons = [_swap_button, _dash_button, _pause_button]
func _style_touch_button(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.06, 0.06, 0.85)
	normal.border_color = Color(0.62, 0.14, 0.1, 1.0)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.4, 0.09, 0.07, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.85, 1.0))
	b.add_theme_font_size_override("font_size", 22)
func _on_touch_fire_down() -> void:
	if input_locked:
		return
	if _player != null:
		_player.set_touch_firing(true)
	if _weapon != null:
		_weapon.set_firing(true)
func _on_touch_fire_up() -> void:
	if _player != null:
		_player.set_touch_firing(false)
	if _weapon != null:
		_weapon.set_firing(false)
func _on_touch_reload_pressed() -> void:
	if input_locked:
		return
	if _weapon != null:
		_weapon.start_reload()
func _on_touch_swap_pressed() -> void:
	if input_locked:
		return
	if _weapon != null:
		_weapon.toggle_weapon()
func _on_touch_dash() -> void:
	if input_locked:
		return
	if _player != null:
		_player.dash()
class TouchJoystick extends Control:
	const MOVE_FRACTION: float = 0.5
	var safe_left: float = 0.0
	var safe_bottom: float = 0.0
	var radius: float = 105.0
	var knob_radius: float = 40.0
	var output: Callable = func(_v: Vector2) -> void: pass
	var _touch_index: int = -1
	var _base_pos: Vector2 = Vector2.ZERO
	var _knob_offset: Vector2 = Vector2.ZERO
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dash_callback: Callable = func() -> void: pass
	var _last_tap_ms: int = -100000
	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if event.pressed:
				if event.index == _touch_index:
					_reset_touch()
				if _touch_index == -1 and _is_move_touch(event.position):
					_touch_index = event.index
					_base_pos = event.position
					_knob_offset = Vector2.ZERO
					output.call(Vector2.ZERO)
					queue_redraw()
					# Double-tap on the move half dashes.
					var now := Time.get_ticks_msec()
					if now - _last_tap_ms < 320:
						dash_callback.call()
						_last_tap_ms = -100000
					else:
						_last_tap_ms = now
			elif event.index == _touch_index:
				_reset_touch()
		elif event is InputEventScreenDrag:
			if event.index == _touch_index:
				_update_knob(event.position)
	func get_touch_index() -> int:
		return _touch_index
	func _reset_touch() -> void:
		_touch_index = -1
		_knob_offset = Vector2.ZERO
		output.call(Vector2.ZERO)
		queue_redraw()
	func _is_move_touch(pos: Vector2) -> bool:
		return pos.x < get_viewport_rect().size.x * MOVE_FRACTION
	func _update_knob(pos: Vector2) -> void:
		var d: Vector2 = pos - _base_pos
		if d.length() > radius:
			d = d.normalized() * radius
		_knob_offset = d
		output.call(d / radius)
		queue_redraw()
	func _draw() -> void:
		if _touch_index == -1:
			var hint := Vector2(160.0 + safe_left, get_viewport_rect().size.y - 220.0 - safe_bottom)
			draw_circle(hint, radius, Color(1, 1, 1, 0.03))
			draw_arc(hint, radius, 0.0, TAU, 48, Color(0.9, 0.25, 0.15, 0.18), 3.0, true)
		else:
			draw_circle(_base_pos, radius, Color(1, 1, 1, 0.1))
			draw_arc(_base_pos, radius, 0.0, TAU, 48, Color(0.9, 0.25, 0.15, 0.55), 3.0, true)
			draw_circle(_base_pos + _knob_offset, knob_radius, Color(1, 1, 1, 0.22))
			draw_arc(_base_pos + _knob_offset, knob_radius, 0.0, TAU, 32, Color(0.9, 0.3, 0.2, 0.8), 2.0, true)
class TouchLookArea extends Control:
	var hud_ref: HUD = null
	var fire_button: Button = null
	var reload_button: Button = null
	var extra_buttons: Array = []
	var stick_ref: TouchJoystick = null
	const FIRE_LEAVE_MARGIN: float = 14.0
	const LOOK_TELEPORT_PX: float = 200.0
	var _touch_index: int = -1
	var _fire_touch_index: int = -1
	var _last_look_pos: Vector2 = Vector2.ZERO
	var _fire_last_pos: Vector2 = Vector2.ZERO
	var _teleport_strikes: int = 0
	func _input(event: InputEvent) -> void:
		if hud_ref == null or hud_ref._player == null:
			return
		if hud_ref.input_locked:
			_release_all()
			return
		if event is InputEventScreenTouch:
			if event.pressed:
				_on_touch_down(event.index, event.position)
			else:
				_on_touch_up(event.index)
		elif event is InputEventScreenDrag:
			_on_touch_drag(event.index, event.position, event.relative)
	func _release_all() -> void:
		_touch_index = -1
		_fire_touch_index = -1
		_teleport_strikes = 0
	func _on_touch_down(index: int, pos: Vector2) -> void:
		if index == _touch_index or index == _fire_touch_index:
			_release_all()
		if _touch_index == -1 and _is_look_touch(pos):
			_touch_index = index
			_last_look_pos = pos
			_teleport_strikes = 0
		elif _fire_touch_index == -1 and _is_fire_touch(pos):
			_fire_touch_index = index
			_fire_last_pos = pos
	func _on_touch_up(index: int) -> void:
		if index == _touch_index:
			_touch_index = -1
			_teleport_strikes = 0
		if index == _fire_touch_index:
			_fire_touch_index = -1
	func _on_touch_drag(index: int, pos: Vector2, _relative: Vector2) -> void:
		# InputEventScreenDrag.relative is deliberately ignored. Godot's web
		# platform computes it against the wrong finger when more than one
		# touch is down (its previous-position table is indexed by the slot
		# inside the touchmove event, not by the touch id), which spun the
		# camera whenever both thumbs were on the screen. The delta is derived
		# from the tracked positions instead, which are always correct.
		if stick_ref != null and index == stick_ref.get_touch_index():
			return
		if index == _touch_index:
			var delta: Vector2 = pos - _last_look_pos
			if delta.length() > LOOK_TELEPORT_PX:
				_teleport_strikes += 1
				_last_look_pos = pos
				if _teleport_strikes >= 2:
					_touch_index = -1
					_teleport_strikes = 0
				return
			_teleport_strikes = 0
			_last_look_pos = pos
			hud_ref._player.apply_touch_look(delta)
		elif index == _fire_touch_index and _touch_index == -1:
			if not _is_fire_touch(pos, FIRE_LEAVE_MARGIN):
				var delta: Vector2 = pos - _fire_last_pos
				_fire_touch_index = -1
				_touch_index = index
				_last_look_pos = pos
				_teleport_strikes = 0
				if delta.length() <= LOOK_TELEPORT_PX:
					hud_ref._player.apply_touch_look(delta)
			else:
				_fire_last_pos = pos
	func _is_fire_touch(pos: Vector2, margin: float = 0.0) -> bool:
		if fire_button == null:
			return false
		return fire_button.get_global_rect().grow(margin).has_point(pos)
	func _is_look_touch(pos: Vector2) -> bool:
		if pos.x < get_viewport_rect().size.x * TouchJoystick.MOVE_FRACTION:
			return false
		if _is_fire_touch(pos):
			return false
		if reload_button != null and reload_button.get_global_rect().has_point(pos):
			return false
		for b in extra_buttons:
			if b != null and b.visible and (b as Control).get_global_rect().has_point(pos):
				return false
		return true
