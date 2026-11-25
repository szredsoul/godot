class_name Pickup
extends Node2D
## 길에 떨어진 구슬(별 조건)과 동전(꾸미기 화폐)

const MARBLE_COLORS: Array[Color] = [Color("6fb0e0"), Color("e87a8f"), Color("7fc79a"), Color("f2c14e"), Color("a98fe0")]

var kind := "coin"
var t := 0.0
var color := Color.WHITE


func setup(k: String, pos: Vector2, rng: RandomNumberGenerator) -> void:
	kind = k
	position = pos
	t = rng.randf() * TAU
	color = MARBLE_COLORS[rng.randi() % MARBLE_COLORS.size()]


func step(delta: float) -> void:
	t += delta * 3.0
	queue_redraw()


func _draw() -> void:
	var lift := 6.0 + sin(t) * 3.0
	draw_colored_polygon(W.ellipse(Vector2.ZERO, 9, 3.5, 16), Color(0.25, 0.15, 0.3, 0.25))
	var c := Vector2(0, -lift)
	if kind == "marble":
		draw_circle(c, 9, color, true, -1.0, true)
		draw_arc(c, 5, t, t + 2.4, 12, color.lightened(0.5), 2.5, true)
		draw_circle(c + Vector2(-3, -3), 2.8, Color(1, 1, 1, 0.85), true, -1.0, true)
	else:
		# 동전은 빙글빙글 도는 것처럼 폭이 변한다
		var w := absf(cos(t * 0.7)) * 8.0 + 1.5
		draw_colored_polygon(W.ellipse(c, w, 8, 20), Color("e8b33c"))
		draw_colored_polygon(W.ellipse(c, w * 0.6, 5, 16), Color("f6d36b"))
