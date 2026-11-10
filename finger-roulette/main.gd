extends Node2D

@onready var timer: Timer = $CountdownTimer
@onready var particles: CPUParticles2D = $WinParticles
@onready var guide_label: Label = $GuideLabel

# 테스트할 때는 1, 실제 모임 APK 추출 시에는 2로 변경하세요!
const MIN_PLAYERS: int = 2

var touches: Dictionary = {}
var winner_index: int = -1
var is_finished: bool = false
var pulse_time: float = 0.0

# 화려한 당첨 연출용 변수들
var flash_alpha: float = 0.0
var shake_strength: float = 0.0
var win_anim_time: float = 0.0

const NEON_COLORS: Array[Color] = [
	Color("#FF2A85"), # 네온 핑크
	Color("#00F0FF"), # 네온 시안
	Color("#39FF14"), # 네온 그린
	Color("#FFE600"), # 네온 옐로우
	Color("#B026FF"), # 네온 퍼플
	Color("#FF6B00"), # 네온 오렌지
	Color("#FF3131"), # 네온 레드
	Color("#1F51FF")  # 일렉트릭 블루
]

func _ready() -> void:
	DisplayServer.screen_set_keep_on(true)
	timer.timeout.connect(_on_countdown_timeout)
	guide_label.text = "화면에 손가락을\n모두 올려주세요!"

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if is_finished:
				_reset_game()
				return
			
			var color_idx: int = touches.size() % NEON_COLORS.size()
			touches[event.index] = {
				"pos": event.position,
				"color": NEON_COLORS[color_idx]
			}
			Input.vibrate_handheld(35)
			_restart_countdown_if_ready()
		else:
			if not is_finished and touches.has(event.index):
				touches.erase(event.index)
				_restart_countdown_if_ready()

	elif event is InputEventScreenDrag:
		if not is_finished and touches.has(event.index):
			touches[event.index]["pos"] = event.position

func _restart_countdown_if_ready() -> void:
	if touches.size() >= MIN_PLAYERS:
		timer.start()
		guide_label.text = "움직이지 마세요!\n추첨 중..."
	else:
		timer.stop()
		guide_label.text = "2명 이상 손가락을\n대면 시작합니다!"

func _on_countdown_timeout() -> void:
	if touches.size() < MIN_PLAYERS:
		return
	
	var keys: Array = touches.keys()
	winner_index = keys.pick_random()
	is_finished = true
	
	# 화려한 당첨 연출 트리거 시작!
	win_anim_time = 0.0
	flash_alpha = 0.85      # 화면 번쩍임 강도
	shake_strength = 38.0   # 화면 흔들림 강도
	
	var win_data: Dictionary = touches[winner_index]
	particles.position = win_data["pos"]
	particles.color = win_data["color"]
	particles.amount = 100  # 폭죽 입자 수 대폭 증가
	particles.restart()
	particles.emitting = true
	
	Input.vibrate_handheld(550) # 0.55초 강한 진동
	guide_label.text = "🎉 당첨! 🎉\n(화면을 터치하면 다시 시작)"

func _reset_game() -> void:
	touches.clear()
	winner_index = -1
	is_finished = false
	flash_alpha = 0.0
	shake_strength = 0.0
	pulse_time = 0.0      # <-- 이 줄을 추가해 깜빡임 속도를 처음으로 되돌립니다!
	win_anim_time = 0.0   # <-- 당첨 파동 시간도 함께 초기화합니다.
	position = Vector2.ZERO
	timer.stop()
	guide_label.text = "화면에 손가락을\n모두 올려주세요!"

func _process(delta: float) -> void:
	pulse_time += delta * 8.0
	
	# 1. 플래시 효과 서서히 감쇠
	if flash_alpha > 0.0:
		flash_alpha = max(0.0, flash_alpha - delta * 2.2)
		
	# 2. 화면 흔들림(쉐이크) 처리 및 복귀
	if shake_strength > 0.1:
		position = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
		shake_strength = lerp(shake_strength, 0.0, delta * 9.0)
	else:
		position = Vector2.ZERO
		
	if is_finished:
		win_anim_time += delta
		
	queue_redraw()

func _draw() -> void:
	# [상태 1] 당첨자 발표 화려한 연출
	if is_finished and touches.has(winner_index):
		var data: Dictionary = touches[winner_index]
		var pos: Vector2 = data["pos"]
		var col: Color = data["color"]
		
		# 배경을 더 어둡게 눌러 당첨자 스포트라이트 극대화
		draw_rect(Rect2(Vector2(-100, -100), Vector2(1400, 2400)), Color(0, 0, 0, 0.55))
		
		# 바깥으로 뻗어나가는 3중 충격파 파동 링
		for i in range(3):
			var wave_progress: float = fmod(win_anim_time * 1.4 + i * 0.33, 1.0)
			var wave_radius: float = lerp(120.0, 650.0, wave_progress)
			var wave_alpha: float = (1.0 - wave_progress) * 0.65
			draw_arc(pos, wave_radius, 0, TAU, 64, Color(col.r, col.g, col.b, wave_alpha), 12.0 * (1.0 - wave_progress), true)
		
		# 당첨자 주변 거대 네온 후광 및 회전 점선 링
		var pulse_r: float = 240.0 + sin(pulse_time * 1.5) * 25.0
		draw_circle(pos, pulse_r + 70.0, Color(col.r, col.g, col.b, 0.22))
		draw_arc(pos, pulse_r, 0, TAU, 64, col, 20.0, true)
		
		# 회전하는 8개의 스포트라이트 광선 점
		for j in range(8):
			var angle: float = win_anim_time * 3.0 + (TAU / 8.0) * j
			var orb_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * (pulse_r + 35.0)
			draw_circle(orb_pos, 14.0, Color.WHITE)
			draw_circle(orb_pos, 24.0, Color(col.r, col.g, col.b, 0.5))
		
		# 중앙 코어 원 (흰색 테두리 강조)
		draw_circle(pos, 145.0, Color.WHITE)
		draw_circle(pos, 130.0, col)
		
		# 순간 화이트 플래시 오버레이
		if flash_alpha > 0.0:
			draw_rect(Rect2(Vector2(-100, -100), Vector2(1400, 2400)), Color(1, 1, 1, flash_alpha))
		return

	# [상태 2] 카운트다운 진행 시 긴장감 연출 (시간이 임박할수록 원이 빠르게 진동)
	var urgency: float = 0.0
	if not timer.is_stopped() and timer.wait_time > 0:
		urgency = 1.0 - (timer.time_left / timer.wait_time) # 0.0 -> 1.0으로 증가

	for idx in touches.keys():
		var data: Dictionary = touches[idx]
		var pos: Vector2 = data["pos"]
		var col: Color = data["color"]
		
		# 카운트다운 막바지에는 손가락 원이 부르르 떨리며 커짐
		var jitter: Vector2 = Vector2.ZERO
		if urgency > 0.4:
			jitter = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (urgency * 10.0)
		
		var draw_pos: Vector2 = pos + jitter
		var pulse: float = sin(pulse_time * (1.0 + urgency * 2.0) + idx) * (14.0 + urgency * 12.0)
		var base_radius: float = 115.0 + pulse + (urgency * 20.0)
		
		draw_circle(draw_pos, base_radius + 40.0, Color(col.r, col.g, col.b, 0.25))
		draw_arc(draw_pos, base_radius + 16.0, 0, TAU, 48, col, 9.0, true)
		draw_circle(draw_pos, base_radius - 10.0, col)
