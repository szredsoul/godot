extends Node2D
## 그림자 밟기 - 게임 매니저
## 차 그림자를 밟으면 아웃. 점프로 넘으면 점수, 아슬아슬하면 2배, 연속이면 콤보 배율.
## 나무 그늘 안에서는 차 그림자를 밟아도 안전.

enum State { TITLE, PLAY, OVER }

const DAY_LEN := 200.0 # 오전 7시 → 오후 7시 까지 걸리는 시간(초)
const DAY_START := 0.1
const NEAR_DIST := 22.0 # 이 거리 안에서 뛰거나 착지하면 '아슬아슬'
const COMBO_TIME := 4.0
const SAVE_PATH := "user://best_score.dat"

const C_TEXT := Color("4a3a32")
const C_SUB := Color("7a6a5e")
const C_ACCENT := Color("e0654f")
const C_GOLD := Color("e09a1f")
const C_SAFE := Color("4f7a46")

static var skip_title := false

var state := State.TITLE
var rng := RandomNumberGenerator.new()
var font: SystemFont
var font_bold: SystemFont

var ground: Ground
var shade_drawer: PolyDrawer
var shadow_drawer: PolyDrawer
var player: Player
var camera: Camera2D
var tint: CanvasModulate

var cars: Array[Car] = []
var trees: Array[ShadeTree] = []

var day_time := 0.0
var sun := Vector2(-0.6, 3.0)
var elapsed := 0.0
var lane_timer: Array[float] = [0.6, 1.8]
var next_tree_x := 360.0

var jump_score := 0
var combo := 0
var combo_timer := 0.0
var best := 0
var start_x := 200.0
var max_x := 200.0
var in_shade := false
var pending_land := false
var air_cleared := {}   # 점프 중 발밑을 지나간 차: instance_id -> Car
var takeoff_dist := {}  # 이륙 순간 각 그림자까지 거리
var takeoff_in_shade := false
var shake := 0.0
var slowmo_until_ms := 0
var warn_timer := 0.0
var over_ready := false

var sfx: Sfx
var step_timer := 0.0
var bird_timer := 2.0

var score_label: Label
var best_label: Label
var clock_label: Label
var sun_label: Label
var combo_label: Label
var mult_label: Label
var combo_bg: ColorRect
var combo_fill: ColorRect
var hide_label: Label
var warn_label: Label
var center_box: CenterContainer
var center_title: Label
var center_body: Label
var center_hint: Label


func _ready() -> void:
	Engine.time_scale = 1.0
	rng.randomize()
	_setup_input()
	_setup_fonts()
	best = _load_best()
	day_time = DAY_LEN * DAY_START
	RenderingServer.set_default_clear_color(Ground.C_GRASS)
	sfx = Sfx.new()
	add_child(sfx)

	ground = Ground.new()
	ground.z_index = -20
	add_child(ground)

	# 그림자는 CanvasGroup으로 묶어서 겹쳐도 한 겹으로 보이게
	var shade_group := CanvasGroup.new()
	shade_group.z_index = -10
	shade_group.self_modulate = Color(1, 1, 1, 0.34)
	add_child(shade_group)
	shade_drawer = PolyDrawer.new()
	shade_drawer.color = Color("3c4a3a")
	shade_group.add_child(shade_drawer)

	var shadow_group := CanvasGroup.new()
	shadow_group.z_index = -9
	shadow_group.self_modulate = Color(1, 1, 1, 0.42)
	add_child(shadow_group)
	shadow_drawer = PolyDrawer.new()
	shadow_drawer.color = Color("3b2747")
	shadow_group.add_child(shadow_drawer)

	player = Player.new()
	player.position = Vector2(start_x, 450)
	add_child(player)
	player.jumped.connect(_on_jumped)
	player.landed.connect(_on_landed)

	camera = Camera2D.new()
	camera.position = Vector2(_half_w(), 360)
	add_child(camera)
	camera.make_current()

	tint = CanvasModulate.new()
	add_child(tint)

	_build_ui()
	_update_trees()
	if skip_title:
		_start_game()
	else:
		_show_title()


func _process(delta: float) -> void:
	_update_slowmo()
	if state != State.TITLE and Input.is_action_just_pressed("restart"):
		_restart()
		return
	match state:
		State.TITLE:
			if Input.is_action_just_pressed("jump"):
				_start_game()
		State.PLAY:
			elapsed += delta
			day_time += delta
			player.step(delta)
		State.OVER:
			if over_ready and Input.is_action_just_pressed("jump"):
				_restart()
				return

	_update_sun()
	_update_cars(delta)
	_update_trees()
	if state == State.PLAY:
		_check_player()
		_update_combo(delta)
		max_x = maxf(max_x, player.position.x)
		_update_footsteps(delta)
	_update_ambient(delta)
	_update_camera(delta)
	_update_drawers()
	_update_hud(delta)


# ───────────── 태양 / 시간 ─────────────

func _day_t() -> float:
	return clampf(day_time / DAY_LEN, 0.0, 0.97)


func _update_sun() -> void:
	var t := _day_t()
	var el := sin(PI * t) # 0: 해가 낮음, 1: 정오
	# x: 아침엔 그림자가 왼쪽, 저녁엔 오른쪽으로 기움 / y: 해가 낮을수록 길다
	sun = Vector2(-cos(PI * t) * 0.6, lerpf(5.0, 2.4, el))
	var morning := Color(1.0, 0.94, 0.86)
	var noon := Color(1.0, 1.0, 0.98)
	var evening := Color(1.0, 0.8, 0.66)
	tint.color = (morning if t < 0.5 else evening).lerp(noon, el)


# ───────────── 차 ─────────────

func _update_cars(delta: float) -> void:
	_spawn_cars(delta)
	var cx := camera.position.x
	var keep: Array[Car] = []
	for car in cars:
		car.step(delta)
		car.update_shadow(sun)
		# 차가 아이 옆을 지나가는 순간 '쉬익'
		if not car.passed and (car.position.x - player.position.x) * car.dir > 0.0:
			car.passed = true
			if state == State.PLAY:
				var pitch := clampf(car.speed / 260.0, 0.7, 1.3) * (1.15 if car.kind == "bike" else 1.0)
				if car.kind == "truck" or car.kind == "bus":
					pitch *= 0.7
				sfx.play("whoosh", pitch, -9.0 if car.lane == 1 else -14.0)
		if absf(car.position.x - cx) > 2200.0:
			car.queue_free()
		else:
			keep.append(car)
	cars = keep


func _spawn_cars(delta: float) -> void:
	var pace := lerpf(1.0, 0.45, clampf(elapsed / 180.0, 0.0, 1.0))
	for lane in 2:
		lane_timer[lane] -= delta
		if lane_timer[lane] > 0.0:
			continue
		var kind := _pick_kind()
		if _spawn_car(kind, lane):
			lane_timer[lane] = rng.randf_range(1.4, 3.2) * pace + float(Car.KINDS[kind]["len"]) / 260.0
		else:
			lane_timer[lane] = 0.3


func _pick_kind() -> String:
	var w := {"bike": 3.0, "car": 5.0}
	if elapsed > 12.0:
		w["van"] = 2.5
	if elapsed > 30.0:
		w["truck"] = 2.0
	if elapsed > 55.0:
		w["bus"] = 1.4
	var total := 0.0
	for k in w:
		total += w[k]
	var r := rng.randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "car"


func _spawn_car(kind: String, lane: int) -> bool:
	var car := Car.new()
	car.setup(kind, lane, rng)
	var edge := _half_w() + 160.0 + car.length
	car.position.x = camera.position.x + (edge if car.dir < 0 else -edge)
	for other in cars:
		if other.lane != lane:
			continue
		var gap := absf(other.position.x - car.position.x)
		if gap < (other.length + car.length) * 0.5 + 60.0:
			car.free()
			return false
		if gap < 1400.0:
			car.speed = minf(car.speed, other.speed) # 앞차를 추월하지 않게
	add_child(car)
	cars.append(car)
	if kind == "truck" or kind == "bus":
		var name_kr := "트럭" if kind == "truck" else "버스"
		warn_label.text = ("%s 온다! →" if car.dir < 0 else "← %s 온다!") % name_kr
		if kind == "bus":
			warn_label.text += "  그늘로 숨어!"
		warn_timer = 2.4
		if state == State.PLAY:
			sfx.play("horn", 0.85 if kind == "truck" else 0.7, -3.0)
	return true


# ───────────── 나무 ─────────────

func _update_trees() -> void:
	while next_tree_x < camera.position.x + 1600.0:
		var t := ShadeTree.new()
		t.setup(next_tree_x, rng)
		add_child(t)
		trees.append(t)
		next_tree_x += rng.randf_range(600.0, 1100.0)
	for t in trees:
		if absf(t.position.x - camera.position.x) > 1500.0:
			continue
		t.update_shade(sun)
		# 아이가 나무 아래로 가면 잎을 반투명하게
		var near := absf(player.position.x - t.position.x) < t.radius + 16.0 \
				and player.position.y < W.SIDEWALK_TOP + 70.0
		t.modulate.a = lerpf(t.modulate.a, 0.45 if near else 1.0, 0.15)


# ───────────── 판정 ─────────────

func _check_player() -> void:
	var foot := player.position
	var was_in_shade := in_shade
	in_shade = false
	for t in trees:
		if absf(t.position.x - foot.x) < 200.0 and Geometry2D.is_point_in_polygon(foot, t.shade):
			in_shade = true
			break
	if in_shade and not was_in_shade:
		sfx.play("shade", rng.randf_range(0.9, 1.1), -6.0)

	var air := player.is_airborne()
	for car in cars:
		if car.shadow.size() < 3:
			continue
		if air:
			if Geometry2D.is_point_in_polygon(foot, car.shadow):
				air_cleared[car.get_instance_id()] = car
		elif not in_shade and _foot_hits(foot, car.shadow):
			_game_over()
			return

	if pending_land:
		pending_land = false
		_resolve_landing()


func _foot_hits(foot: Vector2, poly: PackedVector2Array) -> bool:
	# 발 판정은 일부러 작게 (아슬아슬한 손맛)
	for off in [Vector2.ZERO, Vector2(7, 0), Vector2(-7, 0), Vector2(0, 3), Vector2(0, -3)]:
		if Geometry2D.is_point_in_polygon(foot + off, poly):
			return true
	return false


func _on_jumped() -> void:
	sfx.play("jump", rng.randf_range(0.95, 1.05), -2.0)
	takeoff_in_shade = in_shade
	air_cleared.clear()
	takeoff_dist.clear()
	for car in cars:
		takeoff_dist[car.get_instance_id()] = W.dist_to_polygon(player.position, car.shadow)


func _on_landed() -> void:
	sfx.play("land", rng.randf_range(0.9, 1.1), -4.0)
	pending_land = true # 착지 판정(그림자 위 착지 = 아웃)을 먼저 하고 점수 처리


func _resolve_landing() -> void:
	if air_cleared.is_empty():
		return
	var foot := player.position
	var head := foot + Vector2(0, -95)
	if takeoff_in_shade or in_shade:
		air_cleared.clear()
		_popup("그늘 속 점프는 노카운트", head, C_SUB, 18)
		return

	var near := false
	var n := 0
	for id in air_cleared:
		n += 1
		var car = air_cleared[id]
		if not is_instance_valid(car):
			continue
		var d := minf(W.dist_to_polygon(foot, car.shadow), float(takeoff_dist.get(id, INF)))
		if d < NEAR_DIST:
			near = true
	air_cleared.clear()

	var old_mult := _combo_mult()
	combo += n
	combo_timer = COMBO_TIME
	var pts := 100.0 * n * _combo_mult()
	# 콤보가 쌓일수록 '띵' 소리가 높아진다
	sfx.play("clear", 1.0 + 0.04 * mini(combo, 15), -2.0)
	if near:
		sfx.play("near")
	if _combo_mult() > old_mult:
		sfx.play("combo_up", 1.0, -1.0)
		_popup("배율 x%.1f!" % _combo_mult(), foot + Vector2(0, -190), C_ACCENT, 24)
	if near:
		pts *= 2.0
	if n >= 2:
		pts *= 1.5
	jump_score += int(pts)

	_popup("+%s" % _fmt(int(pts)), head, C_GOLD if near else C_TEXT, 26)
	if near:
		_popup("아슬아슬! x2", head + Vector2(0, -32), C_ACCENT, 32)
		_slowmo()
		shake = 5.0
	if n >= 2:
		_popup("더블!" if n == 2 else "%d연속!" % n, head + Vector2(0, -64), C_GOLD, 26)


func _combo_mult() -> float:
	return minf(1.0 + floorf(combo / 5.0) * 0.5, 4.0)


func _update_combo(delta: float) -> void:
	if combo <= 0:
		return
	combo_timer -= delta
	if combo_timer <= 0.0:
		if combo >= 5:
			_popup("콤보 끝", player.position + Vector2(0, -95), C_SUB, 20)
			sfx.play("combo_end")
		combo = 0


func _total_score() -> int:
	return jump_score + int(maxf(0.0, max_x - start_x) / 10.0)


func _game_over() -> void:
	state = State.OVER
	player.dead = true
	player.queue_redraw()
	shake = 12.0
	Engine.time_scale = 1.0
	var total := _total_score()
	var new_best := total > best
	if new_best:
		best = total
		_save_best(best)
	_popup("앗! 밟았다!", player.position + Vector2(0, -95), C_ACCENT, 32)
	sfx.play("fail")
	get_tree().create_timer(0.9).timeout.connect(_show_over.bind(total, new_best))


# ───────────── 연출 ─────────────

func _slowmo() -> void:
	Engine.time_scale = 0.35
	slowmo_until_ms = Time.get_ticks_msec() + 220


func _update_slowmo() -> void:
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() > slowmo_until_ms:
		Engine.time_scale = 1.0


func _update_camera(delta: float) -> void:
	var target := maxf(player.position.x, _half_w())
	camera.position.x = lerpf(camera.position.x, target, 1.0 - exp(-5.0 * delta))
	shake = maxf(0.0, shake - 30.0 * delta)
	camera.offset = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake


func _update_drawers() -> void:
	var cx := camera.position.x
	shade_drawer.polys.clear()
	for t in trees:
		if absf(t.position.x - cx) < 1500.0:
			shade_drawer.polys.append(t.shade)
	shadow_drawer.polys.clear()
	for car in cars:
		shadow_drawer.polys.append(car.shadow)
	shade_drawer.queue_redraw()
	shadow_drawer.queue_redraw()
	for car in cars:
		car.queue_redraw()
	ground.cam_x = cx
	ground.queue_redraw()


func _popup(text: String, pos: Vector2, color: Color, size: int) -> void:
	var l := _make_label(size, color, true)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(360, 50)
	l.position = pos - Vector2(180, 25)
	l.z_index = 30
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 50.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.35)
	tw.tween_callback(l.queue_free)


# ───────────── UI ─────────────

func _setup_fonts() -> void:
	var names := PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR"])
	font = SystemFont.new()
	font.font_names = names
	font_bold = SystemFont.new()
	font_bold.font_names = names
	font_bold.font_weight = 700


func _make_label(size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font_bold if bold else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(1.0, 0.97, 0.9))
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	score_label = _make_label(40, C_TEXT, true)
	score_label.position = Vector2(28, 12)
	root.add_child(score_label)
	best_label = _make_label(18, C_SUB)
	best_label.position = Vector2(30, 64)
	root.add_child(best_label)

	clock_label = _make_label(24, C_TEXT, true)
	_wide_top(clock_label, 14)
	root.add_child(clock_label)
	sun_label = _make_label(17, C_SUB)
	_wide_top(sun_label, 48)
	root.add_child(sun_label)

	combo_label = _make_label(30, C_ACCENT, true)
	_right_top(combo_label, 12)
	root.add_child(combo_label)
	mult_label = _make_label(18, C_GOLD, true)
	_right_top(mult_label, 52)
	root.add_child(mult_label)
	combo_bg = ColorRect.new()
	combo_bg.color = Color(0.3, 0.2, 0.15, 0.18)
	combo_bg.anchor_left = 1.0
	combo_bg.anchor_right = 1.0
	combo_bg.offset_left = -228
	combo_bg.offset_right = -28
	combo_bg.offset_top = 84
	combo_bg.offset_bottom = 92
	root.add_child(combo_bg)
	combo_fill = ColorRect.new()
	combo_fill.color = C_ACCENT
	combo_fill.size = Vector2(200, 8)
	combo_bg.add_child(combo_fill)

	warn_label = _make_label(30, C_ACCENT, true)
	_wide_top(warn_label, 100)
	root.add_child(warn_label)

	hide_label = _make_label(22, C_SAFE, true)
	hide_label.text = "그늘 속 · 안전해요"
	hide_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hide_label.offset_top = -100
	hide_label.offset_bottom = -70
	hide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hide_label)

	var help := _make_label(16, C_SUB)
	help.text = "이동  WASD / 방향키     점프  Space     다시하기  R"
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 24
	help.offset_top = -38
	help.offset_right = 700
	help.offset_bottom = -12
	root.add_child(help)

	center_box = CenterContainer.new()
	center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center_box)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.97, 0.9, 0.95)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(36)
	sb.border_color = Color("e8c99a")
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0.3, 0.2, 0.1, 0.25)
	sb.shadow_size = 14
	panel.add_theme_stylebox_override("panel", sb)
	center_box.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	center_title = _make_label(52, C_ACCENT, true)
	center_body = _make_label(20, C_TEXT)
	center_hint = _make_label(22, Color("8a6a4e"), true)
	for l in [center_title, center_body, center_hint]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)


func _wide_top(l: Label, top: float) -> void:
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.offset_top = top
	l.offset_bottom = top + 36
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _right_top(l: Label, top: float) -> void:
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.offset_left = -380
	l.offset_right = -28
	l.offset_top = top
	l.offset_bottom = top + 40
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _show_title() -> void:
	state = State.TITLE
	center_title.text = "그림자 밟기"
	center_body.text = "길 옆을 지나가는 자동차 그림자를 밟으면 안 돼요!\n\n" \
		+ "점프해서 그림자를 넘으면 점수\n" \
		+ "아슬아슬하게 넘으면 점수 2배\n" \
		+ "쉬지 않고 넘으면 콤보 배율이 올라가요\n" \
		+ "긴 그림자는 나무 그늘에 숨어서 피하기 (그늘 속은 안전)\n" \
		+ "아침·저녁엔 그림자가 길고, 한낮엔 짧아요"
	center_hint.text = "Space를 눌러 시작"
	center_box.visible = true


func _start_game() -> void:
	state = State.PLAY
	center_box.visible = false
	sfx.play("start", 1.0, -3.0)


func _update_footsteps(delta: float) -> void:
	if not player.moving or player.is_airborne():
		step_timer = 0.05
		return
	step_timer -= delta
	if step_timer <= 0.0:
		step_timer = 0.27
		sfx.play("step", rng.randf_range(0.85, 1.15), -10.0)


## 가끔 들리는 새소리 (따뜻한 동네 분위기)
func _update_ambient(delta: float) -> void:
	bird_timer -= delta
	if bird_timer <= 0.0:
		bird_timer = rng.randf_range(4.0, 9.0)
		sfx.play("bird" if rng.randf() < 0.5 else "bird2", rng.randf_range(0.85, 1.2), rng.randf_range(-18.0, -12.0))


func _show_over(total: int, new_best: bool) -> void:
	center_title.text = "그림자를 밟았다!"
	center_body.text = "점수  %s\n최고  %s%s" % [_fmt(total), _fmt(best), "   신기록!" if new_best else ""]
	center_hint.text = "Space 또는 R로 다시 하기"
	center_box.visible = true
	over_ready = true


func _update_hud(delta: float) -> void:
	var total := _total_score()
	score_label.text = _fmt(total)
	best_label.text = "최고 " + _fmt(maxi(best, total))

	var hour_f := 7.0 + _day_t() * 12.0
	var hh := int(hour_f)
	var mm := int((hour_f - hh) * 6.0) * 10
	var h12 := hh if hh <= 12 else hh - 12
	clock_label.text = "%s %d:%02d" % ["오전" if hh < 12 else "오후", h12, mm]
	if sun.y > 4.0:
		sun_label.text = "그림자가 길어요"
	elif sun.y > 3.0:
		sun_label.text = "그림자 보통"
	else:
		sun_label.text = "한낮 · 그림자가 짧아요"

	var show_combo := state == State.PLAY and combo > 0
	combo_label.visible = show_combo
	mult_label.visible = show_combo
	combo_bg.visible = show_combo
	if show_combo:
		combo_label.text = "%d 콤보" % combo
		mult_label.text = "점수 x%.1f" % _combo_mult()
		combo_fill.size = Vector2(200.0 * clampf(combo_timer / COMBO_TIME, 0.0, 1.0), 8)

	hide_label.visible = state == State.PLAY and in_shade
	player.modulate = Color(0.82, 0.86, 0.92) if in_shade and state == State.PLAY else Color.WHITE

	warn_timer -= delta
	warn_label.visible = state == State.PLAY and warn_timer > 0.0 and fmod(warn_timer, 0.4) > 0.12
	center_hint.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)


func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return out


# ───────────── 기타 ─────────────

func _half_w() -> float:
	return get_viewport_rect().size.x * 0.5


func _restart() -> void:
	skip_title = true
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _setup_input() -> void:
	var map := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE, KEY_J],
		"restart": [KEY_R],
	}
	for action in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in map[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)


func _load_best() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	return f.get_32() if f else 0


func _save_best(v: int) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_32(v)
