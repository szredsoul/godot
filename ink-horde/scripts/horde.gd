class_name Horde
extends Node2D
## 먹 요괴 무리. 수백 마리를 노드 하나로 계산하고 그린다 (요괴마다 노드를 만들면 느려진다).
## 요괴 = Dictionary {kind, p, hp, max, r, spd, dmg, xp, flash, kb, ph, ...}
## 서로 겹치지 않게 칸(격자)으로 나눠 가까운 것끼리만 밀어낸다.

const CELL := 64.0
const KINDS := {
	"imp": {"hp": 8.0, "spd": 92.0, "r": 12.0, "dmg": 8.0, "xp": 1},
	"bat": {"hp": 6.0, "spd": 150.0, "r": 10.0, "dmg": 6.0, "xp": 1},
	"ogre": {"hp": 24.0, "spd": 70.0, "r": 18.0, "dmg": 12.0, "xp": 2},
	"brute": {"hp": 95.0, "spd": 50.0, "r": 30.0, "dmg": 20.0, "xp": 6},
	"elite": {"hp": 320.0, "spd": 64.0, "r": 34.0, "dmg": 22.0, "xp": 25},
	"boss": {"hp": 1600.0, "spd": 58.0, "r": 58.0, "dmg": 30.0, "xp": 150},
}

var list: Array[Dictionary] = []
var grid := {}
var view := Rect2() # 화면 범위 (밖은 그리지 않는다)
var next_id := 0


func spawn(kind: String, p: Vector2, hp_mul: float) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var hp: float = float(k["hp"]) * hp_mul
	next_id += 1
	var e := {"id": next_id, "kind": kind, "p": p, "hp": hp, "max": hp, "r": k["r"], "spd": k["spd"],
			"dmg": k["dmg"], "xp": k["xp"], "flash": 0.0, "kb": Vector2.ZERO, "ph": randf() * TAU,
			"state": "walk", "t": 0.0, "dash_dir": Vector2.ZERO, "cd": 3.0}
	list.append(e)
	return e


func _key(p: Vector2) -> Vector2i:
	return Vector2i(int(floorf(p.x / CELL)), int(floorf(p.y / CELL)))


func rebuild_grid() -> void:
	grid.clear()
	for e in list:
		var k := _key(e["p"])
		if not grid.has(k):
			grid[k] = []
		grid[k].append(e)


## p 근처(반경 radius)의 요괴들
func near(p: Vector2, radius: float) -> Array:
	var out := []
	var c0 := _key(p - Vector2(radius, radius))
	var c1 := _key(p + Vector2(radius, radius))
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			var cell: Array = grid.get(Vector2i(x, y), [])
			for e in cell:
				if (e["p"] as Vector2).distance_to(p) <= radius + float(e["r"]):
					out.append(e)
	return out


func step(dt: float, target: Vector2) -> void:
	rebuild_grid()
	for e in list:
		var p: Vector2 = e["p"]
		e["flash"] = maxf(0.0, float(e["flash"]) - dt)
		e["ph"] = float(e["ph"]) + dt * 3.0
		var to := target - p
		var dir := to.normalized() if to.length() > 1.0 else Vector2.ZERO
		var mv := dir * float(e["spd"])
		if e["kind"] == "boss" or e["kind"] == "elite":
			mv = _big_move(e, dt, dir)
		# 이웃과 겹치지 않게 밀어내기 (같은 칸과 주변 칸만)
		var push := Vector2.ZERO
		var k := _key(p)
		for x in range(k.x - 1, k.x + 2):
			for y in range(k.y - 1, k.y + 2):
				var cell: Array = grid.get(Vector2i(x, y), [])
				for o in cell:
					if is_same(o, e): # 내용 비교(==)는 느리다
						continue
					var d := p - (o["p"] as Vector2)
					var min_d := float(e["r"]) + float(o["r"])
					var dl := d.length()
					if dl < min_d and dl > 0.01:
						push += d / dl * (min_d - dl)
		e["p"] = p + (mv + e["kb"]) * dt + push * 0.35
		e["kb"] = (e["kb"] as Vector2) * pow(0.002, dt)
	queue_redraw()


## 정예·보스: 가끔 붉은 낙관을 띄우고 돌진한다
func _big_move(e: Dictionary, dt: float, dir: Vector2) -> Vector2:
	e["t"] = float(e["t"]) + dt
	match e["state"]:
		"walk":
			e["cd"] = float(e["cd"]) - dt
			if float(e["cd"]) <= 0.0:
				e["state"] = "tele"
				e["t"] = 0.0
			return dir * float(e["spd"])
		"tele":
			e["dash_dir"] = dir
			if float(e["t"]) >= 0.8:
				e["state"] = "dash"
				e["t"] = 0.0
			return Vector2.ZERO
		"dash":
			if float(e["t"]) >= 0.55:
				e["state"] = "walk"
				e["cd"] = randf_range(3.0, 5.0)
			return (e["dash_dir"] as Vector2) * 620.0
	return dir * float(e["spd"])


## 맞음. 쓰러지면 true
func hurt(e: Dictionary, dmg: float, from_dir: Vector2, knock: float) -> bool:
	e["hp"] = float(e["hp"]) - dmg
	e["flash"] = 0.08
	var resist := 0.15 if e["kind"] in ["boss", "elite", "brute"] else 1.0
	e["kb"] = (e["kb"] as Vector2) + from_dir.normalized() * knock * resist
	return float(e["hp"]) <= 0.0


## 쓰러진 요괴를 한 번에 치운다 (프레임마다 한 번)
func cleanup() -> void:
	var keep: Array[Dictionary] = []
	for e in list:
		if not e.get("dead", false):
			keep.append(e)
	list = keep


func remove(e: Dictionary) -> void:
	e["dead"] = true


# ───────────── 그리기 ─────────────
# 요괴마다 매 프레임 다각형을 새로 계산하면 수백 마리에서 느려진다.
# 그래서 종류마다 꿈틀거리는 모양 FRAMES장(+ 맞았을 때 흰 모양)을 미리 메시로 만들어 두고 위치만 바꿔 찍는다.

const FRAMES := 6
var _meshes := {}
var _shadow: ArrayMesh
var _v := PackedVector2Array()
var _c := PackedColorArray()
var _i := PackedInt32Array()


func _add_poly(poly: PackedVector2Array, col: Color) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		return
	var base := _v.size()
	_v.append_array(poly)
	for k in poly.size():
		_c.append(col)
	for k in tri:
		_i.append(base + k)


func _finish_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_INDEX] = _i
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_v = PackedVector2Array()
	_c = PackedColorArray()
	_i = PackedInt32Array()
	return m


## 몸통 가운데를 (0,0)으로 둔 요괴 모양
func _mesh_for(kind: String, frame: int, flash: bool) -> ArrayMesh:
	var key := "%s%d%d" % [kind, frame, int(flash)]
	if _meshes.has(key):
		return _meshes[key]
	var r: float = KINDS[kind]["r"]
	var ph := TAU * frame / FRAMES
	var col := Ink.ROBE if flash else Ink.INK
	_add_poly(Ink.blob(Vector2.ZERO, r, ph, 0.13, 14 if r < 20.0 else 20), col)
	if kind == "bat":
		var flap := sin(ph * 2.0) * 0.5
		_add_poly(PackedVector2Array([Vector2(-r * 0.6, 0), Vector2(-r * 0.9, r * 0.4), Vector2(-r * 2.0, -r * (0.6 + flap))]), col)
		_add_poly(PackedVector2Array([Vector2(r * 0.6, 0), Vector2(r * 2.0, -r * (0.6 + flap)), Vector2(r * 0.9, r * 0.4)]), col)
	elif kind != "imp":
		var hr := r * 1.55
		_add_poly(PackedVector2Array([Vector2(-r * 0.5, -r * 0.7), Vector2(-r * 0.6, -hr), Vector2(-r * 0.18, -r * 0.8)]), col)
		_add_poly(PackedVector2Array([Vector2(r * 0.5, -r * 0.7), Vector2(r * 0.18, -r * 0.8), Vector2(r * 0.6, -hr)]), col)
	if kind == "boss":
		# 붉은 입 무늬 (바깥 호 + 안쪽 호를 이은 띠)
		var band := Ink.arc_points(Vector2.ZERO, r * 0.76, PI * 0.15, PI * 0.85, 10)
		var inner := Ink.arc_points(Vector2.ZERO, r * 0.62, PI * 0.15, PI * 0.85, 10)
		inner.reverse()
		band.append_array(inner)
		_add_poly(band, Ink.SEAL)
	var eye := Ink.INK if flash else Color("f5efe0")
	var es := r / 23.0
	_add_poly(Ink.ellipse(Vector2(-7, -4) * es, 4.5 * es, 4.5 * es, 8), eye)
	_add_poly(Ink.ellipse(Vector2(7, -4) * es, 4.5 * es, 4.5 * es, 8), eye)
	var m := _finish_mesh()
	_meshes[key] = m
	return m


func _ready() -> void:
	# 미리 만든 메시(draw_mesh)는 Godot가 그림 범위를 원점 근처로만 계산해서,
	# 플레이어가 원점에서 멀어지면 요괴 전체가 "화면 밖"으로 판정돼 안 그려진다.
	# 그래서 이 그림은 맵 전체를 덮는다고 직접 알려 준다. (화면 밖 요괴는 아래 _draw에서 따로 거른다)
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, Rect2(-1e7, -1e7, 2e7, 2e7))


func _draw() -> void:
	if _shadow == null:
		_add_poly(Ink.ellipse(Vector2.ZERO, 1.1, 0.4, 12), Color(Ink.INK, 0.18))
		_shadow = _finish_mesh()
	var cull := view.grow(80.0)
	# 화면 안 요괴만 골라 위(뒤)에서 아래(앞) 순서로 그린다
	var vis: Array[Dictionary] = []
	for e in list:
		if cull.has_point(e["p"]):
			vis.append(e)
	vis.sort_custom(func(a, b): return (a["p"] as Vector2).y < (b["p"] as Vector2).y)
	for e in vis:
		var p: Vector2 = e["p"]
		var r: float = e["r"]
		var kind: String = e["kind"]
		draw_mesh(_shadow, null, Transform2D(0.0, Vector2(r, r), 0.0, p))
		var body := p + Vector2(0, -r)
		var squash := 1.0 + 0.06 * sin(float(e["ph"]) * 2.0)
		if e["state"] == "dash":
			squash = 0.8
		var frame := int(float(e["ph"]) * 1.5) % FRAMES
		draw_mesh(_mesh_for(kind, frame, float(e["flash"]) > 0.0), null, Transform2D(0.0, Vector2(1.0 / squash, squash), 0.0, body))
		# 정예·보스의 붉은 낙관 (몇 마리 안 되니 바로 그린다)
		if kind == "elite" or kind == "boss":
			var s := r * 0.32
			if e["state"] == "tele":
				s *= 1.3 + 0.3 * sin(float(e["t"]) * 30.0)
			var c := body + Vector2(0, -r - 18)
			draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), Ink.SEAL)
			draw_rect(Rect2(c - Vector2(s, s) * 0.6, Vector2(s, s) * 1.2), Color("f5efe0"), false, 2.0)
			if e["state"] == "tele":
				draw_line(body, body + (e["dash_dir"] as Vector2) * 340.0, Color(Ink.SEAL, 0.22), r * 1.2, true)
