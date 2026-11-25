class_name Imagination
extends Node2D
## 아이의 상상: 인도에 드리운 그림자(거꾸로 놀이에선 햇빛)가 바다·용암·늪·얼음 구멍으로 보인다.
## pools(월드 좌표 다각형)를 테마에 맞게 칠하고, 거품·물결·상어 지느러미 같은 장식을 얹는다.

const THEMES := {
	"lava": {"name": "용암", "base": Color("d9482b"), "mid": Color("f07a32"), "hi": Color("ffc04a"),
		"edge": Color("7a2a1c"), "glow": Color(1.0, 0.6, 0.25, 0.55)},
	"sea": {"name": "바다", "base": Color("2d6ea6"), "mid": Color("3f8cc4"), "hi": Color("d8f0ff"),
		"edge": Color("f4fbff"), "glow": Color(1, 1, 1, 0.45)},
	"swamp": {"name": "늪", "base": Color("4c6a3a"), "mid": Color("66843f"), "hi": Color("b5cf78"),
		"edge": Color("33472a"), "glow": Color(0.7, 0.85, 0.45, 0.4)},
	"ice": {"name": "얼음 구멍", "base": Color("1f4b78"), "mid": Color("2f6a9c"), "hi": Color("eaf6ff"),
		"edge": Color("f4fbff"), "glow": Color(1, 1, 1, 0.6)},
}
const STEP := 26.0 # 장식 격자 간격

var theme := "lava"
var t := 0.0
var pools: Array[PackedVector2Array] = []


func step(delta: float) -> void:
	t += delta
	queue_redraw()


static func sidewalk_band(x0: float, x1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, W.SIDEWALK_TOP), Vector2(x1, W.SIDEWALK_TOP),
			Vector2(x1, W.SIDEWALK_BOTTOM), Vector2(x0, W.SIDEWALK_BOTTOM)])


func _draw() -> void:
	var th: Dictionary = THEMES[theme]
	for poly in pools:
		if not W.can_fill(poly):
			continue
		draw_colored_polygon(poly, th["base"])
		for inner in Geometry2D.offset_polygon(poly, -9.0):
			if W.can_fill(inner):
				draw_colored_polygon(inner, th["mid"])
		_deco(poly, th)
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		draw_polyline(closed, th["glow"], 7.0, true)
		draw_polyline(closed, th["edge"], 2.5, true)


func _inside(p: Vector2, poly: PackedVector2Array, m: float) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly) \
			and Geometry2D.is_point_in_polygon(p + Vector2(m, 0), poly) \
			and Geometry2D.is_point_in_polygon(p - Vector2(m, 0), poly) \
			and Geometry2D.is_point_in_polygon(p + Vector2(0, m * 0.7), poly) \
			and Geometry2D.is_point_in_polygon(p - Vector2(0, m * 0.7), poly)


func _deco(poly: PackedVector2Array, th: Dictionary) -> void:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	var hi: Color = th["hi"]
	# 땅에 고정된 격자 위치에 장식을 둔다 (그림자가 움직이면 그 아래 세계가 드러나는 느낌)
	for gx in range(int(floorf(r.position.x / STEP)), int(r.end.x / STEP) + 1):
		for gy in range(int(floorf(r.position.y / STEP)), int(r.end.y / STEP) + 1):
			var h := absi(hash(gx * 7919 + gy * 104729))
			var p := Vector2((gx + 0.2 + float(h % 60) / 100.0) * STEP, (gy + 0.2 + float((h / 60) % 60) / 100.0) * STEP)
			if not _inside(p, poly, 9.0):
				continue
			var ph := fposmod(t * 0.7 + float(h % 100) / 100.0, 1.0)
			match theme:
				"lava":
					if h % 3 == 0:
						draw_arc(p, 2.0 + ph * 8.0, 0.0, TAU, 14, Color(hi, 1.0 - ph), 1.8, true)
					elif h % 3 == 1:
						draw_circle(p, 2.5 + sin(t * 3.0 + h) * 1.0, Color(hi, 0.8), true, -1.0, true)
				"sea":
					if h % 2 == 0:
						var wp := p + Vector2(sin(t * 1.8 + h) * 4.0, 0)
						draw_arc(wp, 7.0, PI * 1.15, PI * 1.85, 8, Color(hi, 0.7), 2.0, true)
				"swamp":
					if h % 3 == 0:
						draw_circle(p, 2.0 + ph * 3.0, Color(hi, 0.9 - ph * 0.7), true, -1.0, true)
					elif h % 13 == 1:
						_croc_eyes(p)
				"ice":
					if h % 4 == 0:
						var a := float(h % 628) / 100.0 + t * 0.2
						var s := 5.0 + float(h % 5)
						var sq := PackedVector2Array()
						for k in 4:
							sq.append(p + Vector2.from_angle(a + k * PI * 0.5) * s)
						draw_colored_polygon(sq, Color(hi, 0.85))
	# 바다엔 상어 지느러미가 왔다 갔다
	if theme == "sea" and r.size.x > 70.0:
		var fin := Vector2(r.get_center().x + sin(t * 1.3 + r.position.x * 0.013) * r.size.x * 0.3, r.get_center().y + 6.0)
		if _inside(fin, poly, 14.0):
			var dir := signf(cos(t * 1.3 + r.position.x * 0.013))
			draw_colored_polygon(PackedVector2Array([fin + Vector2(-10 * dir, 0), fin + Vector2(10 * dir, 0), fin + Vector2(4 * dir, -18)]), Color("5b6c7a"))
			draw_arc(fin + Vector2(-6 * dir, 2), 10, 0.2, PI - 0.2, 8, Color(1, 1, 1, 0.7), 2.0, true)


func _croc_eyes(p: Vector2) -> void:
	var blink := fmod(t + p.x * 0.01, 3.0) < 0.15
	for dx in [-6.0, 6.0]:
		draw_circle(p + Vector2(dx, 0), 5, Color("3e5a2c"), true, -1.0, true)
		if blink:
			draw_line(p + Vector2(dx - 3, 0), p + Vector2(dx + 3, 0), Color("1f2a16"), 1.5, true)
		else:
			draw_circle(p + Vector2(dx, -1), 3, Color("f2e48a"), true, -1.0, true)
			draw_rect(Rect2(p + Vector2(dx - 0.8, -3.5), Vector2(1.6, 5)), Color("1f2a16"))


## 물보라·불꽃 튀는 효과
class Splash extends Node2D:
	var parts: Array[Dictionary] = []

	func burst(pos: Vector2, col: Color, n: int, power: float) -> void:
		for i in n:
			var a := randf_range(PI * 1.1, PI * 1.9)
			parts.append({"p": pos, "v": Vector2.from_angle(a) * randf_range(0.4, 1.0) * power,
					"life": randf_range(0.4, 0.7), "age": 0.0, "r": randf_range(2.0, 4.5), "c": col})

	func step(delta: float) -> void:
		for q in parts:
			q["age"] += delta
			q["v"] += Vector2(0, 700.0) * delta
			q["p"] += q["v"] * delta
		var keep: Array[Dictionary] = []
		for q in parts:
			if q["age"] < q["life"]:
				keep.append(q)
		parts = keep
		queue_redraw()

	func _draw() -> void:
		for q in parts:
			var a := 1.0 - float(q["age"]) / float(q["life"])
			draw_circle(q["p"], q["r"], Color(q["c"], a), true, -1.0, true)
