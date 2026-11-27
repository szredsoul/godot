extends Node2D
## 공성전 (시험판)
## 네모난 성을 사방에서 도깨비가 공격한다. 공성추로 성문을 부수거나, 사다리로 성벽을 넘어온다.
## 병사 분대만으로 막는다. 분대는 성벽 위를 걷거나(느리지만 싸우며) 안마당을 가로질러(빠르지만 계단을 오르내림) 이동한다.
## 성 안에 들어온 적은 가운데 본성을 때린다. 본성 체력이 0이 되면 끝.

enum Phase { BUILD, FIGHT, CHOOSE, OVER, WIN }

const C := Vector2(470, 398) # 본성 위치 (성 한가운데)
const HW := 250.0 # 성 가로 절반
const HH := 150.0 # 성 세로 절반
const L := 470.0 - 250.0
const R := 470.0 + 250.0
const T := 398.0 - 150.0
const B := 398.0 + 150.0
const PERIM := 4.0 * 250.0 + 4.0 * 150.0 # 성벽 둘레
const WALL_W := 26.0 # 성벽 두께
const GATE_HALF := 26.0 # 성문 너비 절반
const BOARD := Rect2(16, 92, 908, 612)
const SIDE_NAMES: Array[String] = ["북", "동", "남", "서"]
const NORMALS: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const KEEP_R := 56.0
const KEEP_HP := 300.0
const GATE_HP := 800.0
const WAVES := 15
const START_GOLD := 180
const MAX_SQUADS := 10
const SQUAD_HP := 120.0 # 분대 체력 (병사 3명)
const REGEN := 4.0 # 싸우지 않을 때 초당 회복
const WALL_SPEED := 55.0 # 성벽 위 걷는 속도 (px/초)
const YARD_SPEED := 100.0 # 안마당 속도
const STAIR := 0.8 # 계단 오르내리는 시간
const CLIMB_TIME := 3.0 # 사다리를 다 오르는 시간
const PUSH_TIME := 3.0 # 창병이 사다리를 밀어내는 시간
const GATE_REPAIR_PER_GOLD := 6.0

const SQUADS := [
	{"name": "궁수", "key": "Z", "cost": 70, "dmg": 7.0, "rate": 0.75, "range": 250.0, "col": Color("3f9f5a"),
			"desc": "멀리 쏜다. 사다리를 오르는 적부터 노림. 성벽을 걸으면서도 쏜다"},
	{"name": "창병", "key": "X", "cost": 70, "dmg": 11.0, "rate": 0.8, "range": 46.0, "col": Color("c0503f"),
			"desc": "사다리를 밀어내고, 성벽에 올라온 적·성 안에 들어온 적과 싸운다"},
	{"name": "기름병", "key": "C", "cost": 80, "dmg": 30.0, "rate": 3.2, "range": 85.0, "col": Color("d9822b"),
			"desc": "성벽 바로 아래에 끓는 기름. 성문을 때리는 공성추에 아주 강함"},
	{"name": "석공", "key": "V", "cost": 60, "heal": 14.0, "col": Color("4a73c0"),
			"desc": "가까운 성문을 고친다. 부서진 성문도 다시 세운다"},
]
const S_ARCHER := 0
const S_SPEAR := 1
const S_OIL := 2
const S_MASON := 3

const ENEMY := {
	"grunt": {"name": "졸개", "hp": 60.0, "spd": 30.0, "r": 11.0, "dps": 5.0, "gate": 3.0, "reward": 2, "col": Color("9a7fd4")},
	"ladder": {"name": "사다리병", "hp": 50.0, "spd": 28.0, "r": 11.0, "dps": 4.0, "gate": 2.0, "reward": 3, "col": Color("d9a441")},
	"brute": {"name": "도끼 도깨비", "hp": 200.0, "spd": 22.0, "r": 15.0, "dps": 12.0, "gate": 6.0, "reward": 7, "col": Color("d0716a")},
	"ram": {"name": "공성추", "hp": 520.0, "spd": 13.0, "r": 22.0, "dps": 0.0, "gate": 26.0, "reward": 12, "col": Color("8a6a4a")},
	"boss": {"name": "큰 도깨비", "hp": 900.0, "spd": 13.0, "r": 28.0, "dps": 20.0, "gate": 25.0, "reward": 50, "col": Color("6b4aa0")},
}
const RAM_MUL := {"arrow": 0.3, "spear": 1.0, "oil": 2.5}
const BOSS_MUL := {"oil": 1.5}

const PERKS := {
	"gate": {"name": "두꺼운 문", "char": "문", "desc": "모든 성문 최대 체력 +30%, 부서진 문까지 다 고친다", "once": false},
	"drill": {"name": "발 빠른 훈련", "char": "발", "desc": "분대 이동이 40% 빨라진다", "once": true},
	"veteran": {"name": "노련한 병사", "char": "병", "desc": "모든 분대 피해 +25%", "once": false},
	"recruit": {"name": "의병", "char": "의", "desc": "궁수 분대 하나가 공짜로 합류한다", "once": false},
	"coins": {"name": "골드 주머니", "char": "금", "desc": "골드 +100", "once": false},
	"keep": {"name": "본성 보수", "char": "성", "desc": "본성 체력 +60 (최대 체력도 +20)", "once": false},
	"longbow": {"name": "강궁", "char": "궁", "desc": "궁수 피해 +30%, 사거리 +30", "once": false},
	"oil_up": {"name": "끓는 기름", "char": "기", "desc": "기름병 피해 +40%", "once": false},
	"hook": {"name": "갈고리 창", "char": "창", "desc": "사다리를 두 배 빨리 밀어낸다", "once": true},
	"armor": {"name": "두꺼운 갑옷", "char": "갑", "desc": "모든 분대 최대 체력 +30%, 다 채운다", "once": false},
}

var phase := Phase.BUILD
var wave := 0
var gold := START_GOLD
var keep_hp := KEEP_HP
var keep_max := KEEP_HP
var t := 0.0
var fight_t := 0.0
var speed := 1.0
var rng := RandomNumberGenerator.new()

var gates: Array[Dictionary] = [] # 옆면마다 {hp, max, broken, rebuild, flash}
var squads: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var ladders: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var fxs: Array[Dictionary] = []
var parts: Array[Dictionary] = []
var spawn_queue: Array[Dictionary] = []
var announced := {}
var plan: Array = []

var sel := -1
var held := -1 # 0~3 분대 모집, -2 골드로 성문 수리
var wall_speed := WALL_SPEED
var yard_speed := YARD_SPEED
var squad_max := SQUAD_HP
var perks := {}
var bonus := {"dmg": 0.0, "arrow": 0.0, "range": 0.0, "oil": 0.0, "push": 1.0}
var shake := 0.0
var drum_t := 0.0
var breach_t := 0.0
var deco: Array[Dictionary] = []

var sfx: Sfx
var font_b: SystemFont
var font_r: SystemFont
var ui: Control
var stat_label: Label
var alert_label: Label
var next_title: Label
var next_label: RichTextLabel
var squad_btns: Array[Button] = []
var hire_btns: Array[Button] = []
var repair_btn: Button
var start_btn: Button
var speed_btn: Button
var perk_label: Label
var tip_label: Label
var card_box: CenterContainer
var card_dim: ColorRect
var overlay: CenterContainer
var cards: Array[Dictionary] = []


func _ready() -> void:
	rng.randomize()
	font_b = _font(true)
	font_r = _font(false)
	sfx = Sfx.new()
	add_child(sfx)
	for s in 4:
		gates.append({"hp": GATE_HP, "max": GATE_HP, "broken": false, "rebuild": 0.0, "flash": 0.0})
	# 처음 분대: 북·남 궁수, 동·서 창병
	_add_squad(S_ARCHER, true, gate_u(0) - 60.0, Vector2.ZERO, true)
	_add_squad(S_ARCHER, true, gate_u(2) + 60.0, Vector2.ZERO, true)
	_add_squad(S_SPEAR, true, gate_u(1), Vector2.ZERO, true)
	_add_squad(S_SPEAR, true, gate_u(3), Vector2.ZERO, true)
	_build_deco()
	_make_plan()
	_setup_input()
	_build_ui()
	_refresh_ui()


static func _font(bold: bool) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"])
	f.font_weight = 700 if bold else 400
	return f


# ───────────── 성벽 기하 (둘레 위치 u: 왼쪽 위 모서리에서 시계 방향) ─────────────

func wall_point(u: float) -> Vector2:
	u = fposmod(u, PERIM)
	if u < 2.0 * HW:
		return Vector2(L + u, T)
	u -= 2.0 * HW
	if u < 2.0 * HH:
		return Vector2(R, T + u)
	u -= 2.0 * HH
	if u < 2.0 * HW:
		return Vector2(R - u, B)
	u -= 2.0 * HW
	return Vector2(L, B - u)


func side_of(u: float) -> int:
	u = fposmod(u, PERIM)
	if u < 2.0 * HW:
		return 0
	if u < 2.0 * HW + 2.0 * HH:
		return 1
	if u < 4.0 * HW + 2.0 * HH:
		return 2
	return 3


func gate_u(s: int) -> float:
	return [HW, 2.0 * HW + HH, 2.0 * HW + 2.0 * HH + HW, 4.0 * HW + 2.0 * HH + HH][s]


func gate_point(s: int) -> Vector2:
	return wall_point(gate_u(s))


## 둘레에서 가장 가까운 점 {u, dist}
func project(p: Vector2) -> Dictionary:
	var best_u := 0.0
	var best_d := 1e9
	var cands := [
		[clampf(p.x, L, R) - L, absf(p.y - T), p.x >= L - 20 and p.x <= R + 20],
		[2.0 * HW + clampf(p.y, T, B) - T, absf(p.x - R), p.y >= T - 20 and p.y <= B + 20],
		[2.0 * HW + 2.0 * HH + R - clampf(p.x, L, R), absf(p.y - B), p.x >= L - 20 and p.x <= R + 20],
		[4.0 * HW + 2.0 * HH + B - clampf(p.y, T, B), absf(p.x - L), p.y >= T - 20 and p.y <= B + 20],
	]
	for c in cands:
		if c[2] and float(c[1]) < best_d:
			best_d = c[1]
			best_u = c[0]
	return {"u": best_u, "dist": best_d}


func u_diff(a: float, b: float) -> float:
	## a에서 b까지 가장 짧은 부호 있는 거리
	return wrapf(b - a, -PERIM * 0.5, PERIM * 0.5)


func in_yard(p: Vector2) -> bool:
	return p.x > L + WALL_W * 0.5 + 6 and p.x < R - WALL_W * 0.5 - 6 and p.y > T + WALL_W * 0.5 + 6 and p.y < B - WALL_W * 0.5 - 6


## 마우스가 성벽 위면 둘레 위치, 아니면 -1
func wall_at(p: Vector2) -> float:
	var pr := project(p)
	return float(pr["u"]) if float(pr["dist"]) < 18.0 else -1.0


func near_gate(u: float) -> int:
	for s in 4:
		if absf(u_diff(u, gate_u(s))) < GATE_HALF + 4.0:
			return s
	return -1


# ───────────── 분대 ─────────────

func _add_squad(ty: int, on_wall: bool, u: float, p: Vector2, instant: bool) -> void:
	var sq := {"type": ty, "hp": squad_max, "wall": on_wall, "u": u, "pos": wall_point(u) if on_wall else p,
			"mode": 0, "dest_wall": on_wall, "dest_u": u, "dest_p": p, "step": 1, "stair": 0.0,
			"cd": rng.randf() * 0.5, "flash": 0.0, "fight": 0.0}
	if not instant:
		# 본성에서 나와 걸어간다
		sq["wall"] = false
		sq["pos"] = C + Vector2(0, 46)
		sq["mode"] = 2
		sq["step"] = 1
	squads.append(sq)


func squad_goal_point(sq: Dictionary) -> Vector2:
	if bool(sq["dest_wall"]):
		var u: float = sq["dest_u"]
		return wall_point(u) - NORMALS[side_of(u)] * 22.0
	return sq["dest_p"]


func travel_time(sq: Dictionary, to_wall: bool, u: float, p: Vector2, yard: bool) -> float:
	if to_wall and bool(sq["wall"]) and int(sq["mode"]) != 2 and not yard:
		return absf(u_diff(float(sq["u"]), u)) / wall_speed
	var start: Vector2 = sq["pos"]
	var tt := 0.0
	if bool(sq["wall"]) and int(sq["mode"]) != 2:
		tt += STAIR
		start = wall_point(float(sq["u"])) - NORMALS[side_of(float(sq["u"]))] * 22.0
	var goal := wall_point(u) - NORMALS[side_of(u)] * 22.0 if to_wall else p
	tt += start.distance_to(goal) / yard_speed
	if to_wall:
		tt += STAIR
	return tt


func _order(i: int, to_wall: bool, u: float, p: Vector2, yard: bool) -> void:
	var sq: Dictionary = squads[i]
	var eta := travel_time(sq, to_wall, u, p, yard)
	var on_wall_now := bool(sq["wall"]) and int(sq["mode"]) != 2
	sq["dest_wall"] = to_wall
	sq["dest_u"] = u
	sq["dest_p"] = p
	if to_wall and on_wall_now and not yard:
		sq["mode"] = 1
	elif int(sq["mode"]) == 2:
		# 이미 안마당을 걷는 중이면 목적지만 바꾼다 (계단 내려가는 중이면 그대로)
		if int(sq["step"]) == 2:
			sq["step"] = 1
			sq["stair"] = 0.0
	else:
		sq["mode"] = 2
		sq["step"] = 0 if on_wall_now else 1
		sq["stair"] = STAIR if on_wall_now else 0.0
	sfx.play("pop", 1.2 if yard else 0.9, -8.0)
	var at := wall_point(u) if to_wall else p
	_float_text("%.1f초" % eta, at + Vector2(0, -34), 17, Color("4a3a32"))


func _squads_step(dt: float) -> void:
	for sq in squads:
		sq["flash"] = maxf(0.0, float(sq["flash"]) - dt)
		sq["fight"] = maxf(0.0, float(sq["fight"]) - dt)
		match int(sq["mode"]):
			1: # 성벽 위를 걷는다
				var rem := u_diff(float(sq["u"]), float(sq["dest_u"]))
				var step := wall_speed * dt
				if absf(rem) <= step:
					sq["u"] = sq["dest_u"]
					sq["mode"] = 0
				else:
					sq["u"] = fposmod(float(sq["u"]) + signf(rem) * step, PERIM)
				sq["pos"] = wall_point(float(sq["u"]))
			2: # 안마당: 0 계단 내려감 → 1 걷기 → 2 계단 올라감
				match int(sq["step"]):
					0:
						sq["stair"] = float(sq["stair"]) - dt
						var u: float = sq["u"]
						var k := 1.0 - maxf(0.0, float(sq["stair"])) / STAIR
						sq["pos"] = wall_point(u) - NORMALS[side_of(u)] * 22.0 * k
						if float(sq["stair"]) <= 0.0:
							sq["wall"] = false
							sq["step"] = 1
					1:
						var goal := squad_goal_point(sq)
						var pp: Vector2 = sq["pos"]
						pp = pp.move_toward(goal, yard_speed * dt)
						sq["pos"] = pp
						if pp.distance_to(goal) < 0.5:
							if bool(sq["dest_wall"]):
								sq["step"] = 2
								sq["stair"] = STAIR
							else:
								sq["mode"] = 0
					2:
						sq["stair"] = float(sq["stair"]) - dt
						var u: float = sq["dest_u"]
						var k := 1.0 - maxf(0.0, float(sq["stair"])) / STAIR
						sq["pos"] = (wall_point(u) - NORMALS[side_of(u)] * 22.0).lerp(wall_point(u), k)
						if float(sq["stair"]) <= 0.0:
							sq["wall"] = true
							sq["u"] = u
							sq["mode"] = 0
		if phase == Phase.FIGHT:
			_squad_act(sq, dt)
		# 싸우지 않으면 조금씩 회복
		if float(sq["fight"]) <= 0.0:
			sq["hp"] = minf(squad_max, float(sq["hp"]) + REGEN * dt)
	# 전멸한 분대 정리
	for i in range(squads.size() - 1, -1, -1):
		if float(squads[i]["hp"]) <= 0.0:
			var p: Vector2 = squads[i]["pos"]
			_float_text("%d분대(%s) 전멸!" % [i + 1, SQUADS[int(squads[i]["type"])]["name"]], p + Vector2(0, -30), 22, Color("c0503f"))
			sfx.play("die", 0.8, -2.0)
			for j in 14:
				_spark(p, SQUADS[int(squads[i]["type"])]["col"], 160.0)
			squads.remove_at(i)
			if sel == i:
				sel = -1
			elif sel > i:
				sel -= 1


func _squad_on_wall(sq: Dictionary) -> bool:
	return bool(sq["wall"]) and int(sq["mode"]) != 2


func _squad_act(sq: Dictionary, dt: float) -> void:
	var ty: int = sq["type"]
	var mode: int = sq["mode"]
	if mode == 2:
		return # 계단·안마당을 지나는 동안은 못 싸운다
	var p: Vector2 = sq["pos"]
	var on_wall := _squad_on_wall(sq)
	var info: Dictionary = SQUADS[ty]
	var dmg_mul := 1.0 + float(bonus["dmg"])
	match ty:
		S_ARCHER:
			sq["cd"] = float(sq["cd"]) - dt * (0.6 if mode == 1 else 1.0)
			if float(sq["cd"]) > 0.0:
				return
			var tgt := _archer_target(p, float(info["range"]) + float(bonus["range"]))
			if tgt.is_empty():
				return
			sq["cd"] = info["rate"]
			sq["flash"] = 0.15
			shots.append({"p": p + Vector2(0, -10), "target": tgt, "dmg": float(info["dmg"]) * dmg_mul * (1.0 + float(bonus["arrow"])), "to": tgt["pos"]})
			if randf() < 0.35:
				sfx.play("shoot", randf_range(1.5, 1.7), -18.0)
		S_SPEAR:
			if mode != 0:
				return
			# 사다리 밀어내기
			if on_wall:
				for lad in ladders:
					if not lad["alive"] or (lad["top"] as Vector2).distance_to(p) > 48.0:
						continue
					var top_busy := false
					var climber: Dictionary = lad["busy"]
					if not climber.is_empty() and (int(climber["state"]) == 3 or float(climber["climb"]) > 0.75):
						top_busy = true
					if not top_busy:
						lad["push"] = float(lad["push"]) + dt * float(bonus["push"])
						if float(lad["push"]) >= PUSH_TIME:
							_remove_ladder(lad, true)
			sq["cd"] = float(sq["cd"]) - dt
			if float(sq["cd"]) > 0.0:
				return
			var hits := 0
			for e in enemies:
				if e["dead"]:
					continue
				var st: int = e["state"]
				var can := false
				if on_wall:
					can = st == 3 or (st == 2 and float(e["climb"]) > 0.7)
				else:
					can = st >= 4
				if can and (e["pos"] as Vector2).distance_to(p) < float(info["range"]) + float(e["r"]):
					_hit(e, float(info["dmg"]) * dmg_mul, "spear")
					hits += 1
					if hits >= 2:
						break
			if hits > 0:
				sq["cd"] = info["rate"]
				sq["flash"] = 0.2
				sq["fight"] = 1.0
				if randf() < 0.5:
					sfx.play("cut", randf_range(1.1, 1.3), -14.0)
		S_OIL:
			if not on_wall or mode != 0:
				return
			sq["cd"] = float(sq["cd"]) - dt
			if float(sq["cd"]) > 0.0:
				return
			var n: Vector2 = NORMALS[side_of(float(sq["u"]))]
			var spot := p + n * 40.0
			var any := false
			for e in enemies:
				if e["dead"] or int(e["state"]) > 2:
					continue
				if (e["pos"] as Vector2).distance_to(spot) < float(info["range"]) + float(e["r"]):
					any = true
					_hit(e, float(info["dmg"]) * dmg_mul * (1.0 + float(bonus["oil"])), "oil")
			if any:
				sq["cd"] = info["rate"]
				sq["flash"] = 0.4
				fxs.append({"type": "oil", "p": spot, "t": 0.0, "life": 0.6, "r": float(info["range"])})
				sfx.play("dash", 0.55, -6.0)
		S_MASON:
			if mode != 0:
				return
			for s in 4:
				if gate_point(s).distance_to(p) > 80.0:
					continue
				var g: Dictionary = gates[s]
				var heal: float = float(info["heal"]) * dt
				if bool(g["broken"]):
					g["rebuild"] = float(g["rebuild"]) + heal * 0.5
					if float(g["rebuild"]) >= float(g["max"]) * 0.35:
						g["broken"] = false
						g["hp"] = float(g["max"]) * 0.35
						g["rebuild"] = 0.0
						_float_text("%s문을 다시 세웠다!" % SIDE_NAMES[s], gate_point(s) + Vector2(0, -40), 22, Color("2f8f4a"))
						sfx.play("block", 0.9, -2.0)
				elif float(g["hp"]) < float(g["max"]):
					g["hp"] = minf(float(g["max"]), float(g["hp"]) + heal)
					if randf() < dt * 4.0:
						_spark(gate_point(s), Color("d8cfc0"), 70.0)
				break


## 궁수 표적: 사다리를 오르거나 성벽에 올라온 적 > 성 안의 적 > 가까운 적
func _archer_target(p: Vector2, r: float) -> Dictionary:
	var best: Dictionary = {}
	var bs := -1e9
	for e in enemies:
		if e["dead"]:
			continue
		var d := (e["pos"] as Vector2).distance_to(p)
		if d > r:
			continue
		var st: int = e["state"]
		var s := -d
		if st == 3 or (st == 2 and float(e["climb"]) > 0.0):
			s += 600.0
		elif st >= 4:
			s += 400.0
		elif st == 1:
			s += 150.0
		if s > bs:
			bs = s
			best = e
	return best


# ───────────── 웨이브 ─────────────

func _make_plan() -> void:
	plan.append([])
	for w in range(1, WAVES + 1):
		var ndir := 1 if w <= 2 else (2 if w <= 5 else (3 if w <= 9 else 4))
		var dirs: Array[int] = [0, 1, 2, 3]
		dirs.shuffle()
		var groups := []
		var total := 10.0 + w * 3.4
		for i in ndir:
			var share := total / ndir * (1.25 if i == 0 else 0.9)
			var g := {"side": dirs[i], "delay": i * 8.0, "grunt": 0, "ladder": 0, "brute": 0, "ram": 0, "boss": 0}
			g["ladder"] = maxi(1, int(share * 0.22))
			g["brute"] = int(share * 0.12) if w >= 6 else 0
			g["ram"] = (1 if (w >= 3 and i == 0) or (w >= 8 and i == 1) else 0) + (1 if w >= 12 and i == 0 else 0)
			g["grunt"] = maxi(3, int(share) - int(g["ladder"]) - int(g["brute"]) * 2 - int(g["ram"]) * 3)
			if w % 5 == 0 and i == 0:
				g["boss"] = 1 + (1 if w == 15 else 0)
			groups.append(g)
		plan.append(groups)


func _hp_mul(w: int) -> float:
	return 1.0 + 0.1 * (w - 1) + 0.01 * (w - 1) * (w - 1)


func _start_wave() -> void:
	if phase != Phase.BUILD:
		return
	held = -1
	phase = Phase.FIGHT
	fight_t = 0.0
	announced.clear()
	spawn_queue.clear()
	for g in plan[wave + 1]:
		var at: float = g["delay"]
		var order: Array[String] = []
		for i in int(g["ladder"]):
			order.append("ladder")
		for kind in ["grunt", "brute", "ram", "boss"]:
			for i in int(g[kind]):
				order.append(kind)
		for kind in order:
			spawn_queue.append({"side": g["side"], "kind": kind, "at": at})
			at += 2.0 if kind in ["ram", "boss"] else 0.7
	spawn_queue.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))
	sfx.play("drum", 0.8, 0.0)
	sfx.play("warn", 0.7, -4.0)
	_float_text("%d웨이브 — 적이 성을 에워싼다!" % (wave + 1), C + Vector2(0, -90), 32, Color("8a2a20"))
	_refresh_ui()


func _spawn_point(s: int) -> Vector2:
	match s:
		0:
			return Vector2(rng.randf_range(L + 20, R - 20), BOARD.position.y + 8)
		1:
			return Vector2(BOARD.end.x - 8, rng.randf_range(T + 10, B - 10))
		2:
			return Vector2(rng.randf_range(L + 20, R - 20), BOARD.end.y - 8)
	return Vector2(BOARD.position.x + 8, rng.randf_range(T + 10, B - 10))


func _side_span(s: int) -> Vector2:
	## 옆면의 u 범위 (모서리 30px 빼고)
	var starts := [0.0, 2.0 * HW, 2.0 * HW + 2.0 * HH, 4.0 * HW + 2.0 * HH]
	var lens := [2.0 * HW, 2.0 * HH, 2.0 * HW, 2.0 * HH]
	return Vector2(float(starts[s]) + 30.0, float(starts[s]) + float(lens[s]) - 30.0)


func _spawn(sp: Dictionary) -> void:
	var k: Dictionary = ENEMY[sp["kind"]]
	var s: int = sp["side"]
	if not announced.has(s):
		announced[s] = true
		sfx.play("warn", 0.85, -6.0)
		_float_text("%s쪽에서 적이 온다!" % SIDE_NAMES[s], _spawn_point(s).lerp(C, 0.25), 22, Color("c0503f"))
	var hp: float = float(k["hp"]) * _hp_mul(wave + 1)
	var e := {"kind": sp["kind"], "side": s, "pos": _spawn_point(s), "hp": hp, "max": hp, "spd": k["spd"], "r": k["r"],
			"dps": k["dps"], "gate_dps": k["gate"], "reward": k["reward"], "state": 0, "goal": "gate", "u": gate_u(s),
			"lad": {}, "climb": 0.0, "ph": rng.randf() * TAU, "flash": 0.0, "dead": false, "retarget": 0.0,
			"off": rng.randf_range(-16.0, 16.0)}
	if sp["kind"] == "ladder":
		# 성문에서 떨어진 성벽 아무 곳에 사다리를 건다
		var span := _side_span(s)
		var u := rng.randf_range(span.x, span.y)
		for tries in 8:
			if absf(u_diff(u, gate_u(s))) > GATE_HALF + 40.0:
				break
			u = rng.randf_range(span.x, span.y)
		e["goal"] = "plant"
		e["u"] = u
	elif sp["kind"] in ["grunt", "brute"]:
		_retarget(e)
	enemies.append(e)


## 졸개·도끼 도깨비: 성문이 부서졌으면 성문, 사다리가 있으면 가까운 사다리, 아니면 성문
func _retarget(e: Dictionary) -> void:
	var s: int = e["side"]
	e["state"] = 0
	e["lad"] = {}
	e["climb"] = 0.0
	if bool(gates[s]["broken"]):
		e["goal"] = "gate"
		e["u"] = gate_u(s)
		return
	var best: Dictionary = {}
	var bd := 1e9
	for lad in ladders:
		if lad["alive"] and int(lad["side"]) == s:
			var d := (lad["base"] as Vector2).distance_to(e["pos"])
			if d < bd:
				bd = d
				best = lad
	if best.is_empty():
		e["goal"] = "gate"
		e["u"] = gate_u(s)
	else:
		e["goal"] = "ladder"
		e["lad"] = best
		e["u"] = best["u"]


func _approach_point(e: Dictionary) -> Vector2:
	var u: float = e["u"]
	var n: Vector2 = NORMALS[side_of(u)]
	var along := n.orthogonal() * float(e["off"]) * (1.0 if e["goal"] == "gate" else 0.4)
	return wall_point(u) + n * (WALL_W * 0.5 + float(e["r"]) + 4.0) + along


# ───────────── 매 프레임 ─────────────

func _process(delta: float) -> void:
	if phase == Phase.CHOOSE:
		for i in cards.size():
			if Input.is_action_just_pressed("sq_%d" % (i + 1)):
				_pick_card(i)
	elif phase in [Phase.BUILD, Phase.FIGHT]:
		for i in MAX_SQUADS:
			if Input.is_action_just_pressed("sq_%d" % (i + 1)) and i < squads.size():
				_select(i)
		for i in 4:
			if Input.is_action_just_pressed("hire_%d" % i):
				_pick_hold(i)
		if Input.is_action_just_pressed("repair"):
			_pick_hold(-2)
		if Input.is_action_just_pressed("start"):
			_start_wave()
		if Input.is_action_just_pressed("speed"):
			_toggle_speed()
	if Input.is_action_just_pressed("restart") and phase in [Phase.OVER, Phase.WIN]:
		get_tree().reload_current_scene()
		return
	var dt := delta * (speed if phase == Phase.FIGHT else 1.0)
	t += delta
	for g in gates:
		g["flash"] = maxf(0.0, float(g["flash"]) - delta)
	_squads_step(dt)
	if phase == Phase.FIGHT:
		fight_t += dt
		while not spawn_queue.is_empty() and float(spawn_queue[0]["at"]) <= fight_t:
			_spawn(spawn_queue.pop_front())
		_enemies_step(dt)
		_shots_step(dt)
		_war_drums(delta)
		if phase == Phase.FIGHT:
			_check_wave_end()
	_fx_step(dt)
	shake = maxf(0.0, shake - delta * 30.0)
	position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	modulate = modulate.lerp(Color(0.9, 0.86, 0.93) if phase == Phase.FIGHT else Color.WHITE, minf(1.0, delta * 2.0))
	_refresh_stats()
	_update_alerts()
	_update_tip()
	queue_redraw()


func _war_drums(delta: float) -> void:
	drum_t -= delta
	if drum_t <= 0.0:
		drum_t = 0.75 if breach_t > 0.0 else 1.5
		sfx.play("drum", 0.75 if breach_t > 0.0 else 0.65, -13.0 if breach_t > 0.0 else -17.0)


func _select(i: int) -> void:
	sel = i if sel != i else -1
	held = -1
	sfx.play("pop", 1.0, -10.0)


func _pick_hold(h: int) -> void:
	if phase not in [Phase.BUILD, Phase.FIGHT]:
		return
	held = h if held != h else -1
	sel = -1
	sfx.play("pop", 1.3, -10.0)


func _toggle_speed() -> void:
	speed = {1.0: 2.0, 2.0: 3.0, 3.0: 1.0}[speed]
	_refresh_ui()


func squad_at_point(p: Vector2) -> int:
	var best := -1
	var bd := 22.0
	for i in squads.size():
		var d := (squads[i]["pos"] as Vector2).distance_to(p + Vector2(0, 8))
		if d < bd:
			bd = d
			best = i
	return best


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		if event.is_action_pressed("cancel"):
			held = -1
			sel = -1
		return
	if phase not in [Phase.BUILD, Phase.FIGHT]:
		return
	var mp := get_global_mouse_position()
	var u := wall_at(mp)
	var yard_ok := in_yard(mp) and u < 0.0 and mp.distance_to(C) > KEEP_R
	var right: bool = event.button_index == MOUSE_BUTTON_RIGHT
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	if held == -2:
		if right:
			held = -1
		else:
			_repair_click(mp)
		return
	if held >= 0:
		if right:
			held = -1
			return
		_hire_click(held, u, mp, yard_ok)
		return
	var hit := squad_at_point(mp)
	if not right and hit >= 0:
		_select(hit)
		return
	if sel >= 0:
		if u >= 0.0:
			_order(sel, true, u, Vector2.ZERO, right)
		elif yard_ok:
			_order(sel, false, 0.0, mp, true)
		elif right:
			sel = -1
		return
	if right:
		held = -1


func _hire_click(ty: int, u: float, mp: Vector2, yard_ok: bool) -> void:
	var cost: int = SQUADS[ty]["cost"]
	if squads.size() >= MAX_SQUADS:
		_float_text("분대는 %d개까지" % MAX_SQUADS, mp + Vector2(0, -30), 18, Color("c0503f"))
		return
	if u < 0.0 and not yard_ok:
		return
	if gold < cost:
		_float_text("골드가 모자라요", mp + Vector2(0, -30), 18, Color("c0503f"))
		return
	gold -= cost
	var instant := phase == Phase.BUILD
	_add_squad(ty, u >= 0.0, u, mp, instant)
	var sq: Dictionary = squads[squads.size() - 1]
	if not instant:
		sq["dest_wall"] = u >= 0.0
		sq["dest_u"] = maxf(u, 0.0)
		sq["dest_p"] = mp
	sfx.play("place", 1.1, -2.0)
	_float_text("%s %d분대" % [SQUADS[ty]["name"], squads.size()], mp + Vector2(0, -30), 20, SQUADS[ty]["col"])
	held = -1
	_refresh_ui()


func gate_repair_cost(s: int) -> int:
	var g: Dictionary = gates[s]
	var missing := float(g["max"]) - float(g["hp"]) if not bool(g["broken"]) else float(g["max"])
	if missing < 1.0:
		return 0
	return ceili(missing / GATE_REPAIR_PER_GOLD) + (30 if bool(g["broken"]) else 0)


func _repair_click(mp: Vector2) -> void:
	var best := -1
	for s in 4:
		if gate_point(s).distance_to(mp) < 50.0:
			best = s
	if best < 0:
		_float_text("성문을 누르세요", mp + Vector2(0, -30), 18, Color("c0503f"))
		return
	var cost := gate_repair_cost(best)
	if cost == 0:
		_float_text("멀쩡해요", mp + Vector2(0, -30), 18, Color("4a3a32"))
		return
	var g: Dictionary = gates[best]
	if bool(g["broken"]) and gold < cost:
		_float_text("골드 %d 필요" % cost, mp + Vector2(0, -30), 18, Color("c0503f"))
		return
	var pay := mini(cost, gold)
	if pay <= 0:
		return
	gold -= pay
	if bool(g["broken"]) or pay == cost:
		g["broken"] = false
		g["hp"] = g["max"]
		g["rebuild"] = 0.0
	else:
		g["hp"] = minf(float(g["max"]), float(g["hp"]) + pay * GATE_REPAIR_PER_GOLD)
	sfx.play("block", 1.0, -3.0)
	_float_text("-%d" % pay, gate_point(best) + Vector2(0, -40), 18, Color("c28520"))
	_refresh_ui()


# ───────────── 적 ─────────────

func _enemies_step(dt: float) -> void:
	var inside := false
	for e in enemies:
		if e["dead"]:
			continue
		e["ph"] = float(e["ph"]) + dt * 6.0
		e["flash"] = maxf(0.0, float(e["flash"]) - dt)
		var s: int = e["side"]
		var pos: Vector2 = e["pos"]
		var spd: float = e["spd"]
		match int(e["state"]):
			0: # 성 쪽으로 걸어옴
				if e["kind"] in ["grunt", "brute"]:
					e["retarget"] = float(e["retarget"]) - dt
					if float(e["retarget"]) <= 0.0:
						e["retarget"] = 1.0
						if e["goal"] == "gate" or not (e["lad"] as Dictionary).get("alive", false):
							_retarget(e)
				var goal := _approach_point(e)
				pos = pos.move_toward(goal, spd * dt)
				e["pos"] = pos
				if pos.distance_to(goal) < 1.0:
					match String(e["goal"]):
						"gate":
							e["state"] = 1
						"plant":
							_plant_ladder(e)
						"ladder":
							e["state"] = 2
			1: # 성문을 때린다
				var g: Dictionary = gates[s]
				if bool(g["broken"]):
					e["state"] = 4
				else:
					g["hp"] = float(g["hp"]) - float(e["gate_dps"]) * dt
					g["flash"] = 0.08
					if float(g["hp"]) <= 0.0:
						_break_gate(s)
			2: # 사다리 아래에서 기다리거나 오른다
				var lad: Dictionary = e["lad"]
				if lad.is_empty() or not lad["alive"]:
					_retarget(e)
					continue
				var busy: Dictionary = lad["busy"]
				if busy.is_empty():
					lad["busy"] = e
					busy = e
					e["climb"] = 0.0
				if is_same(busy, e):
					var ct := CLIMB_TIME * (1.25 if e["kind"] == "brute" else 1.0)
					e["climb"] = minf(1.0, float(e["climb"]) + dt / ct)
					e["pos"] = (lad["base"] as Vector2).lerp(lad["top"], float(e["climb"]))
					if float(e["climb"]) >= 1.0:
						if _defenders_near(lad["top"], 50.0).is_empty():
							_over_wall(e, lad)
						else:
							e["state"] = 3
				else:
					var wait: Vector2 = (lad["base"] as Vector2) + NORMALS[s] * 18.0 + NORMALS[s].orthogonal() * float(e["off"])
					e["pos"] = pos.move_toward(wait, spd * dt)
			3: # 성벽 위에서 싸운다
				var lad: Dictionary = e["lad"]
				var foes := _defenders_near(pos, 55.0)
				if foes.is_empty():
					_over_wall(e, lad)
				else:
					var sq: Dictionary = foes[0]
					sq["hp"] = float(sq["hp"]) - float(e["dps"]) * dt
					sq["fight"] = 1.0
			4: # 성 안: 마주친 분대와 싸우거나 본성으로
				inside = true
				var foe := _yard_foe(pos, 55.0)
				if not foe.is_empty():
					foe["hp"] = float(foe["hp"]) - float(e["dps"]) * dt
					foe["fight"] = 1.0
				else:
					pos = pos.move_toward(C, spd * dt)
					e["pos"] = pos
					if pos.distance_to(C) < KEEP_R + float(e["r"]):
						e["state"] = 5
			5: # 본성을 때린다
				inside = true
				var foe := _yard_foe(pos, 55.0)
				if not foe.is_empty():
					foe["hp"] = float(foe["hp"]) - float(e["dps"]) * dt
					foe["fight"] = 1.0
				else:
					keep_hp -= maxf(float(e["dps"]), float(e["gate_dps"]) * 0.5) * dt
					if keep_hp <= 0.0:
						keep_hp = 0.0
						_finish(false)
						return
	var keep: Array[Dictionary] = []
	for e in enemies:
		if not e["dead"]:
			keep.append(e)
	enemies = keep
	breach_t = breach_t + dt if inside else 0.0


## 성벽 위에 있는(계단·안마당 이동 중이 아닌) 분대 중 가까운 것들
func _defenders_near(p: Vector2, r: float) -> Array:
	var out := []
	for sq in squads:
		if _squad_on_wall(sq) and (sq["pos"] as Vector2).distance_to(p) < r:
			out.append(sq)
	return out


## 안마당에 있는 분대 중 가장 가까운 것
func _yard_foe(p: Vector2, r: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := r
	for sq in squads:
		if bool(sq["wall"]) and int(sq["mode"]) != 2:
			continue
		var d := (sq["pos"] as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = sq
	return best


func _plant_ladder(e: Dictionary) -> void:
	var u: float = e["u"]
	var s := side_of(u)
	var n: Vector2 = NORMALS[s]
	var lad := {"side": s, "u": u, "base": wall_point(u) + n * (WALL_W * 0.5 + 22.0), "top": wall_point(u),
			"inside": wall_point(u) - n * (WALL_W * 0.5 + 20.0), "busy": {}, "push": 0.0, "alive": true}
	ladders.append(lad)
	e["lad"] = lad
	e["state"] = 2
	sfx.play("block", 0.6, -6.0)
	_float_text("%s쪽 사다리!" % SIDE_NAMES[s], lad["top"] + n * 40.0, 18, Color("c0503f"))
	# 같은 쪽 졸개들이 이 사다리로 몰린다
	for o in enemies:
		if int(o["side"]) == s and int(o["state"]) == 0 and o["kind"] in ["grunt", "brute"]:
			o["retarget"] = 0.0


func _over_wall(e: Dictionary, lad: Dictionary) -> void:
	e["state"] = 4
	e["pos"] = lad["inside"]
	if not lad.is_empty() and is_same(lad["busy"], e):
		lad["busy"] = {}
	_float_text("넘어왔다!", lad["inside"], 18, Color("c0503f"))
	sfx.play("warn", 1.2, -6.0)


func _remove_ladder(lad: Dictionary, pushed: bool) -> void:
	lad["alive"] = false
	var climber: Dictionary = lad["busy"]
	lad["busy"] = {}
	if pushed:
		_float_text("사다리를 밀어냈다!", lad["top"] + NORMALS[int(lad["side"])] * 40.0, 18, Color("2f8f4a"))
		sfx.play("break", 1.3, -4.0)
		for i in 10:
			_spark(lad["base"], Color("8a6a4a"), 160.0)
	if not climber.is_empty() and not climber["dead"]:
		# 오르던 적은 떨어져서 크게 다친다
		climber["pos"] = lad["base"]
		_hit(climber, float(climber["max"]) * 0.5, "fall")
		if not climber["dead"]:
			_retarget(climber)
	ladders = ladders.filter(func(x): return x["alive"])


func _break_gate(s: int) -> void:
	var g: Dictionary = gates[s]
	g["hp"] = 0.0
	g["broken"] = true
	g["rebuild"] = 0.0
	shake = 12.0
	sfx.play("break", 0.7, 0.0)
	sfx.play("slam", 0.8, -2.0)
	for i in 24:
		_spark(gate_point(s), Color("8a6a4a") if i % 2 == 0 else Color("bfb3a0"), 240.0)
	_float_text("%s문이 부서졌다!" % SIDE_NAMES[s], gate_point(s) + NORMALS[s] * 50.0, 26, Color("c0503f"))
	# 그쪽 적이 모두 성문으로 몰린다
	for e in enemies:
		if int(e["side"]) == s and int(e["state"]) == 0 and e["kind"] in ["grunt", "brute"]:
			_retarget(e)


func _hit(e: Dictionary, dmg: float, src: String) -> void:
	if e["dead"]:
		return
	if e["kind"] == "boss" and BOSS_MUL.has(src):
		dmg *= float(BOSS_MUL[src])
	if e["kind"] == "ram" and RAM_MUL.has(src):
		dmg *= float(RAM_MUL[src])
	e["hp"] = float(e["hp"]) - dmg
	e["flash"] = 0.08
	if float(e["hp"]) <= 0.0:
		e["dead"] = true
		var lad: Dictionary = e["lad"]
		if not lad.is_empty() and is_same(lad["busy"], e):
			lad["busy"] = {}
		gold += int(e["reward"])
		var p: Vector2 = (e["pos"] as Vector2) + Vector2(0, -float(e["r"]))
		sfx.play("coin", randf_range(0.95, 1.1), -12.0)
		for i in 8:
			_spark(p, ENEMY[e["kind"]]["col"], 170.0)
		fxs.append({"type": "coin", "p": p, "t": 0.0, "life": 0.8, "v": int(e["reward"])})
		if e["kind"] in ["boss", "ram"]:
			shake = 8.0
			sfx.play("gong", 1.2 if e["kind"] == "boss" else 1.6, -3.0)


func _shots_step(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for s in shots:
		var tgt: Dictionary = s["target"]
		if not tgt["dead"]:
			s["to"] = (tgt["pos"] as Vector2) + Vector2(0, -float(tgt["r"]))
		var p: Vector2 = s["p"]
		var to: Vector2 = s["to"]
		var step := 680.0 * dt
		if p.distance_to(to) <= step:
			_hit(tgt, s["dmg"], "arrow")
			_spark(to, Color("e8dcc0"), 90.0)
			continue
		s["p"] = p.move_toward(to, step)
		keep.append(s)
	shots = keep


func _check_wave_end() -> void:
	if spawn_queue.is_empty() and enemies.is_empty():
		wave += 1
		var income := 45 + 5 * wave
		gold += income
		shots.clear()
		ladders.clear()
		for sq in squads:
			sq["hp"] = squad_max
		_float_text("수입 +%d" % income, C + Vector2(0, -100), 26, Color("c28520"))
		if wave >= WAVES:
			_finish(true)
			return
		_open_cards()


# ───────────── 카드 ─────────────

func _open_cards() -> void:
	phase = Phase.CHOOSE
	held = -1
	var have := {}
	for sq in squads:
		have[int(sq["type"])] = true
	var pool: Array[String] = []
	for id in PERKS:
		if PERKS[id]["once"] and perks.has(id):
			continue
		if id == "oil_up" and not have.has(S_OIL):
			continue
		if id == "recruit" and squads.size() >= MAX_SQUADS:
			continue
		pool.append(id)
	pool.shuffle()
	cards.clear()
	for id in pool.slice(0, 3):
		cards.append({"id": id})
	sfx.play("rank", 1.0, -3.0)
	_show_cards()


func _pick_card(i: int) -> void:
	if phase != Phase.CHOOSE or i >= cards.size():
		return
	var id: String = cards[i]["id"]
	perks[id] = int(perks.get(id, 0)) + 1
	match id:
		"gate":
			for g in gates:
				g["max"] = float(g["max"]) * 1.3
				g["hp"] = g["max"]
				g["broken"] = false
				g["rebuild"] = 0.0
		"drill":
			wall_speed = WALL_SPEED * 1.4
			yard_speed = YARD_SPEED * 1.4
		"veteran":
			bonus["dmg"] = float(bonus["dmg"]) + 0.25
		"recruit":
			_add_squad(S_ARCHER, false, 0.0, C + Vector2(0, 80), true)
		"coins":
			gold += 100
		"keep":
			keep_max += 20.0
			keep_hp = minf(keep_max, keep_hp + 60.0)
		"longbow":
			bonus["arrow"] = float(bonus["arrow"]) + 0.3
			bonus["range"] = float(bonus["range"]) + 30.0
		"oil_up":
			bonus["oil"] = float(bonus["oil"]) + 0.4
		"hook":
			bonus["push"] = 2.0
		"armor":
			squad_max *= 1.3
			for sq in squads:
				sq["hp"] = squad_max
	sfx.play("place", 1.3, -3.0)
	card_box.visible = false
	card_dim.visible = false
	phase = Phase.BUILD
	_refresh_ui()


func _finish(won: bool) -> void:
	phase = Phase.WIN if won else Phase.OVER
	enemies.clear()
	shots.clear()
	spawn_queue.clear()
	ladders.clear()
	held = -1
	sel = -1
	breach_t = 0.0
	sfx.play("cycle" if won else "over", 1.0, 0.0)
	_show_result(won)


# ───────────── 연출 ─────────────

func _spark(p: Vector2, col: Color, power: float) -> void:
	parts.append({"p": p, "v": Vector2.from_angle(randf_range(-PI, 0.0)) * randf_range(0.3, 1.0) * power,
			"c": col, "age": 0.0, "life": randf_range(0.35, 0.7), "r": randf_range(2.0, 4.5)})


func _float_text(text: String, pos: Vector2, size: int, col: Color) -> void:
	fxs.append({"type": "text", "p": pos, "text": text, "size": size, "c": col, "t": 0.0, "life": 1.3})


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


func _build_deco() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	# 성 안 초가집, 성 밖 나무
	for i in 7:
		var p := Vector2(r.randf_range(L + 40, R - 40), r.randf_range(T + 40, B - 40))
		if p.distance_to(C) < KEEP_R + 50 or absf(p.x - C.x) < 30 or absf(p.y - C.y) < 30:
			continue
		deco.append({"type": "house", "p": p})
	for i in 40:
		var p := Vector2(r.randf_range(BOARD.position.x + 20, BOARD.end.x - 20), r.randf_range(BOARD.position.y + 20, BOARD.end.y - 20))
		if Rect2(L - 70, T - 70, 2 * HW + 140, 2 * HH + 140).has_point(p):
			continue
		if absf(p.x - C.x) < 50 or absf(p.y - C.y) < 50:
			continue
		deco.append({"type": "tree", "p": p, "s": r.randf_range(0.7, 1.15)})


# ───────────── 그리기 ─────────────

func _rrect(rc: Rect2, col: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, rc)


func _ell(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw() -> void:
	draw_rect(Rect2(-40, -40, 1360, 800), Color("d9eef2"))
	_rrect(Rect2(BOARD.position + Vector2(0, 12), BOARD.size).grow(8), Color(0.2, 0.3, 0.35, 0.16), 30)
	_rrect(BOARD.grow(8), Color("e9dcc0"), 30)
	_rrect(BOARD, Color("bfe3a8"), 24)
	# 성문으로 오는 흙길
	for s in 4:
		var g := gate_point(s)
		var far := g + NORMALS[s] * 400.0
		far.x = clampf(far.x, BOARD.position.x, BOARD.end.x)
		far.y = clampf(far.y, BOARD.position.y, BOARD.end.y)
		draw_line(g, far, Color("e2cc98"), 58.0)
		draw_line(g, far, Color("ecdcb0"), 42.0)
	for d in deco:
		if d["type"] == "tree":
			var p: Vector2 = d["p"]
			var sc: float = d["s"]
			_ell(p + Vector2(0, 10 * sc), 16 * sc, 6 * sc, Color(0.2, 0.35, 0.2, 0.18))
			draw_circle(p, 14 * sc, Color("8fcf7e"), true, -1.0, true)
			draw_circle(p + Vector2(-4, -5) * sc, 7 * sc, Color("abdf98"), true, -1.0, true)
	_draw_next_arrows()
	# 안마당
	draw_rect(Rect2(L, T, 2 * HW, 2 * HH), Color("d8e8c0"))
	draw_line(C + Vector2(-HW, 0), C + Vector2(HW, 0), Color("e6dcb8"), 30.0)
	draw_line(C + Vector2(0, -HH), C + Vector2(0, HH), Color("e6dcb8"), 30.0)
	for d in deco:
		if d["type"] == "house":
			var p: Vector2 = d["p"]
			_ell(p + Vector2(0, 12), 22, 6, Color(0, 0, 0, 0.12))
			_rrect(Rect2(p + Vector2(-16, -6), Vector2(32, 18)), Color("f1e7d2"), 3)
			_ell(p + Vector2(0, -8), 22, 11, Color("d9b36a"))
	_draw_keep()
	_draw_walls()
	# 사다리
	for lad in ladders:
		_draw_ladder(lad)
	# 사람들을 위에서 아래 순서로
	var items := []
	for i in squads.size():
		items.append({"y": (squads[i]["pos"] as Vector2).y + 2.0, "squad": i})
	for e in enemies:
		items.append({"y": (e["pos"] as Vector2).y, "enemy": e})
	items.sort_custom(func(a, b): return a["y"] < b["y"])
	_draw_squad_paths()
	for it in items:
		if it.has("squad"):
			_draw_squad(it["squad"])
		else:
			_draw_enemy(it["enemy"])
	for s in shots:
		var p: Vector2 = s["p"]
		var dir := ((s["to"] as Vector2) - p).normalized()
		draw_line(p - dir * 12, p, Color("6a4a2a"), 2.5, true)
	for f in fxs:
		_draw_fx(f)
	for q in parts:
		var a := 1.0 - float(q["age"]) / float(q["life"])
		draw_circle(q["p"], float(q["r"]) * (0.6 + 0.4 * a), Color(q["c"], a), true, -1.0, true)
	_draw_alert_marks()
	_draw_hover()
	if breach_t > 0.0:
		var pulse := 0.18 + 0.14 * sin(t * 8.0)
		for i in 4:
			var w := 26.0 - i * 6.0
			var col := Color(0.85, 0.12, 0.1, pulse * (1.0 - i * 0.22))
			draw_rect(Rect2(BOARD.position, Vector2(BOARD.size.x, w)), col)
			draw_rect(Rect2(BOARD.position + Vector2(0, BOARD.size.y - w), Vector2(BOARD.size.x, w)), col)
			draw_rect(Rect2(BOARD.position, Vector2(w, BOARD.size.y)), col)
			draw_rect(Rect2(BOARD.position + Vector2(BOARD.size.x - w, 0), Vector2(w, BOARD.size.y)), col)


func _draw_next_arrows() -> void:
	var w := wave + 1
	if phase not in [Phase.BUILD, Phase.CHOOSE] or w > WAVES:
		return
	for g in plan[w]:
		var s: int = g["side"]
		var gp := gate_point(s)
		var tip := gp + NORMALS[s] * (90.0 + 6.0 * sin(t * 5.0))
		var dir := -NORMALS[s]
		var side := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([tip + dir * 18, tip - dir * 8 + side * 16, tip - dir * 8 - side * 16]), Color("e04a3a"))
		var txt := _group_text(g)
		var tw := font_b.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var lp := tip + NORMALS[s] * 34.0 + Vector2(-tw * 0.5, 5)
		if s == 1:
			lp = tip + Vector2(-tw * 0.5 + 40, -40)
		elif s == 3:
			lp = tip + Vector2(-tw * 0.5 - 40, -40)
		lp.x = clampf(lp.x, BOARD.position.x + 12, BOARD.end.x - tw - 12)
		lp.y = clampf(lp.y, BOARD.position.y + 22, BOARD.end.y - 10)
		_rrect(Rect2(lp + Vector2(-8, -18), Vector2(tw + 16, 26)), Color(1, 1, 1, 0.9), 10)
		draw_string(font_b, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("c0503f"))


func _group_text(g: Dictionary) -> String:
	var ps: Array[String] = []
	if float(g["delay"]) > 0.0:
		ps.append("%d초 뒤" % int(g["delay"]))
	for kind in ["grunt", "ladder", "brute", "ram", "boss"]:
		if int(g[kind]) > 0:
			ps.append("%s %d" % [ENEMY[kind]["name"], int(g[kind])])
	return " · ".join(ps)


func _draw_keep() -> void:
	var c := C
	_ell(c + Vector2(0, 40), 64, 18, Color(0.2, 0.3, 0.2, 0.2))
	_rrect(Rect2(c + Vector2(-48, -26), Vector2(96, 66)), Color("efe6d6"), 10)
	for x in [-50.0, 34.0]:
		_rrect(Rect2(c + Vector2(x, -50), Vector2(16, 90)), Color("e2d6c0"), 5)
		draw_colored_polygon(PackedVector2Array([c + Vector2(x - 4, -50), c + Vector2(x + 8, -72), c + Vector2(x + 20, -50)]), Color("4a63b8"))
	_rrect(Rect2(c + Vector2(-20, -56), Vector2(40, 40)), Color("f6efe2"), 6)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-26, -56), c + Vector2(0, -86), c + Vector2(26, -56)]), Color("e05a4f"))
	draw_line(c + Vector2(0, -86), c + Vector2(0, -106), Color("8a6a4a"), 2.5, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -106), c + Vector2(18 + 3 * sin(t * 6.0), -101), c + Vector2(0, -95)]), Color("f2b33d"))
	_rrect(Rect2(c + Vector2(-11, 14), Vector2(22, 26)), Color("9a6b3f"), 8)
	var w := 110.0
	var hb := Rect2(c + Vector2(-w * 0.5, 48), Vector2(w, 9))
	_rrect(hb.grow(2), Color(1, 1, 1, 0.85), 5)
	var k := keep_hp / keep_max
	_rrect(Rect2(hb.position, Vector2(w * k, 9)), Color("5ccf6a") if k > 0.5 else (Color("f2b33d") if k > 0.25 else Color("e04a3a")), 4)


func _draw_walls() -> void:
	var hw := WALL_W * 0.5
	var stone := Color("d8cfc0")
	var top := Color("e9e2d4")
	# 그림자
	draw_rect(Rect2(L - hw, T - hw + 8, 2 * HW + WALL_W, WALL_W), Color(0.2, 0.3, 0.2, 0.18))
	draw_rect(Rect2(L - hw, B - hw + 8, 2 * HW + WALL_W, WALL_W), Color(0.2, 0.3, 0.2, 0.18))
	# 네 면 (성문 자리는 비움)
	for s in 4:
		var a := wall_point(gate_u(s) - GATE_HALF)
		var b := wall_point(gate_u(s) + GATE_HALF)
		var corner_a: Vector2 = [Vector2(L, T), Vector2(R, T), Vector2(R, B), Vector2(L, B)][s]
		var corner_b: Vector2 = [Vector2(R, T), Vector2(R, B), Vector2(L, B), Vector2(L, T)][s]
		for seg in [[corner_a, a], [b, corner_b]]:
			draw_line(seg[0], seg[1], stone, WALL_W)
			var n: Vector2 = NORMALS[s]
			draw_line(seg[0] + n * (hw - 4), seg[1] + n * (hw - 4), top, 6.0)
			# 성가퀴
			var seg_len: float = (seg[0] as Vector2).distance_to(seg[1])
			var dir: Vector2 = ((seg[1] as Vector2) - (seg[0] as Vector2)).normalized()
			var x := 8.0
			while x < seg_len - 4:
				draw_rect(Rect2((seg[0] as Vector2) + dir * x + n * (hw + 1) - Vector2(4, 4), Vector2(8, 8)), top)
				x += 18.0
	# 모서리 망루
	for c in [Vector2(L, T), Vector2(R, T), Vector2(R, B), Vector2(L, B)]:
		_ell(c + Vector2(0, 8), 24, 10, Color(0.2, 0.3, 0.2, 0.2))
		draw_circle(c, 22, stone, true, -1.0, true)
		draw_circle(c, 15, top, true, -1.0, true)
	# 성문
	for s in 4:
		_draw_gate(s)


func _draw_gate(s: int) -> void:
	var g: Dictionary = gates[s]
	var p := gate_point(s)
	var n: Vector2 = NORMALS[s]
	var along := n.orthogonal()
	# 문 양옆 문루
	for side in [-1.0, 1.0]:
		var q: Vector2 = p + along * (GATE_HALF + 8) * side
		draw_circle(q, 17, Color("cfc5b4"), true, -1.0, true)
		draw_circle(q, 11, Color("e9e2d4"), true, -1.0, true)
	if bool(g["broken"]):
		var r2 := RandomNumberGenerator.new()
		r2.seed = s * 31 + 5
		for i in 8:
			draw_circle(p + along * r2.randf_range(-GATE_HALF, GATE_HALF) + n * r2.randf_range(-8, 8), r2.randf_range(3, 6), Color("8a6a4a"), true, -1.0, true)
		if float(g["rebuild"]) > 0.0:
			var kk := float(g["rebuild"]) / (float(g["max"]) * 0.35)
			draw_line(p - along * GATE_HALF, p - along * GATE_HALF + along * GATE_HALF * 2.0 * kk, Color(Color("b98a5e"), 0.8), 14.0)
	else:
		var k := float(g["hp"]) / float(g["max"])
		var col := Color("b98a5e").lerp(Color("6a4a2a"), (1.0 - k) * 0.6)
		if float(g["flash"]) > 0.0:
			col = col.lerp(Color("ffd0c8"), 0.5)
		draw_line(p - along * GATE_HALF, p + along * GATE_HALF, col, 16.0)
		for i in 3:
			var q := p + along * (i - 1) * 14.0
			draw_line(q - n * 7, q + n * 7, col.darkened(0.25), 2.0)
	# 성문 체력 막대 (바깥쪽)
	var hp_k := 0.0 if bool(g["broken"]) else float(g["hp"]) / float(g["max"])
	var bp := p + n * 30.0
	var w := 56.0
	var hb := Rect2(bp - Vector2(w * 0.5, 4), Vector2(w, 7))
	_rrect(hb.grow(2), Color(1, 1, 1, 0.85), 4)
	_rrect(Rect2(hb.position, Vector2(w * hp_k, 7)), Color("5ccf6a") if hp_k > 0.5 else (Color("f2b33d") if hp_k > 0.25 else Color("e04a3a")), 3)


func _draw_ladder(lad: Dictionary) -> void:
	var base: Vector2 = lad["base"]
	var top: Vector2 = (lad["top"] as Vector2) + Vector2(0, -6)
	var sd := (top - base).normalized().orthogonal() * 6.0
	draw_line(base + sd, top + sd, Color("8a6a4a"), 3.0, true)
	draw_line(base - sd, top - sd, Color("8a6a4a"), 3.0, true)
	for i in 5:
		var q := base.lerp(top, (i + 0.5) / 5.0)
		draw_line(q + sd, q - sd, Color("8a6a4a"), 2.0, true)
	if float(lad["push"]) > 0.0:
		var k := float(lad["push"]) / PUSH_TIME
		draw_arc(top + Vector2(0, -16), 9, -PI * 0.5, -PI * 0.5 + TAU * k, 16, Color("2f8f4a"), 4.0, true)


func _draw_alert_marks() -> void:
	if phase != Phase.FIGHT:
		return
	# 사다리마다 경보 (지키는 분대가 없으면 붉게)
	for lad in ladders:
		var guarded := not _defenders_near(lad["top"], 50.0).is_empty()
		var p := (lad["top"] as Vector2) - NORMALS[int(lad["side"])] * 30.0
		var s := 1.0 + 0.15 * sin(t * (5.0 if guarded else 11.0))
		draw_circle(p, 9 * s, Color("f2a03d") if guarded else Color("e04a3a"), true, -1.0, true)
		draw_string(font_b, p + Vector2(-3, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


func _draw_squad_paths() -> void:
	for sq in squads:
		if int(sq["mode"]) == 0:
			continue
		var col := Color(SQUADS[int(sq["type"])]["col"], 0.6)
		var goal := wall_point(float(sq["dest_u"])) if bool(sq["dest_wall"]) else (sq["dest_p"] as Vector2)
		if int(sq["mode"]) == 1:
			_wall_path(float(sq["u"]), float(sq["dest_u"]), col)
		else:
			_dash_line(sq["pos"], squad_goal_point(sq), col)
		draw_circle(goal, 6, col, true, -1.0, true)


func _wall_path(u0: float, u1: float, col: Color) -> void:
	var d := u_diff(u0, u1)
	var n := maxi(2, int(absf(d) / 12.0))
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(wall_point(u0 + d * float(i) / n))
	draw_polyline(pts, col, 4.0, true)


func _dash_line(a: Vector2, b: Vector2, col: Color) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / maxf(length, 0.001)
	var x := fmod(t * 30.0, 14.0)
	while x < length:
		draw_line(a + dir * x, a + dir * minf(x + 8.0, length), col, 3.0, true)
		x += 14.0


func _draw_squad(i: int) -> void:
	var sq: Dictionary = squads[i]
	var p: Vector2 = sq["pos"]
	var ty: int = sq["type"]
	var col: Color = SQUADS[ty]["col"]
	var on_wall := _squad_on_wall(sq)
	var out := NORMALS[side_of(float(sq["u"]))] if on_wall else (p - C).normalized()
	var side := out.orthogonal()
	var moving := int(sq["mode"]) != 0
	var men := ceili(float(sq["hp"]) / (squad_max / 3.0))
	if i == sel:
		_ell(p + Vector2(0, 2), 24, 11, Color(1, 0.9, 0.3, 0.6))
	for j in men:
		var off := side * (j - (men - 1) * 0.5) * 11.0
		var bob := absf(sin(t * 10.0 + j)) * 3.0 if moving else 0.0
		var q := p + off + Vector2(0, -bob)
		_ell(q + Vector2(0, 2), 5, 2, Color(0, 0, 0, 0.18))
		_rrect(Rect2(q + Vector2(-4, -10), Vector2(8, 10)), col if float(sq["fight"]) <= 0.0 or fmod(t, 0.2) < 0.1 else col.lightened(0.3), 3)
		draw_circle(q + Vector2(0, -13), 4, Color("f2c79a"), true, -1.0, true)
		draw_arc(q + Vector2(0, -14), 4.5, PI, TAU, 8, col.darkened(0.3), 3.0, true)
		match ty:
			S_ARCHER:
				draw_arc(q + Vector2(5, -7), 5, -1.2, 1.2, 6, Color("8a6a4a"), 1.5, true)
			S_SPEAR:
				var tip := q + Vector2(5, -6) + out * (8.0 + float(sq["flash"]) * 40.0)
				draw_line(q + Vector2(5, -2), tip + Vector2(0, -10), Color("8a6a4a"), 1.5, true)
				draw_circle(tip + Vector2(0, -10), 2, Color("c9d3df"), true, -1.0, true)
			S_OIL:
				_ell(q + Vector2(6, -4), 4, 3, Color("4a4a58"))
			S_MASON:
				var ha := sin(t * 9.0 + j) * 0.7 if not moving else 0.0
				draw_line(q + Vector2(4, -6), q + Vector2(4, -6) + Vector2.from_angle(-1.2 + ha) * 8, Color("8a6a4a"), 2.0, true)
	var fp := p + Vector2(0, -32)
	draw_line(fp + Vector2(-8, 12), fp + Vector2(-8, -6), Color("6a4a2a"), 2.0, true)
	_rrect(Rect2(fp + Vector2(-8, -8), Vector2(18, 13)), col, 3)
	draw_string(font_b, fp + Vector2(-5, 3), "%d" % ((i + 1) % 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	if float(sq["hp"]) < squad_max:
		var w := 28.0
		var hb := Rect2(p + Vector2(-w * 0.5, 5), Vector2(w, 4))
		draw_rect(hb, Color(0, 0, 0, 0.25))
		draw_rect(Rect2(hb.position, Vector2(w * float(sq["hp"]) / squad_max, 4)), Color("5ccf6a") if float(sq["hp"]) > squad_max * 0.4 else Color("e04a3a"))


func _draw_enemy(e: Dictionary) -> void:
	var p: Vector2 = e["pos"]
	var r: float = e["r"]
	var info: Dictionary = ENEMY[e["kind"]]
	var st: int = e["state"]
	var attacking := st in [1, 3, 5]
	var hop := absf(sin(float(e["ph"]))) * (2.0 if attacking else 4.0)
	var s: int = e["side"]
	var inward := -NORMALS[s] if st < 4 else (C - p).normalized()
	var lunge := inward * maxf(0.0, sin(float(e["ph"]) * 1.5)) * 4.0 if attacking else Vector2.ZERO
	_ell(p + Vector2(0, 3), r, r * 0.35, Color(0.15, 0.2, 0.2, 0.2))
	var body := p + Vector2(0, -r - hop) + lunge
	var col: Color = Color.WHITE if float(e["flash"]) > 0.0 else info["col"]
	if e["kind"] == "ram":
		var fwd := inward
		var sdv := fwd.orthogonal()
		var hit := maxf(0.0, sin(float(e["ph"]) * 1.2)) * 7.0 if attacking else 0.0
		body = p + Vector2(0, -10)
		draw_colored_polygon(PackedVector2Array([body + fwd * 20 + sdv * 15, body + fwd * 20 - sdv * 15, body - fwd * 20 - sdv * 17, body - fwd * 20 + sdv * 17]), col)
		draw_line(body - fwd * 10, body + fwd * (32 + hit), Color("6a4a2a"), 8.0, true)
		draw_circle(body + fwd * (32 + hit), 6, Color("4a4a58"), true, -1.0, true)
		var up := Vector2(0, -12)
		draw_colored_polygon(PackedVector2Array([body + fwd * 15 + sdv * 13 + up, body + fwd * 15 - sdv * 13 + up, body - fwd * 15 - sdv * 15 + up, body - fwd * 15 + sdv * 15 + up]), (info["col"] as Color).darkened(0.25))
		for side_k in [-1.0, 1.0]:
			draw_circle(body + sdv * 17 * side_k + Vector2(0, 8), 5, Color("4a3a2a"), true, -1.0, true)
	else:
		_ell(body, r, r * 0.92, col)
		_ell(body + Vector2(-r * 0.3, -r * 0.35), r * 0.35, r * 0.22, Color(1, 1, 1, 0.35))
		if e["kind"] in ["boss", "brute"]:
			var hc := (info["col"] as Color).darkened(0.35)
			draw_colored_polygon(PackedVector2Array([body + Vector2(-r * 0.55, -r * 0.6), body + Vector2(-r * 0.2, -r * 0.85), body + Vector2(-r * 0.5, -r * 1.35)]), hc)
			draw_colored_polygon(PackedVector2Array([body + Vector2(r * 0.55, -r * 0.6), body + Vector2(r * 0.2, -r * 0.85), body + Vector2(r * 0.5, -r * 1.35)]), hc)
		if e["kind"] == "ladder" and String(e["goal"]) == "plant" and st == 0:
			draw_line(body + Vector2(-9, -r - 8), body + Vector2(9, r * 0.4), Color("8a6a4a"), 3.0, true)
			draw_line(body + Vector2(-3, -r - 10), body + Vector2(13, r * 0.2), Color("8a6a4a"), 3.0, true)
		if e["kind"] == "brute":
			draw_line(body + Vector2(r * 0.7, 0), body + Vector2(r * 1.3, -r * 0.8), Color("6a4a2a"), 3.0, true)
			_ell(body + Vector2(r * 1.3, -r * 0.8), 5, 3, Color("c9d3df"))
		var es := r / 15.0
		var look := inward * 1.5 * es
		for ex in [-5.0, 5.0]:
			draw_circle(body + Vector2(ex * es, -2 * es), 4.0 * es, Color.WHITE, true, -1.0, true)
			draw_circle(body + Vector2(ex * es, -2 * es) + look, 2.0 * es, Color("2a2a33"), true, -1.0, true)
	if float(e["hp"]) < float(e["max"]):
		var w := maxf(r * 2.0, 20.0)
		var hb := Rect2(body + Vector2(-w * 0.5, -r - 12), Vector2(w, 4))
		draw_rect(hb, Color(0, 0, 0, 0.25))
		draw_rect(Rect2(hb.position, Vector2(w * float(e["hp"]) / float(e["max"]), 4)), Color("e04a3a") if st >= 3 else Color("5ccf6a"))


func _draw_fx(f: Dictionary) -> void:
	var k := float(f["t"]) / float(f["life"])
	var p: Vector2 = f["p"]
	match f["type"]:
		"text":
			var size: int = f["size"]
			var txt: String = f["text"]
			var w := font_b.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var pos := p + Vector2(-w * 0.5, -40.0 * k)
			pos.x = clampf(pos.x, BOARD.position.x + 6, BOARD.end.x - w - 6)
			var a := 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
			draw_string_outline(font_b, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(1, 1, 1, a))
			draw_string(font_b, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(f["c"], a))
		"coin":
			var q := p + Vector2(0, -50.0 * k + 30.0 * k * k)
			var a := 1.0 - k
			_ell(q, 7 * absf(cos(k * 12.0)) + 2, 7, Color("e8b33c", a))
			draw_string(font_b, q + Vector2(9, 5), "+%d" % int(f["v"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("c28520", a))
		"oil":
			draw_circle(p, float(f["r"]) * (0.6 + 0.4 * k), Color(Color("ffb347"), 0.4 * (1.0 - k)), true, -1.0, true)
			for i in 7:
				var q := p + Vector2.from_angle(TAU * i / 7.0 + k) * float(f["r"]) * 0.6 * k + Vector2(0, -24 * k)
				draw_circle(q, 7 * (1.0 - k), Color(Color("ee5b4b"), 1.0 - k), true, -1.0, true)


func _info_box(p: Vector2, lines: Array[String]) -> void:
	var w := 0.0
	for l in lines:
		w = maxf(w, font_b.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var box := Rect2(p + Vector2(-w * 0.5 - 8, -14), Vector2(w + 16, 20 * lines.size() + 6))
	box.position.x = clampf(box.position.x, BOARD.position.x + 4, BOARD.end.x - box.size.x - 4)
	box.position.y = clampf(box.position.y, BOARD.position.y + 4, BOARD.end.y - box.size.y - 4)
	_rrect(box, Color(1, 1, 1, 0.93), 8)
	for i in lines.size():
		draw_string(font_b, box.position + Vector2(8, 19 + 20 * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("4a3a32"))


func _draw_hover() -> void:
	if phase not in [Phase.BUILD, Phase.FIGHT]:
		return
	var mp := get_global_mouse_position()
	var u := wall_at(mp)
	var yard_ok := in_yard(mp) and u < 0.0 and mp.distance_to(C) > KEEP_R
	if held == -2:
		for s in 4:
			if gate_point(s).distance_to(mp) < 50.0:
				draw_circle(gate_point(s), 40, Color(Color("f2b33d"), 0.35), true, -1.0, true)
				var c := gate_repair_cost(s)
				_info_box(gate_point(s) - NORMALS[s] * 60.0, ["%s문 수리: 골드 %d" % [SIDE_NAMES[s], c] if c > 0 else "%s문: 멀쩡함" % SIDE_NAMES[s]])
		return
	if held >= 0:
		if u >= 0.0:
			draw_circle(wall_point(u), 16, Color(SQUADS[held]["col"], 0.5), true, -1.0, true)
		elif yard_ok:
			draw_circle(mp, 16, Color(SQUADS[held]["col"], 0.4), true, -1.0, true)
		return
	if sel >= 0 and squad_at_point(mp) < 0:
		var sq: Dictionary = squads[sel]
		var lines: Array[String] = []
		if u >= 0.0:
			var gs := near_gate(u)
			var place := ("%s문 위" % SIDE_NAMES[gs]) if gs >= 0 else ("%s쪽 성벽" % SIDE_NAMES[side_of(u)])
			draw_circle(wall_point(u), 9, Color(1, 0.85, 0.3, 0.9), true, -1.0, true)
			if _squad_on_wall(sq):
				_wall_path(float(sq["u"]), u, Color(1, 1, 1, 0.8))
				lines.append("%s · 왼쪽: 성벽 따라 %.1f초 (가면서 싸움)" % [place, travel_time(sq, true, u, Vector2.ZERO, false)])
				lines.append("오른쪽: 안마당 지름길 %.1f초 (계단, 못 싸움)" % travel_time(sq, true, u, Vector2.ZERO, true))
			else:
				lines.append("%s · %.1f초" % [place, travel_time(sq, true, u, Vector2.ZERO, true)])
			_dash_line(sq["pos"], wall_point(u), Color(1, 0.85, 0.3, 0.7))
			_info_box(wall_point(u) - NORMALS[side_of(u)] * 56.0, lines)
		elif yard_ok:
			draw_circle(mp, 9, Color(1, 0.85, 0.3, 0.9), true, -1.0, true)
			_dash_line(sq["pos"], mp, Color(1, 0.85, 0.3, 0.7))
			_info_box(mp + Vector2(0, -44), ["안마당 %.1f초 (들어온 적과 싸움)" % travel_time(sq, false, 0.0, mp, true)])
		return
	var hit := squad_at_point(mp)
	if hit >= 0:
		var sq: Dictionary = squads[hit]
		_info_box((sq["pos"] as Vector2) + Vector2(0, -60), ["%d분대 %s · 체력 %d/%d" % [hit + 1, SQUADS[int(sq["type"])]["name"], ceili(float(sq["hp"])), int(squad_max)], "클릭해서 고르기"])
		return
	for s in 4:
		if gate_point(s).distance_to(mp) < 40.0:
			var g: Dictionary = gates[s]
			_info_box(gate_point(s) - NORMALS[s] * 60.0, ["%s문 %s" % [SIDE_NAMES[s], "부서짐" if bool(g["broken"]) else "%d/%d" % [int(g["hp"]), int(g["max"])]]])


# ───────────── UI ─────────────

func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(6)
	sb.anti_aliasing = true
	return sb


func _label(size: int, col: Color, bold := true) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font_b if bold else font_r)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_btn(text_col: Color, size: int, col: Color, h := 34.0, w := 280.0) -> Button:
	var b := Button.new()
	b.add_theme_font_override("font", font_b)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, h)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(fc, text_col)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, _btn_style(col.lerp(Color.WHITE, 0.62 if st != "hover" else 0.42), col))
	return b


func _section(vb: VBoxContainer, text: String) -> Label:
	var l := _label(15, Color("4a3a32"))
	l.text = text
	vb.add_child(l)
	return l


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	var title := _label(26, Color("4a3a32"))
	title.text = "공성전  ·  시험판"
	title.position = Vector2(30, 14)
	ui.add_child(title)
	stat_label = _label(20, Color("4a3a32"))
	stat_label.position = Vector2(30, 52)
	ui.add_child(stat_label)
	alert_label = _label(18, Color("c0503f"))
	alert_label.position = Vector2(250, 20)
	alert_label.size = Vector2(680, 30)
	ui.add_child(alert_label)

	var panel := Panel.new()
	panel.position = Vector2(952, 12)
	panel.size = Vector2(312, 696)
	var psb := _btn_style(Color(1, 1, 1, 0.92), Color("e2d6bf"))
	psb.set_corner_radius_all(20)
	panel.add_theme_stylebox_override("panel", psb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(panel)
	var vb := VBoxContainer.new()
	vb.position = Vector2(16, 12)
	vb.size = Vector2(280, 672)
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	_section(vb, "분대 (1~0 또는 클릭으로 고르기)")
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	for i in MAX_SQUADS:
		var b := _make_btn(Color("2a2a33"), 12, Color("c4b8a8"), 30, 53)
		b.pressed.connect(_squad_btn.bind(i))
		grid.add_child(b)
		squad_btns.append(b)
	_section(vb, "분대 모집 (본성에서 출발)")
	for i in 4:
		var b := _make_btn(Color("2a2a33"), 14, SQUADS[i]["col"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = SQUADS[i]["desc"]
		b.pressed.connect(_pick_hold.bind(i))
		vb.add_child(b)
		hire_btns.append(b)
	repair_btn = _make_btn(Color("2a2a33"), 14, Color("c28520"))
	repair_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	repair_btn.pressed.connect(_pick_hold.bind(-2))
	vb.add_child(repair_btn)

	var help := _label(12, Color("6a5a4e"), false)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(280, 0)
	help.text = "궁수: 멀리 쏨 · 창병: 사다리를 밀고 올라온 적과 싸움 · 기름병: 성벽 아래 공성추에 강함 · 석공: 성문 수리"
	vb.add_child(help)

	next_title = _section(vb, "다음 웨이브")
	next_label = RichTextLabel.new()
	next_label.bbcode_enabled = true
	next_label.fit_content = true
	next_label.add_theme_font_override("normal_font", font_b)
	next_label.add_theme_font_size_override("normal_font_size", 13)
	next_label.add_theme_color_override("default_color", Color("4a3a32"))
	next_label.custom_minimum_size = Vector2(280, 36)
	next_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(next_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	start_btn = _make_btn(Color.WHITE, 16, Color("ee5b4b"), 42, 186)
	for st in ["normal", "hover", "pressed", "focus"]:
		start_btn.add_theme_stylebox_override(st, _btn_style(Color("ee5b4b") if st != "hover" else Color("f07a6c"), Color("b93a2d")))
	start_btn.add_theme_stylebox_override("disabled", _btn_style(Color("d9cfc4"), Color("c4b8a8")))
	speed_btn = _make_btn(Color("4a3a32"), 16, Color("d8cdb8"), 42, 86)
	start_btn.pressed.connect(_start_wave)
	speed_btn.pressed.connect(_toggle_speed)
	row.add_child(start_btn)
	row.add_child(speed_btn)

	perk_label = _label(12, Color("7a4fb0"))
	perk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perk_label.custom_minimum_size = Vector2(280, 0)
	vb.add_child(perk_label)

	tip_label = _label(14, Color("4a3a32"), false)
	tip_label.position = Vector2(30, 684)
	tip_label.size = Vector2(900, 24)
	ui.add_child(tip_label)

	card_dim = ColorRect.new()
	card_dim.color = Color(0.15, 0.2, 0.25, 0.45)
	card_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_dim.visible = false
	ui.add_child(card_dim)
	card_box = CenterContainer.new()
	card_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_box.visible = false
	ui.add_child(card_box)
	overlay = CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	ui.add_child(overlay)


func _squad_btn(i: int) -> void:
	if i < squads.size() and phase in [Phase.BUILD, Phase.FIGHT]:
		_select(i)


func _refresh_stats() -> void:
	var broken := 0
	for g in gates:
		if bool(g["broken"]):
			broken += 1
	stat_label.text = "웨이브 %d / %d    본성 %d / %d    골드 %d%s" % [mini(wave + (1 if phase == Phase.FIGHT else 0), WAVES), WAVES,
			ceili(keep_hp), int(keep_max), gold, ("    부서진 문 %d" % broken) if broken > 0 else ""]
	for i in MAX_SQUADS:
		var b := squad_btns[i]
		if i < squads.size():
			var sq: Dictionary = squads[i]
			b.text = "%d %s" % [(i + 1) % 10, SQUADS[int(sq["type"])]["name"]]
			var col: Color = SQUADS[int(sq["type"])]["col"]
			b.add_theme_stylebox_override("normal", _btn_style(col.lerp(Color.WHITE, 0.2 if i == sel else 0.62), Color("f2b33d") if i == sel else col))
			b.disabled = false
		else:
			b.text = "-"
			b.disabled = true


func _update_alerts() -> void:
	if phase != Phase.FIGHT:
		alert_label.text = ""
		return
	var msgs: Array[String] = []
	if breach_t > 0.0:
		msgs.append("성 안에 적이 들어왔다!")
	for s in 4:
		var g: Dictionary = gates[s]
		if not bool(g["broken"]) and float(g["flash"]) > 0.0 and float(g["hp"]) < float(g["max"]) * 0.4:
			msgs.append("%s문 위험 (%d%%)" % [SIDE_NAMES[s], int(100.0 * float(g["hp"]) / float(g["max"]))])
	var cnt := {}
	for lad in ladders:
		if _defenders_near(lad["top"], 50.0).is_empty():
			cnt[int(lad["side"])] = int(cnt.get(int(lad["side"]), 0)) + 1
	for s in cnt:
		msgs.append("%s쪽 사다리 %d개!" % [SIDE_NAMES[s], int(cnt[s])])
	alert_label.text = "   ".join(msgs)


func _refresh_ui() -> void:
	_refresh_stats()
	for i in 4:
		hire_btns[i].text = "%s  %s  ·  %d" % [SQUADS[i]["key"], SQUADS[i]["name"], int(SQUADS[i]["cost"])]
	repair_btn.text = "T  골드로 성문 수리  ·  체력 %d당 1" % int(GATE_REPAIR_PER_GOLD)
	var w := wave + 1
	var lines: Array[String] = []
	if w <= WAVES:
		for g in plan[w]:
			lines.append("[color=#c0503f]● %s쪽[/color] %s" % [SIDE_NAMES[int(g["side"])], _group_text(g)])
	next_label.text = "\n".join(lines)
	next_title.text = "이번 웨이브" if phase == Phase.FIGHT else "다음 웨이브"
	start_btn.text = "웨이브 시작 (Space)" if phase == Phase.BUILD else "싸우는 중..."
	start_btn.disabled = phase != Phase.BUILD
	speed_btn.text = "%dx (F)" % int(speed)
	var pl: Array[String] = []
	for id in perks:
		pl.append("%s%s" % [PERKS[id]["name"], (" ×%d" % int(perks[id])) if int(perks[id]) > 1 else ""])
	perk_label.text = ("카드: " + ", ".join(pl)) if not pl.is_empty() else ""


func _update_tip() -> void:
	if phase == Phase.CHOOSE:
		tip_label.text = "카드를 하나 고르세요 (클릭 또는 1·2·3)"
	elif held == -2:
		tip_label.text = "고칠 성문을 누르세요.   취소: 오른쪽 클릭 / Esc"
	elif held >= 0:
		tip_label.text = "%s: 성벽이나 안마당을 누르면 본성에서 출발해요.   취소: 오른쪽 클릭 / Esc" % SQUADS[held]["name"]
	elif sel >= 0:
		tip_label.text = "%d분대: 성벽 왼쪽 클릭 = 성벽 따라 (싸우며) · 오른쪽 클릭 = 안마당 지름길 (빠르지만 못 싸움) · 안마당 클릭 = 그곳으로" % (sel + 1)
	elif phase == Phase.BUILD:
		tip_label.text = "붉은 화살표 쪽에서 적이 와요. 사다리는 창병이, 공성추는 기름병이 막아요"
	elif phase == Phase.FIGHT:
		tip_label.text = "분대를 클릭하거나 숫자로 고른 뒤 성벽·안마당을 누르면 이동해요.   속도: F"
	else:
		tip_label.text = ""


func _show_cards() -> void:
	for c in card_box.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	card_box.add_child(vb)
	var title := _label(32, Color.WHITE)
	title.text = "%d웨이브를 막았다! 하나를 고르세요" % wave
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color("4a3a32"))
	vb.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	vb.add_child(row)
	for i in cards.size():
		var info: Dictionary = PERKS[cards[i]["id"]]
		var accent := Color("7a4fb0")
		var b := Button.new()
		b.custom_minimum_size = Vector2(230, 250)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", _btn_style(Color.WHITE, Color("e2d6bf")))
		b.add_theme_stylebox_override("hover", _btn_style(Color("fffaf0"), accent))
		b.add_theme_stylebox_override("pressed", _btn_style(Color("fffaf0"), accent))
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
		bsb.bg_color = accent
		bsb.set_corner_radius_all(36)
		badge.add_theme_stylebox_override("panel", bsb)
		badge.custom_minimum_size = Vector2(72, 72)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(badge)
		var ch := _label(34, Color.WHITE)
		ch.text = info["char"]
		ch.set_anchors_preset(Control.PRESET_FULL_RECT)
		ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(ch)
		var nm := _label(22, Color("2a2a33"))
		nm.text = "%d. %s" % [i + 1, info["name"]]
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nm)
		var d := _label(15, Color("4a3a32"), false)
		d.text = info["desc"]
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
	var t1 := _label(44, Color("2f8f4a") if won else Color("c0503f"))
	t1.text = "성을 지켰다!" if won else "성이 함락됐다"
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t1)
	var t2 := _label(18, Color("4a3a32"), false)
	t2.text = "%d웨이브까지   ·   본성 체력 %d   ·   분대 %d\nR 키를 눌러 다시" % [wave, ceili(keep_hp), squads.size()]
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t2)
	overlay.add_child(panel)
	overlay.visible = true


func _setup_input() -> void:
	var keys := {
		"sq_1": [KEY_1, KEY_KP_1], "sq_2": [KEY_2, KEY_KP_2], "sq_3": [KEY_3, KEY_KP_3], "sq_4": [KEY_4, KEY_KP_4],
		"sq_5": [KEY_5, KEY_KP_5], "sq_6": [KEY_6, KEY_KP_6], "sq_7": [KEY_7, KEY_KP_7], "sq_8": [KEY_8, KEY_KP_8],
		"sq_9": [KEY_9, KEY_KP_9], "sq_10": [KEY_0, KEY_KP_0],
		"hire_0": [KEY_Z], "hire_1": [KEY_X], "hire_2": [KEY_C], "hire_3": [KEY_V], "repair": [KEY_T],
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
