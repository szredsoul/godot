class_name UI
extends RefCounted
## 공용 UI 도구 (글꼴, 라벨, 버튼, 패널 스타일)

const C_TEXT := Color("4a3a32")
const C_SUB := Color("7a6a5e")
const C_ACCENT := Color("e0654f")
const C_GOLD := Color("e09a1f")
const C_SAFE := Color("4f7a46")
const C_PAPER := Color(1.0, 0.97, 0.9, 0.96)
const C_LINE := Color("e8c99a")

static var _font: SystemFont
static var _bold: SystemFont


static func font(bold := false) -> SystemFont:
	if _font == null:
		var names := PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR"])
		_font = SystemFont.new()
		_font.font_names = names
		_bold = SystemFont.new()
		_bold.font_names = names
		_bold.font_weight = 700
	return _bold if bold else _font


static func label(size: int, color: Color, bold := false, outline := true) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(1.0, 0.97, 0.9))
		l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(bg: Color, border: Color, radius := 18, bw := 3, margin := 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.anti_aliasing = true
	return sb


static func panel_style() -> StyleBoxFlat:
	var sb := box(C_PAPER, C_LINE, 24, 3, 32)
	sb.shadow_color = Color(0.3, 0.2, 0.1, 0.25)
	sb.shadow_size = 14
	return sb


static func button(text: String, size := 22, min_w := 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font(true))
	b.add_theme_font_size_override("font_size", size)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, C_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(C_SUB, 0.6))
	b.add_theme_stylebox_override("normal", box(Color("fff7e6"), C_LINE, 14, 3, 12))
	b.add_theme_stylebox_override("hover", box(Color("fff0d2"), Color("e8b26a"), 14, 3, 12))
	b.add_theme_stylebox_override("pressed", box(Color("fde3b8"), C_ACCENT, 14, 3, 12))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), C_ACCENT, 14, 4, 12))
	b.add_theme_stylebox_override("disabled", box(Color("f1e8d8"), Color("e2d6c0"), 14, 3, 12))
	b.custom_minimum_size = Vector2(min_w, 0)
	return b


static func fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return out


static func stars_text(stars: Array) -> String:
	var s := ""
	for v in stars:
		s += "★" if v else "☆"
	return s
