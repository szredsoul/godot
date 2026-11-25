class_name ShadeTree
extends Node2D
## 가로수. 그늘(shade) 안에 서 있으면 차 그림자를 밟아도 안전하다.

var radius := 58.0
var phase := 0.0
var shade := PackedVector2Array()


func setup(x: float, rng: RandomNumberGenerator) -> void:
	position = Vector2(x, W.SIDEWALK_TOP + 8.0)
	radius = rng.randf_range(52.0, 66.0)
	phase = rng.randf() * TAU
	z_index = 10
	# 나무 구덩이 (땅 높이로 그려지도록 z를 낮춘다)
	var pit := Polygon2D.new()
	pit.polygon = PackedVector2Array([Vector2(-22, -8), Vector2(22, -8), Vector2(22, 14), Vector2(-22, 14)])
	pit.color = Color("c2a47c")
	pit.z_index = -25
	add_child(pit)


## 해가 낮을수록(sun.y 큼) 그늘이 인도 깊숙이 드리운다
func update_shade(sun: Vector2) -> void:
	var top := W.SIDEWALK_TOP - 4.0
	var depth := clampf(30.0 + 45.0 * sun.y, 70.0, W.SIDEWALK_BOTTOM - W.SIDEWALK_TOP + 4.0)
	var c := Vector2(position.x + sun.x * 70.0, top + depth * 0.5)
	var rx := radius * 1.25 + absf(sun.x) * 35.0
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
	draw_circle(c + Vector2(5, 7), radius, Color("5f8a50"), true, -1.0, true)
	draw_circle(c, radius, Color("76a35f"), true, -1.0, true)
	for k in 7:
		var a := phase + k * TAU / 7.0
		draw_circle(c + Vector2.from_angle(a) * radius * 0.78, radius * 0.34, Color("6d9a58"), true, -1.0, true)
	draw_circle(c + Vector2(-radius * 0.3, -radius * 0.22), radius * 0.6, Color("8db86d"), true, -1.0, true)
	draw_circle(c + Vector2(-radius * 0.42, -radius * 0.38), radius * 0.28, Color("b5d48a"), true, -1.0, true)
