class_name Player
extends Node2D
## 인도를 자유롭게 걷는 아이. 점프 높이는 가짜 z값으로 표현한다.
## position = 발 위치 (판정 기준점)

signal jumped
signal landed

const SPEED := 235.0
const JUMP_V := 560.0
const GRAVITY := 1500.0 # 체공 약 0.75초

const C_SKIN := Color("fbd8b4")
const C_HAT := Color("f4c542")
const C_SHIRT := Color("7cb7d6")
const C_PANTS := Color("5b6c8f")
const C_BAG := Color("e0654f")
const C_DARK := Color("4a3a32")

var z := 0.0
var vz := 0.0
var facing := 1.0
var walk_t := 0.0
var moving := false
var dead := false


func _ready() -> void:
	scale = Vector2(1.2, 1.2)


func is_airborne() -> bool:
	return z > 0.0


func step(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	moving = dir.length() > 0.05
	position += dir * SPEED * delta
	position.x = maxf(position.x, 30.0)
	position.y = clampf(position.y, W.WALK_TOP, W.WALK_BOTTOM)
	if absf(dir.x) > 0.1:
		facing = signf(dir.x)
	if moving:
		walk_t += delta * 12.0

	if Input.is_action_just_pressed("jump") and z <= 0.0:
		vz = JUMP_V
		z = 0.01
		jumped.emit()
	if z > 0.0:
		vz -= GRAVITY * delta
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
		# 납작 엎어진 모습
		draw_set_transform(Vector2(0, -6), 0.0, Vector2(1.3, 0.55))
	var on_ground := z <= 0.0
	var bob := absf(sin(walk_t)) * 2.5 if moving and on_ground else 0.0
	var o := Vector2(0, -z * 0.45 - bob) # 화면상 점프 높이는 45%만
	var swing := sin(walk_t) * 4.0 if moving and on_ground else 0.0
	if not on_ground:
		swing = 3.0 # 점프 중엔 다리를 벌림

	# 다리
	W.rrect(self, Rect2(o.x - 8 + swing, o.y - 13, 6, 13), C_PANTS, 3)
	W.rrect(self, Rect2(o.x + 2 - swing, o.y - 13, 6, 13), C_PANTS, 3)
	# 책가방 (등 쪽)
	W.rrect(self, Rect2(o.x - facing * 11 - 6, o.y - 30, 12, 17), C_BAG, 4)
	# 몸통
	W.rrect(self, Rect2(o.x - 11, o.y - 31, 22, 20), C_SHIRT, 8)
	# 머리
	var head := o + Vector2(0, -42)
	draw_circle(head, 12, C_SKIN)
	# 볼터치
	draw_circle(head + Vector2(facing * 6, 4), 3, Color(0.95, 0.55, 0.5, 0.45))
	# 눈
	if dead:
		for ex in [facing * 1.5, facing * 7.0]:
			draw_line(head + Vector2(ex - 2, -2), head + Vector2(ex + 2, 2), C_DARK, 1.5)
			draw_line(head + Vector2(ex - 2, 2), head + Vector2(ex + 2, -2), C_DARK, 1.5)
	else:
		draw_circle(head + Vector2(facing * 1.5, 0), 1.8, C_DARK)
		draw_circle(head + Vector2(facing * 7.0, 0), 1.8, C_DARK)
	# 노란 모자 (반원 + 챙)
	var dome := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		dome.append(head + Vector2(cos(a) * 12.5, sin(a) * 12.5 - 3))
	draw_colored_polygon(dome, C_HAT)
	draw_colored_polygon(W.ellipse(head + Vector2(facing * 9, -3), 9, 3, 16), C_HAT.darkened(0.08))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
