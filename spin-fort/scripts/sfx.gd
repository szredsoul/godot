class_name Sfx
extends Node
## 효과음을 코드로 합성해서 재생한다 (외부 오디오 파일 없음). 타격감 위주로 설계.

const RATE := 22050

static var _cache := {}

var streams := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 4321
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	if _cache.is_empty():
		_build_all()
		_cache = streams
	streams = _cache


func play(sound: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not streams.has(sound):
		return
	var p := players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = streams[sound]
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.play()


func _build_all() -> void:
	# 붓 휘두르기: 짧고 높은 '쉭'
	streams["swing"] = _wav(_norm(_noise(0.13, 5200.0, 1.6, 0.02), 0.45))
	# 타격: 낮은 '퍽' + 날카로운 '탁'
	var hit := _mix(_tone(0.12, 170.0, 70.0, 0, 0.001, 2.2), _noise(0.05, 4000.0, 3.0), 0.0, 0.8)
	streams["hit"] = _wav(_norm(hit, 0.75))
	# 셋째 타격: 더 묵직하게
	var heavy := _mix(_tone(0.22, 140.0, 45.0, 0, 0.001, 1.6), _noise(0.09, 3000.0, 2.2), 0.0, 1.0)
	heavy = _mix(heavy, _tone(0.05, 900.0, 300.0, 2, 0.001, 2.0), 0.0, 0.3)
	streams["heavy"] = _wav(_norm(heavy, 0.85))
	# 회피: 부드러운 바람
	streams["dash"] = _wav(_norm(_noise(0.2, 1800.0, 1.4, 0.03), 0.35))
	# 저스트 회피: 높은 '징' + 아래로 깔리는 울림
	var just := _bell(1760.0, 0.9, 4.0)
	just = _mix(just, _bell(2637.0, 0.7, 5.0), 0.0, 0.5)
	just = _mix(just, _tone(1.2, 110.0, 80.0, 0, 0.01, 1.2), 0.0, 0.6)
	streams["just"] = _wav(_norm(just, 0.8))
	# 한 획 베기: 길게 찢는 '샥!' + 묵직한 끝
	var cut := _noise(0.32, 7000.0, 1.0, 0.005)
	cut = _mix(cut, _tone(0.35, 300.0, 1400.0, 2, 0.005, 1.2), 0.0, 0.25)
	cut = _mix(cut, _tone(0.4, 90.0, 40.0, 0, 0.002, 1.4), 0.18, 1.0)
	streams["cut"] = _wav(_norm(cut, 0.9))
	# 갈라짐: 젖은 '촤악'
	var split := _mix(_noise(0.3, 1400.0, 1.6, 0.003), _tone(0.2, 200.0, 60.0, 0, 0.002, 2.0), 0.0, 0.6)
	streams["split"] = _wav(_norm(split, 0.7))
	# 요괴 쓰러짐
	streams["die"] = _wav(_norm(_mix(_noise(0.25, 900.0, 1.8, 0.003), _tone(0.25, 260.0, 90.0, 1, 0.003, 1.5), 0.0, 0.6), 0.6))
	# 공격 신호 (낙관): 짧은 '칭'
	streams["warn"] = _wav(_norm(_mix(_bell(1318.0, 0.18, 14.0), _bell(1975.0, 0.15, 16.0), 0.04, 0.6), 0.35))
	# 먹 탄 발사
	streams["shoot"] = _wav(_norm(_tone(0.12, 600.0, 220.0, 1, 0.002, 1.5), 0.4))
	# 주인공이 맞음
	var hurt := _mix(_tone(0.3, 240.0, 90.0, 1, 0.002, 1.2), _noise(0.12, 1800.0, 2.0), 0.0, 0.6)
	streams["hurt"] = _wav(_norm(hurt, 0.75))
	# 막 시작: 징 (낮은 금속 울림)
	var gong := _bell(146.8, 2.2, 1.4)
	gong = _mix(gong, _bell(220.0, 1.8, 1.8), 0.0, 0.4)
	streams["gong"] = _wav(_norm(gong, 0.7))
	# 등급 상승
	streams["rank"] = _wav(_norm(_arp([784.0, 1046.5, 1568.0], 0.06, 0.45), 0.45))
	# 끝
	var over := _mix(_bell(196.0, 1.6, 2.0), _bell(146.8, 2.0, 1.6), 0.35, 1.0)
	streams["over"] = _wav(_norm(over, 0.6))
	# 한 획을 긋는 동안 붓 끌리는 소리
	streams["brush"] = _wav(_norm(_noise(0.08, 2400.0, 1.0, 0.02), 0.22))
	# 타워 놓기: 통통 튀는 '뽁'
	var place_snd := _mix(_tone(0.09, 260.0, 620.0, 0, 0.002, 1.6), _tone(0.12, 180.0, 90.0, 0, 0.002, 2.0), 0.06, 0.7)
	streams["place"] = _wav(_norm(place_snd, 0.55))
	# 엽전: '짤랑'
	streams["coin"] = _wav(_norm(_mix(_bell(2349.0, 0.15, 16.0), _bell(3136.0, 0.3, 10.0), 0.05, 0.8), 0.35))
	# 상생이 생김: 맑은 두 음
	streams["link"] = _wav(_norm(_mix(_bell(1046.5, 0.25, 9.0), _bell(1568.0, 0.4, 7.0), 0.07, 0.8), 0.4))
	# 상극이 생김: 낮고 흐린 '뚱'
	streams["clash"] = _wav(_norm(_mix(_tone(0.25, 220.0, 150.0, 1, 0.004, 1.4), _tone(0.25, 233.0, 160.0, 1, 0.004, 1.4), 0.0, 0.7), 0.4))
	# 오행 순환 완성: 다섯 음 아르페지오 + 긴 울림
	var cyc := _arp([523.3, 659.3, 784.0, 1046.5, 1318.5], 0.07, 0.9)
	streams["cycle"] = _wav(_norm(_mix(cyc, _bell(2093.0, 1.2, 3.0), 0.35, 0.5), 0.6))
	# 웨이브 시작 북소리
	streams["drum"] = _wav(_norm(_mix(_tone(0.35, 110.0, 55.0, 0, 0.002, 1.6), _noise(0.08, 800.0, 3.0), 0.0, 0.5), 0.75))
	# 목숨 잃음
	streams["leak"] = _wav(_norm(_mix(_tone(0.3, 440.0, 220.0, 1, 0.004, 1.2), _noise(0.1, 1500.0, 2.5), 0.0, 0.3), 0.5))
	# 방패에 막힘: 단단한 '팅'
	streams["block"] = _wav(_norm(_mix(_bell(2200.0, 0.25, 18.0), _noise(0.03, 6000.0, 3.0), 0.0, 0.6), 0.5))
	# 방패 깨짐: '쩍'
	var brk := _mix(_noise(0.18, 3500.0, 2.0, 0.001), _tone(0.15, 500.0, 120.0, 2, 0.001, 2.0), 0.0, 0.5)
	streams["break"] = _wav(_norm(_mix(brk, _bell(1400.0, 0.3, 12.0), 0.0, 0.3), 0.75))
	# 먹 물결: 땅을 내리치는 '쿵' + 울림
	var slam := _mix(_tone(0.6, 80.0, 35.0, 0, 0.002, 1.1), _noise(0.4, 600.0, 1.5, 0.003), 0.0, 0.8)
	streams["slam"] = _wav(_norm(slam, 0.9))
	# 보스 등장: 낮은 으르렁
	var roar := _tone(1.1, 70.0, 55.0, 2, 0.08, 0.9)
	roar = _mix(roar, _tone(1.1, 105.0, 80.0, 2, 0.08, 0.9), 0.0, 0.6)
	roar = _mix(roar, _noise(1.0, 500.0, 1.2, 0.1), 0.0, 0.5)
	streams["roar"] = _wav(_norm(roar, 0.75))
	# 분열: '뽁뽁'
	var pop := _mix(_tone(0.08, 300.0, 900.0, 0, 0.002, 2.0), _tone(0.08, 400.0, 1100.0, 0, 0.002, 2.0), 0.09, 1.0)
	streams["pop"] = _wav(_norm(pop, 0.5))


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
		out[i] = s * minf(1.0, (float(i) / RATE) / attack) * pow(1.0 - x, decay)
	return out


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
