class_name PolyDrawer
extends Node2D
## 그림자 다각형들을 한 색으로 그린다. CanvasGroup 안에 넣어 겹쳐도 진해지지 않게 사용.

var color := Color.BLACK
var polys: Array[PackedVector2Array] = []


func _draw() -> void:
	for p in polys:
		if p.size() >= 3:
			draw_colored_polygon(p, color)
			var closed := PackedVector2Array(p)
			closed.append(p[0])
			draw_polyline(closed, color, 1.5, true) # 가장자리 안티앨리어싱
