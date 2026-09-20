extends Node
# Procedurally synthesised sound effects. The project ships no audio assets,
# so every sound is generated into an AudioStreamWAV at startup and played
# from small pools of 2D / 3D players. Looked up through the "sfx" group.
const RATE: int = 22050
const POOL_2D: int = 6
const POOL_3D: int = 10
var _streams: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _rng := RandomNumberGenerator.new()
func _ready() -> void:
	add_to_group("sfx")
	_rng.seed = 1337
	_streams["shot"] = _make_wav(_gen_shot())
	_streams["hit"] = _make_wav(_gen_hit())
	_streams["growl"] = _make_wav(_gen_growl())
	_streams["reload"] = _make_wav(_gen_reload())
	_streams["hurt"] = _make_wav(_gen_hurt())
	for i in range(POOL_2D):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players_2d.append(p)
	for i in range(POOL_3D):
		var p3 := AudioStreamPlayer3D.new()
		p3.max_distance = 45.0
		p3.unit_size = 6.0
		add_child(p3)
		_players_3d.append(p3)
func play(kind: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(kind)
	if stream == null:
		return
	var p := _free_2d()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
func play_at(kind: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(kind)
	if stream == null:
		return
	var p := _free_3d()
	p.global_position = pos
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
func _free_2d() -> AudioStreamPlayer:
	for p in _players_2d:
		if not p.playing:
			return p
	return _players_2d[0]
func _free_3d() -> AudioStreamPlayer3D:
	for p in _players_3d:
		if not p.playing:
			return p
	return _players_3d[0]
func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := clampf(samples[i], -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	wav.data = data
	return wav
func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)
func _gen_shot() -> PackedFloat32Array:
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var crack := _noise() * exp(-t * 38.0)
		var thump := sin(TAU * 85.0 * t) * exp(-t * 16.0) * 0.8
		out[i] = clampf((crack + thump) * 1.4, -1.0, 1.0) * 0.8
	return out
func _gen_hit() -> PackedFloat32Array:
	var n := int(RATE * 0.16)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var thud := sin(TAU * (120.0 - 260.0 * t) * t) * exp(-t * 22.0)
		var crunch := _noise() * 0.35 * exp(-t * 60.0)
		out[i] = (thud + crunch) * 0.8
	return out
func _gen_growl() -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var freq := 68.0 + 18.0 * sin(TAU * 5.5 * t)
		phase += freq / RATE
		var saw := 2.0 * (phase - floorf(phase)) - 1.0
		var env := minf(t * 18.0, 1.0) * exp(-maxf(t - 0.22, 0.0) * 9.0)
		out[i] = (saw * 0.5 + _noise() * 0.18) * env * 0.85
	return out
func _gen_reload() -> PackedFloat32Array:
	var n := int(RATE * 0.3)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var a := _noise() * exp(-t * 180.0)
		var t2 := maxf(t - 0.14, 0.0)
		var b := _noise() * exp(-t2 * 160.0) if t >= 0.14 else 0.0
		out[i] = (a + b) * 0.5
	return out
func _gen_hurt() -> PackedFloat32Array:
	var n := int(RATE * 0.2)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		out[i] = (sin(TAU * 170.0 * t) * exp(-t * 14.0) + _noise() * 0.2 * exp(-t * 40.0)) * 0.7
	return out
