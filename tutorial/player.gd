extends Area2D
signal hit

@export var speed = 400 # How fast the player will move (pixels/sec).
var screen_size # Size of the game window.
var target_position = Vector2.ZERO # 터치한 목표 지점 저장 변수
var is_moving = false

# Called when the node enters the scene tree for the first time.
func _ready():
	screen_size = get_viewport_rect().size
	# 시작할 때 화면 정중앙에 배치 (디펜스 게임 국룰)
	position = screen_size / 2
	target_position = position
	
func _input(event):
	# 화면을 터치했거나, 손가락을 댄 채로 드래그(ScreenDrag)할 때
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		target_position = event.position # 터치한 좌표를 목표물로 설정
		is_moving = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	# 터치한 곳이 있다면 그 방향으로 부드럽게 이동 (이동형 디펜스일 경우)
	if is_moving:
		var velocity = target_position - position
		
		# 목표 지점에 거의 도달했다면 정지
		if velocity.length() < 5:
			position = target_position
			is_moving = false
			$AnimatedSprite2D.stop()
		else:
			# 목표를 향해 이동 유도
			velocity = velocity.normalized() * speed
			position += velocity * delta
			$AnimatedSprite2D.play()
			
			# 터치한 방향(좌/우)에 따라 캐릭터 대칭 전환
			if velocity.x != 0:
				$AnimatedSprite2D.animation = "walk"
				$AnimatedSprite2D.flip_h = velocity.x < 0
	else:
		$AnimatedSprite2D.stop()
		
	# 화면 밖으로 이탈 방지
	position = position.clamp(Vector2.ZERO, screen_size)
	
	#var velocity = Vector2.ZERO # The player's movement vector.
	#if Input.is_action_pressed("move_right"):
		#velocity.x += 1
	#if Input.is_action_pressed("move_left"):
		#velocity.x -= 1
	#if Input.is_action_pressed("move_down"):
		#velocity.y += 1
	#if Input.is_action_pressed("move_up"):
		#velocity.y -= 1
#
	#if velocity.length() > 0:
		#velocity = velocity.normalized() * speed
		#$AnimatedSprite2D.play()
	#else:
		#$AnimatedSprite2D.stop()
	#
	#position += velocity * delta
	#position = position.clamp(Vector2.ZERO, screen_size)
	#
	#if velocity.x != 0:
		#$AnimatedSprite2D.animation = "walk"
		#$AnimatedSprite2D.flip_v = false
		#$AnimatedSprite2D.flip_h = velocity.x < 0
	#elif velocity.y != 0:
		#$AnimatedSprite2D.animation = "up"
		#$AnimatedSprite2D.flip_v = velocity.y > 0


func _on_body_entered(_body_):
	hide()
	hit.emit()
	$CollisionShape2D.set_deferred("disabled", true)

func start(pos):
	position = pos
	show()
	$CollisionShape2D.disabled = false
