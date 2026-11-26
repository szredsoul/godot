class_name ShadeTree
extends Node2D
## 가로수. 그늘(shade) 안에 서 있으면 차 그림자를 밟아도 안전하다.
## 겨울에는 잎이 없어서 그늘이 작다.

var radius := 58.0
var phase := 0.0
var shade := PackedVector2Array()
var colors: Array = []
var bare := false
var umbrella := false # 횡단보도 그늘막: 신호를 기다리는 동안 안전한 자리
var umbrella_dx := 0.0


## 횡단보도 앞 그늘막 (해 위치와 상관없이 인도를 넉넉히 덮는다)
func setup_umbrella(x: float, toward_x: float) -> void:
	umbrella = true
	position = Vector2(x, W.SIDEWALK_TOP + 14.0)
	radius = 62.0
	phase = 0.0
	z_index = 110
	colors = [Color("4f9a6a"), Color("f4f8f2")]
	# 그늘은 횡단보도 쪽으로 넓게 (신호를 기다리는 자리까지 덮는다)
	umbrella_dx = signf(toward_x - x) * 25.0


func setup(x: float, rng: RandomNumberGenerator, season: Dictionary) -> void:
	position = Vector2(x, W.SIDEWALK_TOP + 8.0)
	radius = rng.randf_range(52.0, 66.0)
	phase = rng.randf() * TAU
	colors = season["canopy"]
	bare = season["bare"]
	z_index = 110 # 잎은 사람·차보다 위
	var pit := Polygon2D.new()
	pit.polygon = PackedVector2Array([Vector2(-22, -8), Vector2(22, -8), Vector2(22, 14), Vector2(-22, 14)])
	pit.color = Color("d6dde0") if season["snow"] else Color("c2a47c")
	pit.z_as_relative = false
	pit.z_index = -16
	add_child(pit)


## 해가 낮을수록(sun.y 큼) 그늘이 인도 깊숙이 드리운다
func update_shade(sun: Vector2) -> void:
	if umbrella:
		# 둥근 네모: 인도 위아래 끝까지, 횡단보도 바로 앞까지 덮는다
		var r := Rect2(position.x + umbrella_dx - 106.0, W.SIDEWALK_TOP - 2.0, 212.0, W.SIDEWALK_BOTTOM - W.SIDEWALK_TOP + 4.0)
		var cr := 24.0
		var pts := PackedVector2Array()
		var corners := [r.position + Vector2(r.size.x - cr, cr), r.end - Vector2(cr, cr),
				Vector2(r.position.x + cr, r.end.y - cr), r.position + Vector2(cr, cr)]
		for k in 4:
			for s in 7:
				var a := -PI * 0.5 + k * PI * 0.5 + s * PI / 12.0
				pts.append(corners[k] + Vector2.from_angle(a) * cr)
		shade = pts
		return
	var size_mul := 0.6 if bare else 1.0
	var top := W.SIDEWALK_TOP - 4.0
	var depth := clampf((30.0 + 45.0 * sun.y) * size_mul, 60.0, W.SIDEWALK_BOTTOM - W.SIDEWALK_TOP + 4.0)
	var c := Vector2(position.x + sun.x * 70.0, top + depth * 0.5)
	var rx := (radius * 1.25 + absf(sun.x) * 35.0) * size_mul
	var ry := depth * 0.5
	var pts := PackedVector2Array()
	var n := 32
	for i in n:
		var a := TAU * i / n
		var wob := 1.0 + 0.07 * sin(a * 5.0 + phase) + 0.04 * sin(a * 9.0 + phase * 2.0)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry) * wob)
	shade = pts


func _draw() -> void:
	var c := Vector2(0, -46)
	if umbrella:
		# 위에서 본 8각 그늘막 (초록·흰 줄)
		var uc := Vector2(0, -40)
		draw_circle(uc + Vector2(5, 7), radius, Color(0.2, 0.15, 0.1, 0.15), true, -1.0, true)
		for s in 8:
			var a0 := s * TAU / 8.0 - PI / 8.0
			var pts := PackedVector2Array([uc, uc + Vector2.from_angle(a0) * radius, uc + Vector2.from_angle(a0 + TAU / 8.0) * radius])
			draw_colored_polygon(pts, colors[0] if s % 2 == 0 else colors[1])
		draw_circle(uc, 6, Color("3f7a52"), true, -1.0, true)
		return
	if bare:
		_draw_bare(c)
		return
	var dark: Color = colors[0]
	var base: Color = colors[1]
	draw_circle(c + Vector2(5, 7), radius, dark, true, -1.0, true)
	draw_circle(c, radius, base, true, -1.0, true)
	for k in 7:
		var a := phase + k * TAU / 7.0
		draw_circle(c + Vector2.from_angle(a) * radius * 0.78, radius * 0.34, dark.lerp(base, 0.5), true, -1.0, true)
	draw_circle(c + Vector2(-radius * 0.3, -radius * 0.22), radius * 0.6, colors[2], true, -1.0, true)
	draw_circle(c + Vector2(-radius * 0.42, -radius * 0.38), radius * 0.28, colors[3], true, -1.0, true)


## 겨울: 앙상한 가지 + 쌓인 눈
func _draw_bare(c: Vector2) -> void:
	var wood: Color = colors[0]
	draw_circle(Vector2.ZERO, 7, wood, true, -1.0, true)
	for k in 6:
		var a := phase + k * TAU / 6.0
		var tip := c + Vector2.from_angle(a) * radius * 0.85
		draw_line(Vector2(0, -6), tip, wood, 4.0, true)
		var mid := Vector2(0, -6).lerp(tip, 0.6)
		draw_line(mid, mid + Vector2.from_angle(a + 0.6) * radius * 0.3, wood, 2.5, true)
		draw_line(mid, mid + Vector2.from_angle(a - 0.6) * radius * 0.3, wood, 2.5, true)
		draw_circle(tip, 5, colors[2], true, -1.0, true)
	draw_circle(c, 12, colors[3], true, -1.0, true)
