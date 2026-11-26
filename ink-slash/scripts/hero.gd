class_name Hero
extends Node2D
## 주인공: 붓을 든 젊은 서예가. position = 발 위치

const SPEED := 270.0
const DASH_SPEED := 980.0
const DASH_TIME := 0.17
const DASH_INV := 0.26 # 회피 중 무적
const DASH_CD := 0.42
const RADIUS := 16.0

var hp := 5
var inv := 0.0
var dash_t := 0.0
var dash_dir := Vector2.RIGHT
var dash_cd := 0.0
var facing := Vector2.RIGHT # 붓이 향하는 쪽 (마우스)
var walk_t := 0.0
var moving := false
var swing_t := 0.0 # 휘두르는 동작 연출
var swing_dir := 1.0
var hurt_t := 0.0
var dead := false


func is_dashing() -> bool:
	return dash_t > 0.0


func is_invulnerable() -> bool:
	return inv > 0.0


func start_dash(dir: Vector2) -> void:
	dash_dir = dir.normalized() if dir != Vector2.ZERO else facing
	dash_t = DASH_TIME
	dash_cd = DASH_CD
	inv = maxf(inv, DASH_INV)


func step(dt: float, input: Vector2, aim: Vector2) -> void:
	inv = maxf(0.0, inv - dt)
	dash_cd = maxf(0.0, dash_cd - dt)
	swing_t = maxf(0.0, swing_t - dt)
	hurt_t = maxf(0.0, hurt_t - dt)
	if aim != Vector2.ZERO:
		facing = aim.normalized()
	if dash_t > 0.0:
		dash_t -= dt
		position += dash_dir * DASH_SPEED * dt
	else:
		position += input * SPEED * dt
	moving = input.length() > 0.1 or dash_t > 0.0
	if moving:
		walk_t += dt * 11.0
	position.x = clampf(position.x, Ink.ARENA.position.x + RADIUS, Ink.ARENA.end.x - RADIUS)
	position.y = clampf(position.y, Ink.ARENA.position.y + RADIUS, Ink.ARENA.end.y - RADIUS)
	queue_redraw()


func _draw() -> void:
	draw_colored_polygon(Ink.ellipse(Vector2.ZERO, 18, 7), Color(Ink.INK, 0.25))
	if dead:
		draw_set_transform(Vector2(0, -8), 0.0, Vector2(1.4, 0.5))
	var bob := absf(sin(walk_t)) * 2.0 if moving else 0.0
	var o := Vector2(0, -bob)
	var flicker := hurt_t > 0.0 and int(hurt_t * 20.0) % 2 == 0
	var line := Ink.SEAL if flicker else Ink.INK
	# 도포 (흰 옷에 먹 테두리)
	var robe := PackedVector2Array([o + Vector2(-15, -4), o + Vector2(15, -4), o + Vector2(11, -30), o + Vector2(-11, -30)])
	draw_colored_polygon(robe, Ink.ROBE)
	var closed := PackedVector2Array(robe)
	closed.append(robe[0])
	draw_polyline(closed, line, 3.0, true)
	draw_line(o + Vector2(-12, -16), o + Vector2(12, -16), Ink.SEAL, 4.0, true) # 붉은 띠
	# 머리 + 상투
	var head := o + Vector2(0, -40)
	draw_circle(head, 11, Ink.ROBE, true, -1.0, true)
	draw_arc(head, 11, 0, TAU, 20, line, 3.0, true)
	draw_arc(head, 11, PI * 1.05, PI * 1.95, 10, Ink.INK, 7.0, true) # 머리카락
	draw_circle(head + Vector2(0, -13), 5, Ink.INK, true, -1.0, true)
	draw_circle(head + facing * 5.0 + Vector2(0, 1), 1.8, Ink.INK)
	# 붓 (마우스 쪽을 향함, 휘두를 때 크게 돈다)
	var swing := 0.0
	if swing_t > 0.0:
		swing = swing_dir * (1.0 - swing_t / 0.16) * 2.0 - swing_dir * 1.0
	var bd := facing.rotated(swing)
	var hand := o + Vector2(0, -22) + bd * 10.0
	draw_line(hand, hand + bd * 26.0, Color("9a6b3f"), 4.0, true) # 붓대
	draw_colored_polygon(PackedVector2Array([hand + bd * 24.0 + bd.orthogonal() * 4.0,
			hand + bd * 40.0, hand + bd * 24.0 - bd.orthogonal() * 4.0]), Ink.INK) # 붓털
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
