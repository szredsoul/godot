class_name Sfx
extends Node
## 효과음을 코드로 합성해서 재생한다 (외부 오디오 파일 없음).
## 사용: sfx.play("jump", 피치, 볼륨dB)

const RATE := 22050

var streams := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var rng := RandomNumberGenerator.new()
var loop_player: AudioStreamPlayer

static var _cache := {} # 한 번 합성한 소리는 씬이 바뀌어도 재사용


func _ready() -> void:
	rng.seed = 1234 # 매번 같은 소리가 나도록
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	loop_player = AudioStreamPlayer.new()
	add_child(loop_player)
	if _cache.is_empty():
		_build_all()
		_cache = streams
	streams = _cache


## 배경 반복음 (여름 매미 등)
func play_loop(sound: String, vol_db: float) -> void:
	if not streams.has(sound):
		return
	loop_player.stream = streams[sound]
	loop_player.volume_db = vol_db
	loop_player.play()


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

	# 그림자 밟음 (하트 감소): '아야' 내려가는 두 음
	var hit := _mix(_tone(0.12, 660.0, 600.0, 1, 0.004, 0.8), _tone(0.25, 440.0, 330.0, 1, 0.004, 1.0), 0.1, 1.0)
	streams["hit"] = _wav(_norm(_mix(hit, _noise(0.08, 2000.0, 3.0), 0.0, 0.3), 0.55))
	# 동전: '띠링'
	streams["coin"] = _wav(_norm(_mix(_bell(1976.0, 0.12, 18.0), _bell(2637.0, 0.35, 10.0), 0.06, 1.0), 0.4))
	# 구슬: 유리 '딸깍' + 맑은 음
	var marble := _mix(_noise(0.03, 6000.0, 4.0), _bell(2349.0, 0.5, 7.0), 0.01, 0.8)
	marble = _mix(marble, _bell(3136.0, 0.4, 9.0), 0.08, 0.5)
	streams["marble"] = _wav(_norm(marble, 0.5))
	# 강아지: '멍멍'
	var bark := PackedFloat32Array()
	for k in 2:
		var woof := _mix(_tone(0.12, 520.0, 300.0, 2, 0.004, 1.2), _noise(0.1, 1400.0, 2.0), 0.0, 0.5)
		bark = _mix(bark, woof, k * 0.2, 1.0)
	streams["bark"] = _wav(_norm(bark, 0.5))
	# 행인과 부딪힘: '퉁'
	streams["bump"] = _wav(_norm(_mix(_tone(0.15, 200.0, 110.0, 0, 0.002, 2.0), _noise(0.06, 1200.0, 3.0), 0.0, 0.6), 0.5))
	# 보행 신호 초록불: '띠띠띠' (높은 삐삐음)
	var sig := PackedFloat32Array()
	for k in 3:
		sig = _mix(sig, _tone(0.07, 1760.0, 1760.0, 0, 0.003, 0.6), k * 0.14, 1.0)
	streams["signal"] = _wav(_norm(sig, 0.3))
	# 버스 문: '푸쉬'
	streams["door"] = _wav(_norm(_noise(0.5, 3500.0, 1.2, 0.03), 0.35))
	# 배달 오토바이: '부웅' (거친 소리가 지나감)
	var moto := _tone(0.7, 90.0, 140.0, 2, 0.08, 1.0)
	moto = _mix(moto, _noise(0.7, 900.0, 1.0, 0.1), 0.0, 0.6)
	streams["moto"] = _wav(_norm(moto, 0.45))
	# 집 도착: 팡파르
	var fan := _arp([523.3, 659.3, 784.0, 1046.5], 0.11, 0.3)
	fan = _mix(fan, _bell(1318.5, 0.9, 4.0), 0.5, 1.0)
	fan = _mix(fan, _bell(1568.0, 0.9, 4.0), 0.5, 0.7)
	streams["fanfare"] = _wav(_norm(fan, 0.55))
	# 6시가 지남: 낮은 '땡땡'
	streams["late"] = _wav(_norm(_mix(_bell(392.0, 0.5, 5.0), _bell(330.0, 0.8, 4.0), 0.35, 1.0), 0.45))
	# 메뉴 선택 / 구매
	streams["select"] = _wav(_norm(_bell(1568.0, 0.12, 25.0), 0.3))
	streams["buy"] = _wav(_norm(_arp([1046.5, 1568.0, 2093.0], 0.05, 0.3), 0.45))
	# 여름 매미 (반복)
	streams["cicada"] = _cicada()
	# 상상 연출: 풍덩(바다·늪·얼음) / 치익(용암) / 부글(거품)
	var splash := _mix(_noise(0.45, 1800.0, 1.6, 0.005), _tone(0.2, 300.0, 120.0, 0, 0.003, 1.5), 0.0, 0.7)
	streams["splash"] = _wav(_norm(splash, 0.55))
	streams["sizzle"] = _wav(_norm(_noise(0.5, 7000.0, 1.3, 0.01), 0.4))
	var bub := PackedFloat32Array()
	for k in 3:
		bub = _mix(bub, _tone(0.06, 220.0 + k * 90.0, 520.0 + k * 120.0, 0, 0.003, 2.0), k * 0.09, 1.0)
	streams["bubble"] = _wav(_norm(bub, 0.35))


## 매미 소리: 높은 노이즈를 빠르게 떨리게 하고 천천히 커졌다 작아진다 (2초 반복)
func _cicada() -> AudioStreamWAV:
	var dur := 2.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := 1.0 - exp(-TAU * 5000.0 / RATE)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		var pulse := 0.5 + 0.5 * sin(TAU * 32.0 * t)
		var swell := 0.6 + 0.4 * sin(TAU * t / dur)
		out[i] = y * pulse * swell
	var s := _wav(_norm(out, 0.35))
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s


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
