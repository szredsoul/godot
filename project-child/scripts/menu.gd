class_name Menu
extends Node2D
## 시작 화면: 메인 / 그림일기장(날짜 고르기) / 길 고르기 / 문방구(꾸미기)
## 키보드: 방향키로 고르고 Space·Enter로 선택, Esc로 뒤로

static var open_screen := "main" # 게임에서 돌아올 때 열 화면

var sfx: Sfx
var screen := "main"
var view_season := -1 # 하굣길 지도에서 보고 있는 계절
var panel: PanelContainer
var preview: Player
var kid: Player


func _ready() -> void:
	Engine.time_scale = 1.0
	var season: Dictionary = GameData.SEASONS["spring"]
	RenderingServer.set_default_clear_color(season["grass"])
	sfx = Sfx.new()
	add_child(sfx)

	# 배경: 봄날 하굣길
	var ground := Ground.new()
	ground.season = season
	ground.cam_x = 640.0
	ground.show_school = false
	ground.z_index = -20
	add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for x in [180.0, 720.0, 1180.0]:
		var t := ShadeTree.new()
		t.setup(x, rng, season)
		add_child(t)
	kid = Player.new()
	kid.apply_equipped()
	kid.position = Vector2(300, 470)
	add_child(kid)
	var friend := Player.new()
	friend.shirt_color = Color("f2c14e")
	friend.hat_color = Color("6f9fd8")
	friend.bag_color = Color("7fb36a")
	friend.position = Vector2(230, 440)
	add_child(friend)
	var cam := Camera2D.new()
	cam.position = Vector2(640, 360)
	add_child(cam)
	cam.make_current()
	var tint := CanvasModulate.new()
	tint.color = Color(1.0, 0.93, 0.85)
	add_child(tint)

	var layer := CanvasLayer.new()
	add_child(layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel_style())
	center.add_child(panel)

	# 지도는 게임에서 돌아오면 그 계절, 처음이면 가장 멀리 연 계절을 보여 준다
	view_season = GameData.season_idx_of(GameData.stage_idx)
	if open_screen == "main":
		for s in GameData.SEASON_ORDER.size():
			if GameData.is_unlocked(s * GameData.CHAPTERS.size()):
				view_season = s
	_show(open_screen)
	open_screen = "main"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		match screen:
			"diary", "shop":
				_show("main")
			"route":
				_show("diary")


func _show(s: String) -> void:
	screen = s
	for c in panel.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	match s:
		"diary":
			_build_diary(vb)
		"route":
			_build_route(vb)
		"shop":
			_build_shop(vb)
		_:
			_build_main(vb)


func _title(vb: VBoxContainer, text: String, size := 40) -> void:
	var l := UI.label(size, UI.C_ACCENT, true, false)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)


func _text(vb: Control, text: String, size := 18, color := UI.C_SUB) -> Label:
	var l := UI.label(size, color, false, false)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	return l


func _btn(parent: Control, text: String, cb: Callable, size := 22, min_w := 320.0) -> Button:
	var b := UI.button(text, size, min_w)
	b.pressed.connect(func() -> void: sfx.play("select"))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_main(vb: VBoxContainer) -> void:
	_title(vb, "그림자 밟기", 60)
	_text(vb, "하굣길, 자동차 그림자를 밟지 말고 집까지!", 20)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	vb.add_child(gap)
	var first := _btn(vb, "하굣길 (그림일기)", _show.bind("diary"), 24)
	_btn(vb, "도전 모드   ·   최고 %s" % UI.fmt(GameData.endless_best()), _start_endless)
	_btn(vb, "문방구 (꾸미기)   ·   동전 %d" % GameData.coins(), _show.bind("shop"))
	_btn(vb, "끝내기", get_tree().quit)
	first.call_deferred("grab_focus")


## 하굣길 지도: 위에 계절(회차) 탭, 아래에 6장
func _build_diary(vb: VBoxContainer) -> void:
	_title(vb, "하굣길 지도")
	_text(vb, "학교에서 집까지 6장. 장을 지날 때마다 해가 저물어요.")
	var n := GameData.CHAPTERS.size()
	# 계절 탭 (그 계절의 1장이 열려 있어야 고를 수 있다)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	for s in GameData.SEASON_ORDER.size():
		var sd: Dictionary = GameData.SEASONS[GameData.SEASON_ORDER[s]]
		var open := GameData.is_unlocked(s * n)
		var t := _btn(tabs, ("%s 하굣길" % sd["name"]) if open else "잠김", _pick_season.bind(s), 17, 130.0)
		t.disabled = not open
		if s == view_season:
			t.add_theme_stylebox_override("normal", UI.box(Color("fde3b8"), UI.C_ACCENT, 14, 3, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var focus: Button = null
	for c in n:
		var i := view_season * n + c
		var ch: Dictionary = GameData.CHAPTERS[c]
		var unlocked := GameData.is_unlocked(i)
		var text := "%d장\n%s\n%s~%s\n\n" % [ch["ch"], ch["title"], GameData.hour_text(ch["start"]), GameData.hour_text(ch["end"])]
		if unlocked:
			text += UI.stars_text(GameData.get_stars(i))
			var best := GameData.stage_best(i)
			text += "\n" + ("최고 %s" % UI.fmt(best) if best > 0 else "아직 안 감")
		else:
			text += "잠김"
		var b := _btn(row, text, _pick_stage.bind(i), 16, 160.0)
		b.custom_minimum_size = Vector2(160, 200)
		b.disabled = not unlocked
		if unlocked and not GameData.is_cleared(i) and focus == null:
			focus = b
	var back := _btn(vb, "뒤로", _show.bind("main"), 18, 160.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if focus == null:
		focus = row.get_child(0)
	focus.call_deferred("grab_focus")


func _pick_season(s: int) -> void:
	view_season = s
	_show("diary")


func _pick_stage(i: int) -> void:
	GameData.stage_idx = i
	_show("route")


func _build_route(vb: VBoxContainer) -> void:
	var st := GameData.stage()
	var season: Dictionary = GameData.SEASONS[GameData.season_key()]
	_title(vb, "%s 하굣길 · %d장 %s" % [season["name"], st["ch"], st["title"]], 32)
	_text(vb, "%s~%s  ·  어느 길로 갈까?" % [GameData.hour_text(st["start"]), GameData.hour_text(st["end"])])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	var first: Button = null
	for r in st["routes"].size():
		var rt: Dictionary = st["routes"][r]
		var feats: Array[String] = []
		if rt["crossings"].size() > 0:
			feats.append("신호등 %d" % rt["crossings"].size())
		if rt["bus_stops"].size() > 0:
			feats.append("버스 정류장")
		if int(rt["dogs"]) > 0:
			feats.append("강아지 %d" % int(rt["dogs"]))
		if rt["moto"]:
			feats.append("배달 오토바이")
		if int(rt["convoys"]) > 0:
			feats.append("차량 행렬")
		var text := "%s\n%s\n\n거리 %dm\n%s" % [rt["name"], rt["desc"], int(rt["length"]) / 20,
				" · ".join(feats) if not feats.is_empty() else "한적한 길"]
		var b := _btn(row, text, _start_stage.bind(r), 18, 300.0)
		b.custom_minimum_size = Vector2(300, 170)
		if first == null:
			first = b
	var back := _btn(vb, "뒤로", _show.bind("diary"), 18, 160.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	first.call_deferred("grab_focus")


func _build_shop(vb: VBoxContainer) -> void:
	_title(vb, "문방구")
	_text(vb, "길에서 주운 동전으로 모자와 가방을 바꿔요.   동전 %d" % GameData.coins(), 18, UI.C_TEXT)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	vb.add_child(hb)
	# 미리보기
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(170, 230)
	hb.add_child(holder)
	preview = Player.new()
	holder.add_child(preview)
	preview.position = Vector2(85, 200)
	preview.scale = Vector2(3.0, 3.0)
	preview.apply_equipped()

	var lists := VBoxContainer.new()
	lists.add_theme_constant_override("separation", 10)
	hb.add_child(lists)
	var first: Button = null
	for kind in ["hat", "bag"]:
		var table: Dictionary = GameData.HATS if kind == "hat" else GameData.BAGS
		var equipped := GameData.hat_id() if kind == "hat" else GameData.bag_id()
		_text(lists, "모자" if kind == "hat" else "가방", 18, UI.C_TEXT).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		lists.add_child(row)
		for id in table:
			var item_id := "%s:%s" % [kind, id]
			var state := "쓰는 중" if id == equipped else ("쓰기" if GameData.owns(item_id) else "동전 %d" % int(table[id]["price"]))
			var b := _btn(row, "%s\n%s" % [table[id]["name"], state], _shop_pick.bind(item_id), 15, 112.0)
			b.custom_minimum_size = Vector2(112, 64)
			if first == null:
				first = b
	var back := _btn(vb, "뒤로", _show.bind("main"), 18, 160.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	first.call_deferred("grab_focus")


func _shop_pick(item_id: String) -> void:
	if not GameData.owns(item_id):
		if not GameData.buy(item_id):
			sfx.play("bump")
			return
		sfx.play("buy")
	GameData.equip(item_id)
	kid.apply_equipped()
	_show("shop")


func _start_stage(r: int) -> void:
	GameData.mode = GameData.Mode.STAGE
	GameData.route_idx = r
	get_tree().change_scene_to_file("res://game.tscn")


func _start_endless() -> void:
	GameData.mode = GameData.Mode.ENDLESS
	get_tree().change_scene_to_file("res://game.tscn")
