class_name Crossing
extends Node2D
## 신호등 교차로. 인도를 가로지르는 골목(횡단보도)과 큰길 신호를 함께 관리한다.
##  0 큰길 초록: 큰길 차 진행, 골목 차 정지, 횡단보도 초록 (건너기 안전)
##  1 큰길 노랑: 큰길 차 정지 시작
##  2 큰길 빨강: 큰길 차가 줄지어 멈춤(그림자 고정), 골목 차가 세로로 횡단보도를 지나감

const WIDTH := 170.0
const DURATION: Array[float] = [6.5, 1.6, 7.5]

var x0 := 0.0
var phase := 0
var t := 0.0
var snow := false
var signals: Node2D


func setup(x: float, start_phase: int, is_snow: bool) -> void:
	x0 = x
	phase = start_phase
	snow = is_snow
	position = Vector2.ZERO
	z_index = -19 # 땅 바로 위 (골목 도로, 횡단보도)
	signals = Node2D.new()
	signals.position = Vector2(0, W.SIDEWALK_TOP + 12)
	signals.z_index = 19 + int((W.SIDEWALK_TOP + 12) / 8.0) # 땅 기준 z를 되돌리고 앞뒤 정렬
	signals.draw.connect(_draw_signals)
	add_child(signals)


## 단계가 바뀌면 true
func step(delta: float) -> bool:
	t += delta
	if t >= DURATION[phase]:
		t = 0.0
		phase = (phase + 1) % 3
		signals.queue_redraw()
		return true
	return false


func main_go() -> bool:
	return phase == 0


func side_go() -> bool:
	return phase == 2 and t > 1.0 # 모두 빨간불인 짧은 시간 뒤 출발


func ped_green() -> bool:
	return phase == 0


## 큰길 차선의 정지선 (차 앞부분이 넘지 않을 위치)
func main_stop_line(lane: int) -> float:
	return x0 - 16.0 if lane == 1 else x0 + WIDTH + 16.0


func side_x(up: bool) -> float:
	return x0 + WIDTH * (0.7 if up else 0.3)


func side_stop_line(up: bool) -> float:
	return W.SIDEWALK_BOTTOM + 30.0 if up else W.ROAD_TOP - 16.0


func contains_x(x: float, margin := 0.0) -> bool:
	return x > x0 - margin and x < x0 + WIDTH + margin


func _draw() -> void:
	var road := Color("7d7570")
	var line := Color("efe3c6")
	# 골목 도로 (큰길 위아래로)
	draw_rect(Rect2(x0, -400, WIDTH, W.ROAD_TOP + 400), road)
	draw_rect(Rect2(x0, W.ROAD_BOTTOM, WIDTH, 900), road)
	# 모서리 연석
	draw_rect(Rect2(x0 - 6, W.SIDEWALK_BOTTOM, 6, 600), Color("d8c8aa"))
	draw_rect(Rect2(x0 + WIDTH, W.SIDEWALK_BOTTOM, 6, 600), Color("d8c8aa"))
	draw_rect(Rect2(x0 - 6, -400, 6, W.ROAD_TOP + 400), Color("d8c8aa"))
	draw_rect(Rect2(x0 + WIDTH, -400, 6, W.ROAD_TOP + 400), Color("d8c8aa"))
	# 골목 중앙선
	var cx := x0 + WIDTH * 0.5
	var y := W.SIDEWALK_BOTTOM + 60.0
	while y < 760.0:
		draw_rect(Rect2(cx - 2, y, 4, 30), Color("f2cf6b"))
		y += 60.0
	# 횡단보도 (차가 세로로 다니니 줄무늬도 세로)
	var x := x0 + 10.0
	while x < x0 + WIDTH - 12.0:
		draw_rect(Rect2(x, W.SIDEWALK_TOP + 10, 14, W.SIDEWALK_BOTTOM - W.SIDEWALK_TOP - 20), Color(1, 1, 1, 0.85))
		x += 28.0
	# 정지선
	draw_rect(Rect2(x0 + WIDTH * 0.5, W.SIDEWALK_BOTTOM + 28, WIDTH * 0.5, 5), line)
	draw_rect(Rect2(x0, W.ROAD_TOP - 18, WIDTH * 0.5, 5), line)
	draw_rect(Rect2(x0 - 21, (W.ROAD_TOP + W.ROAD_BOTTOM) * 0.5 + 4, 5, (W.ROAD_BOTTOM - W.ROAD_TOP) * 0.5 - 16), line)
	draw_rect(Rect2(x0 + WIDTH + 16, W.ROAD_TOP + 12, 5, (W.ROAD_BOTTOM - W.ROAD_TOP) * 0.5 - 16), line)


func _draw_signals() -> void:
	var s := signals
	# 큰길 차량 신호등 (교차로 왼쪽 연석)
	var p := Vector2(x0 - 34, 0)
	s.draw_circle(p, 5, Color("6f6862"), true, -1.0, true)
	s.draw_line(p, p + Vector2(0, -40), Color("6f6862"), 4.0, true)
	var box := Rect2(p + Vector2(-30, -58), Vector2(60, 22))
	W.rrect(s, box, Color("3b3836"), 6)
	var lamp: Array[Color] = [Color("3f8f4f"), Color("caa23a"), Color("a8473c")]
	var on: Array[Color] = [Color("5fd17a"), Color("ffd35a"), Color("ff6a5a")]
	for i in 3:
		var lit := (phase == 0 and i == 0) or (phase == 1 and i == 1) or (phase == 2 and i == 2)
		s.draw_circle(box.position + Vector2(11 + i * 19, 11), 7, on[i] if lit else lamp[i].darkened(0.5), true, -1.0, true)
	if snow:
		W.rrect(s, Rect2(box.position + Vector2(0, -4), Vector2(60, 7)), Color("f7fafc"), 3)
	# 보행자 신호등 (횡단보도 건너편)
	var q := Vector2(x0 + WIDTH + 28, 0)
	s.draw_circle(q, 5, Color("6f6862"), true, -1.0, true)
	s.draw_line(q, q + Vector2(0, -40), Color("6f6862"), 4.0, true)
	var pbox := Rect2(q + Vector2(-16, -76), Vector2(32, 40))
	W.rrect(s, pbox, Color("3b3836"), 6)
	var green := ped_green()
	var col := Color("5fd17a") if green else Color("ff6a5a")
	var c := pbox.get_center()
	s.draw_circle(c + Vector2(0, -10), 4, col, true, -1.0, true)
	if green:
		s.draw_line(c + Vector2(0, -5), c + Vector2(-5, 12), col, 3.0, true)
		s.draw_line(c + Vector2(0, -5), c + Vector2(5, 12), col, 3.0, true)
		s.draw_line(c + Vector2(0, -3), c + Vector2(7, 2), col, 3.0, true)
	else:
		s.draw_line(c + Vector2(0, -5), c + Vector2(0, 12), col, 4.0, true)
		s.draw_line(c + Vector2(-3, 12), c + Vector2(3, 12), col, 3.0, true)
