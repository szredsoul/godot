class_name Ground
extends Node2D
## 배경 (건너편 풀밭, 차도, 연석, 인도 타일, 담장, 집 지붕, 학교, 우리 집). 카메라 주변만 그린다.

const C_ROAD := Color("7d7570")
const C_ROAD_LINE := Color("efe3c6")
const C_DASH := Color("f2cf6b")
const C_CURB := Color("d8c8aa")
const C_WALK_A := Color("efdfbf")
const C_WALK_B := Color("ead7b2")
const C_WALK_LINE := Color("dcc59c")
const C_WALL := Color("e9cfa8")
const C_WALL_CAP := Color("f6e6c8")
const FLOWERS: Array[Color] = [Color("f6f0e0"), Color("f2b8c6"), Color("f4d35e"), Color("e98a6d")]
const ROOFS: Array[Color] = [Color("d9785b"), Color("8fa9b8"), Color("e0a85a"), Color("b9806a"), Color("9bb38a")]
const SCHOOL_X := 0.0
const SCHOOL_W := 420.0
const HOME_W := 260.0

var cam_x := 640.0
var season: Dictionary = GameData.SEASONS["spring"]
var crossings: Array[float] = [] # 교차로 시작 x (집을 그리지 않는다)
var home_x := INF # 집 대문 x (마지막 장만)
var show_school := true
var district := "home" # 길가 풍경: school / shops / construction / market / park / home
var start_title := "" # 장 시작 표지판 (1장은 학교가 있어서 비움)
var next_x := INF # 다음 장소 표지판 x
var next_title := ""

const AWNINGS: Array[Color] = [Color("e0654f"), Color("6f9fd8"), Color("7fb36a"), Color("f2b84b"), Color("d98ca8")]
const SHOP_NAMES: Array[String] = ["문방구", "분식", "슈퍼", "꽃집", "문구사", "빵집", "장난감"]
const MARKET_NAMES: Array[String] = ["과일", "채소", "생선", "떡", "반찬", "튀김"]


func _hash(i: int) -> int:
	return absi(hash(i * 92821 + 17))


func _near_crossing(x0: float, x1: float) -> bool:
	for c in crossings:
		if x1 > c - 20.0 and x0 < c + Crossing.WIDTH + 20.0:
			return true
	return false


func _draw() -> void:
	var x0 := floorf((cam_x - 1100.0) / 64.0) * 64.0
	var x1 := cam_x + 1100.0
	var w := x1 - x0
	var snow: bool = season["snow"]
	var grass: Color = season["grass"]

	# 건너편 풀밭 + 산울타리 + 꽃
	draw_rect(Rect2(x0, -300, w, W.ROAD_TOP + 300), grass)
	for i in range(int(x0 / 70.0) - 1, int(x1 / 70.0) + 1):
		draw_circle(Vector2(i * 70.0 + 35.0, 8.0 + float(_hash(i) % 10)), 36, season["hedge"], true, -1.0, true)
	if not snow:
		for i in range(int(x0 / 40.0), int(x1 / 40.0) + 1):
			var h := _hash(i + 500)
			if h % 3 == 0:
				var p := Vector2(i * 40.0 + float(h % 30), 50.0 + float((h / 7) % 40))
				draw_circle(p, 3.5, FLOWERS[(h / 13) % FLOWERS.size()], true, -1.0, true)

	# 차도
	draw_rect(Rect2(x0, W.ROAD_TOP, w, W.ROAD_BOTTOM - W.ROAD_TOP), C_ROAD)
	draw_rect(Rect2(x0, W.ROAD_TOP + 8, w, 4), C_ROAD_LINE)
	draw_rect(Rect2(x0, W.ROAD_BOTTOM - 12, w, 4), C_ROAD_LINE)
	var mid := (W.ROAD_TOP + W.ROAD_BOTTOM) * 0.5
	for i in range(int(x0 / 120.0), int(x1 / 120.0) + 1):
		W.rrect(self, Rect2(i * 120.0, mid - 3, 64, 6), C_DASH, 3)

	# 연석
	draw_rect(Rect2(x0, W.ROAD_BOTTOM, w, W.SIDEWALK_TOP - W.ROAD_BOTTOM), C_CURB)
	for i in range(int(x0 / 96.0), int(x1 / 96.0) + 1):
		draw_rect(Rect2(i * 96.0, W.ROAD_BOTTOM, 2, W.SIDEWALK_TOP - W.ROAD_BOTTOM), C_WALK_LINE)

	# 인도 타일 (체크무늬)
	var rows := int((W.SIDEWALK_BOTTOM - W.SIDEWALK_TOP) / 64.0)
	for i in range(int(x0 / 64.0), int(x1 / 64.0) + 1):
		for j in rows:
			var col := C_WALK_A if (i + j) % 2 == 0 else C_WALK_B
			draw_rect(Rect2(i * 64.0, W.SIDEWALK_TOP + j * 64.0, 64, 64), col)
		draw_rect(Rect2(i * 64.0, W.SIDEWALK_TOP, 2, W.SIDEWALK_BOTTOM - W.SIDEWALK_TOP), C_WALK_LINE)
	for j in rows + 1:
		draw_rect(Rect2(x0, W.SIDEWALK_TOP + j * 64.0, w, 2), C_WALK_LINE)
	if snow:
		# 가장자리에 쌓인 눈
		for i in range(int(x0 / 50.0), int(x1 / 50.0) + 1):
			var h := _hash(i + 900)
			draw_circle(Vector2(i * 50.0, W.SIDEWALK_BOTTOM - 4), 16.0 + float(h % 10), Color("f4f8fa"), true, -1.0, true)
			if h % 2 == 0:
				draw_circle(Vector2(i * 50.0 + 20.0, W.SIDEWALK_TOP + 6), 10.0 + float(h % 6), Color("f4f8fa"), true, -1.0, true)

	# 마당, 담장
	draw_rect(Rect2(x0, W.SIDEWALK_BOTTOM, w, 500), season["yard"])
	draw_rect(Rect2(x0, W.SIDEWALK_BOTTOM, w, 30), C_WALL)
	draw_rect(Rect2(x0, W.SIDEWALK_BOTTOM, w, 7), Color("f7fafc") if snow else C_WALL_CAP)
	for i in range(int(x0 / 192.0), int(x1 / 192.0) + 1):
		W.rrect(self, Rect2(i * 192.0, W.SIDEWALK_BOTTOM - 2, 16, 34), C_WALL_CAP, 3)

	# 집 지붕 (위에서 본 모습)
	for b in range(int(floorf(x0 / 320.0)) - 1, int(x1 / 320.0) + 1):
		var bx := b * 320.0
		if _near_crossing(bx, bx + 320.0):
			continue
		if show_school and bx < SCHOOL_X + SCHOOL_W:
			continue
		if bx + 320.0 > home_x - 40.0 and bx < home_x + HOME_W + 40.0:
			continue
		if bx + 320.0 > next_x - 60.0 and bx < next_x + 260.0:
			continue
		var h := _hash(b + 1000)
		match district:
			"shops":
				_draw_shop(bx, h, snow)
			"construction":
				_draw_construction(bx, h, snow)
			"market":
				_draw_market(bx, h, snow)
			"park":
				_draw_park(bx, h, snow)
			_:
				var hx := bx + 40.0 + float(h % 40)
				var hw := 190.0 + float((h / 41) % 60)
				_roof(Rect2(hx, W.SIDEWALK_BOTTOM + 62.0, hw, 200), ROOFS[h % ROOFS.size()], snow)
				for k in 2:
					draw_circle(Vector2(bx + 14.0 + k * 280.0 + float(h % 20), W.SIDEWALK_BOTTOM + 50), 18, season["bush"], true, -1.0, true)

	if show_school and x0 < SCHOOL_X + SCHOOL_W + 100.0:
		_draw_school(snow)
	if x1 > home_x - 100.0 and x0 < home_x + HOME_W + 100.0:
		_draw_home(snow)
	if start_title != "" and x0 < 700.0:
		_signpost(Vector2(120.0, W.SIDEWALK_BOTTOM + 64.0), start_title, Color("6f9fd8"))
	if next_title != "" and x1 > next_x - 100.0 and x0 < next_x + 400.0:
		_signpost(Vector2(next_x - 10.0, W.SIDEWALK_BOTTOM + 64.0), next_title + "  →", UI.C_ACCENT)


func _signpost(p: Vector2, text: String, col: Color) -> void:
	var tw := UI.font(true).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	W.rrect(self, Rect2(p + Vector2(tw * 0.5 + 6, 30), Vector2(8, 60)), Color("9c7f68"), 3)
	W.rrect(self, Rect2(p, Vector2(tw + 32, 34)), Color("fffaf0"), 8, col, 3)
	draw_string(UI.font(true), p + Vector2(16, 25), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col.darkened(0.2))


## 문방구 거리: 줄무늬 차양을 단 가게들
func _draw_shop(bx: float, h: int, snow: bool) -> void:
	var top := W.SIDEWALK_BOTTOM + 34.0
	var col := AWNINGS[h % AWNINGS.size()]
	var w := 280.0
	var x := bx + 20.0
	W.rrect(self, Rect2(x + 6, top + 50, w, 240), Color(0.2, 0.15, 0.1, 0.12), 8)
	W.rrect(self, Rect2(x, top + 44, w, 240), Color("f4f8fa") if snow else Color("efe2c8"), 8)
	# 차양 줄무늬
	for i in 10:
		draw_rect(Rect2(x + i * w / 10.0, top + 30, w / 10.0, 26), col if i % 2 == 0 else Color("fffaf0"))
	for i in 10:
		draw_circle(Vector2(x + (i + 0.5) * w / 10.0, top + 56), w / 20.0, col if i % 2 == 0 else Color("fffaf0"), true, -1.0, true)
	if snow:
		W.rrect(self, Rect2(x, top + 26, w, 8), Color("f7fafc"), 4)
	var shop_name := SHOP_NAMES[(h / 7) % SHOP_NAMES.size()]
	W.rrect(self, Rect2(x + w * 0.5 - 50, top + 72, 100, 30), Color("fffaf0"), 6, col, 2)
	draw_string(UI.font(true), Vector2(x + w * 0.5 - 50, top + 94), shop_name, HORIZONTAL_ALIGNMENT_CENTER, 100, 18, col.darkened(0.25))
	# 가게 앞 뽑기 기계·화분
	W.rrect(self, Rect2(x + 18, top + 64, 26, 34), Color("e85a4f"), 6)
	draw_circle(Vector2(x + 31, top + 74), 9, Color("bcd9e6"), true, -1.0, true)
	draw_circle(Vector2(x + w - 26, top + 80), 14, season["bush"], true, -1.0, true)


## 공사장: 가림막, 고깔, 모래 더미, 굴착기 팔
func _draw_construction(bx: float, h: int, snow: bool) -> void:
	var top := W.SIDEWALK_BOTTOM + 36.0
	draw_rect(Rect2(bx, top + 30, 320, 400), Color("d9c39a") if not snow else Color("e9eef0"))
	# 모래 더미
	draw_colored_polygon(W.ellipse(Vector2(bx + 110 + float(h % 60), top + 140), 70, 34, 20), Color("c9a774") if not snow else Color("f4f8fa"))
	# 굴착기 (위에서 본 모습)
	if h % 2 == 0:
		var e := Vector2(bx + 230, top + 120)
		W.rrect(self, Rect2(e - Vector2(34, 22), Vector2(68, 44)), Color("f2b84b"), 8, Color("c98d2c"), 2)
		draw_line(e, e + Vector2(-70, -40), Color("e09a1f"), 10.0, true)
		draw_line(e + Vector2(-70, -40), e + Vector2(-100, -10), Color("e09a1f"), 8.0, true)
	# 가림막 (흰·파랑 판)
	for i in 8:
		var col := Color("f7fafc") if i % 2 == 0 else Color("8eb4d8")
		draw_rect(Rect2(bx + i * 40.0, top, 40, 32), col)
	if h % 3 == 0:
		W.rrect(self, Rect2(bx + 110, top + 4, 100, 24), Color("f08a3c"), 4)
		draw_string(UI.font(true), Vector2(bx + 110, top + 22), "공사 중", HORIZONTAL_ALIGNMENT_CENTER, 100, 16, Color("fffaf0"))
	# 고깔
	for k in 3:
		var c := Vector2(bx + 40 + k * 110 + float(h % 30), top + 46)
		draw_circle(c, 9, Color("f08a3c"), true, -1.0, true)
		draw_circle(c, 3.5, Color("fffaf0"), true, -1.0, true)


## 시장길: 파라솔 노점과 물건 상자
func _draw_market(bx: float, h: int, snow: bool) -> void:
	var top := W.SIDEWALK_BOTTOM + 40.0
	for k in 2:
		var sx := bx + 30.0 + k * 150.0
		var col := AWNINGS[(h / (k + 1)) % AWNINGS.size()]
		# 물건 상자
		for j in 3:
			W.rrect(self, Rect2(sx + j * 34, top + 70, 30, 24), Color("c98d6c"), 4)
			var fruit: Color = [Color("e85a4f"), Color("f2c14e"), Color("7fb36a"), Color("f08a3c")][(h + j + k) % 4]
			for q in 3:
				draw_circle(Vector2(sx + j * 34 + 7 + q * 8, top + 80), 5, fruit, true, -1.0, true)
		# 파라솔 (위에서 보면 원)
		var pc := Vector2(sx + 52, top + 48)
		draw_circle(pc + Vector2(4, 6), 52, Color(0.2, 0.15, 0.1, 0.12), true, -1.0, true)
		for s in 8:
			var a0 := s * TAU / 8.0
			var pts := PackedVector2Array([pc, pc + Vector2.from_angle(a0) * 50, pc + Vector2.from_angle(a0 + TAU / 8.0) * 50])
			draw_colored_polygon(pts, col if s % 2 == 0 else Color("fffaf0"))
		if snow:
			draw_circle(pc, 30, Color(1, 1, 1, 0.7), true, -1.0, true)
		draw_string(UI.font(true), pc + Vector2(-40, 70), MARKET_NAMES[(h / 3 + k) % MARKET_NAMES.size()], HORIZONTAL_ALIGNMENT_CENTER, 80, 15, Color("6a4e3a"))


## 공원: 잔디, 산책로, 벤치, 둥근 나무
func _draw_park(bx: float, h: int, snow: bool) -> void:
	var top := W.SIDEWALK_BOTTOM + 30.0
	var lawn: Color = season["yard"]
	draw_rect(Rect2(bx, top, 320, 400), lawn.lightened(0.05))
	# 산책로
	draw_rect(Rect2(bx, top + 70, 320, 26), Color("e8d6b0") if not snow else Color("f4f8fa"))
	# 벤치
	W.rrect(self, Rect2(bx + 40 + float(h % 80), top + 46, 64, 16), Color("b98a5e"), 4)
	# 둥근 나무
	var cols: Array = season["canopy"]
	for k in 2:
		var c := Vector2(bx + 80 + k * 160 + float((h / (k + 3)) % 40), top + 150)
		draw_circle(c + Vector2(5, 7), 40, Color(0.2, 0.15, 0.1, 0.12), true, -1.0, true)
		if season["bare"]:
			draw_circle(c, 8, cols[0], true, -1.0, true)
			for a in 5:
				draw_line(c, c + Vector2.from_angle(a * TAU / 5.0) * 32, cols[0], 3.0, true)
		else:
			draw_circle(c, 38, cols[1], true, -1.0, true)
			draw_circle(c + Vector2(-10, -10), 20, cols[2], true, -1.0, true)
	# 꽃밭
	if not snow and h % 2 == 0:
		for q in 6:
			draw_circle(Vector2(bx + 200 + q * 12, top + 30 + (q % 2) * 8), 4, FLOWERS[q % FLOWERS.size()], true, -1.0, true)


func _roof(r: Rect2, roof: Color, snow: bool) -> void:
	W.rrect(self, Rect2(r.position + Vector2(8, 10), r.size), Color(0.2, 0.15, 0.1, 0.12), 10)
	W.rrect(self, Rect2(r.position, Vector2(r.size.x, 66)), Color("f4f8fa") if snow else roof.lightened(0.14), 8)
	W.rrect(self, Rect2(r.position + Vector2(0, 66), Vector2(r.size.x, r.size.y - 66)), roof.lerp(Color("f4f8fa"), 0.5) if snow else roof, 8)
	draw_rect(Rect2(r.position.x, r.position.y + 63, r.size.x, 5), roof.darkened(0.22))
	W.rrect(self, Rect2(r.position + Vector2(r.size.x * 0.7, 16), Vector2(22, 26)), Color("c9b79a"), 4)


func _gate(x: float, width: float, col: Color) -> void:
	# 담장을 비우고 대문을 연다
	draw_rect(Rect2(x, W.SIDEWALK_BOTTOM, width, 30), season["yard"].lerp(C_WALK_B, 0.5))
	W.rrect(self, Rect2(x - 10, W.SIDEWALK_BOTTOM - 4, 14, 38), col.darkened(0.2), 3)
	W.rrect(self, Rect2(x + width - 4, W.SIDEWALK_BOTTOM - 4, 14, 38), col.darkened(0.2), 3)
	W.rrect(self, Rect2(x + 4, W.SIDEWALK_BOTTOM + 18, width * 0.42, 8), col, 3)
	W.rrect(self, Rect2(x + width * 0.54, W.SIDEWALK_BOTTOM + 18, width * 0.42, 8), col, 3)


func _draw_school(snow: bool) -> void:
	var top := W.SIDEWALK_BOTTOM + 70.0
	W.rrect(self, Rect2(SCHOOL_X + 18, top + 10, SCHOOL_W - 20, 240), Color(0.2, 0.15, 0.1, 0.12), 10)
	W.rrect(self, Rect2(SCHOOL_X + 10, top, SCHOOL_W - 20, 240), Color("f4f8fa") if snow else Color("e8dcc0"), 10, Color("cdb991"), 3)
	for i in 6:
		W.rrect(self, Rect2(SCHOOL_X + 34 + i * 62, top + 22, 40, 26), Color("bcd9e6"), 4)
	_gate(SCHOOL_X + 150.0, 110.0, Color("6f9fd8"))
	var sign_pos := Vector2(SCHOOL_X + 120.0, W.SIDEWALK_BOTTOM + 64.0)
	W.rrect(self, Rect2(sign_pos, Vector2(170, 30)), Color("fffaf0"), 6, Color("6f9fd8"), 2)
	draw_string(UI.font(true), sign_pos + Vector2(14, 22), "햇살초등학교", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("3f6f9f"))


func _draw_home(snow: bool) -> void:
	var r := Rect2(home_x - 30.0, W.SIDEWALK_BOTTOM + 62.0, HOME_W, 200)
	_roof(r, Color("6f9fd8"), snow)
	_gate(home_x, 90.0, Color("e0654f"))
	var sign_pos := Vector2(home_x - 20.0, W.SIDEWALK_BOTTOM + 70.0)
	W.rrect(self, Rect2(sign_pos, Vector2(130, 32)), Color("fffaf0"), 8, Color("e0654f"), 3)
	draw_string(UI.font(true), sign_pos + Vector2(26, 24), "우리 집", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("c0503f"))
