class_name Sfx
extends Node
## 효과음을 코드로 합성해서 재생한다 (외부 오디오 파일 없음).
## 사용: sfx.play("jump", 피치, 볼륨dB)

const RATE := 22050

var streams := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 1234 # 매번 같은 소리가 나도록
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	_build_all()


func play(sound: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not streams.has(sound):
		return
	var p := players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = streams[sound]
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.play()


# ───────────── 소리 설계 ─────────────

func _build_all() -> void:
	# 발소리: 짧은 '톡'
	streams["step"] = _wav(_norm(_mix(_noise(0.06, 1800.0, 3.0), _tone(0.05, 220.0, 150.0, 0, 0.002, 3.0), 0.0, 0.7), 0.5))
	# 점프: 위로 올라가는 '뿅'
	streams["jump"] = _wav(_norm(_mix(_tone(0.17, 320.0, 760.0, 1, 0.005, 1.2), _tone(0.17, 640.0, 1520.0, 0, 0.005, 1.5), 0.0, 0.15), 0.55))
	# 착지: 부드러운 '툭'
	streams["land"] = _wav(_norm(_mix(_noise(0.09, 900.0, 2.5), _tone(0.08, 150.0, 70.0, 0, 0.002, 2.0), 0.0, 0.9), 0.5))
	# 그림자 넘기 성공: 맑은 '띵'
	streams["clear"] = _wav(_norm(_bell(1318.5, 0.3, 12.0), 0.42))
	# 아슬아슬: 두 음 반짝이는 차임
	var near := _bell(1046.5, 0.15, 10.0)
	near = _mix(near, _bell(1568.0, 0.5, 6.0), 0.07, 1.0)
	near = _mix(near, _bell(2093.0, 0.4, 8.0), 0.14, 0.5)
	streams["near"] = _wav(_norm(near, 0.6))
	# 콤보 배율 상승: 도-미-솔-도 아르페지오
	streams["combo_up"] = _wav(_norm(_arp([1046.5, 1318.5, 1568.0, 2093.0], 0.06, 0.45), 0.5))
	# 콤보 끝: 내려가는 두 음
	streams["combo_end"] = _wav(_norm(_mix(_tone(0.14, 523.0, 523.0, 1, 0.005, 1.0), _tone(0.22, 392.0, 392.0, 1, 0.005, 1.0), 0.12, 1.0), 0.32))
	# 시작: 상승 차임
	streams["start"] = _wav(_norm(_arp([523.3, 659.3, 784.0, 1046.5], 0.08, 0.5), 0.5))
	# 실패: '삐-요-옹' 내려가는 세 음
	var fail := _tone(0.16, 392.0, 380.0, 1, 0.008, 0.6)
	fail = _mix(fail, _tone(0.16, 330.0, 320.0, 1, 0.008, 0.6), 0.17, 1.0)
	fail = _mix(fail, _vibrato_tone(0.6, 262.0, 200.0), 0.34, 1.0)
	streams["fail"] = _wav(_norm(fail, 0.55))
	# 경적: '빵빵'
	var beep := _mix(_tone(0.15, 415.0, 415.0, 2, 0.01, 0.3), _tone(0.15, 523.0, 523.0, 2, 0.01, 0.3), 0.0, 0.8)
	streams["horn"] = _wav(_norm(_mix(beep, beep, 0.22, 1.0), 0.45))
	# 차가 옆을 지나가는 '쉬익'
	streams["whoosh"] = _wav(_norm(_noise(0.6, 700.0, 2.0, 0.25), 0.5))
	# 그늘에 들어갈 때 나뭇잎 '사락'
	streams["shade"] = _wav(_norm(_noise(0.35, 2600.0, 1.5, 0.08), 0.3))
	# 새소리 (배경 분위기)
	var b1 := PackedFloat32Array()
	for k in 3:
		b1 = _mix(b1, _tone(0.07, 2600.0, 3800.0, 0, 0.005, 1.5), k * 0.1, 1.0)
	streams["bird"] = _wav(_norm(b1, 0.3))
	var b2 := _tone(0.12, 4200.0, 2800.0, 0, 0.005, 1.2)
	b2 = _mix(b2, _tone(0.16, 4000.0, 2600.0, 0, 0.005, 1.2), 0.16, 1.0)
	streams["bird2"] = _wav(_norm(b2, 0.28))


# ───────────── 합성 도구 ─────────────

## wave: 0 사인, 1 삼각파, 2 부드러운 사각파 / f0→f1로 주파수 스윕
func _tone(dur: float, f0: float, f1: float, wave: int = 0, attack: float = 0.005, decay: float = 1.5) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var x := float(i) / n
		ph = fposmod(ph + f0 * pow(f1 / f0, x) / RATE, 1.0)
		var s := 0.0
		match wave:
			0:
				s = sin(TAU * ph)
			1:
				s = 4.0 * absf(ph - 0.5) - 1.0
			_:
				s = clampf(sin(TAU * ph) * 3.0, -1.0, 1.0) * 0.6
		var env := minf(1.0, (float(i) / RATE) / attack) * pow(1.0 - x, decay)
		out[i] = s * env
	return out


func _vibrato_tone(dur: float, f0: float, f1: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var x := float(i) / n
		var t := float(i) / RATE
		var f := lerpf(f0, f1, x) * (1.0 + 0.03 * sin(TAU * 7.0 * t))
		ph = fposmod(ph + f / RATE, 1.0)
		out[i] = (4.0 * absf(ph - 0.5) - 1.0) * minf(1.0, t / 0.01) * pow(1.0 - x, 0.8)
	return out


## 저역 통과 필터를 거친 노이즈
func _noise(dur: float, cutoff: float, decay: float = 2.0, attack: float = 0.002) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in n:
		var x := float(i) / n
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * minf(1.0, (float(i) / RATE) / attack) * pow(1.0 - x, decay)
	return out


## 종소리 (배음 + 지수 감쇠)
func _bell(freq: float, dur: float, k: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := sin(TAU * freq * t) + 0.35 * sin(TAU * 2.0 * freq * t) + 0.12 * sin(TAU * 3.01 * freq * t)
		out[i] = s * exp(-t * k) * minf(1.0, t / 0.003)
	return out


func _arp(freqs: Array, step: float, tail: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in freqs.size():
		var last := i == freqs.size() - 1
		out = _mix(out, _bell(freqs[i], tail if last else 0.2, 7.0 if last else 14.0), i * step, 1.0)
	return out


## base에 add를 offset초 뒤에 gain만큼 섞는다
func _mix(base: PackedFloat32Array, add: PackedFloat32Array, offset: float, gain: float) -> PackedFloat32Array:
	var off := int(offset * RATE)
	var out := PackedFloat32Array(base)
	if out.size() < off + add.size():
		out.resize(off + add.size())
	for i in add.size():
		out[off + i] += add[i] * gain
	return out


func _norm(a: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in a:
		m = maxf(m, absf(v))
	var out := PackedFloat32Array(a)
	for i in out.size():
		out[i] = out[i] / m * peak
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
