extends Node2D
## 먹 무리 (시험판) — 뱀서류
## 이동만 하면 무기가 알아서 공격한다. 몰려오는 먹 요괴를 쓰러뜨려 먹 구슬을 줍고,
## 레벨업 때 무기·보조 능력 3장 중 1장을 고른다. 10분 버티면 승리.

enum Mode { PLAY, CHOOSE, OVER, WIN }

const RUN_TIME := 600.0
const MAX_ALIVE := 380
const BOSS_TIMES: Array[float] = [300.0, 540.0]
const ELITE_TIMES: Array[float] = [90.0, 210.0, 360.0, 450.0]
const GEM_PICK := 90.0 # 구슬 줍는 거리 (기본)
const BULLET_DMG := 12.0
const SAVE_PATH := "user://best.cfg"
const MOUSE_STOP := 10.0 # 커서와 이만큼 가까우면 멈춤
const MOUSE_SLOW := 70.0 # 커서에 가까워지면 이 거리부터 천천히
var mouse_moving := false

var mode := Mode.PLAY
var paused := false
var t := 0.0 # 흐른 시간
var hero: Hero
var horde: Horde
var fx: Fx
var stains: Fx.Stains
var sfx: Sfx
var camera: Camera2D
var world_draw: Node2D
var paper: Node2D

var hp := 100.0
var max_hp := 100.0
var hurt_acc := 0.0
var hurt_snd := 0.0
var xp := 0
var level := 1
var xp_next := 3
var pending := 0
var kills := 0
var weapons := {"brush": 1} # id → 단계
var passives := {}
var weapon_cd := {}
var shots: Array[Dictionary] = [] # 먹 방울
var stamps: Array[Dictionary] = [] # 찍히기 직전의 낙관
var enemy_shots: Array[Dictionary] = []
var gems: Array[Dictionary] = []
var spawn_acc := 0.0
var spawned_events := {}
var boss: Dictionary = {}
var shake := 0.0
var hitstop := 0.0
var snd_last := {}
var cards: Array[String] = []
var best_time := 0.0

# UI
var xp_fill: ColorRect
var level_label: Label
var time_label: Label
var kill_label: Label
var fps_label: Label
var slowest_ms := 0.0 # 최근 1초 중 가장 느린 프레임
var slow_window: Array[float] = []
var icon_row: HBoxContainer
var boss_bg: ColorRect
var boss_fill: ColorRect
var boss_label: Label
var card_box: CenterContainer
var overlay: CenterContainer
var warn_label: Label
var warn_t := 0.0


func _ready() -> void:
	randomize()
	_setup_input()
	_load_best()
	sfx = Sfx.new()
	add_child(sfx)
	paper = Node2D.new()
	paper.z_index = -30
	paper.draw.connect(_draw_paper)
	add_child(paper)
	stains = Fx.Stains.new()
	stains.z_index = -20
	add_child(stains)
	horde = Horde.new()
	horde.z_index = 5
	add_child(horde)
	hero = Hero.new()
	hero.z_index = 6
	add_child(hero)
	world_draw = Node2D.new()
	world_draw.z_index = 8
	world_draw.draw.connect(_draw_world)
	add_child(world_draw)
	fx = Fx.new()
	fx.z_index = 20
	fx.stains = stains
	add_child(fx)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	_build_ui()
	_refresh_icons()


# ───────────── 매 프레임 ─────────────

func _process(delta: float) -> void:
	# 최근 1초 프레임 시간 기록 (화면 FPS 표시용)
	slow_window.append(delta)
	if slow_window.size() > 120:
		slow_window.pop_front()
	slowest_ms = slow_window.max() * 1000.0
	if mode in [Mode.OVER, Mode.WIN]:
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		fx.step(delta)
		return
	if Input.is_action_just_pressed("pause") and mode == Mode.PLAY:
		paused = not paused
		_show_pause(paused)
	if paused:
		return
	if mode == Mode.CHOOSE:
		for i in cards.size():
			if Input.is_action_just_pressed("pick_%d" % (i + 1)):
				_pick(i)
		return
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	if hitstop > 0.0:
		hitstop -= delta
		_update_view(delta)
		return

	t += delta
	hero.speed_mul = 1.0 + 0.08 * _lv("sandal")
	hero.step(delta, _move_input())
	_spawn_step(delta)
	horde.step(delta, hero.position)
	_weapons_step(delta)
	_shots_step(delta)
	_enemy_shots_step(delta)
	_contact_damage(delta)
	_gems_step(delta)
	horde.cleanup()
	fx.step(delta)
	stains.step(delta)
	hurt_snd = maxf(0.0, hurt_snd - delta)
	warn_t = maxf(0.0, warn_t - delta)
	if pending > 0 and mode == Mode.PLAY:
		_open_cards()
	if t >= RUN_TIME and mode == Mode.PLAY:
		_finish(true)
	_update_view(delta)



## 이동: 키보드가 우선, 키보드를 안 누르고 마우스 왼쪽 버튼을 누르고 있으면 커서 쪽으로
func _move_input() -> Vector2:
	var key := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	mouse_moving = false
	if key != Vector2.ZERO or not Input.is_action_pressed("move_mouse"):
		return key
	mouse_moving = true
	return mouse_dir(get_global_mouse_position())


## 커서까지의 방향. 커서 바로 근처에서는 천천히 멈춘다 (도착해서 덜덜 떨지 않게)
func mouse_dir(target: Vector2) -> Vector2:
	var d := target - hero.position
	var dist := d.length()
	if dist < MOUSE_STOP:
		return Vector2.ZERO
	return d / dist * clampf((dist - MOUSE_STOP) / MOUSE_SLOW, 0.25, 1.0)

func _lv(id: String) -> int:
	return int(weapons.get(id, passives.get(id, 0)))


func _dmg_mul() -> float:
	return 1.0 + 0.1 * _lv("ink")


func _cd_mul() -> float:
	return maxf(0.45, 1.0 - 0.08 * _lv("hair"))


func _area_mul() -> float:
	return 1.0 + 0.1 * _lv("stone")


func _play(sound: String, pitch := 1.0, vol := 0.0, gap := 0.05) -> void:
	# 같은 소리가 한 번에 수십 개 겹치지 않게
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(snd_last.get(sound, -1.0)) < gap:
		return
	snd_last[sound] = now
	sfx.play(sound, pitch, vol)


# ───────────── 요괴 나오기 ─────────────

func _spawn_step(delta: float) -> void:
	var hp_mul := 1.0 + t / 200.0
	var rate := 1.3 + t / 22.0 # 초당 마릿수
	spawn_acc += delta * rate
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if horde.list.size() < MAX_ALIVE:
			horde.spawn(_pick_kind(), _edge_point(), hp_mul)
	# 정해진 때 나오는 것들
	for et in ELITE_TIMES:
		if t >= et and not spawned_events.has("elite%d" % int(et)):
			spawned_events["elite%d" % int(et)] = true
			horde.spawn("elite", _edge_point(), hp_mul)
			_warn("붉은 낙관의 정예 요괴가 나타났다!")
	for bt in BOSS_TIMES:
		if t >= bt and not spawned_events.has("boss%d" % int(bt)):
			spawned_events["boss%d" % int(bt)] = true
			boss = horde.spawn("boss", _edge_point(), 1.0 + (bt - 300.0) / 120.0)
			boss["shoot_cd"] = 3.0
			_warn("큰 먹도깨비가 나타났다!")
			_play("roar", 1.0, 0.0, 0.0)
			shake = 10.0
	if t >= 150.0 and not spawned_events.has("ring"):
		# 포위: 사방에서 한꺼번에
		spawned_events["ring"] = true
		for i in 48:
			horde.spawn("imp", hero.position + Vector2.from_angle(TAU * i / 48.0) * 560.0, hp_mul)
		_warn("포위당했다!")
	if t >= 420.0 and not spawned_events.has("bats"):
		spawned_events["bats"] = true
		var side := Vector2.from_angle(randf() * TAU)
		for i in 60:
			horde.spawn("bat", hero.position + side * 700.0 + side.orthogonal() * randf_range(-350, 350), hp_mul)
		_warn("먹 박쥐 떼가 몰려온다!")


func _pick_kind() -> String:
	var w := {"imp": 10.0}
	if t > 45.0:
		w["bat"] = 4.0
	if t > 70.0:
		w["ogre"] = 5.0 + t / 60.0
	if t > 180.0:
		w["brute"] = 1.0 + t / 150.0
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "imp"


## 화면 바로 바깥 둘레에서
func _edge_point() -> Vector2:
	var half := get_viewport_rect().size * 0.5
	var a := randf() * TAU
	return hero.position + Vector2(cos(a) * (half.x + 70.0), sin(a) * (half.y + 70.0))


# ───────────── 무기 ─────────────

func _weapons_step(delta: float) -> void:
	for id in weapons:
		if id == "orbit":
			continue
		weapon_cd[id] = float(weapon_cd.get(id, 0.3)) - delta
		if float(weapon_cd[id]) <= 0.0:
			weapon_cd[id] = _fire(id) * _cd_mul()
	if weapons.has("orbit"):
		_orbit_step(delta)
	# 찍히기 직전의 낙관
	var keep: Array[Dictionary] = []
	for s in stamps:
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) > 0.0:
			keep.append(s)
			continue
		var p: Vector2 = s["p"]
		fx.seal(p, s["r"])
		shake = maxf(shake, 5.0)
		_play("slam", 1.4, -6.0, 0.08)
		for e in horde.near(p, s["r"]):
			_hit(e, s["dmg"], p, 140.0)
	stamps = keep


## 무기를 한 번 쓰고, 다음까지 기다릴 시간을 돌려준다
func _fire(id: String) -> float:
	var lv := _lv(id)
	var dm := _dmg_mul()
	var am := _area_mul()
	match id:
		"brush":
			var reach := (115.0 + 14.0 * (lv - 1) + (40.0 if lv >= 5 else 0.0)) * am
			var dmg := (14.0 + 5.0 * (lv - 1)) * dm
			var dirs := [hero.facing]
			if lv >= 3:
				dirs.append(-hero.facing)
			for d in dirs:
				_brush_swipe(d, reach, dmg)
			hero.swing_t = 0.16
			hero.swing_dir = -hero.swing_dir
			_play("swing", randf_range(0.9, 1.1), -5.0)
			return 0.95
		"drop":
			var count := 1 + (1 if lv >= 3 else 0) + (1 if lv >= 5 else 0)
			var targets := _nearest(hero.position, 700.0, count)
			for i in count:
				var dir := Vector2.from_angle(randf() * TAU)
				if i < targets.size():
					dir = ((targets[i]["p"] as Vector2) + Vector2(0, -float(targets[i]["r"])) - (hero.position + Vector2(0, -20))).normalized()
				shots.append({"p": hero.position + Vector2(0, -20), "dir": dir, "dmg": (9.0 + 4.0 * (lv - 1)) * dm,
						"pierce": 2 if lv >= 4 else 1, "life": 1.3, "hit": {}})
			_play("shoot", randf_range(1.2, 1.4), -9.0)
			return 0.85
		"seal":
			var count := 1 + (1 if lv >= 3 else 0) + (1 if lv >= 5 else 0)
			var cand := horde.near(hero.position, 460.0)
			for i in count:
				if cand.is_empty():
					break
				var e: Dictionary = cand.pick_random()
				stamps.append({"p": e["p"], "t": 0.45, "r": (80.0 + 14.0 * (lv - 1)) * am, "dmg": (24.0 + 10.0 * (lv - 1)) * dm})
			return 2.6
		"stroke":
			_auto_stroke(lv, dm, am)
			return maxf(1.6, 4.2 - 0.4 * (lv - 1))
	return 1.0


func _brush_swipe(dir: Vector2, reach: float, dmg: float) -> void:
	var c := hero.position + Vector2(0, -20)
	var a := dir.angle()
	var half := 1.15
	fx.slash_arc(c, reach * 0.75, a - half, a + half, 14.0)
	var hit_any := false
	for e in horde.near(c, reach):
		var d: Vector2 = (e["p"] as Vector2) + Vector2(0, -float(e["r"])) - c
		if absf(angle_difference(a, d.angle())) < half + 0.25:
			_hit(e, dmg, c, 220.0)
			hit_any = true
	if hit_any:
		_play("hit", randf_range(0.9, 1.1), -4.0)


## 한 획: 16방향 중 요괴가 가장 많이 걸리는 쪽으로 긴 획을 긋는다
func _auto_stroke(lv: int, dm: float, am: float) -> void:
	var length := (520.0 + 70.0 * (lv - 1) + (150.0 if lv >= 5 else 0.0)) * am
	var width := (22.0 + (12.0 if lv >= 5 else 0.0)) * am
	var cand := horde.near(hero.position, length)
	if cand.is_empty():
		return
	var best_dir := Vector2.RIGHT
	var best_n := -1
	var start := hero.position + Vector2(0, -16)
	for i in 16:
		var d := Vector2.from_angle(TAU * i / 16.0)
		var n := 0
		for e in cand:
			var q := Geometry2D.get_closest_point_to_segment(e["p"], start, start + d * length)
			if q.distance_to(e["p"]) < width + float(e["r"]):
				n += 1
		if n > best_n:
			best_n = n
			best_dir = d
	# 살짝 휘어진 붓 획
	var pts := PackedVector2Array()
	var bend := best_dir.orthogonal() * randf_range(-40.0, 40.0)
	for k in 25:
		var u := k / 24.0
		pts.append(start + best_dir * length * u + bend * sin(u * PI))
	fx.stroke(pts, width * 1.5, 1.0, Ink.INK, true)
	fx.stroke(pts, 4.0, 0.1, Color(1, 1, 1, 0.95))
	_play("cut", 1.0, -3.0, 0.0)
	var dmg := (40.0 + 14.0 * (lv - 1) + (10.0 if lv >= 4 else 0.0)) * dm
	var n := 0
	for e in cand:
		if Ink.dist_to_polyline(e["p"], pts) < width + float(e["r"]):
			_hit(e, dmg, e["p"] - best_dir * 30.0, 80.0)
			n += 1
	if n >= 5:
		hitstop = 0.05
		shake = maxf(shake, 7.0)
		_pop("%d연 베기!" % n, hero.position + best_dir * 120.0 + Vector2(0, -60), 30 + mini(n, 20))


func _orbit_step(delta: float) -> void:
	var lv := _lv("orbit")
	var count: int = [2, 3, 3, 4, 5][lv - 1]
	var radius := (88.0 + (22.0 if lv >= 3 else 0.0)) * _area_mul()
	var speed := 3.0 + (1.4 if lv >= 5 else 0.0)
	var dmg := (7.0 + 2.5 * (lv - 1)) * _dmg_mul()
	var c := hero.position + Vector2(0, -18)
	for i in count:
		var p := c + Vector2.from_angle(t * speed + TAU * i / count) * radius
		for e in horde.near(p, 16.0):
			var key := "orb_cd"
			if float(e.get(key, 0.0)) > t:
				continue
			e[key] = t + 0.45
			_hit(e, dmg, c, 160.0)


func _nearest(p: Vector2, radius: float, count: int) -> Array:
	var cand := horde.near(p, radius)
	cand.sort_custom(func(a, b): return (a["p"] as Vector2).distance_squared_to(p) < (b["p"] as Vector2).distance_squared_to(p))
	return cand.slice(0, count)


func _shots_step(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for s in shots:
		s["p"] = (s["p"] as Vector2) + (s["dir"] as Vector2) * 560.0 * delta
		s["life"] = float(s["life"]) - delta
		if float(s["life"]) <= 0.0:
			continue
		var alive := true
		for e in horde.near(s["p"], 10.0):
			if e.get("dead", false) or s["hit"].has(e["id"]):
				continue
			if ((e["p"] as Vector2) + Vector2(0, -float(e["r"]))).distance_to(s["p"]) < float(e["r"]) + 9.0:
				_hit(e, s["dmg"], s["p"] - (s["dir"] as Vector2) * 20.0, 120.0)
				s["pierce"] = int(s["pierce"]) - 1
				s["hit"][e["id"]] = true
				if int(s["pierce"]) <= 0:
					alive = false
					break
		if alive:
			keep.append(s)
	shots = keep


## 피해를 준다. 쓰러지면 구슬을 떨어뜨린다
func _hit(e: Dictionary, dmg: float, from: Vector2, knock: float) -> void:
	if e.get("dead", false):
		return
	var dir: Vector2 = (e["p"] as Vector2) - from
	if horde.hurt(e, dmg, dir, knock):
		_kill(e, dir)
	elif randf() < 0.3:
		fx.splash((e["p"] as Vector2) + Vector2(0, -float(e["r"])), dir, 3, 220.0, 0.6)


func _kill(e: Dictionary, dir: Vector2) -> void:
	horde.remove(e)
	kills += 1
	var p: Vector2 = e["p"]
	var r: float = e["r"]
	var big: bool = e["kind"] in ["elite", "boss", "brute"]
	fx.splash(p + Vector2(0, -r), dir.orthogonal(), 5 + (14 if big else 0), 300.0 + r * 6.0, 2.5)
	if big or randf() < 0.35:
		stains.pool(p, r * 0.9)
	else:
		stains.add(p, r * 0.7, Ink.INK)
	_play("die", randf_range(0.9, 1.2), -8.0, 0.06)
	var v: int = e["xp"]
	if e["kind"] == "elite":
		# 정예: 보따리 = 바로 레벨업 한 번 + 체력 조금
		pending += 1
		hp = minf(max_hp, hp + 20.0)
		_pop("보따리!", p + Vector2(0, -60), 30)
	if e["kind"] == "boss":
		boss = {}
		shake = 16.0
		hitstop = 0.2
		_play("gong", 1.0, 0.0, 0.0)
		_pop("큰 먹도깨비를 쓰러뜨렸다!", p + Vector2(0, -90), 34)
		pending += 2
	gems.append({"p": p, "v": v, "pull": false})


# ───────────── 적 공격 / 내가 맞음 ─────────────

func _contact_damage(delta: float) -> void:
	var dps := 0.0
	for e in horde.near(hero.position, 40.0):
		if e.get("dead", false):
			continue
		if (e["p"] as Vector2).distance_to(hero.position) < float(e["r"]) + Hero.RADIUS:
			dps += float(e["dmg"])
	# 보스는 가끔 부채꼴 먹 탄을 쏜다
	if not boss.is_empty() and not boss.get("dead", false):
		boss["shoot_cd"] = float(boss["shoot_cd"]) - delta
		if float(boss["shoot_cd"]) <= 0.0:
			boss["shoot_cd"] = 3.2
			var base: Vector2 = (hero.position - (boss["p"] as Vector2)).normalized()
			for i in 9:
				enemy_shots.append({"p": (boss["p"] as Vector2) + Vector2(0, -50), "dir": base.rotated((i - 4) * 0.2), "life": 3.0})
			_play("shoot", 0.7, -2.0, 0.0)
	if dps > 0.0:
		_damage(dps * delta)


func _enemy_shots_step(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for s in enemy_shots:
		s["p"] = (s["p"] as Vector2) + (s["dir"] as Vector2) * 300.0 * delta
		s["life"] = float(s["life"]) - delta
		if (s["p"] as Vector2).distance_to(hero.position + Vector2(0, -16)) < 22.0:
			_damage(BULLET_DMG)
			fx.splash(s["p"], s["dir"], 6, 220.0)
			continue
		if float(s["life"]) > 0.0:
			keep.append(s)
	enemy_shots = keep


func _damage(amount: float) -> void:
	hp -= amount
	hurt_acc += amount
	if hurt_acc >= 4.0:
		hurt_acc = 0.0
		hero.hurt_t = 0.3
		shake = maxf(shake, 4.0)
		fx.splash(hero.position + Vector2(0, -20), Vector2.UP, 4, 200.0, 1.5, Ink.SEAL)
		if hurt_snd <= 0.0:
			hurt_snd = 0.35
			sfx.play("hurt", randf_range(0.95, 1.05), -4.0)
	if hp <= 0.0:
		hp = 0.0
		_finish(false)


# ───────────── 먹 구슬 / 레벨업 ─────────────

func _gems_step(delta: float) -> void:
	var pick := GEM_PICK * (1.0 + 0.3 * _lv("pull"))
	var keep: Array[Dictionary] = []
	var hp_pos := hero.position + Vector2(0, -16)
	for g in gems:
		var p: Vector2 = g["p"]
		var d := p.distance_to(hp_pos)
		if g["pull"] or d < pick:
			g["pull"] = true
			g["sp"] = float(g.get("sp", 120.0)) + 1600.0 * delta
			p = p.move_toward(hp_pos, float(g["sp"]) * delta)
			g["p"] = p
			if p.distance_to(hp_pos) < 14.0:
				_gain_xp(g["v"])
				continue
		keep.append(g)
	gems = keep
	# 구슬이 너무 많으면 먼 것끼리 합친다
	if gems.size() > 450:
		var far := gems.filter(func(g): return (g["p"] as Vector2).distance_to(hero.position) > 900.0)
		if far.size() > 20:
			var total := 0
			for g in far:
				total += int(g["v"])
				gems.erase(g)
			gems.append({"p": far[0]["p"], "v": total, "pull": false})


func _gain_xp(v: int) -> void:
	xp += v
	_play("brush", 1.6, -14.0, 0.03)
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		pending += 1
		xp_next = int(3.0 + level * 3.0 + level * level * 0.3) # 초반엔 레벨업이 빠르게


func _open_cards() -> void:
	cards = Upgrades.draw_cards(weapons, passives)
	if cards.is_empty():
		pending = 0
		hp = minf(max_hp, hp + 30.0)
		return
	mode = Mode.CHOOSE
	sfx.play("rank", 1.0, -3.0)
	for c in card_box.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	card_box.add_child(vb)
	var title := Ink.label(38, Ink.INK, true)
	title.text = "레벨 %d! 하나를 고르세요" % level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vb.add_child(row)
	for i in cards.size():
		row.add_child(_card(i, cards[i]))
	var hint := Ink.label(16, Color(Ink.INK, 0.6), false)
	hint.text = "클릭하거나 1 · 2 · 3 키"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	card_box.visible = true


func _card(i: int, id: String) -> Button:
	var info := Upgrades.info(id)
	var lv := _lv(id)
	var is_weapon := Upgrades.WEAPONS.has(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(240, 290)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Ink.PAPER
	normal.border_color = Ink.INK
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate()
	hover.border_color = Ink.SEAL
	hover.set_border_width_all(5)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, normal if st == "normal" else hover)
	b.pressed.connect(_pick.bind(i))
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 14
	vb.offset_right = -14
	vb.offset_top = 16
	vb.offset_bottom = -14
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var seal := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Ink.SEAL if is_weapon else Ink.INK
	sb.set_corner_radius_all(4)
	seal.add_theme_stylebox_override("panel", sb)
	seal.custom_minimum_size = Vector2(72, 72)
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(seal)
	var ch := Ink.label(46, Color("f5efe0"), true, false)
	ch.text = info["char"]
	ch.set_anchors_preset(Control.PRESET_FULL_RECT)
	ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(ch)
	var title_l := Ink.label(28, Ink.INK, true, false)
	title_l.text = "%d. %s" % [i + 1, info["name"]]
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title_l)
	var tag := Ink.label(15, Ink.SEAL if is_weapon else Ink.INK, false, false)
	tag.text = ("새 무기" if is_weapon else "새 보조 능력") if lv == 0 else "%d단계 → %d단계" % [lv, lv + 1]
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tag)
	var d := Ink.label(16, Ink.INK, false, false)
	d.text = Upgrades.desc(id, lv + 1)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.custom_minimum_size = Vector2(205, 0)
	vb.add_child(d)
	return b


func _pick(i: int) -> void:
	if mode != Mode.CHOOSE or i >= cards.size():
		return
	var id := cards[i]
	if Upgrades.WEAPONS.has(id):
		weapons[id] = _lv(id) + 1
	else:
		passives[id] = _lv(id) + 1
		if id == "robe":
			max_hp = 100.0 * (1.0 + 0.2 * _lv("robe"))
			hp = max_hp
	pending -= 1
	card_box.visible = false
	mode = Mode.PLAY
	sfx.play("just", 1.3, -6.0)
	_refresh_icons()


# ───────────── 끝 ─────────────

func _finish(won: bool) -> void:
	mode = Mode.WIN if won else Mode.OVER
	hero.dead = not won
	hero.queue_redraw()
	sfx.play("gong" if won else "over", 1.0, 0.0)
	var new_best := t > best_time
	if new_best:
		best_time = t
		var cfg := ConfigFile.new()
		cfg.set_value("best", "time", best_time)
		cfg.save(SAVE_PATH)
	var names := []
	for id in weapons:
		names.append("%s %d" % [Upgrades.info(id)["name"], weapons[id]])
	_panel([
		["해냈다! 10분을 버텼다" if won else "먹이 다 번졌다", 50, Ink.SEAL if won else Ink.INK, true],
		["버틴 시간 %s   ·   레벨 %d   ·   쓰러뜨린 요괴 %d" % [_clock(t), level, kills], 20, Ink.INK, false],
		["가장 오래 버틴 시간 %s%s" % [_clock(best_time), "  (신기록!)" if new_best else ""], 18, Ink.SEAL if new_best else Ink.INK, false],
		["무기: " + ", ".join(names), 17, Ink.INK, false],
		["R 키를 눌러 다시", 17, Color(Ink.INK, 0.6), false],
	])


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_time = cfg.get_value("best", "time", 0.0)


func _clock(sec: float) -> String:
	return "%02d:%02d" % [int(sec) / 60, int(sec) % 60]


# ───────────── 그리기 ─────────────

func _update_view(delta: float) -> void:
	camera.position = camera.position.lerp(hero.position, 1.0 - exp(-8.0 * delta))
	shake = maxf(0.0, shake - delta * 40.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	var size := get_viewport_rect().size
	horde.view = Rect2(camera.position - size * 0.5, size)
	if stains.view != horde.view.grow(0) and Engine.get_process_frames() % 6 == 0:
		stains.view = horde.view
		stains.queue_redraw()
	paper.queue_redraw()
	world_draw.queue_redraw()
	_update_hud()


func _draw_paper() -> void:
	var size := get_viewport_rect().size
	var r := Rect2(camera.position - size * 0.5 - Vector2(64, 64), size + Vector2(128, 128))
	paper.draw_rect(r, Ink.PAPER)
	# 화선지 결: 256px 칸마다 같은 무늬 (카메라가 움직여도 땅에 붙어 있게)
	var tile := 256.0
	var x0 := int(floorf(r.position.x / tile))
	var y0 := int(floorf(r.position.y / tile))
	for tx in range(x0, int(r.end.x / tile) + 1):
		for ty in range(y0, int(r.end.y / tile) + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector2i(tx, ty))
			for i in 10:
				var p := Vector2(tx * tile + rng.randf() * tile, ty * tile + rng.randf() * tile)
				paper.draw_line(p, p + Vector2.from_angle(rng.randf_range(-0.4, 0.4)) * rng.randf_range(20, 60), Color(Ink.PAPER_DARK, 0.8), 1.0, true)


func _draw_world() -> void:
	# 찍히기 직전의 낙관 자리
	for s in stamps:
		var k := 1.0 - float(s["t"]) / 0.45
		var rr: float = float(s["r"]) * 0.5
		world_draw.draw_rect(Rect2((s["p"] as Vector2) - Vector2(rr, rr), Vector2(rr, rr) * 2.0), Color(Ink.SEAL, 0.15 + 0.3 * k), false, 3.0)
	# 먹 구슬 (작은 건 먹방울, 큰 건 붉은 구슬)
	for g in gems:
		var p: Vector2 = g["p"]
		var v: int = g["v"]
		var r := 4.0 if v <= 1 else (6.0 if v < 5 else 9.0)
		world_draw.draw_circle(p, r, Ink.INK if v < 5 else Ink.SEAL, true, -1.0, true)
		world_draw.draw_circle(p + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.5), true, -1.0, true)
	# 먹 방울
	for s in shots:
		var p: Vector2 = s["p"]
		world_draw.draw_line(p - (s["dir"] as Vector2) * 22.0, p, Color(Ink.INK, 0.35), 7.0, true)
		world_draw.draw_colored_polygon(Ink.blob(p, 8.0, float(s["life"]) * 20.0, 0.2, 10), Ink.INK)
	# 먹 고리
	if weapons.has("orbit"):
		var lv := _lv("orbit")
		var count: int = [2, 3, 3, 4, 5][lv - 1]
		var radius := (88.0 + (22.0 if lv >= 3 else 0.0)) * _area_mul()
		var speed := 3.0 + (1.4 if lv >= 5 else 0.0)
		var c := hero.position + Vector2(0, -18)
		for i in count:
			var a := t * speed + TAU * i / count
			var p := c + Vector2.from_angle(a) * radius
			world_draw.draw_line(p, p - Vector2.from_angle(a + PI * 0.5) * 18.0, Color(Ink.INK, 0.3), 9.0, true)
			world_draw.draw_colored_polygon(Ink.blob(p, 12.0, a * 2.0, 0.15, 14), Ink.INK)
	# 적 먹 탄
	for s in enemy_shots:
		world_draw.draw_colored_polygon(Ink.blob(s["p"], 9.0, float(s["life"]) * 15.0, 0.2, 10), Ink.SEAL)
	# 마우스로 걷는 중이면 가는 곳에 작은 먹 고리
	if mouse_moving:
		var mp := get_global_mouse_position()
		world_draw.draw_arc(mp, 12.0, 0, TAU, 20, Color(Ink.INK, 0.45), 3.0, true)
		world_draw.draw_circle(mp, 3.0, Color(Ink.SEAL, 0.8), true, -1.0, true)
	# 아이 체력 막대
	var hb := Rect2(hero.position + Vector2(-24, 10), Vector2(48, 6))
	world_draw.draw_rect(hb, Color(Ink.INK, 0.2))
	world_draw.draw_rect(Rect2(hb.position, Vector2(hb.size.x * hp / max_hp, hb.size.y)), Ink.SEAL)


func _pop(text: String, pos: Vector2, size: int) -> void:
	var l := Ink.label(size, Ink.INK, true)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(520, size + 20)
	l.position = pos - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	l.z_index = 50
	l.scale = Vector2(1.5, 1.5)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


func _warn(text: String) -> void:
	warn_label.text = text
	warn_t = 3.0


# ───────────── UI ─────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	# 위쪽 경험치 막대
	var xp_bg := ColorRect.new()
	xp_bg.color = Color(Ink.INK, 0.12)
	xp_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	xp_bg.offset_bottom = 12
	root.add_child(xp_bg)
	xp_fill = ColorRect.new()
	xp_fill.color = Ink.INK
	xp_fill.size = Vector2(0, 12)
	xp_bg.add_child(xp_fill)
	level_label = Ink.label(18, Ink.INK, false)
	level_label.position = Vector2(16, 16)
	root.add_child(level_label)
	time_label = Ink.label(40, Ink.INK, true)
	time_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	time_label.offset_top = 16
	time_label.offset_bottom = 64
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(time_label)
	kill_label = Ink.label(18, Ink.INK, false)
	kill_label.anchor_left = 1.0
	kill_label.anchor_right = 1.0
	kill_label.offset_left = -220
	kill_label.offset_right = -16
	kill_label.offset_top = 16
	kill_label.offset_bottom = 40
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(kill_label)
	fps_label = Ink.label(14, Color(Ink.INK, 0.65), false)
	fps_label.anchor_left = 1.0
	fps_label.anchor_right = 1.0
	fps_label.offset_left = -520
	fps_label.offset_right = -16
	fps_label.offset_top = 42
	fps_label.offset_bottom = 62
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(fps_label)
	icon_row = HBoxContainer.new()
	icon_row.position = Vector2(16, 44)
	icon_row.add_theme_constant_override("separation", 5)
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon_row)
	warn_label = Ink.label(26, Ink.SEAL, true)
	warn_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	warn_label.offset_top = 70
	warn_label.offset_bottom = 104
	warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(warn_label)
	boss_label = Ink.label(20, Ink.SEAL, true)
	boss_label.text = "큰 먹도깨비"
	boss_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	boss_label.offset_top = -64
	boss_label.offset_bottom = -40
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(boss_label)
	boss_bg = ColorRect.new()
	boss_bg.color = Color(Ink.INK, 0.15)
	boss_bg.anchor_left = 0.5
	boss_bg.anchor_right = 0.5
	boss_bg.anchor_top = 1.0
	boss_bg.anchor_bottom = 1.0
	boss_bg.offset_left = -240
	boss_bg.offset_right = 240
	boss_bg.offset_top = -36
	boss_bg.offset_bottom = -24
	root.add_child(boss_bg)
	boss_fill = ColorRect.new()
	boss_fill.color = Ink.SEAL
	boss_fill.size = Vector2(480, 12)
	boss_bg.add_child(boss_fill)
	var help := Ink.label(14, Color(Ink.INK, 0.6), false)
	help.text = "이동 WASD·방향키 또는 마우스 왼쪽 버튼을 누른 채로 (공격은 저절로)   멈춤 Esc   다시 R"
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -22
	help.offset_bottom = -4
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(help)
	card_box = CenterContainer.new()
	card_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_box.visible = false
	root.add_child(card_box)
	overlay = CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	root.add_child(overlay)


func _update_hud() -> void:
	xp_fill.size.x = get_viewport_rect().size.x * clampf(float(xp) / xp_next, 0.0, 1.0)
	level_label.text = "레벨 %d" % level
	time_label.text = _clock(t)
	kill_label.text = "쓰러뜨린 요괴 %d" % kills
	# FPS: 1초 평균과 최근 1초 중 가장 느린 프레임
	fps_label.text = "FPS %d   (가장 느린 프레임 %.0fms)   요괴 %d · 먹 자국 %d" % [Engine.get_frames_per_second(), slowest_ms, horde.list.size(), stains.marks.size()]
	fps_label.add_theme_color_override("font_color", Ink.SEAL if Engine.get_frames_per_second() < 55 else Color(Ink.INK, 0.65))
	warn_label.visible = warn_t > 0.0
	warn_label.modulate.a = clampf(warn_t, 0.0, 1.0)
	var boss_alive: bool = not boss.is_empty() and not boss.get("dead", false)
	boss_label.visible = boss_alive
	boss_bg.visible = boss_alive
	if boss_alive:
		boss_fill.size.x = 480.0 * clampf(float(boss["hp"]) / float(boss["max"]), 0.0, 1.0)


## 왼쪽 위: 가진 무기(붉은 도장)와 보조 능력(먹 도장)
func _refresh_icons() -> void:
	for c in icon_row.get_children():
		c.queue_free()
	for group in [weapons, passives]:
		for id in group:
			var seal := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Ink.SEAL if is_same(group, weapons) else Ink.INK
			sb.set_corner_radius_all(3)
			seal.add_theme_stylebox_override("panel", sb)
			seal.custom_minimum_size = Vector2(32, 32)
			icon_row.add_child(seal)
			var ch := Ink.label(19, Color("f5efe0"), true, false)
			ch.text = Upgrades.info(id)["char"]
			ch.set_anchors_preset(Control.PRESET_FULL_RECT)
			ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			seal.add_child(ch)
			var lv := Ink.label(12, Ink.INK, false, true)
			lv.text = str(group[id])
			lv.position = Vector2(23, 17)
			seal.add_child(lv)


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


func _show_pause(p: bool) -> void:
	if not p:
		overlay.visible = false
		return
	_panel([["잠시 멈춤", 44, Ink.INK, true], ["Esc 계속   ·   R 처음부터", 18, Color(Ink.INK, 0.6), false]])


func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"pause": [KEY_ESCAPE], "restart": [KEY_R],
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
	# 마우스 왼쪽 버튼을 누르고 있으면 커서 쪽으로 걷기
	if not InputMap.has_action("move_mouse"):
		InputMap.add_action("move_mouse")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("move_mouse", mb)
