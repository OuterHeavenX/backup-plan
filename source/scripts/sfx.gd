extends Node
# Procedurally synthesised audio. The project ships no audio assets, so every
# sound is generated into an AudioStreamWAV at startup. To swap in real files
# later, replace the entries of `_streams` with loaded .ogg/.wav streams.
const RATE: int = 22050
const POOL_2D: int = 8
const POOL_3D: int = 12
var _streams: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _wind: AudioStreamPlayer = null
var _music: AudioStreamPlayer = null
var _rng := RandomNumberGenerator.new()
func _ready() -> void:
	add_to_group("sfx")
	_rng.seed = 1337
	_streams["shot"] = _make_wav(_gen_shot())
	_streams["shotgun"] = _make_wav(_gen_shotgun())
	_streams["hit"] = _make_wav(_gen_hit())
	_streams["growl"] = _make_wav(_gen_growl())
	_streams["reload"] = _make_wav(_gen_reload())
	_streams["hurt"] = _make_wav(_gen_hurt())
	_streams["step"] = _make_wav(_gen_step())
	_streams["slam"] = _make_wav(_gen_slam())
	_streams["dash"] = _make_wav(_gen_dash())
	_streams["pickup"] = _make_wav(_gen_pickup())
	_streams["wind"] = _make_wav(_gen_wind(), true)
	_streams["music"] = _make_wav(_gen_music(), true)
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
	_wind = AudioStreamPlayer.new()
	_wind.stream = _streams["wind"]
	_wind.volume_db = -16.0
	add_child(_wind)
	_music = AudioStreamPlayer.new()
	_music.stream = _streams["music"]
	_music.volume_db = -13.0
	add_child(_music)
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
func start_ambience() -> void:
	if not _wind.playing:
		_wind.play()
	if not _music.playing:
		_music.play()
func stop_music() -> void:
	_music.stop()
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
func _make_wav(samples: PackedFloat32Array, looped: bool = false) -> AudioStreamWAV:
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
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)
func _buf(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(RATE * seconds))
	return out
func _gen_shot() -> PackedFloat32Array:
	var out := _buf(0.22)
	for i in range(out.size()):
		var t := float(i) / RATE
		var crack := _noise() * exp(-t * 38.0)
		var thump := sin(TAU * 85.0 * t) * exp(-t * 16.0) * 0.8
		out[i] = clampf((crack + thump) * 1.4, -1.0, 1.0) * 0.8
	return out
func _gen_shotgun() -> PackedFloat32Array:
	var out := _buf(0.42)
	var lp := 0.0
	for i in range(out.size()):
		var t := float(i) / RATE
		var n := _noise()
		lp += (n - lp) * 0.25
		var boom := lp * 2.2 * exp(-t * 14.0)
		var thump := sin(TAU * (60.0 - 30.0 * t) * t) * exp(-t * 9.0) * 0.9
		out[i] = clampf(boom + thump, -1.0, 1.0) * 0.9
	return out
func _gen_hit() -> PackedFloat32Array:
	var out := _buf(0.16)
	for i in range(out.size()):
		var t := float(i) / RATE
		var thud := sin(TAU * (120.0 - 260.0 * t) * t) * exp(-t * 22.0)
		var crunch := _noise() * 0.35 * exp(-t * 60.0)
		out[i] = (thud + crunch) * 0.8
	return out
func _gen_growl() -> PackedFloat32Array:
	var out := _buf(0.45)
	var phase := 0.0
	for i in range(out.size()):
		var t := float(i) / RATE
		var freq := 68.0 + 18.0 * sin(TAU * 5.5 * t)
		phase += freq / RATE
		var saw := 2.0 * (phase - floorf(phase)) - 1.0
		var env := minf(t * 18.0, 1.0) * exp(-maxf(t - 0.22, 0.0) * 9.0)
		out[i] = (saw * 0.5 + _noise() * 0.18) * env * 0.85
	return out
func _gen_reload() -> PackedFloat32Array:
	var out := _buf(0.3)
	for i in range(out.size()):
		var t := float(i) / RATE
		var a := _noise() * exp(-t * 180.0)
		var t2 := maxf(t - 0.14, 0.0)
		var b := _noise() * exp(-t2 * 160.0) if t >= 0.14 else 0.0
		out[i] = (a + b) * 0.5
	return out
func _gen_hurt() -> PackedFloat32Array:
	var out := _buf(0.2)
	for i in range(out.size()):
		var t := float(i) / RATE
		out[i] = (sin(TAU * 170.0 * t) * exp(-t * 14.0) + _noise() * 0.2 * exp(-t * 40.0)) * 0.7
	return out
func _gen_step() -> PackedFloat32Array:
	var out := _buf(0.09)
	var lp := 0.0
	for i in range(out.size()):
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.35
		out[i] = (lp * 1.6 * exp(-t * 70.0) + sin(TAU * 95.0 * t) * exp(-t * 50.0) * 0.4) * 0.7
	return out
func _gen_slam() -> PackedFloat32Array:
	var out := _buf(0.5)
	var lp := 0.0
	for i in range(out.size()):
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.12
		out[i] = clampf(lp * 3.0 * exp(-t * 7.0) + sin(TAU * (48.0 - 20.0 * t) * t) * exp(-t * 5.0), -1.0, 1.0) * 0.95
	return out
func _gen_dash() -> PackedFloat32Array:
	var out := _buf(0.25)
	var lp := 0.0
	for i in range(out.size()):
		var t := float(i) / RATE
		lp += (_noise() - lp) * (0.08 + 0.5 * t)
		out[i] = lp * 1.8 * sin(minf(t * 12.0, 1.0) * PI * 0.5) * exp(-maxf(t - 0.08, 0.0) * 14.0) * 0.7
	return out
func _gen_pickup() -> PackedFloat32Array:
	var out := _buf(0.3)
	for i in range(out.size()):
		var t := float(i) / RATE
		var f := 660.0 if t < 0.1 else 880.0
		out[i] = sin(TAU * f * t) * exp(-t * 9.0) * 0.45
	return out
func _gen_wind() -> PackedFloat32Array:
	# 4 s seamless loop of low-passed noise with a slow swell.
	var out := _buf(4.0)
	var n := out.size()
	var lp := 0.0
	var lp2 := 0.0
	for i in range(n):
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.04
		lp2 += (lp - lp2) * 0.04
		var swell := 0.55 + 0.45 * sin(TAU * t / 4.0)
		out[i] = lp2 * 6.0 * swell
	return out
func _gen_music() -> PackedFloat32Array:
	# 8 s seamless drone loop: detuned saws on a minor triad through a
	# one-pole low-pass, with a slow filter sweep. Placeholder for a real
	# music track.
	var seconds := 8.0
	var out := _buf(seconds)
	var n := out.size()
	var base := 55.0
	var freqs := [base, base * 1.189207, base * 1.498307, base * 2.0, base * 1.003, base * 1.498307 * 0.997]
	var phases := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var lp := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var s := 0.0
		for k in range(freqs.size()):
			phases[k] += float(freqs[k]) / RATE
			var ph: float = phases[k]
			s += (2.0 * (ph - floorf(ph)) - 1.0) * 0.16
		var cutoff := 0.02 + 0.03 * (0.5 + 0.5 * sin(TAU * t / seconds))
		lp += (s - lp) * cutoff
		out[i] = lp * 0.9
	# Fade the loop seam.
	var fade := int(RATE * 0.05)
	for i in range(fade):
		var g := float(i) / fade
		out[i] *= g
		out[n - 1 - i] *= g
	return out
