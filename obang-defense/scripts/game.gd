extends Node2D
## 오방 결계 (시험판)
## 길을 따라 오는 도깨비를 오행 타워로 막는다. 타워는 이웃에 따라 서로 살리거나(상생) 깨뜨린다(상극).
## 웨이브가 끝나면 카드 3장 중 1장(부적·강화·엽전)을 고른다. 15웨이브를 버티면 승리.

enum Phase { BUILD, FIGHT, CHOOSE, OVER, WIN }

const TILE := 64.0
const COLS := 14
const ROWS := 9
const ORIGIN := Vector2(24, 92)
const PATH_PTS: Array[Vector2i] = [Vector2i(-1, 1), Vector2i(3, 1), Vector2i(3, 6), Vector2i(7, 6), Vector2i(7, 2), Vector2i(11, 2), Vector2i(11, 7), Vector2i(14, 7)]
## 결계 자리: 모양이 다른 묶음 (2×3, 지그재그, T자, 일자). 다섯 칸 이상 이어진 묶음이 있어야 오행 순환을 만들 수 있다
const SLOTS: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, 3), Vector2i(2, 3), Vector2i(1, 4), Vector2i(2, 4),
	Vector2i(4, 3), Vector2i(5, 3), Vector2i(5, 4), Vector2i(6, 4), Vector2i(6, 5),
	Vector2i(8, 4), Vector2i(9, 4), Vector2i(10, 4), Vector2i(9, 3),
	Vector2i(12, 3), Vector2i(12, 4), Vector2i(12, 5),
]
const EXTRA_SLOTS: Array[Vector2i] = [Vector2i(5, 5), Vector2i(9, 5), Vector2i(13, 4)]
const WAVES := 15
const TOWER_COST := 50
const MOVE_COST := 10
const START_COINS := 120
const LIVES := 20
const ENEMY := {
	"imp": {"hp": 24.0, "spd": 78.0, "r": 13.0, "reward": 2, "leak": 1},
	"ghost": {"hp": 50.0, "spd": 52.0, "r": 17.0, "reward": 3, "leak": 1},
	"big": {"hp": 480.0, "spd": 34.0, "r": 30.0, "reward": 25, "leak": 5},
}

var phase := Phase.BUILD
var wave := 0 # 끝낸 웨이브 수
var coins := START_COINS
var lives := LIVES
var t := 0.0
var speed := 1.0
var rng := RandomNumberGenerator.new()

var slots: Array[Vector2i] = []
var towers := {} # Vector2i → {el, lv, cd, pop, aim, swing}
var ev := {"mults": {}, "links": [], "chains": [], "sad": {}} # 이웃 계산 결과
var talismans := {}
var free_towers: Array[int] = [0, 0, 0, 0, 0]
var free_move := true

var enemies: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var fxs: Array[Dictionary] = []
var parts: Array[Dictionary] = []
var spawn_queue: Array = []
var spawn_t := 0.0
var plan: Array = [] # plan[w] = [{kind, n, el}]

var held := -1 # 들고 있는 기운 (-1 = 없음)
var moving_from := Vector2i(-99, -99) # 옮기는 중인 타워의 원래 자리
var hover := Vector2i(-99, -99)
var hover_override := Vector2i(-99, -99) # 테스트용 (실제 마우스를 움직이지 않고 미리보기 확인)
var cards: Array[Dictionary] = []
var shake := 0.0

var path_pts := PackedVector2Array()
var path_len := 0.0
var path_tiles := {}
var deco: Array[Dictionary] = []

var sfx: Sfx
var font_b: SystemFont
var font_r: SystemFont
# UI
var ui: Control
var stat_label: Label
var next_label: RichTextLabel
var shop_btns: Array[Button] = []
var start_btn: Button
var speed_btn: Button
var tal_label: Label
var tip_label: Label
var card_box: CenterContainer
var card_dim: ColorRect
var overlay: CenterContainer


func _ready() -> void:
	rng.randomize()
	font_b = El.font(true)
	font_r = El.font(false)
	sfx = Sfx.new()
	add_child(sfx)
	slots.assign(SLOTS)
	_build_path()
	_build_deco()
	_make_plan()
	_setup_input()
	_build_ui()
	_refresh_ui()


# ───────────── 맵 ─────────────

func tile_center(c: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * TILE


func tile_at(p: Vector2) -> Vector2i:
	var q := (p - ORIGIN) / TILE
	return Vector2i(int(floorf(q.x)), int(floorf(q.y)))


func _build_path() -> void:
	for i in PATH_PTS.size():
		path_pts.append(tile_center(PATH_PTS[i]))
		if i > 0:
			var a := PATH_PTS[i - 1]
			var b := PATH_PTS[i]
			var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
			var c := a
			while c != b:
				path_tiles[c] = true
				c += step
			path_tiles[b] = true
	for i in path_pts.size() - 1:
		path_len += path_pts[i].distance_to(path_pts[i + 1])


func point_at(d: float) -> Vector2:
	var left := d
	for i in path_pts.size() - 1:
		var seg := path_pts[i].distance_to(path_pts[i + 1])
		if left <= seg:
			return path_pts[i].lerp(path_pts[i + 1], left / seg)
		left -= seg
	return path_pts[path_pts.size() - 1]


func _build_deco() -> void:
	# 빈 칸에 덤불·꽃을 조금 (같은 판이면 늘 같은 자리)
	var r := RandomNumberGenerator.new()
	r.seed = 42
	for x in COLS:
		for y in ROWS:
			var c := Vector2i(x, y)
			if path_tiles.has(c) or c in SLOTS or c in EXTRA_SLOTS:
				continue
			if r.randf() < 0.35:
				deco.append({"p": tile_center(c) + Vector2(r.randf_range(-18, 18), r.randf_range(-14, 14)),
						"kind": r.randi() % 3, "s": r.randf_range(0.7, 1.1), "c": r.randi() % 4})


# ───────────── 웨이브 계획 ─────────────

func _make_plan() -> void:
	plan.append([])
	var last := -1
	for w in range(1, WAVES + 1):
		var e1 := rng.randi() % 5
		while e1 == last:
			e1 = rng.randi() % 5
		last = e1
		var groups := []
		if w % 5 == 0:
			groups.append({"kind": "big", "n": 1 + (1 if w == 15 else 0), "el": e1})
			groups.append({"kind": "ghost", "n": 4 + w / 2, "el": (e1 + 2) % 5})
		else:
			groups.append({"kind": "ghost", "n": 6 + int(w * 1.2), "el": e1})
			if w >= 2:
				var e2 := e1 if w < 4 or rng.randf() < 0.4 else (e1 + 1 + rng.randi() % 4) % 5
				groups.append({"kind": "imp", "n": 3 + int(w * 0.8), "el": e2})
		plan.append(groups)


func _hp_mul(w: int) -> float:
	# 뒤로 갈수록 가파르게 (타워 수·강화·배율이 함께 늘어나므로)
	return 1.0 + 0.28 * (w - 1) + 0.012 * (w - 1) * (w - 1)


func _start_wave() -> void:
	if phase != Phase.BUILD:
		return
	_cancel_hold()
	phase = Phase.FIGHT
	var w := wave + 1
	spawn_queue.clear()
	for g in plan[w]:
		for i in int(g["n"]):
			spawn_queue.append({"kind": g["kind"], "el": g["el"]})
	spawn_queue.shuffle()
	# 큰 요괴는 마지막에
	spawn_queue.sort_custom(func(a, b): return a["kind"] != "big" and b["kind"] == "big")
	spawn_t = 0.0
	sfx.play("drum", 1.0, -2.0)
	_float_text("%d웨이브!" % w, Vector2(472, 380), 44, Color("4a3a32"))
	_refresh_ui()


# ───────────── 이웃 계산 (오행 규칙의 핵심) ─────────────

func _adjacent(a: Vector2i, b: Vector2i, tw: Dictionary) -> bool:
	var d := b - a
	if absi(d.x) + absi(d.y) == 1:
		return true
	if talismans.has("earth_diag") and absi(d.x) == 1 and absi(d.y) == 1:
		return int(tw[a]["el"]) == El.EARTH or int(tw[b]["el"]) == El.EARTH
	return false


## 타워 배치 tw로 배율·연결·순환을 계산한다 (부작용 없음 → 미리보기에도 씀)
func _evaluate(tw: Dictionary) -> Dictionary:
	var mults := {}
	var links := []
	var sad := {}
	var gen := 0.6 if talismans.has("strong_gen") else El.GEN_BONUS
	for p in tw:
		mults[p] = 1.0
	for a in tw:
		for b in tw:
			if a == b or not _adjacent(a, b, tw):
				continue
			var ea: int = tw[a]["el"]
			var eb: int = tw[b]["el"]
			if El.GEN[ea] == eb:
				mults[b] += gen
				links.append({"a": a, "b": b, "k": "gen"})
			elif El.KE[ea] == eb:
				if eb == El.WATER and talismans.has("water_guard"):
					continue
				mults[b] -= El.KE_PENALTY
				links.append({"a": a, "b": b, "k": "ke"})
				sad[b] = true
			elif ea == eb and talismans.has("kin"):
				mults[b] += 0.2
	var chains := _find_chains(tw)
	var in_chain := {}
	for ch in chains:
		for p in ch:
			in_chain[p] = true
	for p in in_chain:
		mults[p] += El.CYCLE_BONUS
	for p in mults:
		mults[p] = maxf(0.2, mults[p])
	return {"mults": mults, "links": links, "chains": chains, "sad": sad}


## 오행 순환: 상생 순서대로 이웃이 이어진 다섯(부적이면 넷) 타워
func _find_chains(tw: Dictionary) -> Array:
	var need := 4 if talismans.has("short_cycle") else 5
	var found := {}
	var out := []
	for p in tw:
		var stack := [[p]]
		while not stack.is_empty():
			var path: Array = stack.pop_back()
			if path.size() == need:
				var key := _chain_key(path)
				if not found.has(key):
					found[key] = true
					out.append(path)
				continue
			var last: Vector2i = path[path.size() - 1]
			var want: int = El.GEN[int(tw[last]["el"])]
			for q in tw:
				if int(tw[q]["el"]) == want and not q in path and _adjacent(last, q, tw):
					var np := path.duplicate()
					np.append(q)
					stack.append(np)
	return out


func _chain_key(ch: Array) -> String:
	var s: Array[String] = []
	for p in ch:
		s.append("%d,%d" % [p.x, p.y])
	s.sort()
	return "|".join(s)


func _recompute() -> void:
	var old := ev
	ev = _evaluate(towers)
	# 새로 생긴 상생·상극, 새로 완성된 순환에 연출
	var old_links := {}
	for l in old["links"]:
		old_links["%s>%s%s" % [l["a"], l["b"], l["k"]]] = true
	var new_gen := false
	var new_ke := false
	for l in ev["links"]:
		if old_links.has("%s>%s%s" % [l["a"], l["b"], l["k"]]):
			continue
		var a := tile_center(l["a"])
		var b := tile_center(l["b"])
		if l["k"] == "gen":
			new_gen = true
			for i in 10:
				_spark(a.lerp(b, randf()) + Vector2(0, -20), El.COL[int(towers[l["a"]]["el"])], 140.0)
		else:
			new_ke = true
	var old_chains := {}
	for ch in old["chains"]:
		old_chains[_chain_key(ch)] = true
	var new_cycle := false
	for ch in ev["chains"]:
		if not old_chains.has(_chain_key(ch)):
			new_cycle = true
			_celebrate(ch)
	if new_cycle:
		sfx.play("cycle", 1.0, -1.0)
	elif new_gen:
		sfx.play("link", randf_range(0.95, 1.08), -3.0)
	elif new_ke:
		sfx.play("clash", 1.0, -4.0)


func _mult(p: Vector2i) -> float:
	return float(ev["mults"].get(p, 1.0))


# ───────────── 놓기 / 옮기기 ─────────────

func _pick_shop(el: int) -> void:
	if phase in [Phase.CHOOSE, Phase.OVER, Phase.WIN]:
		return
	_cancel_hold()
	if coins < TOWER_COST and free_towers[el] <= 0:
		_float_text("엽전이 모자라요", get_global_mouse_position() + Vector2(0, -30), 20, Color("c0503f"))
		return
	held = el
	sfx.play("select" if sfx.streams.has("select") else "brush", 1.4, -8.0)


func _cancel_hold() -> void:
	if moving_from != Vector2i(-99, -99) and held >= 0:
		# 옮기다 취소: 제자리로
		towers[moving_from] = {"el": held, "lv": moving_lv, "cd": 0.3, "pop": 0.0, "aim": Vector2.UP, "swing": 0.0}
		_recompute()
	held = -1
	moving_from = Vector2i(-99, -99)


var moving_lv := 1


func _click_tile(c: Vector2i) -> void:
	if not c in slots:
		if held >= 0:
			_cancel_hold()
		return
	if held >= 0:
		if towers.has(c):
			return
		if moving_from != Vector2i(-99, -99):
			# 옮기기
			if not free_move:
				if coins < MOVE_COST:
					_float_text("옮기는 데 엽전 %d" % MOVE_COST, tile_center(c) + Vector2(0, -40), 20, Color("c0503f"))
					return
				coins -= MOVE_COST
			free_move = false
			_place(c, held, moving_lv)
			moving_from = Vector2i(-99, -99)
			held = -1
		else:
			if free_towers[held] > 0:
				free_towers[held] -= 1
			elif coins >= TOWER_COST:
				coins -= TOWER_COST
			else:
				return
			var el := held
			_place(c, el, 1)
			if free_towers[el] <= 0 and coins < TOWER_COST:
				held = -1
		_refresh_ui()
		return
	# 아무것도 안 들고 있을 때 타워를 누르면 들어서 옮기기 (준비 단계에서만)
	if towers.has(c) and phase == Phase.BUILD:
		var tw: Dictionary = towers[c]
		held = tw["el"]
		moving_lv = tw["lv"]
		moving_from = c
		towers.erase(c)
		_recompute()
		_float_text("옮길 자리를 고르세요" + ("" if free_move else " (엽전 %d)" % MOVE_COST), tile_center(c) + Vector2(0, -50), 18, Color("4a3a32"))
	elif towers.has(c):
		_float_text("싸우는 중엔 못 옮겨요", tile_center(c) + Vector2(0, -50), 18, Color("c0503f"))


func _place(c: Vector2i, el: int, lv: int) -> void:
	towers[c] = {"el": el, "lv": lv, "cd": 0.4, "pop": 0.42, "aim": Vector2.UP, "swing": 0.0}
	sfx.play("place", randf_range(0.95, 1.08), -1.0)
	for i in 8:
		_spark(tile_center(c) + Vector2(0, 8), Color("e8dcc0"), 120.0)
	_recompute()


# ───────────── 매 프레임 ─────────────

func _process(delta: float) -> void:
	hover = hover_override if hover_override != Vector2i(-99, -99) else tile_at(get_global_mouse_position())
	if phase == Phase.CHOOSE:
		for i in cards.size():
			if Input.is_action_just_pressed("pick_%d" % (i + 1)):
				_pick_card(i)
	elif phase in [Phase.BUILD, Phase.FIGHT]:
		for e in 5:
			if Input.is_action_just_pressed("pick_%d" % (e + 1)):
				_pick_shop(e)
		if Input.is_action_just_pressed("start"):
			_start_wave()
		if Input.is_action_just_pressed("speed"):
			_toggle_speed()
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	var dt := delta * (speed if phase == Phase.FIGHT else 1.0)
	t += delta
	for p in towers:
		var tw: Dictionary = towers[p]
		tw["pop"] = maxf(0.0, float(tw["pop"]) - delta)
		tw["swing"] = maxf(0.0, float(tw["swing"]) - delta)
	if phase == Phase.FIGHT:
		_spawn_step(dt)
		_enemies_step(dt)
		_towers_step(dt)
		_shots_step(dt)
		_check_wave_end()
	_fx_step(delta)
	shake = maxf(0.0, shake - delta * 30.0)
	position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	queue_redraw()
	_update_tip()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and phase in [Phase.BUILD, Phase.FIGHT]:
			_click_tile(tile_at(get_global_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_hold()
	elif event.is_action_pressed("cancel"):
		_cancel_hold()


func _toggle_speed() -> void:
	speed = {1.0: 2.0, 2.0: 3.0, 3.0: 1.0}[speed]
	_refresh_ui()


# ───────────── 적 ─────────────

func _spawn_step(dt: float) -> void:
	if spawn_queue.is_empty():
		return
	spawn_t -= dt
	if spawn_t > 0.0:
		return
	var s: Dictionary = spawn_queue.pop_front()
	spawn_t = 1.2 if s["kind"] == "big" else 0.55
	var k: Dictionary = ENEMY[s["kind"]]
	var hp: float = float(k["hp"]) * _hp_mul(wave + 1)
	enemies.append({"kind": s["kind"], "el": s["el"], "hp": hp, "max": hp, "spd": k["spd"], "r": k["r"],
			"reward": k["reward"], "leak": k["leak"], "d": 0.0, "slow_t": 0.0, "slow": 0.0, "stun_t": 0.0,
			"ph": randf() * TAU, "flash": 0.0, "dead": false})


func _enemies_step(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for e in enemies:
		e["ph"] = float(e["ph"]) + dt * 6.0
		e["flash"] = maxf(0.0, float(e["flash"]) - dt)
		e["slow_t"] = maxf(0.0, float(e["slow_t"]) - dt)
		e["stun_t"] = maxf(0.0, float(e["stun_t"]) - dt)
		var sp: float = e["spd"]
		if float(e["slow_t"]) > 0.0:
			sp *= 1.0 - float(e["slow"])
		if float(e["stun_t"]) > 0.0:
			sp = 0.0
		e["d"] = float(e["d"]) + sp * dt
		if float(e["d"]) >= path_len:
			lives -= int(e["leak"])
			shake = 8.0
			sfx.play("leak", 1.0, -2.0)
			_float_text("-%d" % int(e["leak"]), path_pts[path_pts.size() - 1] + Vector2(-30, -40), 30, Color("c0503f"))
			if lives <= 0:
				lives = 0
				_finish(false)
			continue
		if not e["dead"]:
			keep.append(e)
	enemies = keep
	_refresh_stats()


func _epos(e: Dictionary) -> Vector2:
	return point_at(e["d"])


func _hit(e: Dictionary, dmg: float, el: int) -> void:
	if e["dead"]:
		return
	var mul := El.vs(el, e["el"], talismans.has("triple"))
	e["hp"] = float(e["hp"]) - dmg * mul
	e["flash"] = 0.08
	var p := _epos(e) + Vector2(0, -float(e["r"]))
	if mul >= 2.0 and randf() < 0.5:
		_float_text("상극!", p + Vector2(0, -20), 16, El.DARK[el])
	if float(e["hp"]) <= 0.0:
		e["dead"] = true
		coins += int(e["reward"])
		sfx.play("coin", randf_range(0.95, 1.1), -9.0)
		for i in 10:
			_spark(p, El.COL[int(e["el"])], 180.0)
		fxs.append({"type": "coin", "p": p, "t": 0.0, "life": 0.8, "v": int(e["reward"])})
		if e["kind"] == "big":
			shake = 10.0
			sfx.play("gong", 1.2, -2.0)


# ───────────── 타워 ─────────────

func _tower_mul(p: Vector2i) -> float:
	var tw: Dictionary = towers[p]
	return _mult(p) * (1.0 + El.LEVEL_BONUS * (int(tw["lv"]) - 1))


func _towers_step(dt: float) -> void:
	for p in towers:
		var tw: Dictionary = towers[p]
		tw["cd"] = float(tw["cd"]) - dt
		if float(tw["cd"]) > 0.0:
			continue
		var el: int = tw["el"]
		var st: Dictionary = El.STATS[el]
		var c := tile_center(p) + Vector2(0, -24)
		var target := _target(c, st["range"])
		if target.is_empty():
			continue
		tw["cd"] = st["rate"]
		tw["swing"] = 0.25
		var m := _tower_mul(p)
		var dmg: float = float(st["dmg"]) * m
		var tp := _epos(target)
		tw["aim"] = (tp - c).normalized()
		match el:
			El.WOOD:
				shots.append({"el": el, "p": c, "target": target, "dmg": dmg, "m": m, "spd": 620.0, "to": tp})
			El.FIRE:
				shots.append({"el": el, "p": c, "target": target, "dmg": dmg, "m": m, "spd": 380.0, "to": tp, "from": c, "k": 0.0})
			El.EARTH:
				shots.append({"el": el, "p": c, "target": target, "dmg": dmg, "m": m, "spd": 440.0, "to": tp})
			El.METAL:
				# 종소리 파동: 사거리 안 모두 둔화
				var r: float = st["range"]
				fxs.append({"type": "wave", "p": c, "t": 0.0, "life": 0.5, "r": r})
				for e in enemies:
					if not e["dead"] and _epos(e).distance_to(c) < r:
						e["slow_t"] = 1.4
						e["slow"] = minf(0.6, float(st["slow"]) * minf(m, 1.7))
						_hit(e, dmg, el)
				sfx.play("rank" if sfx.streams.has("rank") else "brush", 1.9, -14.0)
			El.WATER:
				_hit(target, dmg, el)
				target["d"] = maxf(0.0, float(target["d"]) - float(st["push"]) * minf(m, 1.8) * (0.3 if target["kind"] == "big" else 1.0))
				fxs.append({"type": "jet", "p": c, "to": tp + Vector2(0, -12), "t": 0.0, "life": 0.25})
				for i in 6:
					_spark(tp + Vector2(0, -12), Color("8fb4ff"), 150.0)


## 사거리 안에서 가장 멀리 간(목적지에 가까운) 적
func _target(c: Vector2, r: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := -1.0
	for e in enemies:
		if e["dead"]:
			continue
		if _epos(e).distance_to(c) <= r and float(e["d"]) > bd:
			bd = e["d"]
			best = e
	return best


func _shots_step(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for s in shots:
		var tgt: Dictionary = s["target"]
		if not tgt["dead"]:
			s["to"] = _epos(tgt) + Vector2(0, -float(tgt["r"]))
		var to: Vector2 = s["to"]
		var p: Vector2 = s["p"]
		var step: float = float(s["spd"]) * dt
		if p.distance_to(to) <= step:
			_shot_land(s, to)
			continue
		s["p"] = p.move_toward(to, step)
		keep.append(s)
	shots = keep


func _shot_land(s: Dictionary, at: Vector2) -> void:
	var el: int = s["el"]
	var tgt: Dictionary = s["target"]
	match el:
		El.FIRE:
			var r: float = float(El.STATS[El.FIRE]["splash"]) * minf(1.0 + 0.2 * (float(s["m"]) - 1.0), 1.5)
			fxs.append({"type": "boom", "p": at, "t": 0.0, "life": 0.4, "r": r})
			for i in 12:
				_spark(at, Color("ffb347") if i % 2 == 0 else Color("ee5b4b"), 220.0)
			for e in enemies:
				if not e["dead"] and (_epos(e) + Vector2(0, -10)).distance_to(at) < r + float(e["r"]):
					_hit(e, s["dmg"], el)
			sfx.play("hit", 1.3, -10.0)
		El.EARTH:
			_hit(tgt, s["dmg"], el)
			if not tgt["dead"]:
				tgt["stun_t"] = float(El.STATS[El.EARTH]["stun"]) * minf(float(s["m"]), 1.8) * (0.4 if tgt["kind"] == "big" else 1.0)
			for i in 6:
				_spark(at, Color("d9b36a"), 140.0)
		_:
			_hit(tgt, s["dmg"], el)
			for i in 4:
				_spark(at, Color("8fd6a5"), 120.0)


func _check_wave_end() -> void:
	if spawn_queue.is_empty() and enemies.is_empty() and phase == Phase.FIGHT:
		wave += 1
		coins += 15
		shots.clear()
		if wave >= WAVES:
			_finish(true)
			return
		_open_cards()


# ───────────── 카드 ─────────────

func _open_cards() -> void:
	phase = Phase.CHOOSE
	var pool: Array[Dictionary] = []
	for id in El.TALISMANS:
		if not talismans.has(id):
			pool.append({"type": "tal", "id": id})
			pool.append({"type": "tal", "id": id}) # 부적이 자주 나오게
	var owned := {}
	for p in towers:
		owned[int(towers[p]["el"])] = true
	for el in owned:
		pool.append({"type": "up", "el": el})
	var spare := 0
	for s in EXTRA_SLOTS:
		if not s in slots:
			spare += 1
	if spare > 0:
		pool.append({"type": "slot"})
	pool.append({"type": "coins"})
	pool.append({"type": "free", "el": rng.randi() % 5})
	pool.shuffle()
	cards.clear()
	var used := {}
	for c in pool:
		var key := "%s%s%s" % [c["type"], c.get("id", ""), c.get("el", "")]
		if used.has(key):
			continue
		used[key] = true
		cards.append(c)
		if cards.size() >= 3:
			break
	sfx.play("rank" if sfx.streams.has("rank") else "link", 1.0, -3.0)
	_show_cards()


func _card_text(c: Dictionary) -> Array:
	match c["type"]:
		"tal":
			var d: Dictionary = El.TALISMANS[c["id"]]
			return [d["char"], d["name"], "부적", d["desc"], Color("7a4fb0")]
		"up":
			return ["↑", "%s 강화" % El.NAMES[c["el"]], "강화", "%s 타워 모두 한 단계 오른다 (+35%%)" % El.NAMES[c["el"]], El.DARK[c["el"]]]
		"slot":
			return ["＋", "결계 자리", "강화", "타워를 지을 자리가 한 칸 늘어난다", Color("6a8a5a")]
		"coins":
			return ["엽", "엽전 꾸러미", "보상", "엽전 +60", Color("c28520")]
		"free":
			return ["무", "공짜 %s" % El.TOWER[c["el"]], "보상", "%s 타워 하나를 공짜로 지을 수 있다" % El.NAMES[c["el"]], El.DARK[c["el"]]]
	return ["?", "?", "", "", Color.GRAY]


func _pick_card(i: int) -> void:
	if phase != Phase.CHOOSE or i >= cards.size():
		return
	var c: Dictionary = cards[i]
	match c["type"]:
		"tal":
			talismans[c["id"]] = true
		"up":
			for p in towers:
				if int(towers[p]["el"]) == int(c["el"]):
					towers[p]["lv"] = int(towers[p]["lv"]) + 1
					towers[p]["pop"] = 0.3
		"slot":
			for s in EXTRA_SLOTS:
				if not s in slots:
					slots.append(s)
					_float_text("새 결계 자리!", tile_center(s) + Vector2(0, -40), 22, Color("3f7a3f"))
					break
		"coins":
			coins += 60
		"free":
			free_towers[c["el"]] += 1
	sfx.play("place", 1.3, -3.0)
	card_box.visible = false
	card_dim.visible = false
	phase = Phase.BUILD
	free_move = true
	_recompute()
	_refresh_ui()


# ───────────── 끝 ─────────────

func _finish(won: bool) -> void:
	phase = Phase.WIN if won else Phase.OVER
	enemies.clear()
	shots.clear()
	sfx.play("cycle" if won else "over", 1.0, 0.0)
	_show_result(won)


# ───────────── 연출 ─────────────

func _spark(p: Vector2, col: Color, power: float) -> void:
	parts.append({"p": p, "v": Vector2.from_angle(randf_range(-PI, 0.0)) * randf_range(0.3, 1.0) * power,
			"c": col, "age": 0.0, "life": randf_range(0.35, 0.7), "r": randf_range(2.0, 4.5)})


func _celebrate(ch: Array) -> void:
	var c := Vector2.ZERO
	for p in ch:
		c += tile_center(p)
	c /= ch.size()
	var r := 0.0
	for p in ch:
		r = maxf(r, tile_center(p).distance_to(c))
	fxs.append({"type": "ring", "p": c + Vector2(0, -16), "r": r + 50.0, "t": 0.0, "life": 1.8})
	_float_text("오행 순환!", c + Vector2(0, -90), 38, Color("7a4fb0"))
	for p in ch:
		for i in 6:
			_spark(tile_center(p) + Vector2(0, -24), El.COL[int(towers[p]["el"])] if towers.has(p) else Color.WHITE, 200.0)


func _float_text(text: String, pos: Vector2, size: int, col: Color) -> void:
	fxs.append({"type": "text", "p": pos, "text": text, "size": size, "c": col, "t": 0.0, "life": 1.1})


func _fx_step(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for f in fxs:
		f["t"] = float(f["t"]) + delta
		if float(f["t"]) < float(f["life"]):
			keep.append(f)
	fxs = keep
	var kp: Array[Dictionary] = []
	for q in parts:
		q["age"] = float(q["age"]) + delta
		q["v"] = (q["v"] as Vector2) + Vector2(0, 420.0) * delta
		q["p"] = (q["p"] as Vector2) + (q["v"] as Vector2) * delta
		if float(q["age"]) < float(q["life"]):
			kp.append(q)
	parts = kp


# ───────────── 그리기 ─────────────

func _rrect(r: Rect2, col: Color, radius: float, border := Color(0, 0, 0, 0), bw := 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	draw_style_box(sb, r)


func _ell(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw() -> void:
	# 바탕과 섬
	draw_rect(Rect2(-40, -40, 1360, 800), Color("d9eef2"))
	var board := Rect2(ORIGIN, Vector2(COLS, ROWS) * TILE)
	_rrect(Rect2(board.position + Vector2(0, 14), board.size).grow(16), Color(0.2, 0.3, 0.35, 0.16), 34)
	_rrect(board.grow(16), Color("e9dcc0"), 34)
	_rrect(board.grow(8), Color("bfe3a8"), 28)
	for x in COLS:
		for y in ROWS:
			if (x + y) % 2 == 0:
				draw_rect(Rect2(ORIGIN + Vector2(x, y) * TILE, Vector2(TILE, TILE)), Color(1, 1, 1, 0.06))
	for d in deco:
		var p: Vector2 = d["p"]
		var s: float = d["s"]
		if d["kind"] == 0:
			_ell(p + Vector2(0, 8), 16 * s, 6 * s, Color(0.2, 0.35, 0.2, 0.15))
			draw_circle(p, 13 * s, Color("8fcf7e"), true, -1.0, true)
			draw_circle(p + Vector2(-4, -4) * s, 6 * s, Color("abdf98"), true, -1.0, true)
		else:
			var fc: Color = [Color("ffffff"), Color("ffd35a"), Color("ff9fb2"), Color("b9a6ff")][d["c"]]
			for k in 5:
				draw_circle(p + Vector2.from_angle(TAU * k / 5.0) * 4 * s, 3.2 * s, fc, true, -1.0, true)
			draw_circle(p, 2.4 * s, Color("ffb347"), true, -1.0, true)
	# 길
	draw_polyline(path_pts, Color("e2cc98"), TILE * 0.84, true)
	draw_polyline(path_pts, Color("f3e4bf"), TILE * 0.7, true)
	for i in range(0, int(path_len), 46):
		var q := point_at(float(i) + fmod(t * 10.0, 46.0))
		draw_circle(q, 3.0, Color(1, 1, 1, 0.45), true, -1.0, true)
	# 귀문(시작)과 마을(끝)
	var g := path_pts[0] + Vector2(34, 0)
	draw_circle(g, 30, Color("6f4f9f"), true, -1.0, true)
	for k in 3:
		draw_arc(g, 22 - k * 7, t * (2 + k) + k, t * (2 + k) + k + 4.0, 16, Color("c9b6ff"), 3.0, true)
	_draw_village(path_pts[path_pts.size() - 1] + Vector2(-34, 0))
	# 결계 자리
	for s in slots:
		var c := tile_center(s)
		_ell(c + Vector2(0, 10), 27, 10, Color(0.2, 0.3, 0.2, 0.18))
		_ell(c + Vector2(0, 4), 27, 14, Color("cfd8d6"))
		_ell(c, 27, 14, Color("eef3f1"))
		if held >= 0 and s == hover and not towers.has(s):
			_ell(c, 29, 16, Color(El.COL[held], 0.45))
	# 이웃 연결 (상생 빛줄기, 상극 금)
	for l in ev["links"]:
		_draw_link(l)
	# 오행 순환 고리 (계속 은은하게)
	for ch in ev["chains"]:
		for p in ch:
			var c := tile_center(p)
			for k in 5:
				var a0 := t * 1.5 + TAU * k / 5.0
				draw_arc(c + Vector2(0, 2), 31, a0, a0 + TAU / 5.0 - 0.15, 8, Color(El.COL[k], 0.75), 4.0, true)
	# 적과 타워를 위에서 아래 순서로
	var items := []
	for p in towers:
		items.append({"y": tile_center(p).y, "tower": p})
	for e in enemies:
		items.append({"y": _epos(e).y, "enemy": e})
	items.sort_custom(func(a, b): return a["y"] < b["y"])
	for it in items:
		if it.has("tower"):
			_draw_tower(it["tower"])
		else:
			_draw_enemy(it["enemy"])
	# 발사체
	for s in shots:
		_draw_shot(s)
	# 효과
	for f in fxs:
		_draw_fx(f)
	for q in parts:
		var a := 1.0 - float(q["age"]) / float(q["life"])
		draw_circle(q["p"], float(q["r"]) * (0.6 + 0.4 * a), Color(q["c"], a), true, -1.0, true)
	# 들고 있는 타워 미리보기
	_draw_preview()
	# 마우스를 올린 타워의 사거리
	if held < 0 and towers.has(hover):
		var st: Dictionary = El.STATS[int(towers[hover]["el"])]
		draw_arc(tile_center(hover) + Vector2(0, -24), st["range"], 0, TAU, 48, Color(1, 1, 1, 0.7), 2.0, true)


func _draw_village(c: Vector2) -> void:
	_ell(c + Vector2(0, 20), 34, 10, Color(0.2, 0.3, 0.2, 0.2))
	_rrect(Rect2(c + Vector2(-24, -14), Vector2(48, 34)), Color("fbf3e4"), 6)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-32, -12), c + Vector2(0, -40), c + Vector2(32, -12)]), Color("ee5b4b"))
	_rrect(Rect2(c + Vector2(-7, 2), Vector2(14, 18)), Color("b98a5e"), 3)


func _draw_link(l: Dictionary) -> void:
	var a := tile_center(l["a"]) + Vector2(0, -16)
	var b := tile_center(l["b"]) + Vector2(0, -16)
	if not towers.has(l["a"]):
		return
	var col: Color = El.COL[int(towers[l["a"]]["el"])]
	if l["k"] == "gen":
		draw_line(a, b, Color(col, 0.35), 10.0, true)
		draw_line(a, b, Color(1, 1, 1, 0.5), 3.0, true)
		# a에서 b로 흐르는 빛 방울
		for k in 3:
			var u := fmod(t * 0.9 + k / 3.0, 1.0)
			draw_circle(a.lerp(b, u), 4.5, Color(col.lightened(0.3), 1.0 - u * 0.4), true, -1.0, true)
		var dir := (b - a).normalized()
		var tip := b - dir * 22.0
		draw_colored_polygon(PackedVector2Array([tip + dir * 9, tip - dir * 5 + dir.orthogonal() * 7, tip - dir * 5 - dir.orthogonal() * 7]), Color("3f9f5a"))
	else:
		# 상극: 짧은 붉은 금
		var m := a.lerp(b, 0.6)
		var n := (b - a).normalized().orthogonal()
		var pts := PackedVector2Array([m - n * 12, m - n * 4 + (b - a).normalized() * 5, m + n * 4 - (b - a).normalized() * 5, m + n * 12])
		draw_polyline(pts, Color("e04a3a"), 3.5, true)


func _draw_tower(p: Vector2i, ghost := false) -> void:
	var tw: Dictionary = towers[p] if towers.has(p) else {"el": held, "lv": 1, "pop": 0.0, "swing": 0.0, "aim": Vector2.UP}
	var el: int = tw["el"]
	var c := tile_center(p)
	var a := 0.55 if ghost else 1.0
	# 톡 떨어지며 튀는 연출
	var pop: float = tw["pop"]
	var drop := 0.0
	var sq := Vector2.ONE
	if pop > 0.0:
		var k := pop / 0.42
		if k > 0.5:
			drop = -60.0 * pow((k - 0.5) * 2.0, 2.0)
		else:
			var b := sin((0.5 - k) * 2.0 * PI) * (k * 2.0)
			sq = Vector2(1.0 + 0.18 * b, 1.0 - 0.18 * b)
	_ell(c + Vector2(0, 6), 22, 8, Color(0.15, 0.2, 0.2, 0.22 * a))
	draw_set_transform(c + Vector2(0, 6 + drop), 0.0, sq)
	var o := Vector2(0, -6)
	var col := Color(El.COL[el], a)
	var dark := Color(El.DARK[el], a)
	var swing: float = tw["swing"]
	match el:
		El.WOOD:
			_ell(o + Vector2(0, 0), 14, 6, Color(Color("c9b79a"), a))
			draw_line(o, o + Vector2(0, -44), Color(Color("9a6b3f"), a), 5.0, true)
			var bird := o + Vector2(0, -48 - swing * 8.0)
			_ell(bird, 14, 8, col)
			_ell(bird + Vector2(-4, -2), 6, 4, Color(col.lightened(0.3), a))
			draw_circle(bird + Vector2(9, -5), 5, col, true, -1.0, true)
			draw_colored_polygon(PackedVector2Array([bird + Vector2(13, -6), bird + Vector2(21, -4), bird + Vector2(13, -2)]), Color(Color("ffb347"), a))
			draw_circle(bird + Vector2(10, -6), 1.6, Color(0.1, 0.1, 0.1, a))
		El.FIRE:
			draw_colored_polygon(PackedVector2Array([o + Vector2(-18, 2), o + Vector2(18, 2), o + Vector2(12, -26), o + Vector2(-12, -26)]), Color(Color("d8cfc2"), a))
			draw_line(o + Vector2(-15, -10), o + Vector2(15, -10), Color(Color("bfb4a5"), a), 2.0, true)
			var fl := 1.0 + 0.12 * sin(t * 14.0) + swing
			var f0 := o + Vector2(0, -30)
			draw_colored_polygon(PackedVector2Array([f0 + Vector2(-13, 0), f0 + Vector2(0, -30 * fl), f0 + Vector2(13, 0)]), col)
			draw_circle(f0 + Vector2(0, -4), 13, col, true, -1.0, true)
			draw_circle(f0 + Vector2(0, -6), 8, Color(Color("ffb347"), a), true, -1.0, true)
			draw_circle(f0 + Vector2(0, -6), 4, Color(Color("fff1a8"), a), true, -1.0, true)
		El.EARTH:
			_rrect(Rect2(o + Vector2(-14, -52), Vector2(28, 54)), col, 14)
			_rrect(Rect2(o + Vector2(-14, -52), Vector2(28, 12)), dark, 7)
			for ex in [-6.0, 6.0]:
				draw_circle(o + Vector2(ex, -30), 5, Color(1, 1, 1, a), true, -1.0, true)
				draw_circle(o + Vector2(ex, -30 - swing * 6), 2.4, Color(0.1, 0.1, 0.1, a), true, -1.0, true)
			draw_arc(o + Vector2(0, -18), 6, 0.2, PI - 0.2, 8, Color(dark, a), 2.5, true)
		El.METAL:
			var rot := sin(swing * 30.0) * swing * 1.2
			draw_set_transform(c + Vector2(0, 6 + drop) + o + Vector2(0, -48), rot, sq)
			draw_line(Vector2(0, -4), Vector2(0, 2), Color(Color("8b97a8"), a), 4.0, true)
			var bell := PackedVector2Array()
			for i in 13:
				var ang := PI + PI * i / 12.0
				bell.append(Vector2(cos(ang) * 14, sin(ang) * 14 + 16))
			bell.append(Vector2(20, 38))
			bell.append(Vector2(-20, 38))
			draw_colored_polygon(bell, col)
			draw_line(Vector2(-20, 37), Vector2(20, 37), Color(dark, a), 4.0, true)
			_ell(Vector2(-5, 18), 3, 8, Color(1, 1, 1, 0.6 * a))
			draw_circle(Vector2(0, 41), 4, Color(dark, a), true, -1.0, true)
		El.WATER:
			_ell(o + Vector2(0, -6), 22, 12, Color(Color("cfd6de"), a))
			_ell(o + Vector2(0, -10), 22, 12, Color(Color("e5eaef"), a))
			_ell(o + Vector2(0, -10), 15, 8, col)
			draw_arc(o + Vector2(0, -10), 5 + fmod(t * 8.0, 9.0), 0, TAU, 16, Color(1, 1, 1, 0.5 * a), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if ghost:
		return
	# 단계 표시 점
	for i in int(tw["lv"]):
		draw_circle(c + Vector2(-8 * (int(tw["lv"]) - 1) * 0.5 + i * 8, 18), 3, dark, true, -1.0, true)
	# 상극을 받으면 시무룩
	if ev["sad"].has(p):
		var b := c + Vector2(18, -52)
		draw_circle(b, 9, Color.WHITE, true, -1.0, true)
		draw_circle(b + Vector2(-3, -1), 1.5, Color("4a3a32"))
		draw_circle(b + Vector2(3, -1), 1.5, Color("4a3a32"))
		draw_arc(b + Vector2(0, 5), 3.5, PI + 0.4, TAU - 0.4, 6, Color("4a3a32"), 1.5, true)
	# 배율 꼬리표
	var m := _mult(p)
	if absf(m - 1.0) > 0.01:
		var txt := "%+d%%" % int(roundf((m - 1.0) * 100.0))
		var col2 := Color("2f8f4a") if m > 1.0 else Color("d0473a")
		var w := font_b.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10
		_rrect(Rect2(c + Vector2(-w * 0.5, 24), Vector2(w, 18)), Color(1, 1, 1, 0.92), 8)
		draw_string(font_b, c + Vector2(-w * 0.5 + 5, 38), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col2)


func _draw_enemy(e: Dictionary) -> void:
	var p := _epos(e)
	var r: float = e["r"]
	var el: int = e["el"]
	var hop := absf(sin(float(e["ph"]))) * (4.0 if float(e["stun_t"]) <= 0.0 else 0.0)
	_ell(p + Vector2(0, 4), r * 1.0, r * 0.35, Color(0.15, 0.2, 0.2, 0.2))
	var body := p + Vector2(0, -r - hop)
	var col: Color = Color.WHITE if float(e["flash"]) > 0.0 else El.COL[el].lerp(Color.WHITE, 0.15)
	if float(e["slow_t"]) > 0.0:
		col = col.lerp(Color("b8d8ff"), 0.4)
	_ell(body, r, r * 0.92, col)
	_ell(body + Vector2(-r * 0.3, -r * 0.35), r * 0.35, r * 0.22, Color(1, 1, 1, 0.35))
	# 뿔
	if e["kind"] != "imp":
		var hc := El.DARK[el]
		draw_colored_polygon(PackedVector2Array([body + Vector2(-r * 0.55, -r * 0.6), body + Vector2(-r * 0.2, -r * 0.85), body + Vector2(-r * 0.5, -r * 1.35)]), hc)
		draw_colored_polygon(PackedVector2Array([body + Vector2(r * 0.55, -r * 0.6), body + Vector2(r * 0.2, -r * 0.85), body + Vector2(r * 0.5, -r * 1.35)]), hc)
	# 눈
	var es := r / 15.0
	for ex in [-5.0, 5.0]:
		draw_circle(body + Vector2(ex * es, -2 * es), 4.0 * es, Color.WHITE, true, -1.0, true)
		draw_circle(body + Vector2(ex * es + 1, -1.5 * es), 2.0 * es, Color("2a2a33"), true, -1.0, true)
	if float(e["stun_t"]) > 0.0:
		for k in 3:
			var a := t * 6.0 + TAU * k / 3.0
			draw_circle(body + Vector2(cos(a) * r * 0.9, -r - 6 + sin(a) * 4), 3.0, Color("ffd35a"), true, -1.0, true)
	if float(e["hp"]) < float(e["max"]):
		var w := r * 2.0
		var hb := Rect2(body + Vector2(-w * 0.5, -r - 14), Vector2(w, 5))
		draw_rect(hb, Color(0, 0, 0, 0.25))
		draw_rect(Rect2(hb.position, Vector2(w * float(e["hp"]) / float(e["max"]), 5)), Color("5ccf6a"))


func _draw_shot(s: Dictionary) -> void:
	var p: Vector2 = s["p"]
	match int(s["el"]):
		El.WOOD:
			var dir := ((s["to"] as Vector2) - p).normalized()
			draw_line(p - dir * 12, p, Color("6fd18f"), 4.0, true)
			_ell(p, 5, 3, Color("3fae6e"))
		El.FIRE:
			draw_circle(p, 8, Color("ee5b4b"), true, -1.0, true)
			draw_circle(p, 5, Color("ffb347"), true, -1.0, true)
		El.EARTH:
			draw_circle(p, 7, Color("c28520"), true, -1.0, true)
			draw_circle(p + Vector2(-2, -2), 3, Color("f2c46a"), true, -1.0, true)


func _draw_fx(f: Dictionary) -> void:
	var k := float(f["t"]) / float(f["life"])
	var p: Vector2 = f["p"]
	match f["type"]:
		"text":
			var size: int = f["size"]
			var txt: String = f["text"]
			var w := font_b.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var pos := p + Vector2(-w * 0.5, -40.0 * k)
			var a := 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
			draw_string_outline(font_b, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(1, 1, 1, a))
			draw_string(font_b, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(f["c"], a))
		"coin":
			var q := p + Vector2(0, -50.0 * k + 30.0 * k * k)
			var a := 1.0 - k
			_ell(q, 8 * absf(cos(k * 12.0)) + 2, 8, Color("e8b33c", a))
			draw_string(font_b, q + Vector2(10, 5), "+%d" % int(f["v"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("c28520", a))
		"wave":
			draw_arc(p, float(f["r"]) * k, 0, TAU, 40, Color(Color("e9eef5"), 1.0 - k), 5.0, true)
			draw_arc(p, float(f["r"]) * k * 0.8, 0, TAU, 40, Color(Color("b9c4d1"), (1.0 - k) * 0.7), 2.0, true)
		"boom":
			draw_circle(p, float(f["r"]) * (0.5 + 0.5 * k), Color(Color("ffb347"), 0.45 * (1.0 - k)), true, -1.0, true)
			draw_arc(p, float(f["r"]) * (0.5 + 0.5 * k), 0, TAU, 32, Color(Color("ee5b4b"), 1.0 - k), 4.0, true)
		"jet":
			var to: Vector2 = f["to"]
			draw_line(p, to, Color(Color("4a63b8"), 0.8 * (1.0 - k)), 8.0 * (1.0 - k) + 2.0, true)
			draw_line(p, to, Color(1, 1, 1, 0.6 * (1.0 - k)), 3.0, true)
		"ring":
			# 오행 순환 완성: 무지개 고리가 한 바퀴 돌며 퍼진다
			var r: float = float(f["r"]) * (0.7 + 0.3 * sin(minf(k * 2.0, 1.0) * PI * 0.5))
			var a := 1.0 if k < 0.7 else 1.0 - (k - 0.7) / 0.3
			for i in 5:
				var a0 := k * TAU * 1.5 + TAU * i / 5.0
				draw_arc(p, r, a0, a0 + TAU / 5.0, 16, Color(El.COL[i], a), 10.0, true)
			draw_arc(p, r + 9, 0, TAU, 48, Color(1, 1, 1, a * 0.6), 2.0, true)


func _draw_preview() -> void:
	if held < 0 or not hover in slots or towers.has(hover):
		return
	# 놓으면 어떻게 되는지 미리 계산
	var tmp := towers.duplicate()
	tmp[hover] = {"el": held, "lv": moving_lv if moving_from != Vector2i(-99, -99) else 1}
	var res := _evaluate(tmp)
	var mults: Dictionary = res["mults"]
	for l in res["links"]:
		if l["a"] != hover and l["b"] != hover:
			continue
		var a := tile_center(l["a"]) + Vector2(0, -16)
		var b := tile_center(l["b"]) + Vector2(0, -16)
		draw_line(a, b, Color("3f9f5a", 0.7) if l["k"] == "gen" else Color("e04a3a", 0.7), 5.0, true)
	_draw_tower(hover, true)
	# 이 칸과 이웃 타워의 바뀌는 배율
	for p in mults:
		var before := _mult(p) if towers.has(p) else 1.0
		var after: float = mults[p]
		if p != hover and absf(after - before) < 0.01:
			continue
		var txt := ("이 칸 %+d%%" % int(roundf((after - 1.0) * 100.0))) if p == hover else "%+d%%" % int(roundf((after - before) * 100.0))
		var good := after >= before if p != hover else after >= 1.0
		# 타워 아래 배율 꼬리표 자리에 덮어 그린다 (위 칸 타워와 겹치지 않게)
		var c := tile_center(p) + Vector2(0, 33)
		var w := font_b.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 14
		_rrect(Rect2(c + Vector2(-w * 0.5, -14), Vector2(w, 24)), Color("2f8f4a") if good else Color("d0473a"), 10)
		draw_string(font_b, c + Vector2(-w * 0.5 + 7, 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	for ch in res["chains"]:
		if hover in ch and not _chain_key(ch) in _chain_keys():
			var c := tile_center(hover) + Vector2(0, -106)
			draw_string_outline(font_b, c + Vector2(-56, 0), "오행 순환!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, Color.WHITE)
			draw_string(font_b, c + Vector2(-56, 0), "오행 순환!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("7a4fb0"))
			break


func _chain_keys() -> Array:
	var out := []
	for ch in ev["chains"]:
		out.append(_chain_key(ch))
	return out


# ───────────── UI ─────────────

func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(8)
	sb.anti_aliasing = true
	return sb


func _label(size: int, col: Color, bold := true) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font_b if bold else font_r)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	var title := _label(26, Color("4a3a32"))
	title.text = "오방 결계  ·  시험판"
	title.position = Vector2(30, 18)
	ui.add_child(title)
	stat_label = _label(22, Color("4a3a32"))
	stat_label.position = Vector2(30, 52)
	ui.add_child(stat_label)

	# 오른쪽 판
	var panel := Panel.new()
	panel.position = Vector2(952, 16)
	panel.size = Vector2(312, 688)
	var psb := _btn_style(Color(1, 1, 1, 0.92), Color("e2d6bf"))
	psb.set_corner_radius_all(20)
	panel.add_theme_stylebox_override("panel", psb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(panel)
	var vb := VBoxContainer.new()
	vb.position = Vector2(16, 14)
	vb.size = Vector2(280, 660)
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var cyc := CycleDiagram.new()
	cyc.custom_minimum_size = Vector2(280, 168)
	cyc.font = font_b
	vb.add_child(cyc)

	var shop_t := _label(17, Color("4a3a32"))
	shop_t.text = "타워 짓기 (엽전 %d)" % TOWER_COST
	vb.add_child(shop_t)
	for el in 5:
		var b := Button.new()
		b.add_theme_font_override("font", font_b)
		b.add_theme_font_size_override("font_size", 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(280, 40)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sb := _btn_style(El.COL[el].lerp(Color.WHITE, 0.55 if st != "hover" else 0.35), El.DARK[el])
			b.add_theme_stylebox_override(st, sb)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
			b.add_theme_color_override(fc, Color("2a2a33"))
		b.pressed.connect(_pick_shop.bind(el))
		b.focus_mode = Control.FOCUS_NONE
		vb.add_child(b)
		shop_btns.append(b)

	var next_t := _label(17, Color("4a3a32"))
	next_t.text = "다음 웨이브"
	vb.add_child(next_t)
	next_label = RichTextLabel.new()
	next_label.bbcode_enabled = true
	next_label.fit_content = true
	next_label.add_theme_font_override("normal_font", font_b)
	next_label.add_theme_font_override("bold_font", font_b)
	next_label.add_theme_font_size_override("normal_font_size", 15)
	next_label.add_theme_font_size_override("bold_font_size", 15)
	next_label.add_theme_color_override("default_color", Color("4a3a32"))
	next_label.custom_minimum_size = Vector2(280, 46)
	next_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(next_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	start_btn = Button.new()
	speed_btn = Button.new()
	for b in [start_btn, speed_btn]:
		b.add_theme_font_override("font", font_b)
		b.add_theme_font_size_override("font_size", 17)
		b.focus_mode = Control.FOCUS_NONE
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			b.add_theme_color_override(fc, Color.WHITE if b == start_btn else Color("4a3a32"))
		row.add_child(b)
	start_btn.custom_minimum_size = Vector2(186, 46)
	speed_btn.custom_minimum_size = Vector2(86, 46)
	for st in ["normal", "hover", "pressed", "focus"]:
		start_btn.add_theme_stylebox_override(st, _btn_style(Color("ee5b4b") if st != "hover" else Color("f07a6c"), Color("b93a2d")))
		speed_btn.add_theme_stylebox_override(st, _btn_style(Color("f4f1ea"), Color("d8cdb8")))
	start_btn.add_theme_stylebox_override("disabled", _btn_style(Color("d9cfc4"), Color("c4b8a8")))
	start_btn.pressed.connect(_start_wave)
	speed_btn.pressed.connect(_toggle_speed)

	tal_label = _label(14, Color("7a4fb0"))
	tal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tal_label.custom_minimum_size = Vector2(280, 0)
	vb.add_child(tal_label)

	tip_label = _label(15, Color("4a3a32"), false)
	tip_label.position = Vector2(30, 676)
	tip_label.size = Vector2(900, 30)
	ui.add_child(tip_label)

	card_dim = ColorRect.new()
	card_dim.color = Color(0.15, 0.2, 0.25, 0.45)
	card_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_dim.visible = false
	ui.add_child(card_dim)
	card_box = CenterContainer.new()
	card_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_box.visible = false
	card_dim.visible = false
	ui.add_child(card_box)
	overlay = CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	ui.add_child(overlay)


func _refresh_stats() -> void:
	stat_label.text = "웨이브 %d / %d     목숨 %d     엽전 %d" % [mini(wave + (1 if phase == Phase.FIGHT else 0), WAVES), WAVES, lives, coins]


func _refresh_ui() -> void:
	_refresh_stats()
	for el in 5:
		var free_txt := "  · 공짜 %d개" % free_towers[el] if free_towers[el] > 0 else ""
		shop_btns[el].text = "%d  %s (%s)%s" % [el + 1, El.TOWER[el], El.NAMES[el], free_txt]
	var w := wave + 1
	var lines: Array[String] = []
	if w <= WAVES:
		for g in plan[w]:
			var kname: String = {"imp": "꼬마 도깨비", "ghost": "도깨비", "big": "큰 도깨비"}[g["kind"]]
			lines.append("[color=#%s]● %s[/color] %s ×%d" % [El.DARK[int(g["el"])].to_html(false), El.NAMES[int(g["el"])], kname, int(g["n"])])
		var weak: Array[String] = []
		for g in plan[w]:
			for tel in 5:
				if El.KE[tel] == int(g["el"]) and not El.TOWER[tel] in weak:
					weak.append(El.TOWER[tel])
		lines.append("[color=#7a6a5e]잘 듣는 타워: %s[/color]" % ", ".join(weak))
	next_label.text = "\n".join(lines)
	start_btn.text = "웨이브 시작 (Space)" if phase == Phase.BUILD else "싸우는 중..."
	start_btn.disabled = phase != Phase.BUILD
	speed_btn.text = "%dx (F)" % int(speed)
	var tl: Array[String] = []
	for id in talismans:
		tl.append("[%s] %s" % [El.TALISMANS[id]["char"], El.TALISMANS[id]["desc"]])
	tal_label.text = ("부적\n" + "\n".join(tl)) if not tl.is_empty() else ""


func _update_tip() -> void:
	if phase == Phase.CHOOSE:
		tip_label.text = "카드를 하나 고르세요 (클릭 또는 1·2·3)"
	elif held >= 0:
		tip_label.text = "빈 결계 자리를 누르면 %s을(를) 놓아요. 이웃 칸에 바뀌는 수치가 떠요.   취소: 오른쪽 클릭 / Esc" % El.TOWER[held]
	elif phase == Phase.BUILD:
		tip_label.text = "타워를 고르고(1~5) 빈 자리에 놓으세요. 놓인 타워를 누르면 옮길 수 있어요%s.   상생은 강해지고, 상극은 약해져요" % ("(이번 준비 1번 공짜)" if free_move else "(엽전 %d)" % MOVE_COST)
	elif phase == Phase.FIGHT:
		tip_label.text = "싸우는 중에도 타워를 지을 수 있어요.   속도: F"
	else:
		tip_label.text = ""


func _show_cards() -> void:
	for c in card_box.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	card_box.add_child(vb)
	var title := _label(32, Color("4a3a32"))
	title.text = "%d웨이브를 막았다! 하나를 고르세요" % wave
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	vb.add_child(row)
	for i in cards.size():
		var info := _card_text(cards[i])
		var b := Button.new()
		b.custom_minimum_size = Vector2(230, 270)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", _btn_style(Color.WHITE, Color("e2d6bf")))
		b.add_theme_stylebox_override("hover", _btn_style(Color("fffaf0"), info[4]))
		b.add_theme_stylebox_override("pressed", _btn_style(Color("fffaf0"), info[4]))
		b.pressed.connect(_pick_card.bind(i))
		var cv := VBoxContainer.new()
		cv.set_anchors_preset(Control.PRESET_FULL_RECT)
		cv.offset_left = 14
		cv.offset_right = -14
		cv.offset_top = 18
		cv.offset_bottom = -14
		cv.add_theme_constant_override("separation", 10)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cv)
		var badge := Panel.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = info[4]
		bsb.set_corner_radius_all(36)
		badge.add_theme_stylebox_override("panel", bsb)
		badge.custom_minimum_size = Vector2(72, 72)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(badge)
		var ch := _label(38, Color.WHITE)
		ch.text = info[0]
		ch.set_anchors_preset(Control.PRESET_FULL_RECT)
		ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(ch)
		var nm := _label(22, Color("2a2a33"))
		nm.text = "%d. %s" % [i + 1, info[1]]
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nm)
		var tag := _label(14, info[4])
		tag.text = info[2]
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(tag)
		var d := _label(15, Color("4a3a32"), false)
		d.text = info[3]
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.custom_minimum_size = Vector2(200, 0)
		cv.add_child(d)
		row.add_child(b)
	card_box.visible = true
	card_dim.visible = true


func _show_result(won: bool) -> void:
	for c in overlay.get_children():
		c.queue_free()
	var panel := PanelContainer.new()
	var sb := _btn_style(Color(1, 1, 1, 0.96), Color("e2d6bf"))
	sb.set_content_margin_all(34)
	sb.set_corner_radius_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t1 := _label(44, Color("7a4fb0") if won else Color("c0503f"))
	t1.text = "마을을 지켰다!" if won else "결계가 무너졌다"
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t1)
	var t2 := _label(18, Color("4a3a32"), false)
	t2.text = "%d웨이브까지   ·   목숨 %d   ·   타워 %d개   ·   부적 %d개\nR 키를 눌러 다시" % [wave, lives, towers.size(), talismans.size()]
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t2)
	overlay.add_child(panel)
	overlay.visible = true


func _setup_input() -> void:
	var keys := {
		"pick_1": [KEY_1, KEY_KP_1], "pick_2": [KEY_2, KEY_KP_2], "pick_3": [KEY_3, KEY_KP_3],
		"pick_4": [KEY_4, KEY_KP_4], "pick_5": [KEY_5, KEY_KP_5],
		"start": [KEY_SPACE], "speed": [KEY_F], "cancel": [KEY_ESCAPE], "restart": [KEY_R],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)


## 오른쪽 위 오행 원: 바깥 화살표 = 상생(살림), 안쪽 별 = 상극(깨뜨림)
class CycleDiagram extends Control:
	var font: Font

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 70)
		var r := 50.0
		var pts: Array[Vector2] = []
		for i in 5:
			pts.append(c + Vector2.from_angle(-PI * 0.5 + TAU * i / 5.0) * r)
		# 상극 별 (안쪽, 붉은 점선 느낌)
		for i in 5:
			var a := pts[i]
			var b := pts[El.KE[i]]
			draw_line(a.lerp(b, 0.2), a.lerp(b, 0.8), Color("e04a3a", 0.55), 2.0, true)
		# 상생 고리 (바깥, 초록 화살표)
		for i in 5:
			var a := pts[i]
			var b := pts[El.GEN[i]]
			var m := a.lerp(b, 0.5)
			var out := (m - c).normalized() * 12.0
			var arc := PackedVector2Array([a.lerp(b, 0.22) + out * 0.5, m + out, a.lerp(b, 0.78) + out * 0.5])
			draw_polyline(arc, Color("3f9f5a"), 3.0, true)
			var dir := (arc[2] - arc[1]).normalized()
			draw_colored_polygon(PackedVector2Array([arc[2] + dir * 6, arc[2] - dir * 3 + dir.orthogonal() * 5, arc[2] - dir * 3 - dir.orthogonal() * 5]), Color("3f9f5a"))
		for i in 5:
			draw_circle(pts[i], 17, El.COL[i], true, -1.0, true)
			draw_arc(pts[i], 17, 0, TAU, 20, El.DARK[i], 2.0, true)
			var txt: String = El.NAMES[i]
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, pts[i] + Vector2(-w * 0.5, 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("2a2a33"))
		draw_string(font, Vector2(4, size.y - 18), "초록 화살표 = 살림 (+40%)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("3f9f5a"))
		draw_string(font, Vector2(4, size.y - 2), "붉은 선 = 깨뜨림 (−40%)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e04a3a"))
