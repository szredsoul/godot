class_name Ground
extends Node2D
## 배경 (건너편 풀밭, 차도, 연석, 인도 타일, 담장, 집 지붕). 카메라 주변만 그린다.

const C_GRASS := Color("b7cf8e")
const C_HEDGE := Color("93b874")
const C_ROAD := Color("7d7570")
const C_ROAD_LINE := Color("efe3c6")
const C_DASH := Color("f2cf6b")
const C_CURB := Color("d8c8aa")
const C_WALK_A := Color("efdfbf")
const C_WALK_B := Color("ead7b2")
const C_WALK_LINE := Color("dcc59c")
const C_WALL := Color("e9cfa8")
const C_WALL_CAP := Color("f6e6c8")
const C_YARD := Color("aac884")
const C_BUSH := Color("86ad68")
const FLOWERS: Array[Color] = [Color("f6f0e0"), Color("f2b8c6"), Color("f4d35e"), Color("e98a6d")]
const ROOFS: Array[Color] = [Color("d9785b"), Color("8fa9b8"), Color("e0a85a"), Color("b9806a"), Color("9bb38a")]

var cam_x := 640.0


func _hash(i: int) -> int:
	return absi(hash(i * 92821 + 17))


func _draw() -> void:
	var x0 := floorf((cam_x - 1100.0) / 64.0) * 64.0
	var x1 := cam_x + 1100.0
	var w := x1 - x0

	# 건너편 풀밭 + 산울타리 + 꽃
	draw_rect(Rect2(x0, -300, w, W.ROAD_TOP + 300), C_GRASS)
	for i in range(int(x0 / 70.0) - 1, int(x1 / 70.0) + 1):
		draw_circle(Vector2(i * 70.0 + 35.0, 8.0 + float(_hash(i) % 10)), 36, C_HEDGE)
	for i in range(int(x0 / 40.0), int(x1 / 40.0) + 1):
		var h := _hash(i + 500)
		if h % 3 == 0:
			var p := Vector2(i * 40.0 + float(h % 30), 50.0 + float((h / 7) % 40))
			draw_circle(p, 3.5, FLOWERS[(h / 13) % FLOWERS.size()])

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

	# 마당, 담장
	draw_rect(Rect2(x0, W.SIDEWALK_BOTTOM, w, 500), C_YARD)
	draw_rect(Rect2(x0, W.SIDEWALK_BOTTOM, w, 30), C_WALL)
	draw_rect(Rect2(x0, W.SIDEWALK_BOTTOM, w, 7), C_WALL_CAP)
	for i in range(int(x0 / 192.0), int(x1 / 192.0) + 1):
		W.rrect(self, Rect2(i * 192.0, W.SIDEWALK_BOTTOM - 2, 16, 34), C_WALL_CAP, 3)

	# 집 지붕 (위에서 본 모습)
	for b in range(int(floorf(x0 / 320.0)) - 1, int(x1 / 320.0) + 1):
		var h := _hash(b + 1000)
		var bx := b * 320.0
		var hx := bx + 40.0 + float(h % 40)
		var hw := 190.0 + float((h / 41) % 60)
		var roof: Color = ROOFS[h % ROOFS.size()]
		var top := W.SIDEWALK_BOTTOM + 62.0
		W.rrect(self, Rect2(hx + 8, top + 10, hw, 260), Color(0.2, 0.15, 0.1, 0.12), 10)
		W.rrect(self, Rect2(hx, top, hw, 66), roof.lightened(0.14), 8)
		W.rrect(self, Rect2(hx, top + 66, hw, 200), roof, 8)
		draw_rect(Rect2(hx, top + 63, hw, 5), roof.darkened(0.22))
		W.rrect(self, Rect2(hx + hw * 0.7, top + 16, 22, 26), Color("c9b79a"), 4)
		# 덤불
		for k in 2:
			draw_circle(Vector2(bx + 14.0 + k * 280.0 + float(h % 20), W.SIDEWALK_BOTTOM + 50), 18, C_BUSH)
