extends Node2D
## 먹 한 획 (시험판)
## 공격이 닿기 직전에 피하면(저스트) 시간이 멈춘다. 멈춘 동안 마우스로 한 획을 그으면
## 그 선을 따라 번개처럼 지나가며 선 위의 요괴를 한 번에 벤다.

enum Mode { FIGHT, JUST, STROKE, CUT, OVER, CHOOSE }

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
const BOSS_EVERY := 5
const BOSS_CUT_DMG := 7 # 한 획이 보스에게 주는 피해 (보스 체력 60)
var cut_blocker: Yokai
var boss_angry_said := false
const RING_SPEED := 330.0 # 먹 물결이 퍼지는 속도
const RING_MAX := 900.0
const RING_THICK := 16.0
const INTRO := {
	"charger": "돌진 요괴: 붉은 낙관이 뜨면 곧 돌진! 닿기 직전에 피하면 저스트",
	"shooter": "먹 탄 요괴: 날아오는 먹 탄도 닿기 직전에 피하면 저스트",
	"shield": "방패 요괴: 앞은 막아요. 옆이나 뒤로 돌아가 베거나, 한 획을 둘러서 그어요 (셋째 베기로 방패 깨기)",
	"splitter": "분열 요괴: 그냥 베면 작은 요괴 둘로 갈라져요. 한 획으로 베면 깔끔!",
	"boss": "큰 먹도깨비: 퍼져 오는 먹 물결은 피할 곳이 없어요. 저스트로 뚫고 지나가요",
}

var rings: Array[Dictionary] = []
var boss: Yokai
var seen := {}
var intro_t := 0.0
var intro_label: Label
var boss_bar_bg: ColorRect
var boss_bar: ColorRect
var boss_name: Label

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

# 붓 기술
var skills := {} # id → 레벨
var strokes_left := 1
var trails: Array[Dictionary] = [] # 번짐: 획 자리에 남은 먹물
var ghost_cuts: Array[Dictionary] = [] # 잔영: 잠시 뒤 다시 긋는 획
var cards: Array[String] = []
var chosen_wave := 0
var recent_pops: Array = [] # 최근 뜬 글씨 (겹치지 않게)
var card_box: CenterContainer
var skill_row: HBoxContainer

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
		Mode.CHOOSE:
			# 붓 기술 고르는 중: 세상은 멈춘다
			for i in cards.size():
				if Input.is_action_just_pressed("pick_%d" % (i + 1)):
					_pick_card(i)
					break
			_update_visuals(delta)
			return
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
	_step_rings(wdt)
	_step_skill_fx(wdt)
	intro_t = maxf(0.0, intro_t - delta)
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
		if _threat_ttc() < _just_window():
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
	if heavy and skill_lv("chain") > 0:
		# 연환: 셋째 베기가 먹 칼날을 쏜다 (뚫고 지나감)
		var lv := skill_lv("chain")
		bullets.append({"p": center, "dir": aim, "age": 0.0, "friendly": true, "blade": true,
				"r": 26.0 + 10.0 * lv, "dmg": lv, "hit": {}, "life": 0.45})
	var hit_any := false
	var blocked := false
	for e in enemies:
		if not e.is_solid():
			continue
		var body := e.position + Vector2(0, -e.radius)
		var d := body - center
		if d.length() > reach + e.radius or absf(angle_difference(a, d.angle())) > half + 0.3:
			continue
		var res := e.take_hit(2 if heavy else 1, d, 420.0 if heavy else 180.0, heavy)
		match res:
			"blocked":
				# 방패에 막힘: 튕겨 나온다
				blocked = true
				hero.position -= aim * 18.0
				fx.splash(body - d.normalized() * e.radius, -d, 6, 260.0, 0.6, Ink.SEAL)
			"guard_break":
				hit_any = true
				sfx.play("break", 1.0, 0.0)
				fx.splash(body, d, 16, 420.0, 1.0)
				_pop("방패 깨짐!", e.position + Vector2(0, -80), 30, Ink.SEAL)
				_gain(10.0, 12.0, 30)
			_:
				hit_any = true
				fx.splash(body, d, 18 if heavy else 9, 430.0 if heavy else 300.0, 0.7)
				_gain(12.0 if heavy else 7.0, 10.0 if heavy else 6.0, 10)
				if res == "kill":
					_kill(e, d.orthogonal().normalized(), false)
	if blocked and not hit_any:
		hitstop = maxf(hitstop, 0.04)
		shake = maxf(shake, 2.5)
		sfx.play("block", randf_range(0.95, 1.05), -2.0)
		_pop("막힘", hero.position + Vector2(0, -70), 22, Color(Ink.INK, 0.7))
	if hit_any:
		hitstop = maxf(hitstop, 0.09 if heavy else 0.05)
		shake = maxf(shake, 8.0 if heavy else 3.5)
		sfx.play("heavy" if heavy else "hit", randf_range(0.92, 1.08), 0.0)


func _gain(ink_add: float, style_add: float, pts: int) -> void:
	ink = minf(100.0, ink + ink_add * (1.0 + 0.5 * skill_lv("inkwell")))
	style = minf(220.0, style + style_add)
	score += int(pts * RANK_MULT[rank])


func _kill(e: Yokai, cut_dir: Vector2, by_cut: bool) -> void:
	# 분열 요괴는 일반 공격으로 쓰러지면 작은 요괴 둘로 갈라진다 (한 획이면 깔끔)
	if e.kind == "splitter" and not by_cut:
		for s in [-1.0, 1.0]:
			_spawn_at("imp", e.position + cut_dir.normalized() * 26.0 * s, true)
		sfx.play("pop", 1.0, -2.0)
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
			best = minf(best, gap / e.dash_speed())
		elif e.is_telegraphing() and e.attack == "dash":
			best = minf(best, (e.tele_time() - e.t) + gap / e.dash_speed())
	# 퍼져 오는 먹 물결
	for rg in rings:
		var d: float = (hp - rg["c"]).length()
		if d > rg["r"]:
			best = minf(best, maxf(0.0, d - rg["r"] - RING_THICK) / RING_SPEED)
	for b in bullets:
		if b.get("friendly", false):
			continue
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
	strokes_left = 1 + skill_lv("double")
	if skill_lv("reflect") > 0:
		# 되받아치기: 주변 먹 탄이 방향을 틀어 요괴를 향한다
		var n := 0
		for b in bullets:
			if b.get("friendly", false) or (b["p"] as Vector2).distance_to(hero.position) > 320.0:
				continue
			var target := _nearest_enemy(b["p"])
			b["dir"] = ((target.position + Vector2(0, -target.radius)) - b["p"]).normalized() if target else -(b["dir"] as Vector2)
			b["friendly"] = true
			n += 1
		if n > 0:
			_pop("되받아치기!", hero.position + Vector2(0, -130), 26, Ink.SEAL)


func _enter_stroke(again := false) -> void:
	mode = Mode.STROKE
	stroke_t = _stroke_time() * (0.65 if again else 1.0)
	stroke_max = _stroke_max()
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


## 획이 방패 정면에 걸리면 그 앞에서 끊긴다. {"pts": 끊긴 획, "blocker": 막은 요괴 또는 null}
func _shield_cut(pts: PackedVector2Array) -> Dictionary:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 0.01:
			continue
		var dir := seg / seg_len
		var best := INF
		var blocker: Yokai = null
		for e in enemies:
			if not e.is_solid() or not e.has_shield or not e.is_front(dir):
				continue
			var c := e.position + Vector2(0, -e.radius * 0.5)
			var q := Geometry2D.get_closest_point_to_segment(c, a, b)
			if q.distance_to(c) < e.radius + _cut_radius() * 0.7:
				var along := (q - a).dot(dir)
				if along < best:
					best = along
					blocker = e
		if blocker:
			var out := pts.slice(0, i + 1)
			# 방패 바로 앞에서 멈춘다
			out.append(a + dir * maxf(0.0, best - blocker.radius - 6.0))
			return {"pts": out, "blocker": blocker}
	return {"pts": pts, "blocker": null}


func _execute_cut() -> void:
	mode = Mode.CUT
	cut_t = 0.0
	var res := _shield_cut(stroke_pts)
	cut_path = res["pts"]
	cut_blocker = res["blocker"]
	if cut_path.size() < 2:
		cut_path = PackedVector2Array([hero.position, hero.position + Vector2(0.1, 0)])
	cut_len = Ink.polyline_length(cut_path)
	ink = maxf(0.0, ink - maxf(0.0, cut_len - STROKE_BASE) / STROKE_PER_INK)
	cut_targets = _targets_on(cut_path)
	sfx.play("cut", 1.0, 0.0)


func _targets_on(path: PackedVector2Array) -> Array[Yokai]:
	var out: Array[Yokai] = []
	for e in enemies:
		if not e.is_solid():
			continue
		var d := minf(Ink.dist_to_polyline(e.position, path), Ink.dist_to_polyline(e.position + Vector2(0, -e.radius), path))
		if d < e.radius + _cut_radius():
			out.append(e)
	return out


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
	if cut_blocker and is_instance_valid(cut_blocker) and cut_blocker.is_solid():
		# 방패에 막혀 획이 끊겼다: 튕겨 나오고, 그 방패만 깨진다
		var bdir := (cut_blocker.position - hero.position).normalized()
		cut_blocker.take_hit(1, bdir, 300.0, true)
		hero.position -= bdir * 36.0
		hitstop = maxf(hitstop, 0.1)
		shake = maxf(shake, 8.0)
		sfx.play("block", 0.8, 0.0)
		sfx.play("break", 1.0, -2.0)
		fx.splash(cut_blocker.position + Vector2(0, -cut_blocker.radius), -bdir, 12, 380.0, 0.9, Ink.SEAL)
		_pop("방패에 막혀 획이 끊겼다!", cut_blocker.position + Vector2(0, -90), 26, Ink.SEAL)
	n += _cut_targets_along(cut_path, cut_targets, cut_blocker)
	n += _skill_after_cut(cut_path)
	if strokes_left > 1:
		# 겹획: 한 획 더
		strokes_left -= 1
		_enter_stroke(true)
		hero.inv = 99.0
		_pop("한 획 더!", hero.position + Vector2(0, -130), 28, Ink.SEAL)
	else:
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


## 획 위의 요괴를 벤다. 벤 수를 돌려준다
func _cut_targets_along(path: PackedVector2Array, targets: Array[Yokai], blocker: Yokai) -> int:
	var n := 0
	for e in targets:
		if not is_instance_valid(e) or not e.is_solid() or e == blocker:
			continue
		var travel := Ink.polyline_dir_near(e.position, path)
		if e.kind == "boss":
			# 보스는 한 획에 죽지 않고 큰 피해만
			if e.take_hit(BOSS_CUT_DMG, travel, 300.0, true) == "kill":
				_kill(e, travel, true)
			fx.splash(e.position + Vector2(0, -e.radius), travel.orthogonal(), 24, 560.0, 2.5)
			n += 1
		elif e.is_front(travel):
			e.take_hit(1, travel, 300.0, true)
			sfx.play("break", 1.0, 0.0)
		else:
			_kill(e, travel, true)
			n += 1
	return n


# ───────────── 붓 기술 ─────────────

func skill_lv(id: String) -> int:
	return skills.get(id, 0)


func _just_window() -> float:
	return JUST_WINDOW + 0.04 * skill_lv("slowink")


func _stroke_time() -> float:
	return STROKE_TIME + 0.6 * skill_lv("slowink")


func _stroke_max() -> float:
	return (STROKE_BASE + ink * STROKE_PER_INK) * (1.0 + 0.4 * skill_lv("fine")) * (1.0 - 0.2 * skill_lv("broad"))


func _cut_radius() -> float:
	return CUT_RADIUS * (1.0 + 0.6 * skill_lv("broad")) * (1.0 - 0.25 * skill_lv("fine"))


func _nearest_enemy(p: Vector2) -> Yokai:
	var best: Yokai = null
	var bd := INF
	for e in enemies:
		if e.is_solid() and e.position.distance_to(p) < bd:
			bd = e.position.distance_to(p)
			best = e
	return best


## 기술로 생긴 피해 (방패는 무시). 쓰러지면 true
func _skill_hit(e: Yokai, dmg: int, from: Vector2, clean: bool) -> bool:
	if not is_instance_valid(e) or not e.is_solid():
		return false
	var dir := (e.position - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var shield := e.has_shield
	e.has_shield = false # 기술은 방패를 무시한다
	var res := e.take_hit(dmg, dir, 260.0, true)
	e.has_shield = shield
	fx.splash(e.position + Vector2(0, -e.radius), dir, 8, 320.0, 0.8)
	if res == "kill":
		_kill(e, dir.orthogonal(), clean)
		return true
	return false


## 한 획이 끝난 뒤 붙는 기술: 꺾음, 낙관, 번짐, 잔영
func _skill_after_cut(path: PackedVector2Array) -> int:
	var n := 0
	var lv := skill_lv("angle")
	if lv > 0:
		for c in _corners(path):
			var r := 55.0 + 20.0 * lv
			fx.splash(c, Vector2.ZERO, 16, 360.0, PI)
			stains.wash(c, r * 0.6, 0.12)
			for e in enemies.duplicate():
				if e.is_solid() and e.position.distance_to(c) < r + e.radius:
					if _skill_hit(e, (4 if e.kind == "boss" else 1) + (1 if lv >= 3 else 0), c, true):
						n += 1
			_pop("꺾!", c + Vector2(0, -30), 24, Ink.INK)
	lv = skill_lv("seal")
	if lv > 0:
		var end := path[path.size() - 1]
		var r := 90.0 + 30.0 * lv
		fx.seal(end, r)
		shake = maxf(shake, 10.0)
		sfx.play("slam", 1.4, -3.0)
		for e in enemies.duplicate():
			if e.is_solid() and e.position.distance_to(end) < r + e.radius:
				if _skill_hit(e, (5 if lv >= 3 else 3) if e.kind == "boss" else 2, end, true):
					n += 1
	lv = skill_lv("bleed")
	if lv > 0:
		trails.append({"pts": path, "t": 2.0 + 2.0 * lv, "max": 2.0 + 2.0 * lv, "dmg": 2 if lv >= 3 else 1})
	if skill_lv("ghost") > 0:
		ghost_cuts.append({"pts": path, "t": 0.6})
	return n


## 획에서 크게 꺾인 자리 (30px 간격으로 다시 찍어 손떨림은 무시)
func _corners(path: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array([path[0]])
	var acc := 0.0
	for i in range(1, path.size()):
		acc += path[i].distance_to(path[i - 1])
		if acc >= 30.0:
			pts.append(path[i])
			acc = 0.0
	var out := PackedVector2Array()
	for i in range(1, pts.size() - 1):
		var a := (pts[i] - pts[i - 1]).normalized()
		var b := (pts[i + 1] - pts[i]).normalized()
		if absf(a.angle_to(b)) > 0.9 and (out.is_empty() or out[out.size() - 1].distance_to(pts[i]) > 60.0):
			out.append(pts[i])
	return out


## 번짐(먹물 자국)과 잔영(먹 그림자 획)
func _step_skill_fx(wdt: float) -> void:
	var keep: Array[Dictionary] = []
	for tr in trails:
		tr["t"] -= wdt
		if tr["t"] <= 0.0:
			continue
		keep.append(tr)
		for e in enemies:
			if not e.is_solid() or Ink.dist_to_polyline(e.position, tr["pts"]) > e.radius + 16.0:
				continue
			e.slow_t = 0.3 # 먹물에 발이 묶여 느려진다
			var cd: float = e.get_meta("bleed_cd", 0.0) - wdt
			if cd <= 0.0:
				cd = 0.6
				_skill_hit(e, tr["dmg"], e.position + Vector2(0, 10), false)
			e.set_meta("bleed_cd", cd)
	trails = keep
	var kg: Array[Dictionary] = []
	for g in ghost_cuts:
		g["t"] -= wdt
		if g["t"] > 0.0:
			kg.append(g)
			continue
		# 먹 그림자가 같은 획을 다시 긋는다
		var path: PackedVector2Array = g["pts"]
		var res := _shield_cut(path)
		fx.stroke(res["pts"], 26.0, 1.0, Color(0.25, 0.2, 0.3, 0.85), true)
		sfx.play("cut", 1.25, -4.0)
		var n := _cut_targets_along(res["pts"], _targets_on(res["pts"]), res["blocker"])
		if n > 0:
			hitstop = maxf(hitstop, 0.1)
			shake = maxf(shake, 8.0)
			_pop("잔영 %d연!" % n, (path[path.size() - 1]) + Vector2(0, -60), 28, Color(0.25, 0.2, 0.3))
	ghost_cuts = kg


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


func _on_fire(from: Vector2, dir: Vector2, count: int, spread: float) -> void:
	for i in count:
		var s := (i - (count - 1) * 0.5) * spread
		bullets.append({"p": from, "dir": dir.rotated(s), "age": 0.0})
	sfx.play("shoot", randf_range(0.95, 1.05) * (0.8 if count > 3 else 1.0), -4.0)


## 큰 먹도깨비의 먹 물결: 고리가 퍼져 나간다. 피할 곳이 없으니 저스트로 뚫고 지나가야 한다
func _on_slam(center: Vector2) -> void:
	rings.append({"c": center, "r": 40.0, "hit": false})
	shake = maxf(shake, 10.0)
	sfx.play("slam", 1.0, 0.0)
	stains.wash(center, 90.0, 0.12)


func _step_rings(wdt: float) -> void:
	var keep: Array[Dictionary] = []
	for rg in rings:
		rg["r"] += RING_SPEED * wdt
		if rg["r"] < RING_MAX:
			keep.append(rg)
	rings = keep


func _step_bullets(wdt: float) -> void:
	var keep: Array[Dictionary] = []
	for b in bullets:
		var friendly: bool = b.get("friendly", false)
		var blade: bool = b.get("blade", false)
		# 아군 먹 탄·칼날은 멈춘 시간에도 아이 쪽 시간으로 날아간다
		var dt := get_process_delta_time() if friendly and mode == Mode.FIGHT else wdt
		b["p"] += b["dir"] * (720.0 if blade else BULLET_SPEED * (1.4 if friendly else 1.0)) * dt
		b["age"] += dt
		if not Ink.ARENA.grow(20.0).has_point(b["p"]) or (blade and b["age"] > b["life"]):
			stains.add(b["p"], 8.0, Ink.INK)
			continue
		if friendly:
			# 요괴를 친다 (칼날은 뚫고 지나가며 한 번씩, 되받아친 먹 탄은 맞으면 사라짐)
			var r: float = b.get("r", BULLET_R)
			var gone := false
			for e in enemies.duplicate():
				if not e.is_solid() or b.has("hit") and b["hit"].has(e.get_instance_id()):
					continue
				if (e.position + Vector2(0, -e.radius)).distance_to(b["p"]) < e.radius + r:
					_skill_hit(e, int(b.get("dmg", 2)), b["p"] - b["dir"] * 20.0, false)
					sfx.play("hit", 1.2, -4.0)
					if blade:
						b["hit"][e.get_instance_id()] = true
					else:
						gone = true
						break
			if gone:
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
	for rg in rings:
		var rel: Vector2 = hp - rg["c"]
		if not rg["hit"] and absf(rel.length() - float(rg["r"])) < RING_THICK + Hero.RADIUS * 0.5 and not hero.is_invulnerable():
			rg["hit"] = true
			_hurt(rel.normalized())
			return
	var keep: Array[Dictionary] = []
	for b in bullets:
		if not b.get("friendly", false) and (b["p"] as Vector2).distance_to(hp) < Hero.RADIUS + BULLET_R and not hero.is_invulnerable():
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
		# 막을 마치면 붓 기술을 고른다 (잠깐 숨 돌린 뒤)
		if wave >= 1 and chosen_wave < wave and wave_t <= 0.8:
			chosen_wave = wave
			_open_cards()
			return
		if wave_t <= 0.0:
			wave += 1
			wave_t = 1.6
			ink = minf(100.0, ink + 30.0 * skill_lv("inkwell"))
			spawn_queue = _wave_list(wave)
			spawn_t = 0.3
			sfx.play("gong", 1.0, -2.0)
			_pop("제 %d 막" % wave, Ink.ARENA.get_center() + Vector2(0, -40), 64, Ink.INK)
			if wave % BOSS_EVERY == 0:
				_pop("큰 먹도깨비가 나타났다!", Ink.ARENA.get_center() + Vector2(0, 30), 30, Ink.SEAL)
				sfx.play("roar", 1.0, 0.0)
	if not spawn_queue.is_empty():
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = 0.55
			_spawn(spawn_queue.pop_front())


## 막마다 나오는 요괴. 새 종류는 3막(방패), 4막(분열)부터, 5막마다 보스
func _wave_list(n: int) -> Array[String]:
	var list: Array[String] = []
	if n % BOSS_EVERY == 0:
		list.append("boss")
		for i in 1 + n / BOSS_EVERY:
			list.append("charger")
		return list
	for i in 2 + n / 2:
		list.append("charger")
	for i in mini(n - 1, 3):
		list.append("shooter")
	if n >= 3:
		for i in mini((n - 1) / 2, 3):
			list.append("shield")
	if n >= 4:
		for i in mini((n - 2) / 2, 2):
			list.append("splitter")
	list.shuffle()
	return list


func _spawn(kind: String) -> void:
	var p := Vector2.ZERO
	for i in 20:
		p = Vector2(randf_range(Ink.ARENA.position.x + 60, Ink.ARENA.end.x - 60), randf_range(Ink.ARENA.position.y + 60, Ink.ARENA.end.y - 40))
		if p.distance_to(hero.position) > 300.0:
			break
	if kind == "boss":
		p = Vector2(Ink.ARENA.get_center().x, Ink.ARENA.position.y + 120.0)
	_spawn_at(kind, p, false)
	stains.wash(p, 26.0 if kind != "boss" else 70.0, 0.1) # 요괴가 나타난 자리의 번진 먹


func _spawn_at(kind: String, p: Vector2, instant: bool) -> void:
	var e := Yokai.new()
	e.setup(kind, p, wave)
	if instant:
		e.state = "move"
	e.fire.connect(_on_fire)
	e.slam.connect(_on_slam)
	add_child(e)
	enemies.append(e)
	if kind == "boss":
		boss = e
	# 처음 보는 요괴는 아래에 짧은 설명
	if INTRO.has(kind) and not seen.has(kind):
		seen[kind] = true
		intro_label.text = INTRO[kind]
		intro_t = 5.0


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
	# 먹 물결 (두꺼운 먹 고리 + 안쪽 번짐)
	for rg in rings:
		var c: Vector2 = rg["c"]
		var r: float = rg["r"]
		var fade := clampf(1.0 - r / RING_MAX, 0.0, 1.0)
		world_draw.draw_arc(c, r - RING_THICK * 1.6, 0, TAU, 96, Color(Ink.INK, 0.12 * fade), RING_THICK * 2.0, true)
		world_draw.draw_arc(c, r, 0, TAU, 96, Color(Ink.INK, 0.85 * fade + 0.15), RING_THICK, true)
	# 번짐: 획 자리에 남은 먹물 (점점 옅어진다)
	for tr in trails:
		var a: float = clampf(float(tr["t"]) / float(tr["max"]), 0.0, 1.0)
		world_draw.draw_polyline(tr["pts"], Color(Ink.INK, 0.22 * a + 0.05), 30.0, true)
		world_draw.draw_polyline(tr["pts"], Color(Ink.INK, 0.35 * a), 12.0, true)
	# 먹 탄
	for b in bullets:
		var p: Vector2 = b["p"]
		var dir: Vector2 = b["dir"]
		if b.get("blade", false):
			# 연환의 먹 칼날: 앞으로 휜 반달
			var r: float = b["r"]
			var a := dir.angle()
			Ink.draw_brush(world_draw, Ink.arc_points(p - dir * r * 0.6, r, a - 1.2, a + 1.2, 12), 10.0, Ink.INK)
			continue
		var col := Ink.SEAL if b.get("friendly", false) else Ink.INK
		world_draw.draw_line(p - dir * 26.0, p, Color(col, 0.35), 8.0, true)
		world_draw.draw_colored_polygon(Ink.blob(p, BULLET_R, float(b["age"]) * 20.0, 0.2, 12), col)
	# 한 획 그리는 중 (방패에 걸리면 그 뒤는 흐린 회색 + ✕ 표시)
	if mode == Mode.STROKE:
		var remain := 1.0 - Ink.polyline_length(stroke_pts) / stroke_max
		var res := _shield_cut(stroke_pts)
		var live: PackedVector2Array = res["pts"]
		var blocker: Yokai = res["blocker"]
		if stroke_pts.size() > 1:
			if blocker:
				world_draw.draw_polyline(stroke_pts, Color(Ink.INK, 0.16), 8.0, true) # 끊긴 뒤쪽 (흐리게)
			if live.size() > 1:
				world_draw.draw_polyline(live, Color(Ink.INK, 0.6), 16.0, true) # 반투명 조각이 겹쳐 구슬처럼 보이지 않게 한 줄로
		if blocker:
			var xp := live[live.size() - 1]
			world_draw.draw_line(xp + Vector2(-12, -12), xp + Vector2(12, 12), Ink.SEAL, 5.0, true)
			world_draw.draw_line(xp + Vector2(-12, 12), xp + Vector2(12, -12), Ink.SEAL, 5.0, true)
		var tip := stroke_pts[stroke_pts.size() - 1]
		world_draw.draw_arc(tip, 10.0 + 18.0 * remain, 0, TAU, 32, Color(Ink.SEAL, 0.8), 2.5, true)
		# 실제로 벨 요괴는 붉은 고리, 획을 막을 방패병은 회색 고리
		for e in enemies:
			if not e.is_solid() or live.size() < 2:
				continue
			if e == blocker:
				world_draw.draw_arc(e.position + Vector2(0, -e.radius), e.radius + 10.0, 0, TAU, 24, Color(Ink.INK, 0.45), 3.0, true)
			elif Ink.dist_to_polyline(e.position, live) < e.radius + _cut_radius():
				world_draw.draw_arc(e.position + Vector2(0, -e.radius), e.radius + 10.0, 0, TAU, 24, Ink.SEAL, 3.0, true)


func _update_visuals(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 40.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	var slow_target := 1.0 if mode in [Mode.JUST, Mode.STROKE, Mode.CUT, Mode.CHOOSE] else 0.0
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
	# 같은 자리에 잇달아 뜨는 글씨는 위로 쌓는다
	var now := Time.get_ticks_msec()
	for r in recent_pops:
		if now - int(r["ms"]) < 500 and (r["p"] as Vector2).distance_to(pos) < 160.0:
			pos.y = minf(pos.y, float(r["y"]) - 4.0 - size * 0.5) # 앞 글씨 위쪽 끝보다 위로
	recent_pops = recent_pops.filter(func(r): return now - int(r["ms"]) < 500)
	# 위쪽 점수판과 겹치지 않게
	pos.y = maxf(pos.y, 130.0 + size * 0.5)
	recent_pops.append({"ms": now, "p": pos, "y": pos.y - size * 0.5, "h": 0.0})
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

	intro_label = Ink.label(19, Ink.INK, false)
	intro_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	intro_label.offset_top = -62
	intro_label.offset_bottom = -36
	intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(intro_label)

	boss_name = Ink.label(22, Ink.SEAL, true)
	boss_name.text = "큰 먹도깨비"
	boss_name.set_anchors_preset(Control.PRESET_TOP_WIDE)
	boss_name.offset_top = 76
	boss_name.offset_bottom = 104
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(boss_name)
	boss_bar_bg = ColorRect.new()
	boss_bar_bg.color = Color(Ink.INK, 0.15)
	boss_bar_bg.anchor_left = 0.5
	boss_bar_bg.anchor_right = 0.5
	boss_bar_bg.offset_left = -220
	boss_bar_bg.offset_right = 220
	boss_bar_bg.offset_top = 104
	boss_bar_bg.offset_bottom = 114
	root.add_child(boss_bar_bg)
	boss_bar = ColorRect.new()
	boss_bar.color = Ink.SEAL
	boss_bar.size = Vector2(440, 10)
	boss_bar_bg.add_child(boss_bar)

	help_label = Ink.label(15, Color(Ink.INK, 0.7), false)
	help_label.text = "이동 WASD   베기 클릭   회피 Space·우클릭   공격이 닿기 직전에 피하면 시간이 멈춰요   다시 R"
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -32
	help_label.offset_bottom = -8
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(help_label)

	skill_row = HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 6)
	skill_row.position = Vector2(26, 84)
	skill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(skill_row)

	card_box = CenterContainer.new()
	card_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_box.visible = false
	root.add_child(card_box)

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
	var boss_alive := boss != null and is_instance_valid(boss) and not boss.dying
	boss_name.visible = boss_alive
	boss_bar_bg.visible = boss_alive
	if boss_alive:
		boss_bar.size.x = 440.0 * clampf(float(boss.hp) / boss.max_hp, 0.0, 1.0)
		if boss.is_angry() and not boss_angry_said:
			boss_angry_said = true
			sfx.play("roar", 1.15, 0.0)
			shake = maxf(shake, 10.0)
			_pop("먹도깨비가 성났다!", boss.position + Vector2(0, -130), 34, Ink.SEAL)
			boss_name.text = "큰 먹도깨비 (성남)"
	intro_label.visible = intro_t > 0.0 and mode == Mode.FIGHT
	intro_label.modulate.a = clampf(intro_t, 0.0, 1.0)
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


## 붓 기술 카드 3장
func _open_cards() -> void:
	cards = Skills.draw_cards(skills, hero.hp, 5)
	if cards.is_empty():
		return
	mode = Mode.CHOOSE
	sfx.play("rank", 0.8, -4.0)
	for c in card_box.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	card_box.add_child(vb)
	var title := Ink.label(40, Ink.INK, true)
	title.text = "제 %d 막을 마쳤다 · 붓 기술을 하나 고르세요" % wave
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	vb.add_child(row)
	for i in cards.size():
		row.add_child(_card(i, cards[i]))
	var hint := Ink.label(16, Color(Ink.INK, 0.6), false)
	hint.text = "클릭하거나 1 · 2 · 3 키"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	card_box.visible = true


func _card(i: int, id: String) -> Button:
	var info: Dictionary = Skills.ALL[id]
	var lv := skill_lv(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(250, 300)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(Ink.PAPER, 0.97)
	normal.border_color = Ink.INK
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate()
	hover.border_color = Ink.SEAL
	hover.set_border_width_all(5)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.pressed.connect(_pick_card.bind(i))
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 16
	vb.offset_right = -16
	vb.offset_top = 18
	vb.offset_bottom = -16
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	# 붉은 도장에 새긴 글자
	var seal := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Ink.SEAL
	sb.set_corner_radius_all(4)
	seal.add_theme_stylebox_override("panel", sb)
	seal.custom_minimum_size = Vector2(78, 78)
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(seal)
	var ch := Ink.label(52, Color("f5efe0"), true, false)
	ch.text = info["char"]
	ch.set_anchors_preset(Control.PRESET_FULL_RECT)
	ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(ch)
	var title_l := Ink.label(30, Ink.INK, true, false)
	title_l.text = "%d. %s" % [i + 1, info["name"]]
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title_l)
	var lvl := Ink.label(15, Ink.SEAL, false, false)
	lvl.text = "새 기술" if lv == 0 or id == "heal" else "단계 %d → %d" % [lv, lv + 1]
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lvl)
	var desc := Ink.label(16, Ink.INK, false, false)
	desc.text = Skills.desc_for(id, lv + 1)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size = Vector2(210, 0)
	vb.add_child(desc)
	return b


func _pick_card(i: int) -> void:
	if mode != Mode.CHOOSE or i >= cards.size():
		return
	var id := cards[i]
	if id == "heal":
		hero.hp = mini(5, hero.hp + 2)
	else:
		skills[id] = skill_lv(id) + 1
	sfx.play("just", 1.2, -4.0)
	card_box.visible = false
	mode = Mode.FIGHT
	wave_t = 0.6
	_refresh_skill_row()
	_pop(Skills.ALL[id]["name"] + "!", hero.position + Vector2(0, -90), 36, Ink.SEAL)


## 왼쪽 아래: 모은 기술 도장
func _refresh_skill_row() -> void:
	for c in skill_row.get_children():
		c.queue_free()
	for id in skills:
		var seal := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Ink.SEAL
		sb.set_corner_radius_all(3)
		seal.add_theme_stylebox_override("panel", sb)
		seal.custom_minimum_size = Vector2(34, 34)
		seal.tooltip_text = Skills.ALL[id]["name"]
		skill_row.add_child(seal)
		var ch := Ink.label(20, Color("f5efe0"), true, false)
		ch.text = Skills.ALL[id]["char"]
		ch.set_anchors_preset(Control.PRESET_FULL_RECT)
		ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seal.add_child(ch)
		if skills[id] > 1:
			var lv := Ink.label(12, Ink.INK, false, true)
			lv.text = str(skills[id])
			lv.position = Vector2(24, 18)
			seal.add_child(lv)


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
		"pick_1": [KEY_1, KEY_KP_1], "pick_2": [KEY_2, KEY_KP_2], "pick_3": [KEY_3, KEY_KP_3],
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
