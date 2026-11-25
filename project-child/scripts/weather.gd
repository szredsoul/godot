class_name Weather
extends Node2D
## 계절 효과: 봄 꽃잎, 가을 낙엽, 겨울 눈. 카메라 주변에서만 흩날린다.

var kind := ""
var parts: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var view := Rect2()


func setup(k: String) -> void:
	kind = k
	z_index = 120
	rng.randomize()


func _count() -> int:
	match kind:
		"snow":
			return 140
		"petal":
			return 45
		"leaf":
			return 32
	return 0


func step(delta: float, cam_center: Vector2, view_size: Vector2) -> void:
	if kind == "":
		return
	view = Rect2(cam_center - view_size * 0.5 - Vector2(60, 60), view_size + Vector2(120, 120))
	while parts.size() < _count():
		parts.append(_spawn(true))
	for p in parts:
		var wob := sin(p["ph"] + Time.get_ticks_msec() * 0.001 * p["freq"])
		p["pos"] += (p["vel"] + Vector2(wob * p["sway"], 0)) * delta
		p["rot"] += p["spin"] * delta
		var pos: Vector2 = p["pos"]
		# 화면 밖으로 나가면 반대편에서 다시
		if pos.y > view.end.y:
			pos.y = view.position.y
			pos.x = rng.randf_range(view.position.x, view.end.x)
		if pos.x < view.position.x:
			pos.x = view.end.x
		elif pos.x > view.end.x:
			pos.x = view.position.x
		p["pos"] = pos
	queue_redraw()


func _spawn(anywhere: bool) -> Dictionary:
	var pos := Vector2(rng.randf_range(view.position.x, view.end.x),
			rng.randf_range(view.position.y, view.end.y) if anywhere else view.position.y)
	var d := {"pos": pos, "rot": rng.randf() * TAU, "ph": rng.randf() * TAU, "freq": rng.randf_range(0.8, 2.0)}
	match kind:
		"snow":
			d["vel"] = Vector2(rng.randf_range(-15, 15), rng.randf_range(40, 90))
			d["sway"] = 20.0
			d["spin"] = 0.0
			d["size"] = rng.randf_range(1.8, 4.0)
		"petal":
			d["vel"] = Vector2(rng.randf_range(20, 60), rng.randf_range(30, 60))
			d["sway"] = 30.0
			d["spin"] = rng.randf_range(-3, 3)
			d["size"] = rng.randf_range(3.0, 5.0)
		_:
			d["vel"] = Vector2(rng.randf_range(10, 50), rng.randf_range(35, 70))
			d["sway"] = 40.0
			d["spin"] = rng.randf_range(-4, 4)
			d["size"] = rng.randf_range(5.0, 8.0)
			d["col"] = [Color("d97b3c"), Color("eba54a"), Color("c8643c"), Color("f2c14e")][rng.randi() % 4]
	return d


func _draw() -> void:
	for p in parts:
		var pos: Vector2 = p["pos"]
		var s: float = p["size"]
		match kind:
			"snow":
				draw_circle(pos, s, Color(1, 1, 1, 0.9), true, -1.0, true)
			"petal":
				draw_set_transform(pos, p["rot"], Vector2.ONE)
				draw_colored_polygon(W.ellipse(Vector2.ZERO, s, s * 0.55, 10), Color("f6c4d2"))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_:
				draw_set_transform(pos, p["rot"], Vector2.ONE)
				var col: Color = p["col"]
				draw_colored_polygon(W.ellipse(Vector2.ZERO, s, s * 0.5, 10), col)
				draw_line(Vector2(-s, 0), Vector2(s, 0), col.darkened(0.3), 1.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 겨울 눈 위 발자국
class Footprints extends Node2D:
	var marks: Array[Dictionary] = []

	func add(pos: Vector2, side: float) -> void:
		marks.append({"pos": pos + Vector2(0, side * 4.0), "t": 0.0})
		if marks.size() > 120:
			marks.pop_front()

	func step(delta: float) -> void:
		for m in marks:
			m["t"] += delta
		while not marks.is_empty() and marks[0]["t"] > 8.0:
			marks.pop_front()
		queue_redraw()

	func _draw() -> void:
		for m in marks:
			var a := clampf(1.0 - float(m["t"]) / 8.0, 0.0, 1.0) * 0.35
			draw_colored_polygon(W.ellipse(m["pos"], 5, 3, 10), Color(0.45, 0.55, 0.65, a))
