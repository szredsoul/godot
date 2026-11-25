class_name Player
extends Node2D
## 인도를 자유롭게 걷는 아이 (친구 NPC도 같은 클래스를 쓴다).
## 점프 높이는 가짜 z값으로 표현한다. position = 발 위치 (판정 기준점)

signal jumped
signal landed

const WALK := 200.0
const RUN := 320.0
const JUMP_V := 520.0
const G_HOLD := 1300.0 # 점프 키를 누르고 있으면 천천히 올라감 (최대 체공 약 0.77초)
const G_CUT := 3000.0  # 일찍 떼면 빨리 꺾임 (최소 체공 약 0.42초)
const G_FALL := 1500.0
const AIR_CONTROL := 2.5 # 공중에서는 방향을 천천히만 바꿀 수 있다
const Z_VIS := 0.45 # 화면에 보이는 높이 비율

var z := 0.0
var vz := 0.0
var vel := Vector2.ZERO
var facing := 1.0
var walk_t := 0.0
var moving := false
var running := false
var dead := false
var max_x := INF
var stepped := false # 이번 프레임에 발을 디뎠는지 (발소리·발자국)
var sink := 0.0 # 상상 속 용암/바다에 빠진 정도 (0~1, 밟았을 때 연출)
var sink_color := Color("2d6ea6")
var heat := 0.0 # 거꾸로 놀이: 햇빛을 받아 더워진 정도 (0~1)

var hat_color := Color("f4c542")
var hat_style := "cap"
var bag_color := Color("e0654f")
var shirt_color := Color("7cb7d6")
var pants_color := Color("5b6c8f")

const C_SKIN := Color("fbd8b4")
const C_DARK := Color("4a3a32")


func _ready() -> void:
	scale = Vector2(1.2, 1.2)


func apply_equipped() -> void:
	var h: Dictionary = GameData.HATS[GameData.hat_id()]
	hat_color = h["color"]
	hat_style = h["style"]
	bag_color = GameData.BAGS[GameData.bag_id()]["color"]
	queue_redraw()


func is_airborne() -> bool:
	return z > 0.0


func vis_z() -> float:
	return z * Z_VIS


func step(delta: float, dir: Vector2, jump_pressed: bool, jump_held: bool, run: bool) -> void:
	stepped = false
	running = run and dir.length() > 0.1
	var target := dir * (RUN if run else WALK)
	if z <= 0.0:
		vel = target
	else:
		vel = vel.lerp(target, 1.0 - exp(-AIR_CONTROL * delta))
	moving = vel.length() > 10.0
	position += vel * delta
	position.x = clampf(position.x, 30.0, max_x)
	position.y = clampf(position.y, W.WALK_TOP, W.WALK_BOTTOM)
	if absf(vel.x) > 10.0:
		facing = signf(vel.x)
	if moving and z <= 0.0:
		var before := floorf(walk_t / PI)
		walk_t += delta * (16.0 if running else 12.0)
		stepped = floorf(walk_t / PI) != before

	if jump_pressed and z <= 0.0:
		vz = JUMP_V
		z = 0.01
		jumped.emit()
	if z > 0.0:
		var g := G_FALL
		if vz > 0.0:
			g = G_HOLD if jump_held else G_CUT
		vz -= g * delta
		z += vz * delta
		if z <= 0.0:
			z = 0.0
			vz = 0.0
			landed.emit()
	queue_redraw()


func _draw() -> void:
	# 발밑 그림자 (높이 뜰수록 작아짐)
	var s := clampf(1.0 - z / 220.0, 0.5, 1.0)
	draw_colored_polygon(W.ellipse(Vector2.ZERO, 15.0 * s, 6.0 * s), Color(0.25, 0.15, 0.3, 0.35))

	if dead:
		draw_set_transform(Vector2(0, -6), 0.0, Vector2(1.3, 0.55))
	var on_ground := z <= 0.0
	var bob := absf(sin(walk_t)) * 2.5 if moving and on_ground else 0.0
	var o := Vector2(0, -vis_z() - bob + sink * 22.0)
	if sink > 0.0:
		# 빠진 자리 물결
		draw_colored_polygon(W.ellipse(Vector2.ZERO, 20.0, 7.0), Color(sink_color, 0.9 * sink))
		draw_arc(Vector2.ZERO, 22.0 * (1.2 - sink * 0.4), PI * 1.05, PI * 1.95, 12, Color(1, 1, 1, 0.7 * sink), 2.0, true)
	var swing := sin(walk_t) * (6.0 if running else 4.0) if moving and on_ground else 0.0
	if not on_ground:
		swing = 3.0

	W.rrect(self, Rect2(o.x - 8 + swing, o.y - 13, 6, 13), pants_color, 3)
	W.rrect(self, Rect2(o.x + 2 - swing, o.y - 13, 6, 13), pants_color, 3)
	W.rrect(self, Rect2(o.x - facing * 11 - 6, o.y - 30, 12, 17), bag_color, 4)
	W.rrect(self, Rect2(o.x - 11, o.y - 31, 22, 20), shirt_color, 8)
	var head := o + Vector2(0, -42)
	draw_circle(head, 12, C_SKIN, true, -1.0, true)
	draw_circle(head + Vector2(facing * 6, 4), 3, Color(0.95, 0.55, 0.5, 0.45))
	if dead:
		for ex in [facing * 1.5, facing * 7.0]:
			draw_line(head + Vector2(ex - 2, -2), head + Vector2(ex + 2, 2), C_DARK, 1.5)
			draw_line(head + Vector2(ex - 2, 2), head + Vector2(ex + 2, -2), C_DARK, 1.5)
	else:
		draw_circle(head + Vector2(facing * 1.5, 0), 1.8, C_DARK)
		draw_circle(head + Vector2(facing * 7.0, 0), 1.8, C_DARK)
	_draw_hat(head)
	if heat > 0.05:
		# 더위: 땀방울과 김
		var a := clampf(heat, 0.0, 1.0)
		draw_circle(head + Vector2(-facing * 13, -2 + sin(walk_t) * 2.0), 2.5, Color(0.55, 0.8, 1.0, a), true, -1.0, true)
		if heat > 0.5:
			for i in 3:
				var sx := (i - 1) * 7.0
				draw_arc(head + Vector2(sx, -24 - fmod(Time.get_ticks_msec() * 0.03 + i * 6.0, 14.0)), 3.0, 0.0, PI, 6, Color(1, 1, 1, a * 0.7), 1.5, true)
	if sink > 0.0:
		# 물/용암 표면 아래는 가린다 (몸이 잠긴 것처럼)
		draw_colored_polygon(W.ellipse(Vector2(0, 2), 18.0, 6.0 + sink * 10.0), Color(sink_color, sink))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _dome(head: Vector2, r: float, dy: float) -> PackedVector2Array:
	var dome := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		dome.append(head + Vector2(cos(a) * r, sin(a) * r + dy))
	return dome


func _draw_hat(head: Vector2) -> void:
	match hat_style:
		"straw":
			draw_colored_polygon(W.ellipse(head + Vector2(0, -4), 19, 5, 24), hat_color.darkened(0.08))
			draw_colored_polygon(_dome(head, 11.0, -5), hat_color)
			draw_rect(Rect2(head.x - 10, head.y - 7, 20, 3), Color("e0654f"))
		"beanie":
			draw_colored_polygon(_dome(head, 13.0, -2), hat_color)
			W.rrect(self, Rect2(head.x - 13, head.y - 5, 26, 6), hat_color.darkened(0.15), 3)
			draw_circle(head + Vector2(0, -16), 4.5, Color("fff3f6"), true, -1.0, true)
		_: # cap
			draw_colored_polygon(_dome(head, 12.5, -3), hat_color)
			draw_colored_polygon(W.ellipse(head + Vector2(facing * 9, -3), 9, 3, 16), hat_color.darkened(0.08))
