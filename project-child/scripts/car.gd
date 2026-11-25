class_name Car
extends Node2D
## 차. 큰길(가로) 또는 교차로 골목(세로)을 달린다. 높이(h)와 태양 벡터로 그림자를 만든다.
## 이동은 game.gd가 앞차 간격·신호·정류장을 보고 결정한다.

const KINDS := {
	"bike":  {"len": 58.0,  "wid": 26.0, "h": 50.0,  "speed": 400.0},
	"moto":  {"len": 66.0,  "wid": 30.0, "h": 58.0,  "speed": 580.0},
	"car":   {"len": 112.0, "wid": 54.0, "h": 62.0,  "speed": 380.0},
	"van":   {"len": 142.0, "wid": 62.0, "h": 88.0,  "speed": 340.0},
	"truck": {"len": 220.0, "wid": 70.0, "h": 118.0, "speed": 290.0},
	"bus":   {"len": 250.0, "wid": 72.0, "h": 132.0, "speed": 250.0},
}
const PALETTE: Array[Color] = [
	Color("e8875f"), Color("7fb3a6"), Color("f2c14e"),
	Color("8ea6d8"), Color("d98ca8"), Color("a7c66b"),
]
const C_GLASS := Color("bcd9e6")
const C_TIRE := Color("4a4248")
const ACCEL := 320.0

var kind := "car"
var group := "" # 같은 차선끼리 앞차를 따라간다 ("main0", "main1", "side3u" ...)
var lane := -1 # 큰길 차선 (0: 먼 차선 ←, 1: 가까운 차선 →), 골목 차는 -1
var vertical := false
var length := 112.0
var width := 54.0
var height := 62.0
var max_speed := 270.0
var cur_speed := 270.0
var dir := 1
var body_color := Color.WHITE
var shadow := PackedVector2Array()
var passed := false # 아이 옆을 지나갔는지 (효과음용)
var stop_at := INF # 버스 정류장에 설 위치 (앞부분 좌표)
var dwell := 0.0 # 정류장에 서 있을 남은 시간
var cleared_stop := false


func setup(k: String, rng: RandomNumberGenerator, grp: String, direction: int, is_vertical := false) -> void:
	kind = k
	group = grp
	dir = direction
	vertical = is_vertical
	var d: Dictionary = KINDS[k]
	length = d["len"]
	width = d["wid"]
	height = d["h"]
	max_speed = float(d["speed"]) * rng.randf_range(0.88, 1.12)
	if vertical:
		max_speed *= 0.6 # 골목에서 나오는 차는 천천히
	cur_speed = max_speed
	body_color = PALETTE[rng.randi() % PALETTE.size()]
	if k == "bus":
		body_color = Color("f2b84b") if rng.randf() < 0.5 else Color("6fae8f")
	z_index = 5


func axis_pos() -> float:
	return position.y if vertical else position.x


func front() -> float:
	return axis_pos() + dir * length * 0.5


func rear() -> float:
	return axis_pos() - dir * length * 0.5


func advance(d: float) -> void:
	if vertical:
		position.y += d * dir
	else:
		position.x += d * dir


func half_extents() -> Vector2:
	return Vector2(width, length) * 0.5 if vertical else Vector2(length, width) * 0.5


func body_rect() -> Rect2:
	var he := half_extents()
	return Rect2(position - he, he * 2.0)


func update_shadow(sun: Vector2) -> void:
	var he := half_extents()
	var base := PackedVector2Array([
		position + Vector2(-he.x, -he.y), position + Vector2(he.x, -he.y),
		position + Vector2(he.x, he.y), position + Vector2(-he.x, he.y),
	])
	var all := PackedVector2Array(base)
	for p in base:
		all.append(p + sun * height)
	var hull := Geometry2D.convex_hull(all)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.resize(hull.size() - 1)
	shadow = hull


func _draw() -> void:
	# 앞쪽이 항상 +x가 되도록 돌리거나 뒤집어서 그린다
	if vertical:
		draw_set_transform(Vector2.ZERO, dir * PI * 0.5, Vector2.ONE)
	else:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(dir, 1))
	var hl := length * 0.5
	var hw := width * 0.5
	var edge := body_color.darkened(0.22)
	match kind:
		"bike":
			W.rrect(self, Rect2(-hl, -3, length, 6), C_TIRE, 3)
			W.rrect(self, Rect2(-hl * 0.5, -hw + 4, length * 0.55, width - 8), body_color, 8, edge, 2)
			draw_circle(Vector2(-2, 0), 9, Color("5b6c8f"), true, -1.0, true)
			draw_circle(Vector2(4, 0), 7, Color("f4ead8"), true, -1.0, true)
		"moto":
			W.rrect(self, Rect2(-hl, -4, length, 8), C_TIRE, 4)
			W.rrect(self, Rect2(-hl * 0.2, -hw + 5, length * 0.55, width - 10), Color("e85a4f"), 8, Color("b8443b"), 2)
			# 배달통
			W.rrect(self, Rect2(-hl - 2, -hw + 1, length * 0.36, width - 2), Color("f4ead8"), 5, Color("d8c8aa"), 2)
			draw_rect(Rect2(-hl + 4, -3, length * 0.24, 6), Color("e85a4f"))
			draw_circle(Vector2(6, 0), 9, Color("f4f4f4"), true, -1.0, true)
			draw_circle(Vector2(8, 0), 6, Color("3b3b44"), true, -1.0, true)
		"truck":
			_tires(hl, hw)
			var box_len := length * 0.7
			W.rrect(self, Rect2(-hl, -hw, box_len, width), Color("f4ead8"), 6, Color("d8c8aa"), 2)
			for i in 3:
				draw_rect(Rect2(-hl + 14 + i * box_len / 3.0, -hw + 6, 3, width - 12), Color("e4d6bc"))
			W.rrect(self, Rect2(-hl + box_len + 4, -hw + 3, length - box_len - 4, width - 6), body_color, 10, edge, 2)
			W.rrect(self, Rect2(hl - 22, -hw + 8, 14, width - 16), C_GLASS, 5)
			_lights(hl, hw)
		"bus":
			_tires(hl, hw)
			W.rrect(self, Rect2(-hl, -hw, length, width), body_color, 14, edge, 2)
			W.rrect(self, Rect2(-hl + 10, -hw + 10, length - 20, width - 20), body_color.lightened(0.18), 8)
			var n := 6
			for i in n:
				var x := -hl + 22 + i * (length - 60) / n
				W.rrect(self, Rect2(x, -hw + 3, 26, 6), C_GLASS, 3)
				W.rrect(self, Rect2(x, hw - 9, 26, 6), C_GLASS, 3)
			W.rrect(self, Rect2(hl - 20, -hw + 8, 12, width - 16), C_GLASS, 5)
			_lights(hl, hw)
		_: # car, van
			_tires(hl, hw)
			W.rrect(self, Rect2(-hl, -hw, length, width), body_color, 18 if kind == "car" else 12, edge, 2)
			var roof_start := -hl * 0.55 if kind == "car" else -hl * 0.8
			var roof_end := hl * 0.18 if kind == "car" else hl * 0.35
			W.rrect(self, Rect2(roof_end, -hw + 7, hl * 0.32, width - 14), C_GLASS, 7)
			W.rrect(self, Rect2(roof_start - hl * 0.18, -hw + 8, hl * 0.16, width - 16), C_GLASS, 5)
			W.rrect(self, Rect2(roof_start, -hw + 6, roof_end - roof_start, width - 12), body_color.lightened(0.15), 8)
			_lights(hl, hw)
	# 멈춰 있으면 브레이크등
	if cur_speed < 5.0 and kind != "bike":
		draw_circle(Vector2(-hl + 3, -hw + 8), 5, Color(1.0, 0.3, 0.25, 0.6), true, -1.0, true)
		draw_circle(Vector2(-hl + 3, hw - 8), 5, Color(1.0, 0.3, 0.25, 0.6), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tires(hl: float, hw: float) -> void:
	for x in [-hl * 0.65, hl * 0.6]:
		W.rrect(self, Rect2(x - 10, -hw - 3, 20, 7), C_TIRE, 3)
		W.rrect(self, Rect2(x - 10, hw - 4, 20, 7), C_TIRE, 3)


func _lights(hl: float, hw: float) -> void:
	draw_circle(Vector2(hl - 4, -hw + 8), 4, Color("fff3c4"))
	draw_circle(Vector2(hl - 4, hw - 8), 4, Color("fff3c4"))
	draw_circle(Vector2(-hl + 3, -hw + 8), 3, Color("e85a4f"))
	draw_circle(Vector2(-hl + 3, hw - 8), 3, Color("e85a4f"))
