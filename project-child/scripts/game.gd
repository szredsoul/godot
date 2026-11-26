extends Node2D
## 그림자 밟기 - 게임 진행
## 하굣길(스테이지): 학교에서 집까지 6장. 장마다 시간대가 넘어간다 (오후 3시 → 해질녘 6시 반). 하트 3개.
## 도전 모드: 끝없는 길, 한 번 밟으면 끝 (예전 규칙).

enum State { PLAY, CLEAR, FAIL, OVER }

const NEAR_DIST := 22.0 # 이 거리 안에서 뛰거나 착지하면 '아슬아슬'
const COMBO_TIME := 4.0
const MAX_HEARTS := 3
const INVULN_TIME := 1.6 # 밟은 뒤 잠깐 무적
const DAY_LEN := 200.0 # 도전 모드: 오전 7시 → 오후 7시
const QUEUE_GAP := 46.0 # 신호에 멈춘 차 사이 간격 (그림자 사이에 내려설 수 있을 만큼)
const FOOT_R := 9.0
const START_X := 220.0
const ENDLESS_ROUTE := {
	"name": "도전", "pace": 1.0, "kinds": {}, "trees": [600, 1100], "obstacles": 0.5,
	"peds": 0, "dogs": 0, "crossings": [], "bus_stops": [], "moto": true, "convoys": 0,
	"marbles": 0, "coins": 0,
}

var state := State.PLAY
var endless := false
var paused := false
var rng := RandomNumberGenerator.new()
var gen := RandomNumberGenerator.new() # 맵 생성용 (같은 스테이지는 같은 배치)
var route: Dictionary
var season: Dictionary
var season_key := "spring"
var length := INF
var time_limit := 120.0
var chapter: Dictionary = {}
var chap_start := 15.0
var chap_end := 18.0

var sfx: Sfx
var ground: Ground
var shade_drawer: PolyDrawer
var shadow_drawer: PolyDrawer
var player: Player
var friend: Player
var camera: Camera2D
var tint: CanvasModulate
var weather: Weather
var footprints: Weather.Footprints

var cars: Array[Car] = []
var trees: Array[ShadeTree] = []
var obstacles: Array[Obstacle] = []
var pickups: Array[Pickup] = []
var npcs: Array[Npc] = []
var crossings: Array[Crossing] = []
var bus_stops: Array[Dictionary] = []

var elapsed := 0.0
var day_time := DAY_LEN * 0.1
var hour := 15.0
var sun := Vector2(0.5, 3.0)
var lane_timer: Array[float] = [0.6, 1.8]
var convoy_left: Array[int] = [0, 0]
var convoy_points: Array[float] = []
var convoy_timer := 35.0
var moto_timer := 8.0
var npc_timer := 5.0
var gen_x := 0.0
var gen_skip_until := 0.0
var next_tree_x := 380.0
var next_crossing_x := 2600.0
var next_bus_x := 4300.0

var jump_score := 0
var combo := 0
var combo_timer := 0.0
var hearts := MAX_HEARTS
var invuln := 0.0
var stun := 0.0
var coins_got := 0
var marbles_got := 0
var marbles_total := 0
var late := false
var final_score := 0
var events := {"hits": 0, "near": 0, "max_combo": 0, "bus": false, "truck": false, "dog": 0, "bump": 0, "friend_hit": 0, "hops": 0, "ride": 0.0}
var friend_hit_cd := 0.0

# 상상 연출 / 거꾸로 놀이
var reverse := false # 거꾸로 놀이: 햇빛이 용암, 그늘로만 다니기
var speed_mul := 1.0
var imag: Imagination
var cover: PolyDrawer # 용암 위에 덮는 '안전한 땅' (나무 그늘, 거꾸로 놀이에선 모든 그림자)
var splash: Imagination.Splash
var hop_src := "" # 거꾸로 놀이: 뛰어오른 그림자
var heat_snd := 0.0
var bubble_timer := 1.5
var heat_bg: ColorRect
var heat_fill: ColorRect
const UMBRELLA_GAP := 115.0 # 횡단보도에서 그늘막 기둥까지 거리 (신호등을 가리지 않게)
var wait_hint_cd := 0.0
const HEAT_UP := 1.3 # 햇빛에서 이 시간(초) 버티면 데임
const HEAT_DOWN := 1.2

var in_shade := false
var pending_land := false
var air_cleared := {} # 점프 중 발밑을 지나간 차: instance_id -> Car
var takeoff_dist := {}
var takeoff_in_shade := false
var shake := 0.0
var slowmo_until_ms := 0
var warn_timer := 0.0
var bird_timer := 2.0

# UI
var score_label: Label
var best_label: Label
var hearts_label: Label
var items_label: Label
var clock_label: Label
var sun_label: Label
var combo_label: Label
var mult_label: Label
var combo_bg: ColorRect
var combo_fill: ColorRect
var hide_label: Label
var warn_label: Label
var progress: ProgressDraw
var overlay: CenterContainer
var overlay_panel: PanelContainer


## 하단 진행 막대 (학교 → 집)
class ProgressDraw extends Control:
	var frac := 0.0
	var from_text := "학교"
	var to_text := "집"

	func _draw() -> void:
		var w := size.x
		var y := size.y * 0.5
		draw_line(Vector2(0, y), Vector2(w, y), Color(0.3, 0.2, 0.15, 0.25), 6.0, true)
		draw_line(Vector2(0, y), Vector2(w * frac, y), UI.C_GOLD, 6.0, true)
		var fw := UI.font(true).get_string_size(from_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(UI.font(true), Vector2(-12 - fw, y + 6), from_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.C_SUB)
		draw_string(UI.font(true), Vector2(w + 12, y + 6), to_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.C_ACCENT)
		draw_circle(Vector2(w * frac, y), 10, Color("fff7e6"), true, -1.0, true)
		draw_circle(Vector2(w * frac, y), 7, GameData.HATS[GameData.hat_id()]["color"], true, -1.0, true)


func _ready() -> void:
	Engine.time_scale = 1.0
	rng.randomize()
	_setup_input()
	endless = GameData.mode == GameData.Mode.ENDLESS
	if endless:
		route = ENDLESS_ROUTE
		season_key = ["spring", "summer", "autumn", "winter"][rng.randi() % 4]
		gen.randomize()
	else:
		chapter = GameData.stage()
		route = GameData.route().duplicate(true)
		season_key = GameData.season_key()
		# 계절(회차)이 지날수록 차가 조금씩 많아진다
		route["pace"] = float(route["pace"]) * GameData.SEASON_PACE[GameData.season_idx_of(GameData.stage_idx)]
		chap_start = float(chapter["start"])
		chap_end = float(chapter["end"])
		hour = chap_start
		length = float(route["length"])
		time_limit = length / Player.WALK * 2.2 # 쉬지 않고 걸으면 장 시간의 절반쯤에 도착
		gen.seed = 1000 + GameData.stage_idx * 10 + GameData.route_idx
		reverse = chapter.get("rule", "normal") == "reverse"
		if reverse:
			# 느린 그림자만 타고 가면 늦는다 → 앞 그림자로 옮겨 타야 제시간에 도착
			time_limit = length / Player.WALK * 1.5
		speed_mul = float(route.get("speed_mul", 1.0))
	season = GameData.SEASONS[season_key]
	RenderingServer.set_default_clear_color(season["grass"])

	sfx = Sfx.new()
	add_child(sfx)

	ground = Ground.new()
	ground.season = season
	ground.z_index = -20
	if not endless:
		var ci := GameData.chapter_idx_of(GameData.stage_idx)
		ground.district = chapter["district"]
		ground.show_school = ci == 0
		if ci > 0:
			ground.start_title = chapter["title"]
		if GameData.is_last_chapter(GameData.stage_idx):
			ground.home_x = length
		else:
			ground.next_x = length
			ground.next_title = GameData.CHAPTERS[ci + 1]["title"]
	add_child(ground)

	if season["snow"]:
		footprints = Weather.Footprints.new()
		footprints.z_index = -15
		add_child(footprints)

	# 층 순서 (아래→위)
	#  보통: 땅 -20 / 차 그림자 -9 / 상상(바다·용암…) -8 / 나무 그늘 자리 덮개 -7 / 나무 그늘 -6
	#  거꾸로: 땅 -20 / 상상(햇빛 용암) -12 / 그림자 자리 덮개 -11 / 차 그림자 -9 / 나무 그늘 -6
	imag = Imagination.new()
	imag.theme = "lava" if reverse else season["imag"]
	imag.z_index = -12 if reverse else -8
	add_child(imag)
	cover = PolyDrawer.new()
	cover.color = Ground.C_WALK_A
	cover.z_index = -11 if reverse else -7
	add_child(cover)
	# 그림자는 CanvasGroup으로 묶어서 겹쳐도 한 겹으로 보이게
	var shade_group := CanvasGroup.new()
	shade_group.z_index = -6
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
	splash = Imagination.Splash.new()
	splash.z_index = 125
	add_child(splash)

	player = Player.new()
	player.apply_equipped()
	player.position = Vector2(START_X, 450)
	player.max_x = length + 60.0
	add_child(player)
	player.jumped.connect(_on_jumped)
	player.landed.connect(_on_landed)
	player.sink_color = Imagination.THEMES[imag.theme]["base"]

	if not endless:
		friend = Player.new()
		friend.shirt_color = Color("f2c14e")
		friend.hat_color = Color("6f9fd8")
		friend.bag_color = Color("7fb36a")
		friend.pants_color = Color("8a6a5a")
		friend.position = Vector2(START_X - 70, 400)
		friend.max_x = length + 40.0
		add_child(friend)

	camera = Camera2D.new()
	camera.position = Vector2(_half_w(), 360)
	add_child(camera)
	camera.make_current()

	tint = CanvasModulate.new()
	add_child(tint)

	weather = Weather.new()
	weather.setup(season["particle"])
	add_child(weather)

	_build_ui()
	if not endless:
		_place_fixed_features()
	_generate_until(camera.position.x + 1800.0)
	if season["ambient"] == "cicada":
		sfx.play_loop("cicada", -20.0)
	sfx.play("start", 1.0, -3.0)
	if not endless:
		_popup("%d장 · %s" % [chapter["ch"], chapter["title"]], player.position + Vector2(0, -170), UI.C_ACCENT, 34)
		_popup(chapter["intro"], player.position + Vector2(0, -130), UI.C_TEXT, 22)
		if reverse:
			_popup("햇빛이 용암이야! 그늘로만 다녀!", player.position + Vector2(0, -95), UI.C_ACCENT, 24)
		_popup(_goal_text(), player.position + Vector2(0, -60), UI.C_TEXT, 20)


func _process(delta: float) -> void:
	_update_slowmo()
	if state == State.PLAY and Input.is_action_just_pressed("pause"):
		_set_paused(not paused)
	if paused:
		return
	if state == State.PLAY and Input.is_action_just_pressed("restart"):
		_restart()
		return

	if state == State.PLAY:
		elapsed += delta
		day_time += delta
		invuln = maxf(0.0, invuln - delta)
		_step_player(delta)
	_update_sun()
	_update_crossings(delta)
	_update_traffic(delta)
	_generate_until(camera.position.x + 1800.0)
	_update_trees()
	_update_npcs(delta)
	if state == State.PLAY:
		_update_friend(delta)
		if reverse:
			_check_reverse(delta)
		else:
			_check_player()
		_check_pickups()
		_update_combo(delta)
		_check_progress()
	for p in pickups:
		p.step(delta)
	player.sink = maxf(0.0, player.sink - delta * 1.4)
	imag.step(delta)
	splash.step(delta)
	_update_ambient(delta)
	_update_camera(delta)
	_update_depth()
	_update_drawers()
	weather.step(delta, camera.get_screen_center_position(), get_viewport_rect().size)
	if footprints:
		footprints.step(delta)
	_update_hud(delta)


# ───────────── 아이 조작 ─────────────

func _step_player(delta: float) -> void:
	var dir := Vector2.ZERO
	var jump := false
	if stun > 0.0:
		stun -= delta
	else:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		jump = Input.is_action_just_pressed("jump")
	var prev_x := player.position.x
	player.step(delta, dir, jump, Input.is_action_pressed("jump"), Input.is_action_pressed("run"))
	_resolve_obstacles(player)
	_block_red_crossing(prev_x, delta)
	# 무적 시간엔 깜빡임
	player.visible = invuln <= 0.0 or int(invuln * 12.0) % 2 == 0
	if player.stepped:
		sfx.play("step", rng.randf_range(0.85, 1.15), -10.0 if not player.running else -7.0)
		if footprints:
			footprints.add(player.position, 1.0 if int(player.walk_t / PI) % 2 == 0 else -1.0)


## 보행 신호가 빨간불이면 횡단보도에 들어갈 수 없다 (이미 건너는 중이면 마저 건넌다)
func _block_red_crossing(prev_x: float, delta: float) -> void:
	wait_hint_cd = maxf(0.0, wait_hint_cd - delta)
	for cr in crossings:
		if cr.ped_green():
			continue
		var zone := cr.walk_zone()
		var was_in := prev_x > zone.x and prev_x < zone.y
		var now_in := player.position.x > zone.x and player.position.x < zone.y
		if now_in and not was_in:
			player.position.x = zone.x if prev_x <= zone.x else zone.y
			player.vel.x = 0.0
			if wait_hint_cd <= 0.0:
				wait_hint_cd = 3.0
				_popup("빨간불! 그늘막에서 기다리자", player.position + Vector2(0, -100), UI.C_ACCENT, 22)


func _resolve_obstacles(p: Player) -> void:
	var foot := p.position
	for o in obstacles:
		if absf(o.rect.get_center().x - foot.x) > o.rect.size.x * 0.5 + 40.0:
			continue
		foot = o.push_out(foot, FOOT_R, p.vis_z())
	foot.y = clampf(foot.y, W.WALK_TOP, W.WALK_BOTTOM)
	foot.x = clampf(foot.x, 30.0, p.max_x)
	p.position = foot


# ───────────── 태양 / 시간 ─────────────

func _update_sun() -> void:
	var t: float
	if endless:
		t = clampf(day_time / DAY_LEN, 0.0, 0.97)
		hour = 7.0 + t * 12.0
	else:
		# 장마다 정해진 시간대 안에서 흐른다 (늦으면 그 뒤로도 계속 흐름)
		hour = chap_start + (chap_end - chap_start) * elapsed / time_limit
		t = clampf((hour - 7.0) / 12.0, 0.0, 0.97)
	var el := sin(PI * t) # 0: 해가 낮음, 1: 정오
	var len_y := lerpf(5.0, 2.4, el)
	if not endless:
		# 하굣길: 3시에도 승용차 그림자가 인도를 거의 다 덮고, 해질녘으로 갈수록 더 길어진다
		# (실제 해 높이대로면 3시엔 인도 아래쪽이 늘 안전해서 피하기만 하면 됨)
		# 해질녘에도 x4.6까지만: 더 길면 먼 차선 그림자까지 인도를 다 덮어서 위협이 두 배가 된다
		len_y = lerpf(3.6, 4.6, clampf((hour - 15.0) / 3.5, 0.0, 1.0))
	sun = Vector2(-cos(PI * t) * 0.6, len_y * float(season["shadow_mul"]))
	var c: Color
	if endless:
		var morning := Color(1.0, 0.94, 0.86)
		var noon := Color(1.0, 1.0, 0.98)
		var evening := Color(1.0, 0.8, 0.66)
		c = (morning if t < 0.5 else evening).lerp(noon, el)
	else:
		c = _dusk_tint(hour)
	tint.color = c * Color(season["tint"])


## 하굣길 시간대별 빛: 오후의 맑은 빛 → 노을 → 해질녘
const DUSK_KEYS: Array[float] = [15.0, 16.3, 17.0, 17.5, 18.0, 18.5, 19.0]
const DUSK_COLORS: Array[Color] = [
	Color(1.0, 0.99, 0.96), Color(1.0, 0.96, 0.88), Color(1.0, 0.91, 0.78),
	Color(1.0, 0.85, 0.7), Color(1.0, 0.77, 0.64), Color(0.9, 0.72, 0.72), Color(0.78, 0.68, 0.78),
]


func _dusk_tint(h: float) -> Color:
	if h <= DUSK_KEYS[0]:
		return DUSK_COLORS[0]
	for i in range(1, DUSK_KEYS.size()):
		if h <= DUSK_KEYS[i]:
			var k := (h - DUSK_KEYS[i - 1]) / (DUSK_KEYS[i] - DUSK_KEYS[i - 1])
			return DUSK_COLORS[i - 1].lerp(DUSK_COLORS[i], k)
	return DUSK_COLORS[DUSK_COLORS.size() - 1]


## 이 장의 목표 ("3:40까지 문방구 거리로!")
func _goal_text() -> String:
	var ci := GameData.chapter_idx_of(GameData.stage_idx)
	if GameData.is_last_chapter(GameData.stage_idx):
		return "%s까지 집에 가자!" % GameData.hour_text(chap_end)
	return "%s까지 %s!" % [GameData.hour_text(chap_end), GameData.with_ro(GameData.CHAPTERS[ci + 1]["title"])]


# ───────────── 교차로 / 차 ─────────────

func _update_crossings(delta: float) -> void:
	for cr in crossings:
		if cr.step(delta) and cr.ped_green() and absf(cr.x0 - player.position.x) < 700.0 and state == State.PLAY:
			sfx.play("signal", 1.0, -6.0)
		# 골목 차는 큰길이 빨간불일 때만 나온다
		if cr.side_go() and absf(cr.x0 - camera.position.x) < 1500.0:
			cr.set_meta("side_timer", float(cr.get_meta("side_timer", 0.0)) - delta)
			if float(cr.get_meta("side_timer")) <= 0.0:
				cr.set_meta("side_timer", rng.randf_range(1.1, 2.2))
				_spawn_side_car(cr)


func _spawn_side_car(cr: Crossing) -> void:
	var up := rng.randf() < 0.5
	var car := Car.new()
	var kind: String = ["car", "car", "van", "bike"][rng.randi() % 4]
	car.setup(kind, rng, "side%d%s" % [cr.get_instance_id(), "u" if up else "d"], -1 if up else 1, true)
	car.max_speed *= speed_mul
	car.cur_speed = car.max_speed
	car.position = Vector2(cr.side_x(up), 950.0 if up else -350.0)
	car.set_meta("crossing", cr)
	for other in cars:
		if other.group == car.group and absf(other.axis_pos() - car.axis_pos()) < (other.length + car.length) * 0.5 + 40.0:
			car.free()
			return
	add_child(car)
	cars.append(car)


func _update_traffic(delta: float) -> void:
	_spawn_main_cars(delta)
	var groups := {}
	for car in cars:
		if not groups.has(car.group):
			groups[car.group] = []
		groups[car.group].append(car)

	# 골목 차가 교차로에 남아 있으면 큰길 차는 초록불이어도 기다린다
	for cr in crossings:
		cr.set_meta("busy", false)
	for car in cars:
		if car.vertical and car.has_meta("crossing"):
			var cr: Crossing = car.get_meta("crossing")
			if is_instance_valid(cr) and car.body_rect().intersects(Rect2(cr.x0, W.ROAD_TOP - 10.0, Crossing.WIDTH, W.ROAD_BOTTOM - W.ROAD_TOP + 20.0)):
				cr.set_meta("busy", true)

	var cx := camera.position.x
	var keep: Array[Car] = []
	for car in cars:
		var allowed := INF
		# 정류장에 서 있는 중
		if car.dwell > 0.0:
			car.dwell -= delta
			allowed = 0.0
			if car.dwell <= 0.0:
				car.cleared_stop = true
		# 앞차
		for other in groups[car.group]:
			if other == car or (other.axis_pos() - car.axis_pos()) * car.dir <= 0.0:
				continue
			allowed = minf(allowed, (other.rear() - car.front()) * car.dir - QUEUE_GAP)
		# 신호
		for cr in crossings:
			if car.vertical:
				if not car.group.begins_with("side%d" % cr.get_instance_id()) or cr.side_go():
					continue
				var d := (cr.side_stop_line(car.dir < 0) - car.front()) * car.dir
				if d >= -2.0:
					allowed = minf(allowed, d)
			elif not cr.main_go() or bool(cr.get_meta("busy", false)):
				var d := (cr.main_stop_line(car.lane) - car.front()) * car.dir
				# 노란불: 충분히 멀리 있는 차만 멈춘다
				if d >= -2.0 and (cr.phase != 1 or d > 50.0):
					allowed = minf(allowed, d)
		# 버스 정류장
		if car.stop_at < INF and not car.cleared_stop and car.dwell <= 0.0:
			var d := (car.stop_at - car.front()) * car.dir
			if d >= -2.0:
				allowed = minf(allowed, d)
				if d < 3.0 and car.cur_speed < 8.0:
					car.dwell = 5.0
					if absf(car.position.x - player.position.x) < 900.0:
						sfx.play("door", 1.0, -6.0)
		# 속도
		var desired := car.max_speed
		if allowed < INF:
			desired = minf(desired, maxf(0.0, allowed) * 2.5)
		if desired > car.cur_speed:
			car.cur_speed = minf(desired, car.cur_speed + Car.ACCEL * delta)
		else:
			car.cur_speed = desired
		var mv := car.cur_speed * delta
		if allowed < INF:
			mv = minf(mv, maxf(0.0, allowed))
		car.advance(mv)
		car.update_shadow(sun)
		car.queue_redraw()
		# 차가 아이 옆을 지나가는 순간 '쉬익'
		if not car.vertical and not car.passed and (car.position.x - player.position.x) * car.dir > 0.0:
			car.passed = true
			if state == State.PLAY and car.cur_speed > 60.0:
				var pitch := clampf(car.cur_speed / 360.0, 0.7, 1.3)
				if car.kind == "truck" or car.kind == "bus":
					pitch *= 0.7
				sfx.play("whoosh", pitch, -9.0 if car.lane == 1 else -14.0)
		var gone := car.position.y < -500.0 or car.position.y > 1150.0 if car.vertical else absf(car.position.x - cx) > 2400.0
		if gone:
			car.queue_free()
		else:
			keep.append(car)
	cars = keep


func _spawn_main_cars(delta: float) -> void:
	var pace := float(route["pace"])
	if endless:
		pace = lerpf(1.0, 0.45, clampf(elapsed / 180.0, 0.0, 1.0))
	# 근처 교차로가 빨간불이면 새 차를 들여보내지 않는다 (줄이 끝없이 길어지지 않게)
	var red_near := _red_light_near()
	for lane in 2:
		lane_timer[lane] -= delta
		if lane_timer[lane] > 0.0:
			continue
		if red_near:
			lane_timer[lane] = 0.3
			continue
		var in_convoy := convoy_left[lane] > 0
		var kind := ("car" if rng.randf() < 0.7 else "van") if in_convoy else _pick_kind()
		if _spawn_main_car(kind, lane) != null:
			if in_convoy:
				convoy_left[lane] -= 1
				lane_timer[lane] = 0.05
			else:
				lane_timer[lane] = rng.randf_range(1.4, 3.2) * pace + float(Car.KINDS[kind]["len"]) / 260.0
		else:
			lane_timer[lane] = 0.2

	# 배달 오토바이 (예고 없이 쌩)
	if bool(route["moto"]) and (not endless or elapsed > 40.0) and state == State.PLAY and not red_near:
		moto_timer -= delta
		if moto_timer <= 0.0:
			var gap: Array = route.get("moto_gap", [7.0, 13.0])
			moto_timer = rng.randf_range(float(gap[0]), float(gap[1]))
			if _spawn_main_car("moto", rng.randi() % 2) != null:
				sfx.play("moto", rng.randf_range(0.9, 1.1), -8.0)

	# 도전 모드 차량 행렬
	if endless and elapsed > 20.0:
		convoy_timer -= delta
		if convoy_timer <= 0.0:
			convoy_timer = rng.randf_range(30.0, 50.0)
			_start_convoy()


func _red_light_near() -> bool:
	for cr in crossings:
		if not cr.main_go() and absf(cr.x0 - camera.position.x) < 1600.0:
			return true
	return false


func _start_convoy() -> void:
	var lane := rng.randi() % 2
	convoy_left[lane] = rng.randi_range(4, 6)
	lane_timer[lane] = 0.0
	_warn("차가 줄지어 와요! 콤보 찬스! " + ("→" if lane == 0 else "←"))


func _pick_kind() -> String:
	var w: Dictionary = route["kinds"]
	if endless:
		w = {"bike": 3.0, "car": 5.0}
		if elapsed > 12.0:
			w["van"] = 2.5
		if elapsed > 30.0:
			w["truck"] = 2.0
		if elapsed > 55.0:
			w["bus"] = 1.4
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "car"


func _spawn_main_car(kind: String, lane: int, stop_at := INF) -> Car:
	var car := Car.new()
	var dir := -1 if lane == 0 else 1
	car.setup(kind, rng, "main%d" % lane, dir)
	car.max_speed *= speed_mul
	if reverse and lane == 1:
		# 같은 방향 차는 아이보다 느리게: 그림자를 끝까지 타고 갈 수 없고 앞 그림자로 옮겨 타야 한다
		car.max_speed *= 0.8
	car.cur_speed = car.max_speed
	car.lane = lane
	car.stop_at = stop_at
	car.position.y = W.LANE_Y[lane]
	var edge := _half_w() + 160.0 + car.length
	car.position.x = camera.position.x + (edge if dir < 0 else -edge)
	for other in cars:
		if other.group != car.group:
			continue
		if absf(other.position.x - car.position.x) < (other.length + car.length) * 0.5 + QUEUE_GAP + 10.0:
			car.free()
			return null
	add_child(car)
	cars.append(car)
	if kind == "truck" or kind == "bus":
		var name_kr := "트럭" if kind == "truck" else "버스"
		var text := ("%s 온다! →" if dir < 0 else "← %s 온다!") % name_kr
		if kind == "bus" and stop_at == INF:
			text += "  그늘로 숨어!"
		_warn(text)
		if state == State.PLAY:
			sfx.play("horn", 0.85 if kind == "truck" else 0.7, -3.0)
	return car


# ───────────── 맵 생성 ─────────────

func _place_fixed_features() -> void:
	for f in route["crossings"]:
		_add_crossing(roundf(length * float(f)))
	for f in route["bus_stops"]:
		_add_bus_stop(roundf(length * float(f)))
	marbles_total = int(route["marbles"])
	for i in marbles_total:
		var x := lerpf(600.0, length - 500.0, (i + 0.5) / marbles_total) + gen.randf_range(-150.0, 150.0)
		_add_pickup("marble", x, true)
	var n_conv := int(route["convoys"])
	for i in n_conv:
		convoy_points.append(length * (i + 1) / (n_conv + 1) + gen.randf_range(-300.0, 300.0))
	# 행인과 강아지는 길 곳곳에서 마주 온다
	for i in int(route["peds"]):
		_add_npc("ped", gen.randf_range(900.0, length - 200.0))
	for i in int(route["dogs"]):
		_add_npc("dog", gen.randf_range(1200.0, length - 200.0))


func _add_crossing(x: float) -> void:
	var cr := Crossing.new()
	cr.setup(x, gen.randi() % 3, season["snow"])
	cr.set_meta("side_timer", 0.5)
	add_child(cr)
	crossings.append(cr)
	ground.crossings.append(x)
	ground.queue_redraw()
	# 횡단보도 양쪽 그늘막: 빨간불을 기다리는 동안 멈춘 차 그림자를 피할 자리
	for ux in [x - UMBRELLA_GAP, x + Crossing.WIDTH + UMBRELLA_GAP]:
		var u := ShadeTree.new()
		u.setup_umbrella(ux, x + Crossing.WIDTH * 0.5)
		add_child(u)
		trees.append(u)


func _add_bus_stop(x: float) -> void:
	_put_obstacle(Obstacle.make("shelter", x, gen, season["snow"]))
	_put_obstacle(Obstacle.make("sign", x + 140.0, gen, season["snow"]))
	bus_stops.append({"x": x, "used": false})


func _put_obstacle(o: Obstacle) -> void:
	add_child(o)
	obstacles.append(o)
	o.z_index = _zy(o.rect.end.y)


func _add_npc(kind: String, x: float) -> void:
	var n := Npc.new()
	n.setup(kind, Vector2(x, gen.randf_range(W.WALK_TOP + 20.0, W.WALK_BOTTOM - 20.0)), gen)
	add_child(n)
	npcs.append(n)


## 교차로·정류장 근처는 비워 둔다
func _blocked(x0: float, x1: float) -> bool:
	if x0 < 520.0 or x1 > length - 420.0:
		return true
	for cr in crossings:
		if x1 > cr.x0 - 120.0 and x0 < cr.x0 + Crossing.WIDTH + 120.0:
			return true
	for bs in bus_stops:
		if x1 > float(bs["x"]) - 80.0 and x0 < float(bs["x"]) + 220.0:
			return true
	return false


func _free_spot(x: float, near_curb: bool) -> Vector2:
	for i in 12:
		var p := Vector2(x + gen.randf_range(-40.0, 40.0),
				gen.randf_range(352.0, 384.0) if near_curb else gen.randf_range(W.WALK_TOP + 14.0, W.WALK_BOTTOM - 10.0))
		var ok := true
		for o in obstacles:
			if o.rect.grow(22.0).has_point(p):
				ok = false
				break
		if ok:
			return p
	return Vector2(INF, INF)


func _add_pickup(kind: String, x: float, near_curb: bool) -> void:
	var p := _free_spot(x, near_curb)
	if p.x == INF:
		return
	var pk := Pickup.new()
	pk.setup(kind, p, gen)
	add_child(pk)
	pickups.append(pk)


func _generate_until(limit: float) -> void:
	if not endless:
		limit = minf(limit, length)
	while gen_x < limit:
		var x := gen_x
		gen_x += 400.0
		if endless:
			if x >= next_crossing_x:
				_add_crossing(x + 100.0)
				next_crossing_x = x + gen.randf_range(3000.0, 5000.0)
				continue
			if x >= next_bus_x and not _blocked(x, x + 300.0):
				_add_bus_stop(x + 100.0)
				next_bus_x = x + gen.randf_range(3500.0, 6000.0)
				continue
		if _blocked(x, x + 400.0):
			continue
		# 장애물 (한 구간에 하나, 긴 장애물 뒤는 비워 둔다)
		var prob := float(route["obstacles"])
		if endless:
			prob = lerpf(0.3, 0.75, clampf(elapsed / 120.0, 0.0, 1.0))
		var ox := x + gen.randf_range(20.0, 180.0)
		if ox > gen_skip_until and gen.randf() < prob:
			_try_obstacle(ox)
		# 동전
		var coin_prob := 0.35 if endless else float(route["coins"]) / maxf(1.0, (length - 1000.0) / 400.0)
		var cp := coin_prob
		while cp > 0.0:
			if gen.randf() < cp:
				_add_pickup("coin", x + gen.randf_range(40.0, 360.0), false)
			cp -= 1.0
		# 도전 모드 행인
	# 나무
	while next_tree_x < minf(limit, length - 250.0):
		var tx := next_tree_x
		next_tree_x += gen.randf_range(float(route["trees"][0]), float(route["trees"][1]))
		var spot := Rect2(tx - 34.0, W.SIDEWALK_TOP, 68.0, 44.0)
		var ok := true
		for cr in crossings:
			if cr.contains_x(tx, UMBRELLA_GAP + 140.0): # 그늘막 자리는 비워 둔다
				ok = false
		for o in obstacles:
			if o.rect.intersects(spot):
				ok = false
		if ok:
			var t := ShadeTree.new()
			t.setup(tx, gen, season)
			add_child(t)
			trees.append(t)


func _try_obstacle(x: float) -> void:
	var kinds := ["pole", "pole", "trash", "trash", "trash", "bike", "bike", "flowerbed", "flowerbed", "construction"]
	var kind: String = kinds[gen.randi() % kinds.size()]
	var o := Obstacle.make(kind, x, gen, season["snow"])
	if _blocked(o.rect.position.x, o.rect.end.x):
		o.free()
		return
	for p in pickups:
		if o.rect.grow(24.0).has_point(p.position):
			o.free()
			return
	for t in trees:
		if o.rect.intersects(Rect2(t.position.x - 34.0, W.SIDEWALK_TOP, 68.0, 44.0)):
			o.free()
			return
	_put_obstacle(o)
	gen_skip_until = o.rect.end.x + 80.0


func _update_trees() -> void:
	for t in trees:
		if absf(t.position.x - camera.position.x) > 1500.0:
			continue
		t.update_shade(sun)
		# 아이가 나무 아래로 가면 잎을 반투명하게
		var near := absf(player.position.x - t.position.x) < t.radius + 16.0 \
				and player.position.y < W.SIDEWALK_TOP + 70.0
		t.modulate.a = lerpf(t.modulate.a, 0.45 if near else 1.0, 0.15)


# ───────────── 행인 / 강아지 / 친구 ─────────────

func _update_npcs(delta: float) -> void:
	if endless and state == State.PLAY:
		npc_timer -= delta
		if npc_timer <= 0.0:
			npc_timer = rng.randf_range(6.0, 12.0)
			var n := Npc.new()
			n.setup("dog" if rng.randf() < 0.3 else "ped",
					Vector2(camera.position.x + _half_w() + 120.0, rng.randf_range(W.WALK_TOP + 20.0, W.WALK_BOTTOM - 20.0)), rng)
			n.dir = -1.0
			add_child(n)
			npcs.append(n)
	var cx := camera.position.x
	var keep: Array[Npc] = []
	for n in npcs:
		if absf(n.position.x - cx) < 1500.0:
			n.step(delta, obstacles)
			if state == State.PLAY:
				_npc_contact(n)
		if n.position.x < cx - 2200.0 or n.position.x < -200.0:
			n.queue_free()
		else:
			keep.append(n)
	npcs = keep


func _npc_contact(n: Npc) -> void:
	var foot := player.position
	if n.kind == "dog" and not n.barked and foot.distance_to(n.dog_pos()) < 110.0:
		n.barked = true
		n.bark_t = 0.9
		stun = 0.6
		events["dog"] += 1
		sfx.play("bark", rng.randf_range(0.95, 1.1), -2.0)
		_popup("깜짝!", foot + Vector2(0, -100), UI.C_ACCENT, 26)
	if n.bump_cd <= 0.0 and player.vis_z() < 25.0 and foot.distance_to(n.position) < 26.0:
		n.bump_cd = 1.5
		stun = 0.4
		events["bump"] += 1
		var away := (foot - n.position).normalized()
		if away == Vector2.ZERO:
			away = Vector2(-n.dir, 0)
		player.position += away * 30.0
		_resolve_obstacles(player)
		sfx.play("bump", 1.0, -3.0)
		_popup("앗, 죄송합니다!", foot + Vector2(0, -100), UI.C_SUB, 22)


## 친구: 아이 조금 앞에서 걸으며 그림자를 알아서 넘는다. 빨간불엔 기다린다.
func _update_friend(delta: float) -> void:
	if friend == null:
		return
	friend_hit_cd = maxf(0.0, friend_hit_cd - delta)
	var target_x := minf(player.position.x + 140.0, length + 20.0)
	var dx := target_x - friend.position.x
	var dir := Vector2(signf(dx) if absf(dx) > 30.0 else 0.0, 0.0)
	for cr in crossings:
		if not cr.ped_green() and friend.position.x > cr.x0 - 50.0 and friend.position.x < cr.x0 - 10.0 and dir.x > 0.0:
			dir.x = 0.0
	# 위아래 위치: 장애물을 피하고, 아이와 겹치지 않게
	var probe := friend.position + Vector2(signf(dx) * 40.0, 0)
	var want_y := 400.0 if player.position.y > 440.0 else 490.0
	for o in obstacles:
		if o.rect.grow(16.0).has_point(probe):
			want_y = o.rect.position.y - 20.0 if o.rect.position.y - 20.0 > W.WALK_TOP else o.rect.end.y + 20.0
	dir.y = clampf((want_y - friend.position.y) / 60.0, -1.0, 1.0)
	var jump := false
	if friend.z <= 0.0:
		for car in cars:
			var ahead := (car.position.x - friend.position.x) * car.dir < 0.0
			if ahead and W.dist_to_polygon(friend.position, car.shadow) < 16.0:
				jump = true
				break
	friend.step(delta, dir.limit_length(1.0) * 0.95, jump, true, false)
	_resolve_obstacles(friend)
	# 친구가 그림자를 밟으면 놀린다 (친구는 영향 없음, 거꾸로 놀이에선 안 함)
	if not reverse and friend.z <= 0.0 and friend_hit_cd <= 0.0:
		for car in cars:
			if car.shadow.size() >= 3 and Geometry2D.is_point_in_polygon(friend.position, car.shadow) and not _in_tree_shade(friend.position):
				friend_hit_cd = 3.0
				events["friend_hit"] += 1
				_popup("친구: 앗! 밟았다 ㅋㅋ", friend.position + Vector2(0, -100), UI.C_SUB, 18)
				break


# ───────────── 판정 ─────────────

func _in_tree_shade(p: Vector2) -> bool:
	return _shade_at(p) != null


## 발밑의 나무 그늘·그늘막 (없으면 null)
func _shade_at(p: Vector2) -> ShadeTree:
	for t in trees:
		if absf(t.position.x - p.x) < 220.0 and Geometry2D.is_point_in_polygon(p, t.shade):
			return t
	return null


func _check_player() -> void:
	var foot := player.position
	var was_in_shade := in_shade
	in_shade = _in_tree_shade(foot)
	if in_shade and not was_in_shade:
		sfx.play("shade", rng.randf_range(0.9, 1.1), -6.0)

	var air := player.is_airborne()
	for car in cars:
		if car.shadow.size() < 3:
			continue
		# 골목 차는 차체에 부딪혀도 아웃
		if car.vertical and invuln <= 0.0 and car.body_rect().grow(4.0).has_point(foot):
			_on_hit(true)
			return
		if air:
			if Geometry2D.is_point_in_polygon(foot, car.shadow):
				air_cleared[car.get_instance_id()] = car
		elif not in_shade and invuln <= 0.0 and _foot_hits(foot, car.shadow):
			_on_hit(false)
			return

	if pending_land:
		pending_land = false
		_resolve_landing()


## 거꾸로 놀이: 그늘(차 그림자·나무 그늘) 밖 햇빛에 서 있으면 더위가 찬다
func _check_reverse(delta: float) -> void:
	var foot := player.position
	var cool := _cool_at(foot)
	var was_in_shade := in_shade
	in_shade = cool[0] != ""
	if in_shade and not was_in_shade and player.heat > 0.3:
		sfx.play("shade", rng.randf_range(0.9, 1.1), -6.0)
	for car in cars:
		if car.vertical and invuln <= 0.0 and car.body_rect().grow(4.0).has_point(foot):
			_on_hit(true)
			return
	if not player.is_airborne() and invuln <= 0.0:
		if in_shade:
			player.heat = maxf(0.0, player.heat - delta / HEAT_DOWN)
		else:
			player.heat = minf(1.0, player.heat + delta / HEAT_UP)
			heat_snd -= delta
			if heat_snd <= 0.0 and player.heat > 0.25:
				heat_snd = 0.35
				sfx.play("sizzle", 1.4, -16.0 + player.heat * 8.0)
		if player.heat >= 1.0:
			player.heat = 0.35
			_on_hit(false)
			return
	# 버스·트럭 그림자를 타고 가는 시간 (일기용)
	var cid: String = cool[0]
	if cid.begins_with("car:"):
		var c = instance_from_id(int(cid.substr(4)))
		if is_instance_valid(c) and (c.kind == "bus" or c.kind == "truck"):
			events["ride"] += delta
	if pending_land:
		pending_land = false
		if not in_shade and invuln <= 0.0:
			# 햇빛 위에 착지하면 발바닥이 확 덴다 (점프 연타로 햇빛을 건너는 것 방지)
			player.heat = minf(1.0, player.heat + 0.3)
			sfx.play("sizzle", 1.6, -8.0)
			splash.burst(foot, Imagination.THEMES["lava"]["hi"], 5, 200.0)
			if player.heat >= 1.0:
				player.heat = 0.35
				_on_hit(false)
				return
		_resolve_hop()


## 발밑의 그늘: [아이디, 다각형]. 햇빛이면 ["", 빈 다각형]
func _cool_at(p: Vector2) -> Array:
	for car in cars:
		if car.shadow.size() >= 3 and Geometry2D.is_point_in_polygon(p, car.shadow):
			return ["car:%d" % car.get_instance_id(), car.shadow]
	for t in trees:
		if absf(t.position.x - p.x) < 200.0 and Geometry2D.is_point_in_polygon(p, t.shade):
			return ["tree:%d" % t.get_instance_id(), t.shade]
	return ["", PackedVector2Array()]


## 다각형 테두리까지의 거리 (안쪽이어도 잰다)
func _edge_dist(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


## 거꾸로 놀이: 다른 그늘로 뛰어 옮겨 타면 점수
func _resolve_hop() -> void:
	var foot := player.position
	var dst := _cool_at(foot)
	var head := foot + Vector2(0, -100)
	if hop_src == "" or dst[0] == "" or dst[0] == hop_src:
		return
	events["hops"] += 1
	var near := _edge_dist(foot, dst[1]) < 14.0
	var old_mult := _combo_mult()
	combo += 1
	combo_timer = COMBO_TIME * 1.5
	events["max_combo"] = maxi(events["max_combo"], combo)
	var pts := 100.0 * _combo_mult() * (2.0 if near else 1.0)
	jump_score += int(pts)
	sfx.play("clear", 1.0 + 0.04 * mini(combo, 15), -2.0)
	_popup("옮겨 탔다! +%s" % UI.fmt(int(pts)), head, UI.C_GOLD if near else UI.C_TEXT, 24)
	if near:
		events["near"] += 1
		sfx.play("near")
		_popup("아슬아슬 착지! x2", head + Vector2(0, -32), UI.C_ACCENT, 30)
		_slowmo()
	if _combo_mult() > old_mult:
		sfx.play("combo_up", 1.0, -1.0)
		_popup("배율 x%.1f!" % _combo_mult(), head + Vector2(0, -64), UI.C_ACCENT, 24)


func _foot_hits(foot: Vector2, poly: PackedVector2Array) -> bool:
	# 발 판정은 일부러 작게 (아슬아슬한 손맛)
	for off in [Vector2.ZERO, Vector2(7, 0), Vector2(-7, 0), Vector2(0, 3), Vector2(0, -3)]:
		if Geometry2D.is_point_in_polygon(foot + off, poly):
			return true
	return false


func _on_hit(by_car: bool) -> void:
	var th: Dictionary = Imagination.THEMES[imag.theme]
	if not by_car:
		# 상상 속 바다·용암에 풍덩
		player.sink = 1.0
		splash.burst(player.position, th["mid"], 18, 420.0)
		splash.burst(player.position, th["hi"], 8, 320.0)
		sfx.play("sizzle" if imag.theme == "lava" else "splash", 1.0, -2.0)
	if endless:
		_game_over()
		return
	hearts -= 1
	events["hits"] += 1
	invuln = INVULN_TIME
	combo = 0
	shake = 9.0
	sfx.play("hit", 1.0, -1.0)
	var text := "빵! 조심해!"
	if by_car:
		sfx.play("horn", 1.0, -4.0)
	elif reverse:
		text = "앗 뜨거! 그늘로!"
	else:
		text = {"lava": "앗 뜨거!", "sea": "풍덩! 상어다!", "swamp": "꾸르륵! 악어다!", "ice": "풍덩! 차가워!"}[imag.theme]
	_popup(text, player.position + Vector2(0, -100), UI.C_ACCENT, 30)
	if friend and not by_car and rng.randf() < 0.6:
		_popup("친구: ㅋㅋㅋ 빠졌다!", friend.position + Vector2(0, -100), UI.C_SUB, 18)
	if hearts <= 0:
		_end_stage(false)


func _on_jumped() -> void:
	sfx.play("jump", rng.randf_range(0.95, 1.05), -2.0)
	if reverse:
		hop_src = _cool_at(player.position)[0]
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
	var head := foot + Vector2(0, -100)
	if takeoff_in_shade or in_shade:
		air_cleared.clear()
		_popup("그늘 속 점프는 노카운트", head, UI.C_SUB, 18)
		return

	var near := false
	var n := 0
	for id in air_cleared:
		n += 1
		var car = air_cleared[id]
		if not is_instance_valid(car):
			continue
		if car.kind == "bus":
			events["bus"] = true
		if car.kind == "truck":
			events["truck"] = true
		var d := minf(W.dist_to_polygon(foot, car.shadow), float(takeoff_dist.get(id, INF)))
		if d < NEAR_DIST:
			near = true
	air_cleared.clear()

	var old_mult := _combo_mult()
	combo += n
	combo_timer = COMBO_TIME
	events["max_combo"] = maxi(events["max_combo"], combo)
	var pts := 100.0 * n * _combo_mult()
	if near:
		pts *= 2.0
		events["near"] += 1
	if n >= 2:
		pts *= 1.5
	jump_score += int(pts)
	sfx.play("clear", 1.0 + 0.04 * mini(combo, 15), -2.0)

	_popup("+%s" % UI.fmt(int(pts)), head, UI.C_GOLD if near else UI.C_TEXT, 26)
	if near:
		sfx.play("near")
		_popup("아슬아슬! x2", head + Vector2(0, -32), UI.C_ACCENT, 32)
		_slowmo()
		shake = 5.0
		# 발밑에서 상상 속 바다·용암이 튄다
		var th: Dictionary = Imagination.THEMES[imag.theme]
		splash.burst(foot, th["mid"], 9, 260.0)
		splash.burst(foot, th["hi"], 4, 220.0)
	if n >= 2:
		_popup("더블!" if n == 2 else "%d연속!" % n, head + Vector2(0, -64), UI.C_GOLD, 26)
	if _combo_mult() > old_mult:
		sfx.play("combo_up", 1.0, -1.0)
		_popup("배율 x%.1f!" % _combo_mult(), head + Vector2(0, -96), UI.C_ACCENT, 24)


func _combo_mult() -> float:
	return minf(1.0 + floorf(combo / 5.0) * 0.5, 4.0)


func _update_combo(delta: float) -> void:
	if combo <= 0:
		return
	combo_timer -= delta
	if combo_timer <= 0.0:
		if combo >= 5:
			_popup("콤보 끝", player.position + Vector2(0, -100), UI.C_SUB, 20)
			sfx.play("combo_end")
		combo = 0


func _check_pickups() -> void:
	var foot := player.position
	var keep: Array[Pickup] = []
	for p in pickups:
		if foot.distance_to(p.position) < 24.0 and player.vis_z() < 30.0:
			if p.kind == "marble":
				marbles_got += 1
				sfx.play("marble")
				_popup("구슬 %d/%d" % [marbles_got, marbles_total], p.position + Vector2(0, -60), Color("6f9fd8"), 22)
			else:
				coins_got += 1
				sfx.play("coin", rng.randf_range(0.97, 1.05), -4.0)
				_popup("+1", p.position + Vector2(0, -50), UI.C_GOLD, 20)
			p.queue_free()
		else:
			keep.append(p)
	pickups = keep


## 버스 정류장 / 차량 행렬 / 시간 / 도착
func _check_progress() -> void:
	var px := player.position.x
	for bs in bus_stops:
		if not bs["used"] and px > float(bs["x"]) - 1300.0 and px < float(bs["x"]):
			if _spawn_main_car("bus", 1, float(bs["x"]) + 120.0) != null:
				bs["used"] = true
				_warn("← 버스가 정류장에 서요! 그림자가 멈춰요")
	while not convoy_points.is_empty() and px > convoy_points[0]:
		convoy_points.pop_front()
		_start_convoy()
	if endless:
		return
	if not late and hour >= chap_end:
		late = true
		sfx.play("late", 1.0, -2.0)
		_popup("%s가 지났다! 서두르자!" % GameData.hour_text(chap_end), player.position + Vector2(0, -110), UI.C_ACCENT, 26)
	if px >= length + 20.0:
		_end_stage(true)


# ───────────── 끝 ─────────────

func _end_stage(cleared: bool) -> void:
	state = State.CLEAR if cleared else State.FAIL
	Engine.time_scale = 1.0
	player.visible = true
	var stars := [not late, events["hits"] == 0, marbles_got >= marbles_total]
	final_score = jump_score + coins_got * 10
	if cleared:
		final_score += hearts * 300 + (500 if not late else 0)
		GameData.record_clear(GameData.stage_idx, stars, final_score)
		sfx.play("fanfare")
		if friend:
			_popup("친구: 내일 봐~!", friend.position + Vector2(0, -100), UI.C_TEXT, 20)
	else:
		player.dead = true
		player.queue_redraw()
		sfx.play("fail")
	GameData.add_coins(coins_got)
	get_tree().create_timer(1.1).timeout.connect(_show_result.bind(cleared, stars))


func _game_over() -> void:
	state = State.OVER
	player.dead = true
	player.queue_redraw()
	shake = 12.0
	Engine.time_scale = 1.0
	final_score = _total_score()
	var new_best := final_score > GameData.endless_best()
	if new_best:
		GameData.set_endless_best(final_score)
	GameData.add_coins(coins_got)
	_popup("앗! 밟았다!", player.position + Vector2(0, -100), UI.C_ACCENT, 32)
	sfx.play("fail")
	get_tree().create_timer(0.9).timeout.connect(_show_endless_over.bind(new_best))


func _total_score() -> int:
	if endless:
		return jump_score + int(maxf(0.0, player.position.x - START_X) / 10.0)
	return jump_score


func _clock_text(h: float) -> String:
	var hh := int(h)
	var mm := int((h - hh) * 6.0) * 10
	var h12 := hh if hh <= 12 else hh - 12
	return "%s %d:%02d" % ["오전" if hh < 12 else "오후", h12, mm]


func _diary_text(cleared: bool) -> String:
	var lines: Array[String] = []
	match season_key:
		"spring":
			lines.append("벚꽃잎이 바람에 날렸다.")
		"summer":
			lines.append("매미가 맴맴 시끄럽게 울었다.")
		"autumn":
			lines.append("낙엽이 바스락바스락 굴러다녔다.")
		"winter":
			lines.append("하얀 눈이 소복소복 쌓였다.")
	match String(chapter.get("district", "")):
		"school":
			lines.append("교문을 나서자마자 그림자 놀이 시작!")
		"shops":
			lines.append("문방구 앞에서 뽑기 구경을 했다.")
		"construction":
			lines.append("공사장 아스팔트가 뜨끈뜨끈했다.")
		"market":
			lines.append("시장에서 떡볶이 냄새가 났다.")
		"park":
			lines.append("공원 그림자가 길게길게 늘어졌다.")
		"home":
			lines.append("해가 져서 하늘이 주황색이 됐다.")
	if reverse:
		lines.append("오늘은 거꾸로 놀이! 햇빛이 용암이었다.")
		if events["hops"] > 0:
			lines.append("그림자를 %d번이나 옮겨 탔다." % events["hops"])
		if events["ride"] > 3.0:
			lines.append("느릿느릿 버스랑 트럭 그림자를 타고 갔다.")
	else:
		lines.append("차 그림자는 오늘도 %s였다." % Imagination.THEMES[imag.theme]["name"])
		if events["bus"]:
			lines.append("버스 그림자를 뛰어넘었다! 엄청 길었다.")
		elif events["truck"]:
			lines.append("트럭 그림자도 넘었다.")
	if events["max_combo"] >= 8:
		lines.append("그림자를 %d개나 연달아 넘었다." % events["max_combo"])
	if events["near"] >= 3:
		lines.append("아슬아슬한 순간이 %d번이나 있었다." % events["near"])
	if events["dog"] > 0:
		lines.append("강아지가 '멍!' 하고 짖어서 깜짝 놀랐다.")
	if events["bump"] > 0:
		lines.append("어른이랑 부딪혀서 죄송하다고 했다.")
	if events["friend_hit"] > 0:
		lines.append("친구는 그림자를 %d번 밟았다. 히히." % events["friend_hit"])
	if cleared:
		if events["hits"] == 0:
			lines.append("오늘은 한 번도 안 데었다!" if reverse else "오늘은 그림자를 한 번도 안 밟았다!")
		else:
			lines.append(("햇빛에 %d번 데었다." if reverse else "그림자를 %d번 밟아 버렸다.") % events["hits"])
		if marbles_got >= marbles_total:
			lines.append("길에서 구슬을 전부 주웠다!")
		elif marbles_got > 0:
			lines.append("구슬을 %d개 주웠다." % marbles_got)
		var at_home := GameData.is_last_chapter(GameData.stage_idx)
		if at_home:
			if late:
				lines.append("늦게 들어가서 엄마한테 혼났다...")
			else:
				lines.append("%s에 집에 왔다. 엄마가 칭찬해 주셨다." % _clock_text(hour))
		else:
			var next_title: String = GameData.CHAPTERS[GameData.chapter_idx_of(GameData.stage_idx) + 1]["title"]
			if late:
				lines.append("늦어 버렸다! %s 발걸음을 재촉했다." % GameData.with_ro(next_title))
			else:
				lines.append("%s에 %s 들어섰다." % [_clock_text(hour), GameData.with_ro(next_title)])
	else:
		lines.append("그림자를 너무 많이 밟아서 넘어졌다. 다시 힘내서 가 보자.")
	while lines.size() > 6:
		lines.remove_at(2)
	return "\n".join(lines)


# ───────────── 결과 / 일시정지 화면 ─────────────

func _show_overlay(content: Control) -> void:
	for c in overlay_panel.get_children():
		c.queue_free()
	overlay_panel.add_child(content)
	overlay.visible = true


func _button_row(items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var first: Button = null
	for it in items:
		var b := UI.button(it[0], 20, 170.0)
		b.pressed.connect(it[1])
		b.pressed.connect(func() -> void: sfx.play("select"))
		row.add_child(b)
		if first == null:
			first = b
	if first:
		first.call_deferred("grab_focus")
	return row


func _show_result(cleared: bool, stars: Array) -> void:
	var st := GameData.stage()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	var title := UI.label(30, UI.C_ACCENT if cleared else UI.C_SUB, true, false)
	title.text = "%s 하굣길 · %d장 %s · 그림일기" % [season["name"], st["ch"], st["title"]]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	vb.add_child(hb)
	var pic := DiaryPicture.new()
	pic.custom_minimum_size = Vector2(360, 250)
	pic.hour = hour
	pic.season_key = season_key
	pic.late = late
	pic.cleared = cleared
	pic.at_home = GameData.is_last_chapter(GameData.stage_idx)
	if not pic.at_home:
		pic.place = GameData.CHAPTERS[GameData.chapter_idx_of(GameData.stage_idx) + 1]["title"]
	hb.add_child(pic)
	var text := UI.label(19, UI.C_TEXT, false, false)
	text.text = _diary_text(cleared)
	text.custom_minimum_size = Vector2(420, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_constant_override("line_spacing", 6)
	hb.add_child(text)

	if cleared:
		var star_label := UI.label(34, UI.C_GOLD, true, false)
		star_label.text = UI.stars_text(stars)
		star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(star_label)
		var why := UI.label(15, UI.C_SUB, false, false)
		why.text = "%s 전 도착 %s   ·   %s %s   ·   구슬 다 줍기 %s" % [
			GameData.hour_text(chap_end), "O" if stars[0] else "X", "한 번도 안 데기" if reverse else "한 번도 안 밟기",
			"O" if stars[1] else "X", "O" if stars[2] else "X"]
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(why)
	var sc := UI.label(18, UI.C_TEXT, true, false)
	sc.text = "점수 %s   ·   동전 +%d (모은 동전 %d)" % [UI.fmt(final_score), coins_got, GameData.coins()]
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sc)

	var items := []
	if cleared and GameData.stage_idx + 1 < GameData.stage_count():
		if GameData.is_last_chapter(GameData.stage_idx):
			var next_season: Dictionary = GameData.SEASONS[GameData.SEASON_ORDER[GameData.season_idx_of(GameData.stage_idx) + 1]]
			items.append(["%s 하굣길로" % next_season["name"], _go_next_day])
		else:
			items.append(["다음 장으로", _go_next_day])
	items.append(["다시 하기", _restart])
	items.append(["하굣길 지도", _go_menu.bind("diary")])
	vb.add_child(_button_row(items))
	_show_overlay(vb)


func _show_endless_over(new_best: bool) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	var title := UI.label(48, UI.C_ACCENT, true, false)
	title.text = "그림자를 밟았다!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var body := UI.label(20, UI.C_TEXT, false, false)
	body.text = "점수  %s\n최고  %s%s\n동전 +%d" % [UI.fmt(final_score), UI.fmt(GameData.endless_best()),
			"   신기록!" if new_best else "", coins_got]
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(body)
	vb.add_child(_button_row([["다시 하기", _restart], ["메뉴로", _go_menu.bind("main")]]))
	_show_overlay(vb)


func _set_paused(p: bool) -> void:
	paused = p
	Engine.time_scale = 1.0
	if not p:
		overlay.visible = false
		return
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	var title := UI.label(40, UI.C_TEXT, true, false)
	title.text = "잠깐 쉬는 중"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	var first := true
	for it in [["계속하기", _set_paused.bind(false)], ["다시 하기", _restart], ["나가기", _go_menu.bind("main" if endless else "diary")]]:
		var b := UI.button(it[0], 22)
		b.pressed.connect(it[1])
		col.add_child(b)
		if first:
			b.call_deferred("grab_focus")
			first = false
	vb.add_child(col)
	_show_overlay(vb)


func _go_next_day() -> void:
	GameData.stage_idx += 1
	GameData.route_idx = 0
	Menu.open_screen = "route"
	get_tree().change_scene_to_file("res://menu.tscn")


func _go_menu(screen: String) -> void:
	Engine.time_scale = 1.0
	Menu.open_screen = screen
	get_tree().change_scene_to_file("res://menu.tscn")


func _restart() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# ───────────── 연출 ─────────────

func _slowmo() -> void:
	Engine.time_scale = 0.35
	slowmo_until_ms = Time.get_ticks_msec() + 220


func _update_slowmo() -> void:
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() > slowmo_until_ms:
		Engine.time_scale = 1.0


func _update_camera(delta: float) -> void:
	var hw := _half_w()
	var target := maxf(player.position.x, hw)
	if not endless:
		target = minf(target, length + 300.0 - hw + 200.0)
	camera.position.x = lerpf(camera.position.x, target, 1.0 - exp(-5.0 * delta))
	shake = maxf(0.0, shake - 30.0 * delta)
	camera.offset = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake


func _zy(y: float) -> int:
	return clampi(int(y / 8.0), 0, 100)


## 위에서 내려다보는 시점이라 아래쪽(발 위치가 큰 것)이 앞에 그려진다
func _update_depth() -> void:
	player.z_index = _zy(player.position.y)
	if friend:
		friend.z_index = _zy(friend.position.y)
	for n in npcs:
		n.z_index = _zy(n.position.y + 2.0)
	for p in pickups:
		p.z_index = _zy(p.position.y)
	for car in cars:
		car.z_index = _zy(car.position.y + car.half_extents().y)


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
	ground.cam_x = cx
	ground.queue_redraw()

	# 상상 연출: 인도 위만 바다·용암으로 보인다
	var band := Imagination.sidewalk_band(cx - 1000.0, cx + 1000.0)
	imag.pools.clear()
	cover.polys.clear()
	if reverse:
		# 햇빛이 용암 → 인도 전체를 용암으로 칠하고, 그늘 자리는 땅으로 덮는다
		imag.pools.append(band)
		for car in cars:
			if car.shadow.size() >= 3:
				cover.polys.append_array(Geometry2D.intersect_polygons(car.shadow, band))
		for t in trees:
			if absf(t.position.x - cx) < 1100.0:
				cover.polys.append_array(Geometry2D.intersect_polygons(t.shade, band))
	else:
		var boxes: Array[Rect2] = []
		for car in cars:
			if car.shadow.size() < 3:
				continue
			for p in Geometry2D.intersect_polygons(car.shadow, band):
				imag.pools.append(p)
				var r := Rect2(p[0], Vector2.ZERO)
				for q in p:
					r = r.expand(q)
				boxes.append(r)
		# 나무 그늘은 안전한 땅으로 덮는다 (바다·용암과 겹칠 때만)
		for t in trees:
			if absf(t.position.x - cx) > 1100.0 or t.shade.size() < 3:
				continue
			var tr := Rect2(t.shade[0], Vector2.ZERO)
			for q in t.shade:
				tr = tr.expand(q)
			for b in boxes:
				if b.intersects(tr):
					cover.polys.append_array(Geometry2D.intersect_polygons(t.shade, band))
					break
	cover.queue_redraw()


func _update_ambient(delta: float) -> void:
	# 가까운 바다·용암에서 가끔 부글부글
	if state == State.PLAY and not reverse:
		bubble_timer -= delta
		if bubble_timer <= 0.0:
			bubble_timer = rng.randf_range(1.5, 3.0)
			for p in imag.pools:
				if W.dist_to_polygon(player.position, p) < 120.0:
					sfx.play("bubble", rng.randf_range(0.8, 1.2), -15.0)
					break
	if season["ambient"] != "bird":
		return
	bird_timer -= delta
	if bird_timer <= 0.0:
		bird_timer = rng.randf_range(4.0, 9.0)
		sfx.play("bird" if rng.randf() < 0.5 else "bird2", rng.randf_range(0.85, 1.2), rng.randf_range(-18.0, -12.0))


var _popup_ms := 0
var _popup_stack := 0


func _popup(text: String, pos: Vector2, color: Color, size: int) -> void:
	# 연달아 뜨는 글씨는 위로 쌓아서 겹치지 않게
	var now := Time.get_ticks_msec()
	_popup_stack = _popup_stack + 1 if now - _popup_ms < 350 else 0
	_popup_ms = now
	pos.y -= _popup_stack * 30.0
	var l := UI.label(size, color, true)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(420, 50)
	l.position = pos - Vector2(210, 25)
	l.z_index = 130
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 50.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.4)
	tw.tween_callback(l.queue_free)


func _warn(text: String) -> void:
	warn_label.text = text
	warn_timer = 2.4


# ───────────── HUD ─────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	score_label = UI.label(38, UI.C_TEXT, true)
	score_label.position = Vector2(28, 10)
	root.add_child(score_label)
	best_label = UI.label(17, UI.C_SUB)
	best_label.position = Vector2(30, 58)
	root.add_child(best_label)
	hearts_label = UI.label(30, UI.C_ACCENT, true)
	hearts_label.position = Vector2(28, 80)
	hearts_label.visible = not endless
	root.add_child(hearts_label)
	items_label = UI.label(18, UI.C_TEXT, true)
	items_label.position = Vector2(30, 122 if not endless else 82)
	root.add_child(items_label)
	# 거꾸로 놀이 더위 게이지
	heat_bg = ColorRect.new()
	heat_bg.color = Color(0.25, 0.17, 0.12, 0.55)
	heat_bg.position = Vector2(76, 156)
	heat_bg.size = Vector2(160, 16)
	heat_bg.visible = reverse
	root.add_child(heat_bg)
	heat_fill = ColorRect.new()
	heat_fill.size = Vector2(0, 14)
	heat_bg.add_child(heat_fill)
	var heat_text := UI.label(14, UI.C_SUB, true)
	heat_text.text = "더위"
	heat_text.position = Vector2(-46, -6)
	heat_bg.add_child(heat_text)

	clock_label = UI.label(24, UI.C_TEXT, true)
	_wide_top(clock_label, 12)
	root.add_child(clock_label)
	sun_label = UI.label(16, UI.C_SUB)
	_wide_top(sun_label, 46)
	root.add_child(sun_label)

	combo_label = UI.label(30, UI.C_ACCENT, true)
	_right_top(combo_label, 10)
	root.add_child(combo_label)
	mult_label = UI.label(18, UI.C_GOLD, true)
	_right_top(mult_label, 50)
	root.add_child(mult_label)
	combo_bg = ColorRect.new()
	combo_bg.color = Color(0.3, 0.2, 0.15, 0.18)
	combo_bg.anchor_left = 1.0
	combo_bg.anchor_right = 1.0
	combo_bg.offset_left = -228
	combo_bg.offset_right = -28
	combo_bg.offset_top = 82
	combo_bg.offset_bottom = 90
	root.add_child(combo_bg)
	combo_fill = ColorRect.new()
	combo_fill.color = UI.C_ACCENT
	combo_fill.size = Vector2(200, 8)
	combo_bg.add_child(combo_fill)

	warn_label = UI.label(28, UI.C_ACCENT, true)
	_wide_top(warn_label, 96)
	root.add_child(warn_label)

	hide_label = UI.label(22, UI.C_SAFE, true)
	hide_label.text = "나무 그늘 · 안전해요"
	hide_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hide_label.offset_top = -104
	hide_label.offset_bottom = -74
	hide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hide_label)

	if not endless:
		progress = ProgressDraw.new()
		progress.from_text = chapter["title"]
		var ci := GameData.chapter_idx_of(GameData.stage_idx)
		progress.to_text = "집" if GameData.is_last_chapter(GameData.stage_idx) else GameData.CHAPTERS[ci + 1]["title"]
		progress.anchor_left = 0.5
		progress.anchor_right = 0.5
		progress.anchor_top = 1.0
		progress.anchor_bottom = 1.0
		progress.offset_left = -260
		progress.offset_right = 260
		progress.offset_top = -62
		progress.offset_bottom = -40
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(progress)

	var help := UI.label(14, UI.C_SUB)
	help.text = "이동 WASD·방향키   달리기 Shift   점프 Space (길게=멀리)   쉬기 Esc"
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -30
	help.offset_bottom = -8
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(help)

	overlay = CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	root.add_child(overlay)
	overlay_panel = PanelContainer.new()
	overlay_panel.add_theme_stylebox_override("panel", UI.panel_style())
	overlay.add_child(overlay_panel)


func _wide_top(l: Label, top: float) -> void:
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.offset_top = top
	l.offset_bottom = top + 34
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _right_top(l: Label, top: float) -> void:
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.offset_left = -380
	l.offset_right = -28
	l.offset_top = top
	l.offset_bottom = top + 40
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _update_hud(delta: float) -> void:
	var total := _total_score()
	score_label.text = UI.fmt(total)
	if endless:
		best_label.text = "도전 모드 · 최고 " + UI.fmt(maxi(GameData.endless_best(), total))
		items_label.text = "동전 %d" % coins_got
		clock_label.text = _clock_text(hour)
	else:
		best_label.text = "%s 하굣길 · %d장 %s (%s)" % [season["name"], chapter["ch"], chapter["title"], route["name"]]
		var h := ""
		for i in MAX_HEARTS:
			h += "♥" if i < hearts else "♡"
		hearts_label.text = h
		items_label.text = "구슬 %d/%d    동전 %d" % [marbles_got, marbles_total, coins_got]
		clock_label.text = "%s  /  %s" % [_clock_text(hour), _goal_text().trim_suffix("!")]
		var hurry := hour >= chap_end - (chap_end - chap_start) * 0.25
		clock_label.add_theme_color_override("font_color", UI.C_ACCENT if hurry else UI.C_TEXT)
		progress.frac = clampf((player.position.x - START_X) / (length - START_X), 0.0, 1.0)
		progress.queue_redraw()
	if sun.y > 4.0:
		sun_label.text = "그림자가 길어요"
	elif sun.y > 3.0:
		sun_label.text = "그림자 보통"
	else:
		sun_label.text = "그림자가 짧아요"
	if reverse:
		sun_label.text = "거꾸로 놀이 · 햇빛이 용암! 그늘로만 다녀요"
		heat_fill.size.x = 160.0 * player.heat
		heat_fill.color = Color("f2c14e").lerp(Color("e0503f"), player.heat)
	else:
		sun_label.text += "  ·  그림자는 %s!" % Imagination.THEMES[imag.theme]["name"]

	var show_combo := state == State.PLAY and combo > 0
	combo_label.visible = show_combo
	mult_label.visible = show_combo
	combo_bg.visible = show_combo
	if show_combo:
		combo_label.text = "%d 콤보" % combo
		mult_label.text = "점수 x%.1f" % _combo_mult()
		combo_fill.size = Vector2(200.0 * clampf(combo_timer / COMBO_TIME, 0.0, 1.0), 8)

	if reverse:
		# 거꾸로 놀이: 햇빛에 서 있으면 경고
		var hot := state == State.PLAY and not in_shade and not player.is_airborne()
		hide_label.visible = hot
		hide_label.text = "뜨거워! 그늘로!"
		hide_label.add_theme_color_override("font_color", UI.C_ACCENT)
		player.modulate = Color.WHITE
	else:
		hide_label.visible = state == State.PLAY and in_shade
		if in_shade:
			var st := _shade_at(player.position)
			hide_label.text = "그늘막 · 안전해요" if st != null and st.umbrella else "나무 그늘 · 안전해요"
		player.modulate = Color(0.82, 0.86, 0.92) if in_shade and state == State.PLAY else Color.WHITE

	warn_timer -= delta
	warn_label.visible = state == State.PLAY and warn_timer > 0.0 and fmod(warn_timer, 0.4) > 0.12


func _half_w() -> float:
	return get_viewport_rect().size.x * 0.5


func _setup_input() -> void:
	var map := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE, KEY_J],
		"run": [KEY_SHIFT, KEY_K],
		"pause": [KEY_ESCAPE, KEY_P],
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
