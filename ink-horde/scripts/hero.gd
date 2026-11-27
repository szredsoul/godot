class_name Hero
extends Node2D
## 주인공: 붓을 든 젊은 서예가. 이동만 하고 공격은 무기가 알아서 한다. position = 발 위치

const BASE_SPEED := 215.0
const RADIUS := 15.0

var speed_mul := 1.0
var facing := Vector2.RIGHT # 마지막으로 움직인 방향 (붓 휘두르기 방향)
var walk_t := 0.0
var moving := false
var swing_t := 0.0
var swing_dir := 1.0
var hurt_t := 0.0
var dead := false


func step(dt: float, input: Vector2) -> void:
	swing_t = maxf(0.0, swing_t - dt)
	hurt_t = maxf(0.0, hurt_t - dt)
	moving = input.length() > 0.1
	if moving:
		facing = input.normalized()
		walk_t += dt * 11.0
		position += input.limit_length(1.0) * BASE_SPEED * speed_mul * dt
	queue_redraw()


func _draw() -> void:
	draw_colored_polygon(Ink.ellipse(Vector2.ZERO, 17, 6), Color(Ink.INK, 0.25))
	if dead:
		draw_set_transform(Vector2(0, -8), 0.0, Vector2(1.4, 0.5))
	var bob := absf(sin(walk_t)) * 2.0 if moving else 0.0
	var o := Vector2(0, -bob)
	var flicker := hurt_t > 0.0 and int(hurt_t * 24.0) % 2 == 0
	var line := Ink.SEAL if flicker else Ink.INK
	var robe := PackedVector2Array([o + Vector2(-14, -4), o + Vector2(14, -4), o + Vector2(10, -29), o + Vector2(-10, -29)])
	draw_colored_polygon(robe, Ink.ROBE)
	var closed := PackedVector2Array(robe)
	closed.append(robe[0])
	draw_polyline(closed, line, 3.0, true)
	draw_line(o + Vector2(-11, -15), o + Vector2(11, -15), Ink.SEAL, 4.0, true)
	var head := o + Vector2(0, -39)
	draw_circle(head, 10.5, Ink.ROBE, true, -1.0, true)
	draw_arc(head, 10.5, 0, TAU, 20, line, 3.0, true)
	draw_arc(head, 10.5, PI * 1.05, PI * 1.95, 10, Ink.INK, 7.0, true)
	draw_circle(head + Vector2(0, -12), 5, Ink.INK, true, -1.0, true)
	draw_circle(head + facing * 5.0 + Vector2(0, 1), 1.8, Ink.INK)
	var swing := 0.0
	if swing_t > 0.0:
		swing = swing_dir * ((1.0 - swing_t / 0.16) * 2.2 - 1.1)
	var bd := facing.rotated(swing)
	var hand := o + Vector2(0, -21) + bd * 9.0
	draw_line(hand, hand + bd * 24.0, Color("9a6b3f"), 4.0, true)
	draw_colored_polygon(PackedVector2Array([hand + bd * 22.0 + bd.orthogonal() * 4.0,
			hand + bd * 37.0, hand + bd * 22.0 - bd.orthogonal() * 4.0]), Ink.INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
