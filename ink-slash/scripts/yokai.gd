class_name Yokai
extends Node2D
## 먹 요괴. 공격 직전에 붉은 낙관(도장)이 번쩍인다.
##  charger: 다가오다 낙관 → 직선 돌진 → 지쳐서 헐떡임(이때 때리기 좋음)
##  shooter: 거리를 두고 맴돌다 낙관 → 먹 탄 발사

signal fire(from: Vector2, dir: Vector2, count: int)

const SPAWN_TIME := 0.7

var kind := "charger"
var hp := 3
var radius := 22.0
var state := "spawn"
var t := 0.0
var cd := 1.0
var dash_dir := Vector2.ZERO
var vel := Vector2.ZERO # 맞아서 밀려나는 속도
var phase := 0.0
var flash := 0.0
var shots := 1
var dying := false
# 한 획에 베였을 때 반으로 갈라지는 연출
var split := false
var split_dir := Vector2.RIGHT
var split_t := 0.0


func setup(k: String, pos: Vector2, wave: int) -> void:
	kind = k
	position = pos
	phase = randf() * TAU
	if kind == "shooter":
		hp = 2
		radius = 20.0
		shots = 1 if wave < 4 else 3
		cd = randf_range(1.2, 2.0)
	else:
		hp = 3
		radius = 23.0
		cd = randf_range(0.4, 1.0)


func is_solid() -> bool:
	return state != "spawn" and not dying


func is_dash_attacking() -> bool:
	return state == "dash"


## 공격 신호 중인지 (낙관)
func is_telegraphing() -> bool:
	return state == "tele"


func step(dt: float, hero: Vector2) -> void:
	phase += dt * 3.0
	flash = maxf(0.0, flash - dt)
	if split:
		split_t += dt
		queue_redraw()
		return
	position += vel * dt
	vel *= pow(0.004, dt) # 밀려남은 금방 멈춘다
	t += dt
	var to := hero - position
	var dist := to.length()
	match state:
		"spawn":
			if t >= SPAWN_TIME:
				state = "move"
				t = 0.0
		"move":
			cd -= dt
			if kind == "charger":
				position += to.normalized() * 105.0 * dt
				if dist < 320.0 and cd <= 0.0:
					state = "tele"
					t = 0.0
					dash_dir = to.normalized()
			else:
				# 거리를 340~420으로 두고 옆으로 돈다
				var want := to.normalized() * (1.0 if dist > 420.0 else (-1.0 if dist < 340.0 else 0.0))
				position += (want + to.normalized().orthogonal() * 0.6) * 95.0 * dt
				if cd <= 0.0:
					state = "tele"
					t = 0.0
		"tele":
			# 앞쪽 75% 동안은 방향을 따라오고, 마지막엔 고정 (피할 틈)
			if t < 0.42:
				dash_dir = to.normalized()
			if t >= (0.58 if kind == "charger" else 0.5):
				t = 0.0
				if kind == "charger":
					state = "dash"
				else:
					fire.emit(position + Vector2(0, -20), (hero - position).normalized(), shots)
					state = "move"
					cd = randf_range(1.8, 2.6)
		"dash":
			position += dash_dir * 950.0 * dt
			if t >= 0.32 or not Ink.ARENA.grow(-10).has_point(position):
				state = "tired"
				t = 0.0
		"tired":
			if t >= 0.75:
				state = "move"
				t = 0.0
				cd = randf_range(0.8, 1.6)
	position.x = clampf(position.x, Ink.ARENA.position.x + radius, Ink.ARENA.end.x - radius)
	position.y = clampf(position.y, Ink.ARENA.position.y + radius, Ink.ARENA.end.y - radius)
	queue_redraw()


func hurt(dmg: int, from_dir: Vector2, knock: float) -> bool:
	hp -= dmg
	flash = 0.09
	vel = from_dir.normalized() * knock
	if state == "tele" and dmg >= 2:
		state = "tired" # 세게 맞으면 공격이 끊긴다
		t = 0.0
	return hp <= 0


func _draw() -> void:
	if split:
		_draw_split()
		return
	var r := radius
	if state == "spawn":
		# 먹이 번지며 나타난다
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
		squash = Vector2(0.88, 1.15)
	var body_c := Vector2(0, -r)
	var ang := dash_dir.angle() if state == "dash" else 0.0
	draw_set_transform(body_c, ang, squash)
	var col := Ink.ROBE if flash > 0.0 else Ink.INK
	draw_colored_polygon(Ink.blob(Vector2.ZERO, r, phase, 0.14 if kind == "charger" else 0.08), col)
	if kind == "charger":
		# 뿔
		draw_colored_polygon(PackedVector2Array([Vector2(-12, -r * 0.7), Vector2(-4, -r * 0.8), Vector2(-14, -r * 1.5)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(12, -r * 0.7), Vector2(4, -r * 0.8), Vector2(14, -r * 1.5)]), col)
	else:
		# 길쭉한 입
		draw_colored_polygon(Ink.ellipse(Vector2(0, 6), 7, 4 + (3.0 if state == "tele" else 0.0)), Ink.SEAL)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 눈
	var eye := Color("f5efe0") if flash <= 0.0 else Ink.INK
	var look := dash_dir * 2.0
	for ex in [-7.0, 7.0]:
		draw_circle(body_c + Vector2(ex, -4) + look, 4.5 if state != "tired" else 2.0, eye, true, -1.0, true)
	# 붉은 낙관: 곧 공격한다는 신호
	if state == "tele":
		var limit := 0.58 if kind == "charger" else 0.5
		var k := t / limit
		var s := 10.0 + 6.0 * sin(k * PI * 6.0) * (1.0 - k) + k * 4.0
		var c := body_c + Vector2(0, -r - 22)
		draw_set_transform(c, 0.08, Vector2.ONE)
		draw_rect(Rect2(-s, -s, s * 2, s * 2), Ink.SEAL)
		draw_rect(Rect2(-s * 0.62, -s * 0.62, s * 1.24, s * 1.24), Color("f5efe0"), false, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if kind == "charger" and t >= 0.42:
			# 돌진할 길을 먹 자국으로 미리 보여 준다
			draw_line(body_c, body_c + dash_dir * 300.0, Color(Ink.SEAL, 0.25), r * 1.4, true)


func _draw_split() -> void:
	# 반으로 갈라져 양쪽으로 밀려나며 사라진다
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
	# 베인 자리에 하얀 섬광
	if split_t < 0.12:
		draw_line(line_a, line_b, Color(1, 1, 1, 1.0 - split_t / 0.12), 4.0, true)
