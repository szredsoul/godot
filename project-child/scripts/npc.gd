class_name Npc
extends Node2D
## 인도를 걷는 행인. kind == "dog"이면 강아지를 산책시키는 사람 (강아지가 아이를 보면 짖는다).
## 어른들은 그림자 놀이를 안 하니까 그림자에 영향받지 않는다.

const SHIRTS: Array[Color] = [Color("8ea6d8"), Color("d98ca8"), Color("a7c66b"), Color("e8a36f"), Color("b0a2d6"), Color("8fc2b8")]
const DOG_COLORS: Array[Color] = [Color("c89b6d"), Color("f2e6d0"), Color("6e5a4a"), Color("e3c08f")]

var kind := "ped"
var dir := -1.0
var speed := 70.0
var walk_t := 0.0
var shirt := Color.WHITE
var hair := Color("4a3a32")
var dog_color := Color.WHITE
var barked := false
var bump_cd := 0.0
var bark_t := 0.0 # 짖는 연출 시간


func setup(k: String, pos: Vector2, rng: RandomNumberGenerator) -> void:
	kind = k
	position = pos
	dir = -1.0 if rng.randf() < 0.75 else 1.0 # 대부분 마주 오는 방향
	speed = rng.randf_range(55.0, 85.0)
	shirt = SHIRTS[rng.randi() % SHIRTS.size()]
	hair = [Color("4a3a32"), Color("2f2a2a"), Color("8a7a6a"), Color("d8d0c8")][rng.randi() % 4]
	dog_color = DOG_COLORS[rng.randi() % DOG_COLORS.size()]
	walk_t = rng.randf() * TAU


func dog_pos() -> Vector2:
	return position + Vector2(dir * 40.0, 10.0)


func step(delta: float, obstacles: Array) -> void:
	bump_cd = maxf(0.0, bump_cd - delta)
	bark_t = maxf(0.0, bark_t - delta)
	position.x += dir * speed * delta
	walk_t += delta * 8.0
	# 앞에 장애물이 있으면 위아래로 비켜 간다
	var probe := position + Vector2(dir * 40.0, 0)
	for o in obstacles:
		var r: Rect2 = o.rect.grow(14.0)
		if r.has_point(probe):
			var go_up := (probe.y - r.position.y) < (r.end.y - probe.y)
			if go_up and r.position.y - 4.0 < W.WALK_TOP:
				go_up = false
			if not go_up and r.end.y + 4.0 > W.WALK_BOTTOM:
				go_up = true
			position.y += (-1.0 if go_up else 1.0) * 120.0 * delta
			break
	position.y = clampf(position.y, W.WALK_TOP, W.WALK_BOTTOM)
	queue_redraw()


func _draw() -> void:
	var sw := sin(walk_t) * 4.0
	draw_colored_polygon(W.ellipse(Vector2.ZERO, 18, 7), Color(0.25, 0.15, 0.3, 0.3))
	# 다리
	W.rrect(self, Rect2(-9 + sw, -18, 7, 18), Color("5b5560"), 3)
	W.rrect(self, Rect2(2 - sw, -18, 7, 18), Color("5b5560"), 3)
	# 몸
	W.rrect(self, Rect2(-14, -46, 28, 30), shirt, 10)
	# 머리
	var head := Vector2(0, -59)
	draw_circle(head, 13, Color("f6d2b0"), true, -1.0, true)
	var hair_arc := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		hair_arc.append(head + Vector2(cos(a) * 13.5, sin(a) * 13.5 - 2))
	draw_colored_polygon(hair_arc, hair)
	draw_circle(head + Vector2(dir * 5, 1), 1.8, Color("4a3a32"))
	if kind == "dog":
		var d := dog_pos() - position
		draw_line(Vector2(dir * 12, -30), d + Vector2(dir * 4, -14), Color("c0503f"), 1.5, true)
		_draw_dog(d)


func _draw_dog(d: Vector2) -> void:
	var hop := absf(sin(walk_t * 1.6)) * 2.0
	draw_colored_polygon(W.ellipse(d, 13, 5), Color(0.25, 0.15, 0.3, 0.3))
	var b := d + Vector2(0, -10 - hop)
	draw_colored_polygon(W.ellipse(b, 13, 8, 18), dog_color)
	var h := b + Vector2(dir * 12, -6)
	draw_circle(h, 8, dog_color, true, -1.0, true)
	draw_colored_polygon(W.ellipse(h + Vector2(-dir * 3, -6), 3, 5, 10), dog_color.darkened(0.25))
	draw_circle(h + Vector2(dir * 7, 1), 2, Color("3a2e28"))
	draw_circle(h + Vector2(dir * 3, -2), 1.5, Color("3a2e28"))
	# 꼬리 흔들기
	var tail := b + Vector2(-dir * 13, -2)
	draw_line(tail, tail + Vector2(-dir * 7, -6 + sin(walk_t * 4.0) * 4.0), dog_color.darkened(0.15), 3.0, true)
	if bark_t > 0.0:
		draw_string(UI.font(true), h + Vector2(dir * 8 - 14, -14), "멍!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e0654f"))
