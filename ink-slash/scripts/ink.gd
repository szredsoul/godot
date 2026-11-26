class_name Ink
extends RefCounted
## 먹 화풍 도구 모음: 색, 경기장 크기, 먹 덩어리·붓 획 그리기, 글꼴

const PAPER := Color("f2ebdc")
const PAPER_DARK := Color("e4dac5")
const INK := Color("1c1a1f")
const INK_WASH := Color(0.11, 0.1, 0.12, 0.18)
const SEAL := Color("c8372d")
const ROBE := Color("fbf8f0")
const ARENA := Rect2(90, 96, 1100, 560)

static var _font: SystemFont
static var _bold: SystemFont
static var _brush: SystemFont


static func font(bold := false) -> SystemFont:
	if _font == null:
		var names := PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"])
		_font = SystemFont.new()
		_font.font_names = names
		_bold = SystemFont.new()
		_bold.font_names = names
		_bold.font_weight = 700
	return _bold if bold else _font


## 붓글씨 느낌 글꼴 (윈도우 궁서체, 없으면 바탕 → 맑은 고딕)
static func brush_font() -> SystemFont:
	if _brush == null:
		_brush = SystemFont.new()
		_brush.font_names = PackedStringArray(["Gungsuh", "궁서", "GungsuhChe", "Batang", "Malgun Gothic"])
		_brush.font_weight = 700
	return _brush


static func label(size: int, color: Color, brush := false, outline := true) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", brush_font() if brush else font(true))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", PAPER)
		l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 울퉁불퉁한 먹 덩어리
static func blob(c: Vector2, r: float, phase: float, wob := 0.12, n := 22) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		var k := 1.0 + wob * sin(a * 3.0 + phase) + wob * 0.6 * sin(a * 5.0 - phase * 1.3)
		pts.append(c + Vector2(cos(a), sin(a)) * r * k)
	return pts


static func ellipse(c: Vector2, rx: float, ry: float, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func arc_points(c: Vector2, r: float, a0: float, a1: float, n := 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * r)
	return pts


## 붓 획: 선을 따라 굵기가 변하는 먹 띠 (양 끝은 가늘게). 구간마다 사각형 + 이음매 원으로 그린다
static func draw_brush(ci: CanvasItem, pts: PackedVector2Array, width: float, col: Color, taper := true) -> void:
	var n := pts.size()
	if n < 2:
		return
	var widths := PackedFloat32Array()
	widths.resize(n)
	for i in n:
		var k := float(i) / (n - 1)
		var w := width
		if taper:
			# 시작은 꾹 눌렀다가 끝으로 갈수록 붓이 빠지며 가늘어진다
			w = width * (0.55 + 0.45 * sin(minf(k * 3.0, 1.0) * PI * 0.5)) * (1.0 - k * k * 0.85)
		widths[i] = maxf(w, 1.0)
	for i in n - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		if d.length_squared() < 0.01:
			continue
		var nrm := d.normalized().orthogonal()
		var quad := PackedVector2Array([a + nrm * widths[i] * 0.5, b + nrm * widths[i + 1] * 0.5,
				b - nrm * widths[i + 1] * 0.5, a - nrm * widths[i] * 0.5])
		ci.draw_colored_polygon(quad, col)
		ci.draw_circle(b, widths[i + 1] * 0.5, col, true, -1.0, true)
	ci.draw_circle(pts[0], widths[0] * 0.5, col, true, -1.0, true)


static func polyline_length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


static func dist_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	if pts.size() == 1:
		return p.distance_to(pts[0])
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


## 선 위에서 p와 가장 가까운 지점의 진행 방향
static func polyline_dir_near(p: Vector2, pts: PackedVector2Array) -> Vector2:
	var best := INF
	var dir := Vector2.RIGHT
	for i in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		var d := p.distance_to(q)
		if d < best and pts[i] != pts[i + 1]:
			best = d
			dir = (pts[i + 1] - pts[i]).normalized()
	return dir
