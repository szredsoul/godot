class_name Obstacle
extends Node2D
## 인도 위 장애물. rect(월드 좌표)로 길을 막고, 화면상 점프 높이가 height보다 높으면 넘을 수 있다.
## position = rect 아래 가운데 (앞뒤 정렬 기준)

const TALL := 999.0

var kind := "trash"
var rect := Rect2()
var height := 16.0
var snow := false
var rng_seed := 0


static func make(k: String, x: float, rng: RandomNumberGenerator, is_snow: bool) -> Obstacle:
	var o := Obstacle.new()
	o.kind = k
	o.snow = is_snow
	o.rng_seed = rng.randi()
	match k:
		"pole":
			o.rect = Rect2(x - 11, W.SIDEWALK_TOP + 8, 22, 22)
			o.height = TALL
		"trash":
			o.rect = Rect2(x - 18, rng.randf_range(W.WALK_TOP + 20, W.WALK_BOTTOM - 30), 36, 26)
			o.height = 16.0
		"bike":
			o.rect = Rect2(x - 32, rng.randf_range(W.WALK_TOP + 30, W.WALK_BOTTOM - 20), 64, 18)
			o.height = 30.0
		"flowerbed":
			var l := rng.randf_range(180.0, 320.0)
			o.rect = Rect2(x, W.SIDEWALK_BOTTOM - 72, l, 72)
			o.height = 16.0
		"construction":
			var l := rng.randf_range(220.0, 340.0)
			var h := 92.0
			var top := W.SIDEWALK_TOP + 2 if rng.randf() < 0.5 else W.SIDEWALK_BOTTOM - h
			o.rect = Rect2(x, top, l, h)
			o.height = TALL
		"shelter":
			o.rect = Rect2(x, W.SIDEWALK_BOTTOM - 46, 124, 42)
			o.height = TALL
		"sign":
			o.rect = Rect2(x - 8, W.SIDEWALK_TOP + 8, 16, 16)
			o.height = TALL
	o.position = Vector2(o.rect.get_center().x, o.rect.end.y)
	return o


## 막히면 발 위치를 rect 밖으로 밀어낸 위치를, 아니면 그대로 돌려준다
func push_out(foot: Vector2, radius: float, vis_z: float) -> Vector2:
	if vis_z > height:
		return foot
	var closest := Vector2(clampf(foot.x, rect.position.x, rect.end.x), clampf(foot.y, rect.position.y, rect.end.y))
	var d := foot - closest
	if d.length_squared() > 0.0001:
		if d.length() >= radius:
			return foot
		return closest + d.normalized() * radius
	# 발이 rect 안에 있다 → 가장 가까운 변으로
	var left := foot.x - rect.position.x
	var right := rect.end.x - foot.x
	var up := foot.y - rect.position.y
	var down := rect.end.y - foot.y
	var m := minf(minf(left, right), minf(up, down))
	if m == left:
		return Vector2(rect.position.x - radius, foot.y)
	if m == right:
		return Vector2(rect.end.x + radius, foot.y)
	if m == up:
		return Vector2(foot.x, rect.position.y - radius)
	return Vector2(foot.x, rect.end.y + radius)


func _draw() -> void:
	var r := Rect2(rect.position - position, rect.size) # 로컬 좌표
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	match kind:
		"pole":
			draw_circle(r.get_center() + Vector2(3, 4), 12, Color(0.2, 0.15, 0.1, 0.18), true, -1.0, true)
			draw_circle(r.get_center(), 11, Color("bdb5aa"), true, -1.0, true)
			draw_circle(r.get_center(), 7, Color("d3ccc2"), true, -1.0, true)
			draw_line(r.get_center() + Vector2(-16, -2), r.get_center() + Vector2(16, -2), Color("8a8178"), 3.0, true)
		"trash":
			var cols := [Color("93a8b6"), Color("a7bac6"), Color("e8e2d4")]
			for i in 3:
				var c := r.position + Vector2(9 + i * 9, 13 + (i % 2) * 2)
				draw_colored_polygon(W.ellipse(c, 11, 10, 18), cols[i])
				draw_circle(c + Vector2(0, -9), 2.5, cols[i].darkened(0.2))
			if snow:
				draw_colored_polygon(W.ellipse(r.get_center() + Vector2(0, -6), 16, 5, 16), Color("f7fafc"))
		"bike":
			var c := r.get_center()
			for wx in [-22.0, 22.0]:
				draw_colored_polygon(W.ellipse(c + Vector2(wx, 0), 11, 4, 16), Color("4a4248"))
			draw_line(c + Vector2(-20, 0), c + Vector2(18, 0), Color("6f9fd8"), 4.0, true)
			draw_line(c + Vector2(18, -9), c + Vector2(18, 9), Color("4a4248"), 3.0, true)
			W.rrect(self, Rect2(c + Vector2(-12, -4), Vector2(12, 8)), Color("5b4b42"), 3)
		"flowerbed":
			W.rrect(self, r, Color("c98d6c"), 6)
			W.rrect(self, r.grow(-6), Color("8a6a4c") if not snow else Color("eef3f5"), 4)
			if not snow:
				var cols := [Color("f2b8c6"), Color("f4d35e"), Color("f6f0e0"), Color("e98a6d")]
				for i in int(r.size.x / 18.0):
					var p := r.position + Vector2(10 + i * 18 + rng.randf_range(-4, 4), rng.randf_range(16, r.size.y - 14))
					draw_circle(p, 7, Color("7fae62"), true, -1.0, true)
					draw_circle(p + Vector2(0, -2), 3.5, cols[i % cols.size()], true, -1.0, true)
		"construction":
			W.rrect(self, r, Color("d9c39a"), 6)
			W.rrect(self, r.grow(-14), Color("b99d73"), 4)
			# 줄무늬 가림막
			var n := int(r.size.x / 24.0)
			for i in n:
				var col := Color("f08a3c") if i % 2 == 0 else Color("fbf3e4")
				draw_rect(Rect2(r.position.x + i * 24, r.position.y, 24, 8), col)
				draw_rect(Rect2(r.position.x + i * 24, r.end.y - 8, 24, 8), col)
			for p in [r.position + Vector2(10, 10), Vector2(r.end.x - 10, r.position.y + 10), Vector2(r.position.x + 10, r.end.y - 10), r.end - Vector2(10, 10)]:
				draw_circle(p, 8, Color("f08a3c"), true, -1.0, true)
				draw_circle(p, 3, Color("fbf3e4"), true, -1.0, true)
		"shelter":
			W.rrect(self, r, Color(0.55, 0.75, 0.85, 0.55), 6, Color("7fa6b8"), 2)
			W.rrect(self, Rect2(r.position + Vector2(10, r.size.y - 14), Vector2(r.size.x - 20, 8)), Color("b98a5e"), 3)
			if snow:
				W.rrect(self, Rect2(r.position, Vector2(r.size.x, 10)), Color("f7fafc"), 5)
		"sign":
			var c := r.get_center()
			draw_circle(c, 5, Color("8a8178"), true, -1.0, true)
			draw_circle(c + Vector2(0, -34), 15, Color("3f7fc0"), true, -1.0, true)
			draw_circle(c + Vector2(0, -34), 11, Color("f7fafc"), true, -1.0, true)
			draw_string(UI.font(true), c + Vector2(-11, -29), "버스", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("3f7fc0"))
