class_name W
extends RefCounted
## 월드 레이아웃 상수와 그리기/기하 헬퍼 모음

const ROAD_TOP := 100.0
const ROAD_BOTTOM := 320.0
const LANE_Y: Array[float] = [165.0, 258.0] # 0: 먼 차선(←), 1: 가까운 차선(→)
const SIDEWALK_TOP := 338.0
const SIDEWALK_BOTTOM := 530.0
const WALK_TOP := 346.0
const WALK_BOTTOM := 522.0


static func ellipse(c: Vector2, rx: float, ry: float, n: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## 점과 다각형 사이 거리 (안쪽이면 0)
static func dist_to_polygon(p: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return INF
	if Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## 둥근 사각형 (반드시 해당 CanvasItem의 _draw 안에서 호출)
static func rrect(ci: CanvasItem, r: Rect2, col: Color, radius: float = 8.0, border := Color(0, 0, 0, 0), bw: int = 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 8
	sb.anti_aliasing = true
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	ci.draw_style_box(sb, r)
