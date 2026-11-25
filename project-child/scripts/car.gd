class_name Car
extends Node2D
## 차도를 달리는 차. 높이(h)와 태양 벡터로 그림자를 만든다.

const KINDS := {
	"bike":  {"len": 58.0,  "wid": 26.0, "h": 50.0,  "speed": 330.0},
	"car":   {"len": 112.0, "wid": 54.0, "h": 62.0,  "speed": 270.0},
	"van":   {"len": 142.0, "wid": 62.0, "h": 88.0,  "speed": 240.0},
	"truck": {"len": 220.0, "wid": 70.0, "h": 118.0, "speed": 205.0},
	"bus":   {"len": 250.0, "wid": 72.0, "h": 132.0, "speed": 175.0},
}
const PALETTE: Array[Color] = [
	Color("e8875f"), Color("7fb3a6"), Color("f2c14e"),
	Color("8ea6d8"), Color("d98ca8"), Color("a7c66b"),
]
const C_GLASS := Color("bcd9e6")
const C_TIRE := Color("4a4248")

var kind := "car"
var lane := 0
var length := 112.0
var width := 54.0
var height := 62.0
var speed := 270.0
var dir := 1
var body_color := Color.WHITE
var shadow := PackedVector2Array()
var passed := false # 아이 옆을 지나갔는지 (효과음용)


func setup(k: String, lane_idx: int, rng: RandomNumberGenerator) -> void:
	kind = k
	lane = lane_idx
	var d: Dictionary = KINDS[k]
	length = d["len"]
	width = d["wid"]
	height = d["h"]
	speed = float(d["speed"]) * rng.randf_range(0.88, 1.12)
	dir = -1 if lane == 0 else 1
	body_color = PALETTE[rng.randi() % PALETTE.size()]
	if k == "bus":
		body_color = Color("f2b84b") if rng.randf() < 0.5 else Color("6fae8f")
	position.y = W.LANE_Y[lane]
	z_index = 5


func step(delta: float) -> void:
	position.x += speed * dir * delta


func update_shadow(sun: Vector2) -> void:
	var hl := length * 0.5
	var hw := width * 0.5
	var base := PackedVector2Array([
		position + Vector2(-hl, -hw), position + Vector2(hl, -hw),
		position + Vector2(hl, hw), position + Vector2(-hl, hw),
	])
	var all := PackedVector2Array(base)
	for p in base:
		all.append(p + sun * height)
	var hull := Geometry2D.convex_hull(all)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.resize(hull.size() - 1)
	shadow = hull


func _draw() -> void:
	# 앞쪽이 항상 +x가 되도록 뒤집어서 그린다
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(dir, 1))
	var hl := length * 0.5
	var hw := width * 0.5
	var edge := body_color.darkened(0.22)
	match kind:
		"bike":
			W.rrect(self, Rect2(-hl, -3, length, 6), C_TIRE, 3)
			W.rrect(self, Rect2(-hl * 0.5, -hw + 4, length * 0.55, width - 8), body_color, 8, edge, 2)
			draw_circle(Vector2(-2, 0), 9, Color("5b6c8f"))
			draw_circle(Vector2(4, 0), 7, Color("f4ead8"))
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
