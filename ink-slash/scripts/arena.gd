extends Node2D
## 먹 한 획 (시험판)
## 공격이 닿기 직전에 피하면(저스트) 시간이 멈춘다. 멈춘 동안 마우스로 한 획을 그으면
## 그 선을 따라 번개처럼 지나가며 선 위의 요괴를 한 번에 벤다.

enum Mode { FIGHT, JUST, STROKE, CUT, OVER }

const JUST_WINDOW := 0.22 # 공격이 닿기까지 이 시간(초) 안에 피하면 저스트
const STROKE_TIME := 1.8 # 멈춘 시간 동안 한 획을 그을 수 있는 시간 (실제 초)
const STROKE_BASE := 420.0 # 한 획 기본 길이
const STROKE_PER_INK := 6.0 # 먹 1당 늘어나는 길이 (먹 100 → +600)
const CUT_TIME := 0.16 # 한 획을 따라 지나가는 시간
const CUT_RADIUS := 20.0
const WORLD_SLOW := 0.03
const BULLET_SPEED := 390.0
const BULLET_R := 9.0
const RANK_STYLE: Array[float] = [0.0, 25.0, 70.0, 130.0]
const RANK_NAME: Array[String] = ["", "멋", "신", "절"]
const RANK_MULT: Array[float] = [1.0, 1.5, 2.0, 3.0]
const SAVE_PATH := "user://best.cfg"

var mode := Mode.FIGHT
var paused := false
var hero: Hero
var enemies: Array[Yokai] = []
var bullets: Array[Dictionary] = []
var fx: Fx
var stains: Fx.Stains
var sfx: Sfx
var camera: Camera2D
var tint: CanvasModulate
var world_draw: Node2D

var hitstop := 0.0
var shake := 0.0
var flash := 0.0
var flash_col := Color.WHITE
var slow_amt := 0.0 # 화면이 먹색으로 가라앉는 정도
var just_t := 0.0
var stroke_t := 0.0
var stroke_pts := PackedVector2Array()
var stroke_max := 420.0
var drawing := false
var cut_t := 0.0
var cut_path := PackedVector2Array()
var cut_len := 0.0
var cut_targets: Array[Yokai] = []
var brush_snd := 0.0

var ink := 30.0 # 0~100. 때리거나 저스트하면 찬다. 한 획 길이가 늘어난다
var style := 0.0
var rank := 0
var combo_i := -1
var combo_t := 0.0
var attack_cd := 0.0
var score := 0
var wave := 0
var wave_t := 1.0
var spawn_queue: Array[String] = []
var spawn_t := 0.0
var kills := 0
var best_cut := 0
var best_score := 0

# UI
var hp_draw: Control
var ink_fill: ColorRect
var score_label: Label
var wave_label: Label
var rank_label: Label
var rank_box: Panel
var stroke_label: Label
var stroke_bar: ColorRect
var stroke_bar_bg: ColorRect
var help_label: Label
var flash_rect: ColorRect
var dim_rect: ColorRect
var overlay: CenterContainer


func _ready() -> void:
	randomize()
	_setup_input()
	_load_best()
	sfx = Sfx.new()
	add_child(sfx)

	var bg := Node2D.new()
	bg.z_index = -30
	bg.draw.connect(_draw_paper.bind(bg))
	add_child(bg)
	stains = Fx.Stains.new()
	stains.z_index = -20
	add_child(stains)
	world_draw = Node2D.new()
	world_draw.z_index = 90
	world_draw.draw.connect(_draw_world)
	add_child(world_draw)
	fx = Fx.new()
	fx.z_index = 100
	fx.stains = stains
	add_child(fx)

	hero = Hero.new()
	hero.position = Ink.ARENA.get_center() + Vector2(0, 60)
	add_child(hero)

	camera = Camera2D.new()
	camera.position = Vector2(640, 360)
	add_child(camera)
	camera.make_current()
	tint = CanvasModulate.new()
	add_child(tint)
	_build_ui()


# ───────────── 매 프레임 ─────────────

func _process(delta: float) -> void:
	if mode != Mode.OVER and Input.is_action_just_pressed("pause"):
		paused = not paused
		_show_pause(paused)
	if paused:
		return
	if mode == Mode.OVER:
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		_update_visuals(delta)
		fx.step(delta)
		return
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return

	flash = maxf(0.0, flash - delta * 3.5)
	if hitstop > 0.0:
		# 히트스톱: 맞는 순간 모든 게 잠깐 멈춘다 (타격감의 핵심)
		hitstop -= delta
		_update_visuals(delta)
		return

	var wdt := delta # 세상 시간
	match mode:
		Mode.FIGHT:
			_fight_input(delta)
		Mode.JUST:
			wdt = delta * WORLD_SLOW
			hero.step(delta, Vector2.ZERO, _aim())
			fx.ghost(hero.position, hero.facing)
			just_t -= delta
			if just_t <= 0.0:
				_enter_stroke()
		Mode.STROKE:
			wdt = delta * WORLD_SLOW * 0.5
			_stroke_input(delta)
		Mode.CUT:
			wdt = delta * WORLD_SLOW
			_cut_step(delta)

	_step_enemies(wdt)
	_step_bullets(wdt)
	if mode == Mode.FIGHT:
		_check_hits()
		_step_waves(delta)
		style = maxf(0.0, style - delta * 7.0)
		combo_t = maxf(0.0, combo_t - delta)
	_update_rank()
	fx.step(wdt if mode != Mode.FIGHT else delta)
	_update_visuals(delta)


func _aim() -> Vector2:
	var d := get_global_mouse_position() - (hero.position + Vector2(0, -22))
	return d.normalized() if d.length() > 4.0 else hero.facing


func _fight_input(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var aim := _aim()
	if Input.is_action_just_pressed("dodge") and hero.dash_cd <= 0.0 and not hero.is_dashing():
		var dir := move if move != Vector2.ZERO else -aim
		if _threat_ttc() < JUST_WINDOW:
			_on_just(dir)
			return
		hero.start_dash(dir)
		sfx.play("dash", randf_range(0.95, 1.05), -4.0)
	if Input.is_action_just_pressed("attack") and attack_cd <= 0.0 and not hero.is_dashing():
		_attack(aim)
	hero.step(delta, Vector2.ZERO if hero.is_dashing() else move, aim)
	if hero.is_dashing():
		fx.ghost(hero.position, hero.facing)


# ───────────── 공격 ─────────────

func _attack(aim: Vector2) -> void:
	combo_i = combo_i + 1 if combo_t > 0.0 and combo_i < 2 else 0
	combo_t = 0.55
	var heavy := combo_i == 2
	attack_cd = 0.32 if heavy else 0.16
	var sdir := -1.0 if combo_i == 1 else 1.0
	hero.swing_t = 0.16
	hero.swing_dir = sdir
	hero.position += aim * (22.0 if heavy else 12.0) # 앞으로 한 발
	var a := aim.angle()
	var reach := 96.0 if heavy else 76.0
	var half := 1.4 if heavy else 1.0
	var center := hero.position + Vector2(0, -22)
	fx.slash_arc(center, reach * 0.78, a - half * sdir, a + half * sdir, 17.0 if heavy else 11.0)
	sfx.play("swing", randf_range(0.9, 1.1) * (0.8 if heavy else 1.0), -3.0)
	var hit_any := false
	for e in enemies:
		if not e.is_solid():
			continue
		var body := e.position + Vector2(0, -e.radius)
		var d := body - center
		if d.length() > reach + e.radius or absf(angle_difference(a, d.angle())) > half + 0.3:
			continue
		hit_any = true
		var killed := e.hurt(2 if heavy else 1, d, 420.0 if heavy else 180.0)
		fx.splash(body, d, 18 if heavy else 9, 430.0 if heavy else 300.0, 0.7)
		_gain(12.0 if heavy else 7.0, 10.0 if heavy else 6.0, 10)
		if killed:
			_kill(e, d.orthogonal().normalized())
	if hit_any:
		hitstop = maxf(hitstop, 0.09 if heavy else 0.05)
		shake = maxf(shake, 8.0 if heavy else 3.5)
		sfx.play("heavy" if heavy else "hit", randf_range(0.92, 1.08), 0.0)


func _gain(ink_add: float, style_add: float, pts: int) -> void:
	ink = minf(100.0, ink + ink_add)
	style = minf(220.0, style + style_add)
	score += int(pts * RANK_MULT[rank])


func _kill(e: Yokai, cut_dir: Vector2) -> void:
	e.dying = true
	e.split = true
	e.split_dir = cut_dir.normalized() if cut_dir != Vector2.ZERO else Vector2.RIGHT
	var body := e.position + Vector2(0, -e.radius)
	fx.splash(body, cut_dir.orthogonal(), 14, 520.0, 3.0)
	fx.splash(body, -cut_dir.orthogonal(), 14, 520.0, 3.0)
	stains.pool(e.position, e.radius * 1.15)
	kills += 1
	score += int(100 * RANK_MULT[rank])
	style = minf(220.0, style + 12.0)
	sfx.play("die", randf_range(0.9, 1.1), -2.0)


# ───────────── 저스트 회피 → 멈춘 시간 → 한 획 ─────────────

## 가장 빨리 닿을 공격까지 남은 시간 (없으면 INF)
func _threat_ttc() -> float:
	var best := INF
	var hp := hero.position + Vector2(0, -16)
	for e in enemies:
		if not e.is_solid():
			continue
		var body := e.position + Vector2(0, -e.radius)
		var rel := hp - body
		var along := rel.dot(e.dash_dir)
		var lateral := absf(rel.cross(e.dash_dir))
		if lateral > Hero.RADIUS + e.radius + 16.0 or along < -10.0:
			continue
		var gap := maxf(0.0, along - Hero.RADIUS - e.radius)
		if e.is_dash_attacking():
			best = minf(best, gap / 950.0)
		elif e.is_telegraphing() and e.kind == "charger":
			best = minf(best, (0.58 - e.t) + gap / 950.0)
	for b in bullets:
		var rel: Vector2 = hp - b["p"]
		var dir: Vector2 = b["dir"]
		var along := rel.dot(dir)
		if along > 0.0 and absf(rel.cross(dir)) < Hero.RADIUS + BULLET_R + 10.0:
			best = minf(best, maxf(0.0, along - Hero.RADIUS) / BULLET_SPEED)
	return best


func _on_just(dir: Vector2) -> void:
	mode = Mode.JUST
	hero.start_dash(dir)
	hero.inv = 99.0
	just_t = Hero.DASH_TIME
	hitstop = 0.07
	flash = 1.0
	flash_col = Color(1, 1, 1, 0.85)
	shake = 6.0
	sfx.play("just", 1.0, 0.0)
	_gain(25.0, 25.0, 50)
	_pop("저스트!", hero.position + Vector2(0, -90), 46, Ink.SEAL)


func _enter_stroke() -> void:
	mode = Mode.STROKE
	stroke_t = STROKE_TIME
	stroke_max = STROKE_BASE + ink * STROKE_PER_INK
	stroke_pts = PackedVector2Array([hero.position])
	drawing = false


func _stroke_input(delta: float) -> void:
	stroke_t -= delta
	brush_snd -= delta
	if Input.is_action_pressed("attack"):
		drawing = true
		var m := get_global_mouse_position()
		m.x = clampf(m.x, Ink.ARENA.position.x + 10.0, Ink.ARENA.end.x - 10.0)
		m.y = clampf(m.y, Ink.ARENA.position.y + 10.0, Ink.ARENA.end.y - 10.0)
		var last := stroke_pts[stroke_pts.size() - 1]
		var remain := stroke_max - Ink.polyline_length(stroke_pts)
		var d := m.distance_to(last)
		if d > 6.0 and remain > 1.0:
			stroke_pts.append(last + (m - last).normalized() * minf(d, remain))
			if brush_snd <= 0.0:
				brush_snd = 0.07
				sfx.play("brush", randf_range(0.9, 1.2), -6.0)
	elif drawing:
		_execute_cut()
		return
	if stroke_t <= 0.0:
		if stroke_pts.size() > 1:
			_execute_cut()
		else:
			mode = Mode.FIGHT
			hero.inv = 0.4
			_pop("...", hero.position + Vector2(0, -80), 30, Ink.INK)


func _execute_cut() -> void:
	mode = Mode.CUT
	cut_t = 0.0
	cut_path = stroke_pts
	cut_len = Ink.polyline_length(cut_path)
	ink = maxf(0.0, ink - maxf(0.0, cut_len - STROKE_BASE) / STROKE_PER_INK)
	cut_targets.clear()
	for e in enemies:
		if not e.is_solid():
			continue
		var d := minf(Ink.dist_to_polyline(e.position, cut_path), Ink.dist_to_polyline(e.position + Vector2(0, -e.radius), cut_path))
		if d < e.radius + CUT_RADIUS:
			cut_targets.append(e)
	sfx.play("cut", 1.0, 0.0)


func _cut_step(delta: float) -> void:
	cut_t += delta
	var k := clampf(cut_t / CUT_TIME, 0.0, 1.0)
	hero.position = _point_along(cut_path, cut_len * k)
	hero.facing = Ink.polyline_dir_near(hero.position, cut_path)
	hero.queue_redraw()
	fx.ghost(hero.position, hero.facing)
	if k < 1.0:
		return
	# 획이 끝났다: 선 위의 요괴가 한꺼번에 갈라진다
	fx.stroke(cut_path, 36.0, 1.6, Ink.INK, true) # 마른 붓 자국이 있는 굵은 획
	fx.stroke(cut_path, 5.0, 0.12, Color(1, 1, 1, 0.95), false) # 베는 순간의 섬광
	var n := 0
	for e in cut_targets:
		if is_instance_valid(e) and e.is_solid():
			_kill(e, Ink.polyline_dir_near(e.position, cut_path))
			n += 1
	mode = Mode.FIGHT
	hero.inv = 0.5
	best_cut = maxi(best_cut, n)
	if n > 0:
		hitstop = 0.16 + 0.03 * mini(n, 5)
		shake = 12.0 + 3.0 * n
		flash = 0.8
		flash_col = Color(Ink.INK, 0.35)
		sfx.play("split", 1.0, 0.0)
		score += int(n * n * 150 * RANK_MULT[rank])
		style = minf(220.0, style + 18.0 * n)
		_pop("일격!" if n == 1 else "%d연 베기!" % n, hero.position + Vector2(0, -90), 40 + 6 * mini(n, 4), Ink.INK)
	else:
		_pop("헛손질", hero.position + Vector2(0, -80), 28, Color(Ink.INK, 0.7))


func _point_along(pts: PackedVector2Array, dist: float) -> Vector2:
	var left := dist
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if left <= seg:
			return pts[i].lerp(pts[i + 1], left / maxf(seg, 0.001))
		left -= seg
	return pts[pts.size() - 1]


# ───────────── 요괴 / 먹 탄 ─────────────

func _step_enemies(wdt: float) -> void:
	var keep: Array[Yokai] = []
	for e in enemies:
		e.step(wdt if not e.split else maxf(wdt, get_process_delta_time() * 0.5), hero.position)
		if e.split and e.split_t > 0.5:
			e.queue_free()
			continue
		keep.append(e)
		# 공격 신호가 시작되면 '칭'
		if e.is_telegraphing() and not e.has_meta("warned"):
			e.set_meta("warned", true)
			sfx.play("warn", randf_range(0.95, 1.05), -6.0)
		elif not e.is_telegraphing() and e.has_meta("warned"):
			e.remove_meta("warned")
		e.z_index = clampi(int(e.position.y / 8.0), 0, 80)
	enemies = keep
	# 서로 겹치지 않게 밀어낸다
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			var a := enemies[i]
			var b := enemies[j]
			if not a.is_solid() or not b.is_solid():
				continue
			var d := b.position - a.position
			var min_d := a.radius + b.radius
			if d.length() < min_d and d.length() > 0.01:
				var push := d.normalized() * (min_d - d.length()) * 0.5
				a.position -= push
				b.position += push
	hero.z_index = clampi(int(hero.position.y / 8.0), 0, 80)


func _on_fire(from: Vector2, dir: Vector2, count: int) -> void:
	var spread := [0.0] if count == 1 else [-0.28, 0.0, 0.28]
	for s in spread:
		bullets.append({"p": from, "dir": dir.rotated(s), "age": 0.0})
	sfx.play("shoot", randf_range(0.95, 1.05), -4.0)


func _step_bullets(wdt: float) -> void:
	var keep: Array[Dictionary] = []
	for b in bullets:
		b["p"] += b["dir"] * BULLET_SPEED * wdt
		b["age"] += wdt
		if not Ink.ARENA.grow(20.0).has_point(b["p"]):
			stains.add(b["p"], 8.0, Ink.INK)
			continue
		keep.append(b)
	bullets = keep


func _check_hits() -> void:
	var hp := hero.position + Vector2(0, -16)
	for e in enemies:
		if not e.is_solid():
			continue
		var body := e.position + Vector2(0, -e.radius)
		var d := hp - body
		if d.length() < Hero.RADIUS + e.radius:
			if e.is_dash_attacking() and not hero.is_invulnerable():
				_hurt(e.dash_dir)
				return
			# 그냥 부딪히면 밀어내기만
			hero.position += d.normalized() * (Hero.RADIUS + e.radius - d.length())
	var keep: Array[Dictionary] = []
	for b in bullets:
		if (b["p"] as Vector2).distance_to(hp) < Hero.RADIUS + BULLET_R and not hero.is_invulnerable():
			fx.splash(b["p"], b["dir"], 8, 250.0)
			_hurt(b["dir"])
			continue
		keep.append(b)
	bullets = keep


func _hurt(dir: Vector2) -> void:
	hero.hp -= 1
	hero.inv = 1.0
	hero.hurt_t = 0.6
	hero.position += dir.normalized() * 34.0
	hitstop = 0.12
	shake = 13.0
	flash = 1.0
	flash_col = Color(Ink.SEAL, 0.35)
	style = maxf(0.0, style - 45.0)
	combo_i = -1
	sfx.play("hurt", 1.0, 0.0)
	fx.splash(hero.position + Vector2(0, -20), dir, 16, 380.0, 1.3, Ink.SEAL)
	if hero.hp <= 0:
		_game_over()


# ───────────── 막(웨이브) ─────────────

func _step_waves(delta: float) -> void:
	var alive := 0
	for e in enemies:
		if not e.dying:
			alive += 1
	if alive == 0 and spawn_queue.is_empty():
		wave_t -= delta
		if wave_t <= 0.0:
			wave += 1
			wave_t = 1.6
			var chargers := 2 + wave
			var shooters := mini(wave - 1, 4)
			for i in chargers:
				spawn_queue.append("charger")
			for i in shooters:
				spawn_queue.insert(randi() % (spawn_queue.size() + 1), "shooter")
			spawn_t = 0.3
			sfx.play("gong", 1.0, -2.0)
			_pop("제 %d 막" % wave, Ink.ARENA.get_center() + Vector2(0, -40), 64, Ink.INK)
	if not spawn_queue.is_empty():
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = 0.55
			_spawn(spawn_queue.pop_front())


func _spawn(kind: String) -> void:
	var p := Vector2.ZERO
	for i in 20:
		p = Vector2(randf_range(Ink.ARENA.position.x + 60, Ink.ARENA.end.x - 60), randf_range(Ink.ARENA.position.y + 60, Ink.ARENA.end.y - 40))
		if p.distance_to(hero.position) > 300.0:
			break
	var e := Yokai.new()
	e.setup(kind, p, wave)
	e.fire.connect(_on_fire)
	add_child(e)
	enemies.append(e)
	stains.wash(p, 26.0, 0.1) # 요괴가 나타난 자리의 번진 먹


# ───────────── 등급 / 끝 ─────────────

func _update_rank() -> void:
	var r := 0
	for i in RANK_STYLE.size():
		if style >= RANK_STYLE[i]:
			r = i
	if r > rank:
		sfx.play("rank", 1.0, -3.0)
		_pop(RANK_NAME[r], Vector2(1150, 150), 72, Ink.SEAL)
	rank = r


func _game_over() -> void:
	mode = Mode.OVER
	hero.dead = true
	hero.queue_redraw()
	sfx.play("over", 1.0, 0.0)
	var new_best := score > best_score
	if new_best:
		best_score = score
		var cfg := ConfigFile.new()
		cfg.set_value("best", "score", best_score)
		cfg.save(SAVE_PATH)
	get_tree().create_timer(0.9).timeout.connect(_show_over.bind(new_best))


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = cfg.get_value("best", "score", 0)


# ───────────── 그리기 ─────────────

func _draw_paper(ci: Node2D) -> void:
	ci.draw_rect(Rect2(-200, -200, 1680, 1120), Ink.PAPER)
	# 화선지 결
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 140:
		var p := Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720))
		ci.draw_line(p, p + Vector2.from_angle(rng.randf_range(-0.4, 0.4)) * rng.randf_range(20, 70), Color(Ink.PAPER_DARK, 0.7), 1.0, true)
	# 경기장 밖은 먹물이 번진 테두리
	var r := Ink.ARENA
	for k in 6:
		var g := 6.0 + k * 9.0
		ci.draw_rect(r.grow(g), Color(Ink.INK, 0.05), false, 12.0)
	ci.draw_rect(r, Color(Ink.INK, 0.6), false, 3.0)
	# 바닥의 큰 먹 글씨 (흐리게)
	ci.draw_string(Ink.brush_font(), r.get_center() + Vector2(-110, 80), "墨", HORIZONTAL_ALIGNMENT_CENTER, 220, 240, Color(Ink.INK, 0.05))


func _draw_world() -> void:
	# 먹 탄
	for b in bullets:
		var p: Vector2 = b["p"]
		var dir: Vector2 = b["dir"]
		world_draw.draw_line(p - dir * 26.0, p, Color(Ink.INK, 0.35), 8.0, true)
		world_draw.draw_colored_polygon(Ink.blob(p, BULLET_R, float(b["age"]) * 20.0, 0.2, 12), Ink.INK)
	# 한 획 그리는 중
	if mode == Mode.STROKE:
		var remain := 1.0 - Ink.polyline_length(stroke_pts) / stroke_max
		if stroke_pts.size() > 1:
			Ink.draw_brush(world_draw, stroke_pts, 18.0, Color(Ink.INK, 0.55), false)
		var tip := stroke_pts[stroke_pts.size() - 1]
		world_draw.draw_arc(tip, 10.0 + 18.0 * remain, 0, TAU, 32, Color(Ink.SEAL, 0.8), 2.5, true)
		# 선에 걸릴 요괴 표시
		for e in enemies:
			if e.is_solid() and stroke_pts.size() > 1 and Ink.dist_to_polyline(e.position, stroke_pts) < e.radius + CUT_RADIUS:
				world_draw.draw_arc(e.position + Vector2(0, -e.radius), e.radius + 10.0, 0, TAU, 24, Ink.SEAL, 3.0, true)


func _update_visuals(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 40.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	var slow_target := 1.0 if mode in [Mode.JUST, Mode.STROKE, Mode.CUT] else 0.0
	slow_amt = lerpf(slow_amt, slow_target, 1.0 - exp(-14.0 * delta))
	tint.color = Color.WHITE.lerp(Color(0.78, 0.76, 0.8), slow_amt)
	dim_rect.color = Color(Ink.INK, 0.16 * slow_amt)
	flash_rect.color = Color(flash_col, flash_col.a * flash)
	world_draw.queue_redraw()
	_update_hud()


func _pop(text: String, pos: Vector2, size: int, col: Color) -> void:
	var l := Ink.label(size, col, true)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 위쪽 점수판과 겹치지 않게
	pos.y = maxf(pos.y, 130.0 + size * 0.5)
	l.size = Vector2(520, size + 20)
	l.position = pos - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	l.z_index = 200
	l.scale = Vector2(1.6, 1.6)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.45)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


# ───────────── UI ─────────────

class HpDraw extends Control:
	var hp := 5

	func _draw() -> void:
		for i in 5:
			var c := Vector2(14 + i * 30, 16)
			var full := i < hp
			draw_colored_polygon(Ink.blob(c, 11.0, i * 1.7, 0.1, 16), Ink.INK if full else Color(Ink.INK, 0.15))
			if full:
				draw_circle(c + Vector2(-3, -3), 3, Color(1, 1, 1, 0.5), true, -1.0, true)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	dim_rect = ColorRect.new()
	dim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim_rect)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)

	hp_draw = HpDraw.new()
	hp_draw.position = Vector2(26, 20)
	hp_draw.size = Vector2(160, 32)
	hp_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp_draw)
	var ink_text := Ink.label(16, Ink.INK, false)
	ink_text.text = "먹"
	ink_text.position = Vector2(28, 56)
	root.add_child(ink_text)
	var ink_bg := ColorRect.new()
	ink_bg.color = Color(Ink.INK, 0.12)
	ink_bg.position = Vector2(56, 62)
	ink_bg.size = Vector2(150, 12)
	root.add_child(ink_bg)
	ink_fill = ColorRect.new()
	ink_fill.color = Ink.INK
	ink_fill.size = Vector2(0, 12)
	ink_bg.add_child(ink_fill)

	wave_label = Ink.label(26, Ink.INK, true)
	wave_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	wave_label.offset_top = 16
	wave_label.offset_bottom = 50
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(wave_label)
	score_label = Ink.label(20, Ink.INK, false)
	score_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	score_label.offset_top = 50
	score_label.offset_bottom = 76
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(score_label)

	rank_box = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Ink.SEAL
	sb.set_corner_radius_all(4)
	rank_box.add_theme_stylebox_override("panel", sb)
	rank_box.anchor_left = 1.0
	rank_box.anchor_right = 1.0
	rank_box.offset_left = -96
	rank_box.offset_right = -26
	rank_box.offset_top = 14
	rank_box.offset_bottom = 84
	rank_box.rotation = 0.05
	root.add_child(rank_box)
	rank_label = Ink.label(48, Color("f5efe0"), true, false)
	rank_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_box.add_child(rank_label)

	stroke_label = Ink.label(24, Ink.SEAL, true)
	stroke_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	stroke_label.offset_top = -98
	stroke_label.offset_bottom = -66
	stroke_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(stroke_label)
	stroke_bar_bg = ColorRect.new()
	stroke_bar_bg.color = Color(Ink.INK, 0.15)
	stroke_bar_bg.anchor_left = 0.5
	stroke_bar_bg.anchor_right = 0.5
	stroke_bar_bg.anchor_top = 1.0
	stroke_bar_bg.anchor_bottom = 1.0
	stroke_bar_bg.offset_left = -160
	stroke_bar_bg.offset_right = 160
	stroke_bar_bg.offset_top = -62
	stroke_bar_bg.offset_bottom = -54
	root.add_child(stroke_bar_bg)
	stroke_bar = ColorRect.new()
	stroke_bar.color = Ink.SEAL
	stroke_bar.size = Vector2(320, 8)
	stroke_bar_bg.add_child(stroke_bar)

	help_label = Ink.label(15, Color(Ink.INK, 0.7), false)
	help_label.text = "이동 WASD   베기 클릭   회피 Space·우클릭   공격이 닿기 직전에 피하면 시간이 멈춰요   다시 R"
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -32
	help_label.offset_bottom = -8
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(help_label)

	overlay = CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	root.add_child(overlay)


func _update_hud() -> void:
	(hp_draw as HpDraw).hp = hero.hp
	hp_draw.queue_redraw()
	ink_fill.size.x = 150.0 * ink / 100.0
	wave_label.text = "제 %d 막" % maxi(wave, 1)
	score_label.text = "%d점   ·   최고 한 획 %d연" % [score, best_cut]
	rank_box.visible = rank > 0
	rank_label.text = RANK_NAME[rank]
	var stroking := mode == Mode.STROKE
	stroke_label.visible = stroking
	stroke_bar_bg.visible = stroking
	if stroking:
		stroke_label.text = "마우스를 누른 채 한 획을 그어요" if not drawing else "손을 떼면 벤다!"
		stroke_bar.size.x = 320.0 * clampf(stroke_t / STROKE_TIME, 0.0, 1.0)


func _panel(lines: Array) -> void:
	for c in overlay.get_children():
		c.queue_free()
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Ink.PAPER, 0.96)
	sb.border_color = Ink.INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(36)
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	for it in lines:
		var l := Ink.label(it[1], it[2], it[3], false)
		l.text = it[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
	overlay.add_child(panel)
	overlay.visible = true


func _show_over(new_best: bool) -> void:
	_panel([
		["먹이 다 번졌다", 52, Ink.INK, true],
		["제 %d 막까지 · 쓰러뜨린 요괴 %d" % [wave, kills], 20, Ink.INK, false],
		["%d점%s   ·   최고 기록 %d점" % [score, "  (신기록!)" if new_best else "", best_score], 20, Ink.SEAL if new_best else Ink.INK, false],
		["가장 많이 벤 한 획: %d연" % best_cut, 20, Ink.INK, false],
		["R 키를 눌러 다시", 18, Color(Ink.INK, 0.6), false],
	])


func _show_pause(p: bool) -> void:
	if not p:
		overlay.visible = false
		return
	_panel([["잠시 멈춤", 44, Ink.INK, true], ["Esc 계속   ·   R 처음부터", 18, Color(Ink.INK, 0.6), false]])


func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"dodge": [KEY_SPACE, KEY_SHIFT], "pause": [KEY_ESCAPE], "restart": [KEY_R],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	var mouse := {"attack": MOUSE_BUTTON_LEFT, "dodge": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var m := InputEventMouseButton.new()
		m.button_index = mouse[action]
		InputMap.action_add_event(action, m)
