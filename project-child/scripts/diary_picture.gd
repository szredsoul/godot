class_name DiaryPicture
extends Control
## 그림일기의 그림 칸. 도착 시각(하늘색, 해 위치), 계절, 엄마 표정이 달라진다.

var hour := 17.0
var season_key := "spring"
var late := false
var cleared := true


func _draw() -> void:
	var w := size.x
	var h := size.y
	var season: Dictionary = GameData.SEASONS[season_key]
	var k := clampf((hour - 15.0) / 3.5, 0.0, 1.0)
	var sky := Color("bfe0f0").lerp(Color("f4b183"), k)
	draw_rect(Rect2(0, 0, w, h * 0.62), sky)
	# 해
	var sun_pos := Vector2(lerpf(w * 0.2, w * 0.85, k), lerpf(h * 0.15, h * 0.5, k))
	draw_circle(sun_pos, 22, Color("ffd35a").lerp(Color("f08a3c"), k), true, -1.0, true)
	# 땅
	draw_rect(Rect2(0, h * 0.62, w, h * 0.38), season["grass"])
	draw_rect(Rect2(0, h * 0.62, w, 6), Color(season["grass"]).darkened(0.12))
	# 나무
	var tx := w * 0.16
	var ground_y := h * 0.62
	draw_rect(Rect2(tx - 5, ground_y - 50, 10, 54), Color("9c7f68"))
	if season["bare"]:
		for a in [-0.9, -0.4, 0.3, 0.8]:
			draw_line(Vector2(tx, ground_y - 40), Vector2(tx, ground_y - 40) + Vector2.from_angle(a - PI * 0.5) * 34, Color("9c7f68"), 3.0, true)
	else:
		var cols: Array = season["canopy"]
		draw_circle(Vector2(tx, ground_y - 70), 34, cols[1], true, -1.0, true)
		draw_circle(Vector2(tx - 10, ground_y - 80), 18, cols[2], true, -1.0, true)
	# 집
	var hx := w * 0.62
	var house := Rect2(hx, ground_y - 80, 110, 84)
	draw_rect(house, Color("fbf1dc"))
	draw_colored_polygon(PackedVector2Array([Vector2(hx - 14, ground_y - 78), Vector2(hx + 55, ground_y - 128), Vector2(hx + 124, ground_y - 78)]), Color("6f9fd8"))
	draw_rect(Rect2(hx + 66, ground_y - 46, 26, 50), Color("e0654f"))
	draw_rect(Rect2(hx + 14, ground_y - 62, 30, 24), Color("bcd9e6"))
	# 엄마 (문 앞)
	var m := Vector2(hx - 18, ground_y)
	draw_rect(Rect2(m.x - 9, m.y - 40, 18, 34), Color("d98ca8"))
	draw_circle(m + Vector2(0, -50), 10, Color("f6d2b0"), true, -1.0, true)
	draw_arc(m + Vector2(0, -52), 10.5, PI, TAU, 12, Color("4a3a32"), 5.0, true)
	if cleared:
		if late:
			draw_line(m + Vector2(-6, -55), m + Vector2(-2, -53), Color("4a3a32"), 1.5, true)
			draw_line(m + Vector2(6, -55), m + Vector2(2, -53), Color("4a3a32"), 1.5, true)
			draw_string(UI.font(true), m + Vector2(12, -62), "!!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("e0654f"))
		else:
			draw_arc(m + Vector2(0, -47), 4, 0.2, PI - 0.2, 8, Color("4a3a32"), 1.5, true)
			draw_line(m + Vector2(9, -36), m + Vector2(20, -56), Color("f6d2b0"), 4.0, true) # 손 흔들기
	# 아이
	var c := Vector2(w * 0.45 if cleared else w * 0.38, ground_y)
	var hat: Color = GameData.HATS[GameData.hat_id()]["color"]
	draw_rect(Rect2(c.x - 8, c.y - 30, 16, 24), Color("7cb7d6"))
	draw_rect(Rect2(c.x - 15, c.y - 28, 8, 14), GameData.BAGS[GameData.bag_id()]["color"])
	draw_circle(c + Vector2(0, -40), 10, Color("fbd8b4"), true, -1.0, true)
	draw_arc(c + Vector2(0, -42), 10.5, PI, TAU, 12, hat, 6.0, true)
	if not cleared:
		draw_string(UI.font(true), c + Vector2(12, -50), "흑흑", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("6f9fd8"))
	# 계절 장식
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 18:
		var p := Vector2(rng.randf() * w, rng.randf() * h * 0.6)
		match season["particle"]:
			"snow":
				draw_circle(p, 3, Color(1, 1, 1, 0.95), true, -1.0, true)
			"petal":
				draw_circle(p, 3, Color("f6c4d2"), true, -1.0, true)
			"leaf":
				draw_circle(p, 3, Color("eba54a"), true, -1.0, true)
	# 크레파스 테두리
	draw_rect(Rect2(2, 2, w - 4, h - 4), Color("8a6a4e"), false, 3.0)
