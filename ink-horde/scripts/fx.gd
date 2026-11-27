class_name Fx
extends Node2D
## 먹 효과: 튀는 먹방울(떨어지면 바닥 자국이 됨), 잠깐 남는 붓 획, 잔상
## 바닥 먹 자국은 Stains가 따로 그린다 (계속 쌓인다)

var drops: Array[Dictionary] = []
var strokes: Array[Dictionary] = []
var ghosts: Array[Dictionary] = []
var seals: Array[Dictionary] = []
var stains: Stains
var stain_chance := 0.25
const MAX_DROPS := 450


## 먹 튀김: dir 쪽으로 부채꼴로 흩뿌린다
func splash(pos: Vector2, dir: Vector2, count: int, power: float, spread := 1.2, col := Ink.INK) -> void:
	if drops.size() > MAX_DROPS:
		count = mini(count, 2) # 방울이 너무 많으면 줄인다
	var base := dir.angle() if dir != Vector2.ZERO else randf() * TAU
	for i in count:
		var a := base + randf_range(-spread, spread)
		var sp := randf_range(0.3, 1.0) * power
		drops.append({"p": pos, "v": Vector2.from_angle(a) * sp, "r": randf_range(2.0, 6.0),
				"life": randf_range(0.18, 0.42), "age": 0.0, "c": col})


func stroke(pts: PackedVector2Array, width: float, life: float, col := Ink.INK, dry := false) -> void:
	var s := {"pts": pts, "w": width, "life": life, "age": 0.0, "c": col, "dry": []}
	if dry:
		# 마른 붓 자국: 획 안쪽에 종이색 가는 줄이 군데군데 끊겨 지나간다
		var lines := []
		for k in 5:
			var off := randf_range(-0.42, 0.42)
			var segs := []
			var i := 0
			while i < pts.size() - 1:
				var run := randi_range(2, 6)
				if randf() < 0.6:
					segs.append([i, mini(i + run, pts.size() - 1)])
				i += run + randi_range(1, 3)
			lines.append({"off": off, "segs": segs, "w": randf_range(1.0, 2.6)})
		s["dry"] = lines
	strokes.append(s)


## 반달 모양 베기 궤적
func slash_arc(center: Vector2, radius: float, a0: float, a1: float, width: float) -> void:
	stroke(Ink.arc_points(center, radius, a0, a1, 14), width, 0.22)


## 낙관: 붉은 도장이 크게 찍혔다가 옅어진다
func seal(pos: Vector2, r: float) -> void:
	seals.append({"p": pos, "r": r, "life": 0.9, "age": 0.0, "rot": randf_range(-0.2, 0.2)})
	splash(pos, Vector2.ZERO, 22, 480.0, PI, Ink.SEAL)
	if stains:
		stains.seal_mark(pos, r)


func ghost(pos: Vector2, facing: Vector2) -> void:
	# 잔상은 띄엄띄엄 (매 프레임 그리면 굵은 관처럼 보인다)
	if not ghosts.is_empty() and (ghosts[ghosts.size() - 1]["p"] as Vector2).distance_to(pos) < 26.0:
		return
	ghosts.append({"p": pos, "f": facing, "life": 0.25, "age": 0.0})


func step(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for d in drops:
		d["age"] += dt
		d["p"] += d["v"] * dt
		d["v"] *= 0.86
		if d["age"] >= d["life"]:
			# 바닥에 떨어져 자국으로 남는다
			if stains and randf() < stain_chance: # 무리가 많은 게임이라 일부만 자국으로
				stains.add(d["p"], float(d["r"]) * randf_range(0.8, 1.6), d["c"])
		else:
			keep.append(d)
	drops = keep
	var ks: Array[Dictionary] = []
	for s in strokes:
		s["age"] += dt
		if s["age"] < s["life"]:
			ks.append(s)
	strokes = ks
	var kg: Array[Dictionary] = []
	for g in ghosts:
		g["age"] += dt
		if g["age"] < g["life"]:
			kg.append(g)
	ghosts = kg
	var kseal: Array[Dictionary] = []
	for s in seals:
		s["age"] += dt
		if s["age"] < s["life"]:
			kseal.append(s)
	seals = kseal
	queue_redraw()


func _draw() -> void:
	for g in ghosts:
		var a := 1.0 - float(g["age"]) / float(g["life"])
		draw_colored_polygon(Ink.blob(g["p"] + Vector2(0, -20), 13.0 * (0.7 + 0.3 * a), 0.0, 0.05), Color(Ink.INK, 0.16 * a))
	for s in strokes:
		var a := 1.0 - pow(float(s["age"]) / float(s["life"]), 2.0)
		var pts: PackedVector2Array = s["pts"]
		Ink.draw_brush(self, pts, float(s["w"]), Color(s["c"], a))
		for ln in s["dry"]:
			for sg in ln["segs"]:
				var part := PackedVector2Array()
				for i in range(sg[0], sg[1] + 1):
					var j := clampi(i, 0, pts.size() - 1)
					var d := (pts[mini(j + 1, pts.size() - 1)] - pts[maxi(j - 1, 0)]).normalized()
					part.append(pts[j] + d.orthogonal() * float(ln["off"]) * float(s["w"]))
				if part.size() >= 2:
					draw_polyline(part, Color(Ink.PAPER, 0.55 * a), float(ln["w"]), true)
	for d in drops:
		draw_circle(d["p"], d["r"], d["c"], true, -1.0, true)
	for s in seals:
		# 쾅 찍히듯 크게 나타났다가 제자리에서 옅어진다
		var k := float(s["age"]) / float(s["life"])
		var r: float = float(s["r"]) * (1.25 - 0.25 * minf(k * 6.0, 1.0))
		var a := 1.0 - k * k
		draw_set_transform(s["p"], s["rot"], Vector2.ONE)
		draw_rect(Rect2(-r * 0.5, -r * 0.5, r, r), Color(Ink.SEAL, 0.85 * a))
		draw_rect(Rect2(-r * 0.38, -r * 0.38, r * 0.76, r * 0.76), Color(Ink.PAPER, 0.9 * a), false, maxf(3.0, r * 0.05))
		draw_string(Ink.brush_font(), Vector2(-r * 0.32, r * 0.22), "印", HORIZONTAL_ALIGNMENT_CENTER, r * 0.64, int(r * 0.55), Color(Ink.PAPER, 0.9 * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 바닥에 쌓이는 먹 자국 (추가될 때만 다시 그린다)
## 바닥의 먹 자국. 시간이 지나면 옅어져 사라진다 (쌓이기만 하면 구슬이 안 보이고 느려진다)
class Stains extends Node2D:
	const MAX_MARKS := 350
	const LIFE := 7.0 # 작은 자국이 사라지기까지 (초)
	const FADE := 2.5 # 마지막 이 시간 동안 옅어진다
	const REDRAW := 0.12 # 옅어지는 모습을 다시 그리는 간격 (매 프레임 그리면 느리다)

	var marks: Array[Dictionary] = []
	var view := Rect2(-1e6, -1e6, 2e6, 2e6) # 화면 밖 자국은 그리지 않는다
	var now := 0.0
	var _redraw_t := 0.0

	func _push(poly: PackedVector2Array, col: Color, life := LIFE) -> void:
		marks.append({"poly": poly, "c": col, "end": now + life})
		if marks.size() > MAX_MARKS:
			marks.pop_front()
		queue_redraw()

	func add(pos: Vector2, r: float, col: Color) -> void:
		_push(Ink.blob(pos, r, randf() * TAU, 0.25, 9), Color(col, randf_range(0.45, 0.7)))

	## 번진 먹 (옅은 층이 여러 겹 겹쳐 가장자리가 부드럽다)
	func wash(pos: Vector2, r: float, alpha := 0.14) -> void:
		for k in 3:
			var rr := r * (1.0 - k * 0.25) * randf_range(0.9, 1.1)
			var off := Vector2.from_angle(randf() * TAU) * r * 0.15
			_push(Ink.blob(pos + off, rr, randf() * TAU, 0.22, 14), Color(Ink.INK, alpha), LIFE + 2.0)

	## 요괴가 쓰러진 자리: 번진 먹 + 진한 가운데 + 튄 방울
	func pool(pos: Vector2, r: float) -> void:
		wash(pos, r * 1.4, 0.1)
		for k in 2:
			_push(Ink.blob(pos + Vector2.from_angle(randf() * TAU) * r * 0.3, r * randf_range(0.3, 0.55), randf() * TAU, 0.3, 10), Color(Ink.INK, 0.5), LIFE + 2.0)
		for i in 4:
			add(pos + Vector2.from_angle(randf() * TAU) * r * randf_range(1.1, 2.2), randf_range(2.0, 6.0), Ink.INK)

	## 낙관 도장 자국 (붉은 네모)
	func seal_mark(pos: Vector2, r: float) -> void:
		_push(Ink.blob(pos, r * 0.35, randf() * TAU, 0.15, 4), Color(Ink.SEAL, 0.35))

	func step(dt: float) -> void:
		now += dt
		# 다 사라진 자국은 버린다 (오래된 것이 앞에 있다)
		var cut := 0
		while cut < marks.size() and float(marks[cut]["end"]) <= now:
			cut += 1
		if cut > 0:
			marks.assign(marks.slice(cut))
		_redraw_t -= dt
		if _redraw_t <= 0.0:
			_redraw_t = REDRAW
			queue_redraw()

	func _draw() -> void:
		var cull := view.grow(60.0)
		for m in marks:
			var poly: PackedVector2Array = m["poly"]
			if not cull.has_point(poly[0]):
				continue
			var c: Color = m["c"]
			var left := float(m["end"]) - now
			if left < FADE:
				c.a *= clampf(left / FADE, 0.0, 1.0)
			draw_colored_polygon(poly, c)
