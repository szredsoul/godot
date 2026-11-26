class_name Yokai
extends Node2D
## 먹 요괴. 공격 직전에 붉은 낙관(도장)이 번쩍인다.
##  charger  돌진형: 다가오다 낙관 → 직선 돌진 → 헐떡임(때리기 좋음)
##  shooter  먹 탄형: 거리를 두고 맴돌다 낙관 → 먹 탄
##  shield   방패형: 앞을 먹 방패로 막고 천천히 몸을 돌린다. 가까우면 방패로 밀침
##  splitter 분열형: 크고 느리다. 일반 공격으로 쓰러지면 작은 요괴 둘로 갈라진다 (한 획이면 깔끔)
##  imp      작은 요괴: 빠르게 튀어 오른다
##  boss     큰 먹도깨비: 큰 돌진 / 먹 물결 / 부채꼴 먹 탄

signal fire(from: Vector2, dir: Vector2, count: int, spread: float)
signal slam(center: Vector2)

const SPAWN_TIME := 0.7
const TELE := {"charger": 0.58, "shooter": 0.5, "shield": 0.5, "splitter": 0.7, "imp": 0.34, "boss": 0.8}
const DASH_SPEED := {"charger": 950.0, "shield": 700.0, "splitter": 650.0, "imp": 760.0, "boss": 820.0}
const DASH_TIME := {"charger": 0.32, "shield": 0.18, "splitter": 0.38, "imp": 0.2, "boss": 0.5}
const TIRED := {"charger": 0.75, "shield": 0.6, "splitter": 1.0, "imp": 0.4, "boss": 1.1}
const MOVE_SPEED := {"charger": 105.0, "shooter": 95.0, "shield": 80.0, "splitter": 65.0, "imp": 150.0, "boss": 60.0}
const TELE_RANGE := {"charger": 320.0, "shield": 140.0, "splitter": 300.0, "imp": 220.0}
const SHIELD_TURN := 2.4 # 방패가 도는 속도 (라디안/초) → 빠르게 돌아 들어가면 뒤를 잡을 수 있다

var kind := "charger"
var hp := 3
var max_hp := 3
var radius := 22.0
var state := "spawn"
var t := 0.0
var cd := 1.0
var attack := "dash" # 이번 낙관 뒤에 나올 공격
var dash_dir := Vector2.ZERO
var facing := Vector2.DOWN # 방패가 향하는 쪽
var has_shield := false
var shield_break_t := 0.0
var boss_turn := 0
var ring_pending := 0.0
var slow_t := 0.0
var vel := Vector2.ZERO
var phase := 0.0
var flash := 0.0
var shots := 1
var dying := false
var split := false
var split_dir := Vector2.RIGHT
var split_t := 0.0


func setup(k: String, pos: Vector2, wave: int) -> void:
	kind = k
	position = pos
	phase = randf() * TAU
	match kind:
		"shooter":
			hp = 2
			radius = 20.0
			shots = 1 if wave < 4 else 3
			cd = randf_range(1.2, 2.0)
		"shield":
			hp = 3
			radius = 24.0
			has_shield = true
			cd = randf_range(0.8, 1.4)
		"splitter":
			hp = 4
			radius = 32.0
			cd = randf_range(0.8, 1.4)
		"imp":
			hp = 1
			radius = 13.0
			cd = randf_range(0.2, 0.6)
		"boss":
			hp = 60
			radius = 50.0
			cd = 1.6
		_:
			hp = 3
			radius = 23.0
			cd = randf_range(0.4, 1.0)
	max_hp = hp


## 보스: 체력이 절반 아래면 성난다 (공격이 빨라지고 세진다)
func is_angry() -> bool:
	return kind == "boss" and hp <= max_hp / 2


func tele_time() -> float:
	return TELE.get(kind, 0.5) + (0.1 if kind == "boss" and attack == "ring" else 0.0)


func dash_speed() -> float:
	return DASH_SPEED.get(kind, 900.0)


func is_solid() -> bool:
	return state != "spawn" and not dying


func is_dash_attacking() -> bool:
	return state == "dash"


func is_telegraphing() -> bool:
	return state == "tele"


## 공격자가 앞(방패 쪽)에 있는지. from_dir = 공격자 → 요괴 방향
func is_front(from_dir: Vector2) -> bool:
	return has_shield and facing.dot(-from_dir.normalized()) > 0.35


func step(dt: float, hero: Vector2) -> void:
	phase += dt * 3.0
	flash = maxf(0.0, flash - dt)
	shield_break_t = maxf(0.0, shield_break_t - dt)
	if split:
		split_t += dt
		queue_redraw()
		return
	# 번짐 먹물에 발이 묶이면 모든 동작이 절반 속도
	slow_t = maxf(0.0, slow_t - dt)
	if slow_t > 0.0:
		dt *= 0.5
	position += vel * dt
	vel *= pow(0.004, dt)
	t += dt
	if ring_pending > 0.0:
		ring_pending -= dt
		if ring_pending <= 0.0:
			slam.emit(position)
	var to := hero - position
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector2.DOWN
	if has_shield and state != "dash":
		# 방패는 아이 쪽으로 천천히 돈다
		var a := facing.angle()
		var target := dir.angle()
		facing = Vector2.from_angle(a + clampf(angle_difference(a, target), -SHIELD_TURN * dt, SHIELD_TURN * dt))
	match state:
		"spawn":
			if t >= SPAWN_TIME:
				state = "move"
				t = 0.0
		"move":
			cd -= dt
			_move(dt, dir, dist)
		"tele":
			if t < tele_time() * 0.72:
				dash_dir = facing if kind == "shield" else dir
			if t >= tele_time():
				t = 0.0
				_release(hero)
		"dash":
			position += dash_dir * dash_speed() * dt
			if t >= DASH_TIME.get(kind, 0.3) or not Ink.ARENA.grow(-10).has_point(position):
				state = "tired"
				t = 0.0
		"tired":
			if t >= TIRED.get(kind, 0.7):
				state = "move"
				t = 0.0
				cd = randf_range(0.8, 1.6) if kind != "boss" else (0.75 if is_angry() else 1.3)
	position.x = clampf(position.x, Ink.ARENA.position.x + radius, Ink.ARENA.end.x - radius)
	position.y = clampf(position.y, Ink.ARENA.position.y + radius, Ink.ARENA.end.y - radius)
	queue_redraw()


func _move(dt: float, dir: Vector2, dist: float) -> void:
	var sp: float = MOVE_SPEED.get(kind, 100.0)
	match kind:
		"shooter":
			var want := dir * (1.0 if dist > 420.0 else (-1.0 if dist < 340.0 else 0.0))
			position += (want + dir.orthogonal() * 0.6) * sp * dt
			if cd <= 0.0:
				_tele("shot")
		"boss":
			if dist > 240.0:
				position += dir * sp * dt
			if cd <= 0.0:
				# 돌진 → 먹 물결 → 부채꼴 먹 탄 순서로 돌아가며
				var pattern: Array[String] = ["dash", "ring", "fan"]
				_tele(pattern[boss_turn % 3])
				boss_turn += 1
		_:
			position += dir * sp * dt
			if dist < TELE_RANGE.get(kind, 300.0) and cd <= 0.0:
				_tele("dash")


func _tele(what: String) -> void:
	state = "tele"
	t = 0.0
	attack = what


func _release(hero: Vector2) -> void:
	match attack:
		"dash":
			state = "dash"
		"shot":
			fire.emit(position + Vector2(0, -20), (hero - position).normalized(), shots, 0.28)
			state = "move"
			cd = randf_range(1.8, 2.6)
		"fan":
			var n := 11 if is_angry() else 7
			fire.emit(position + Vector2(0, -radius), (hero - position).normalized(), n, 0.17 if is_angry() else 0.22)
			state = "tired"
		"ring":
			slam.emit(position)
			if is_angry():
				ring_pending = 0.6 # 성나면 먹 물결이 두 겹
			state = "tired"


## 맞았을 때: "blocked"(방패에 막힘) / "guard_break"(방패 깨짐) / "hit" / "kill"
func take_hit(dmg: int, from_dir: Vector2, knock: float, heavy: bool) -> String:
	if is_front(from_dir):
		if heavy:
			has_shield = false
			shield_break_t = 0.5
			state = "tired"
			t = -0.4 # 평소보다 오래 비틀거린다
			flash = 0.1
			vel = from_dir.normalized() * knock * 0.6
			return "guard_break"
		vel = from_dir.normalized() * knock * 0.25
		return "blocked"
	hp -= dmg
	flash = 0.09
	vel = from_dir.normalized() * knock * (0.25 if kind == "boss" else 1.0)
	if state == "tele" and dmg >= 2 and kind != "boss":
		state = "tired"
		t = 0.0
	return "kill" if hp <= 0 else "hit"


func _draw() -> void:
	if split:
		_draw_split()
		return
	var r := radius
	if state == "spawn":
		var k := clampf(t / SPAWN_TIME, 0.0, 1.0)
		draw_colored_polygon(Ink.blob(Vector2.ZERO, r * 1.6 * k, phase, 0.2), Color(Ink.INK, 0.25 * k))
		draw_colored_polygon(Ink.blob(Vector2(0, -r * k), r * k, phase), Color(Ink.INK, k))
		return
	draw_colored_polygon(Ink.ellipse(Vector2.ZERO, r * 1.1, r * 0.4), Color(Ink.INK, 0.2))
	var squash := Vector2.ONE
	if state == "dash":
		squash = Vector2(1.35, 0.8)
	elif state == "tired":
		squash = Vector2(1.15, 0.8 + 0.08 * sin(t * 18.0))
	elif state == "tele":
		squash = Vector2(0.88, 1.15) if kind != "boss" else Vector2(1.0 + 0.1 * t, 1.0 + 0.15 * t)
	if kind == "imp" and state == "dash":
		squash = Vector2(1.0, 1.0)
	var hop := -18.0 * sin(t / DASH_TIME["imp"] * PI) if kind == "imp" and state == "dash" else 0.0
	var body_c := Vector2(0, -r + hop)
	var ang := dash_dir.angle() if state == "dash" and kind != "imp" else 0.0
	draw_set_transform(body_c, ang, squash)
	var col := Ink.ROBE if flash > 0.0 else Ink.INK
	draw_colored_polygon(Ink.blob(Vector2.ZERO, r, phase, 0.14 if kind in ["charger", "imp", "boss"] else 0.08), col)
	match kind:
		"charger", "imp", "boss":
			var hr := r * (1.5 if kind != "boss" else 1.7)
			draw_colored_polygon(PackedVector2Array([Vector2(-r * 0.5, -r * 0.7), Vector2(-r * 0.18, -r * 0.8), Vector2(-r * 0.6, -hr)]), col)
			draw_colored_polygon(PackedVector2Array([Vector2(r * 0.5, -r * 0.7), Vector2(r * 0.18, -r * 0.8), Vector2(r * 0.6, -hr)]), col)
			if kind == "boss":
				# 붉은 무늬와 이빨 난 입 (성나면 무늬가 굵어지고 뿔끝이 붉어진다)
				draw_arc(Vector2.ZERO, r * 0.7, PI * 0.15, PI * 0.85, 12, Ink.SEAL, 9.0 if is_angry() else 5.0, true)
				if is_angry():
					draw_circle(Vector2(-r * 0.6, -hr * 0.95), 5, Ink.SEAL, true, -1.0, true)
					draw_circle(Vector2(r * 0.6, -hr * 0.95), 5, Ink.SEAL, true, -1.0, true)
				for i in 5:
					var x := -r * 0.4 + i * r * 0.2
					draw_colored_polygon(PackedVector2Array([Vector2(x - 5, r * 0.3), Vector2(x + 5, r * 0.3), Vector2(x, r * 0.48)]), Color("f5efe0"))
		"shooter":
			draw_colored_polygon(Ink.ellipse(Vector2(0, 6), 7, 4 + (3.0 if state == "tele" else 0.0)), Ink.SEAL)
		"splitter":
			# 가운데 금 (갈라질 자리)
			draw_line(Vector2(0, -r * 0.9), Vector2(0, r * 0.9), Color(Ink.ROBE, 0.5), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 눈
	var eye := Color("f5efe0") if flash <= 0.0 else Ink.INK
	var look := dash_dir * 2.0
	var ex_list: Array = [-7.0, 7.0]
	if kind == "splitter":
		ex_list = [-15.0, -6.0, 6.0, 15.0]
	elif kind == "boss":
		ex_list = [-16.0, 16.0]
	var er := 4.5 * (r / 23.0 if kind != "imp" else 0.7)
	for ex in ex_list:
		draw_circle(body_c + Vector2(ex * r / 23.0 if kind == "boss" else ex, -4) + look, er if state != "tired" else er * 0.45, eye, true, -1.0, true)
	# 방패
	if has_shield:
		var fa := facing.angle()
		var sc := body_c + facing * 4.0
		var pts := Ink.arc_points(sc, r + 10.0, fa - 1.05, fa + 1.05, 14)
		Ink.draw_brush(self, pts, 11.0, Ink.INK, false)
		for k in 3:
			draw_circle(sc + Vector2.from_angle(fa - 0.6 + k * 0.6) * (r + 10.0), 3.0, Ink.SEAL, true, -1.0, true)
	elif shield_break_t > 0.0:
		for k in 4:
			var a := facing.angle() - 0.9 + k * 0.6
			var p := body_c + Vector2.from_angle(a) * (r + 10.0 + (0.5 - shield_break_t) * 120.0)
			draw_colored_polygon(Ink.blob(p, 5.0, k, 0.3, 6), Color(Ink.INK, shield_break_t * 2.0))
	# 붉은 낙관: 곧 공격한다는 신호
	if state == "tele":
		var k := t / tele_time()
		var s := (10.0 if kind != "boss" else 18.0) + 6.0 * sin(k * PI * 6.0) * (1.0 - k) + k * 4.0
		var c := body_c + Vector2(0, -r - 22 - (20.0 if kind == "boss" else 0.0))
		draw_set_transform(c, 0.08, Vector2.ONE)
		draw_rect(Rect2(-s, -s, s * 2, s * 2), Ink.SEAL)
		draw_rect(Rect2(-s * 0.62, -s * 0.62, s * 1.24, s * 1.24), Color("f5efe0"), false, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if attack == "dash" and t >= tele_time() * 0.72:
			var reach: float = dash_speed() * float(DASH_TIME.get(kind, 0.3))
			draw_line(body_c, body_c + dash_dir * reach, Color(Ink.SEAL, 0.25), r * 1.4, true)
		elif attack == "ring":
			draw_arc(Vector2.ZERO, r * (1.2 + k * 1.5), 0, TAU, 40, Color(Ink.SEAL, 0.5 * k), 4.0, true)


func _draw_split() -> void:
	var a := clampf(1.0 - split_t / 0.45, 0.0, 1.0)
	var off := split_dir.orthogonal() * (6.0 + split_t * 120.0)
	var body := Ink.blob(Vector2(0, -radius), radius, phase, 0.12)
	var line_a := Vector2(0, -radius) - split_dir * radius * 2.0
	var line_b := Vector2(0, -radius) + split_dir * radius * 2.0
	var nrm := split_dir.orthogonal()
	var half1 := PackedVector2Array([line_a, line_b, line_b + nrm * radius * 3, line_a + nrm * radius * 3])
	var half2 := PackedVector2Array([line_a, line_b, line_b - nrm * radius * 3, line_a - nrm * radius * 3])
	for p in Geometry2D.intersect_polygons(body, half1):
		if p.size() >= 3:
			draw_set_transform(off, 0.0, Vector2.ONE)
			draw_colored_polygon(p, Color(Ink.INK, a))
	for p in Geometry2D.intersect_polygons(body, half2):
		if p.size() >= 3:
			draw_set_transform(-off, 0.0, Vector2.ONE)
			draw_colored_polygon(p, Color(Ink.INK, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if split_t < 0.12:
		draw_line(line_a, line_b, Color(1, 1, 1, 1.0 - split_t / 0.12), 4.0, true)
