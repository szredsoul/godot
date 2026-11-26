class_name GameData
extends RefCounted
## 스테이지·계절·꾸미기 데이터와 저장 (씬이 바뀌어도 static var는 유지된다)

enum Mode { STAGE, ENDLESS }

const SAVE_PATH := "user://save.cfg"
const OLD_BEST_PATH := "user://best_score.dat" # 예전 버전 최고 기록 (옮겨 온다)

static var mode: int = Mode.STAGE
static var stage_idx := 0
static var route_idx := 0
static var _cfg: ConfigFile = null

## 계절별 색과 규칙. canopy = [그늘쪽 진한색, 기본, 밝은색, 하이라이트]
const SEASONS := {
	"spring": {
		"name": "봄", "imag": "sea", "shadow_mul": 1.0, "particle": "petal", "ambient": "bird", "bare": false, "snow": false,
		"grass": Color("b7cf8e"), "hedge": Color("93b874"), "yard": Color("aac884"), "bush": Color("86ad68"),
		"canopy": [Color("d98ca2"), Color("e9a6b8"), Color("f3c4d0"), Color("fff0f3")],
		"tint": Color(1.0, 0.98, 0.97),
	},
	"summer": {
		"name": "여름", "imag": "lava", "shadow_mul": 0.85, "particle": "", "ambient": "cicada", "bare": false, "snow": false,
		"grass": Color("9fc77a"), "hedge": Color("7aa95e"), "yard": Color("92bd6c"), "bush": Color("6f9f55"),
		"canopy": [Color("557f47"), Color("68965a"), Color("80ad66"), Color("a9cb80")],
		"tint": Color(1.0, 1.0, 0.94),
	},
	"autumn": {
		"name": "가을", "imag": "swamp", "shadow_mul": 1.1, "particle": "leaf", "ambient": "bird", "bare": false, "snow": false,
		"grass": Color("c9c48a"), "hedge": Color("b5a865"), "yard": Color("c2b77c"), "bush": Color("b08a4a"),
		"canopy": [Color("b85a36"), Color("d97b3c"), Color("eba54a"), Color("f6d27a")],
		"tint": Color(1.0, 0.95, 0.89),
	},
	"winter": {
		"name": "겨울", "imag": "ice", "shadow_mul": 1.3, "particle": "snow", "ambient": "", "bare": true, "snow": true,
		"grass": Color("e6ecef"), "hedge": Color("cfdade"), "yard": Color("e9eef0"), "bush": Color("c4d2d6"),
		"canopy": [Color("8a6e5a"), Color("9c7f68"), Color("f4f8fa"), Color("ffffff")],
		"tint": Color(0.95, 0.97, 1.0),
	},
}

## 하굣길은 6개 장(챕터)으로 나뉜다. 장을 지날 때마다 시간대가 넘어간다 (오후 3시 → 해질녘 6시 반).
## 한 계절(회차)의 6장을 다 깨면 다음 계절 하굣길이 열린다: 봄 → 여름 → 가을 → 겨울.
## 진행 번호(stage_idx) = 계절 번호 × 6 + 장 번호 (0~23)
const SEASON_ORDER: Array[String] = ["spring", "summer", "autumn", "winter"]
const SEASON_PACE: Array[float] = [1.0, 0.92, 0.85, 0.8] # 계절이 지날수록 차가 조금씩 많아진다

## 장 설정 키
## start, end: 이 장의 시간대 (시, 소수) — end까지 다음 장소에 도착하면 별
## district: 길가 풍경 (school 학교·주택 / shops 가게 / construction 공사장 / market 시장 / park 공원 / home 주택가)
## "rule": "reverse"가 있으면 거꾸로 놀이 (햇빛이 용암, 그늘로만 다니기)
## 경로 설정 키
## length: 거리(px) / pace: 차 간격 배수(클수록 한산) / kinds: 차종 가중치
## trees: 나무 간격 범위 / obstacles: 400px당 장애물 확률 / peds, dogs: 행인·강아지 수
## crossings, bus_stops: 위치(전체 길이 대비 비율) / moto: 배달 오토바이 / convoys: 차량 행렬 횟수
## marbles: 구슬 수(별 조건) / coins: 동전 수 / speed_mul: 차 속도 배수(없으면 1)
const CHAPTERS := [
	{"ch": 1, "title": "학교 앞", "district": "school", "start": 15.0, "end": 15.67,
	 "intro": "학교 끝! 집에 가자", "routes": [
		{"name": "큰길", "desc": "짧지만 차가 많아요", "length": 5200, "pace": 1.0,
		 "kinds": {"bike": 3, "car": 5}, "trees": [600, 1000], "obstacles": 0.45,
		 "peds": 2, "dogs": 0, "crossings": [], "bus_stops": [], "moto": false, "convoys": 1,
		 "marbles": 5, "coins": 12},
		{"name": "골목길", "desc": "길지만 나무 그늘이 많아요", "length": 6600, "pace": 1.5,
		 "kinds": {"bike": 4, "car": 4}, "trees": [380, 700], "obstacles": 0.7,
		 "peds": 3, "dogs": 1, "crossings": [], "bus_stops": [], "moto": false, "convoys": 0,
		 "marbles": 5, "coins": 16},
	]},
	{"ch": 2, "title": "문방구 거리", "district": "shops", "start": 15.67, "end": 16.33,
	 "intro": "문방구 앞은 언제나 북적북적", "routes": [
		{"name": "큰길", "desc": "신호등 사거리를 지나가요", "length": 6000, "pace": 0.9,
		 "kinds": {"bike": 2, "car": 5, "van": 2}, "trees": [600, 1000], "obstacles": 0.5,
		 "peds": 4, "dogs": 0, "crossings": [0.5], "bus_stops": [], "moto": false, "convoys": 1,
		 "marbles": 5, "coins": 18},
		{"name": "골목길", "desc": "강아지 산책길, 장애물이 많아요", "length": 7400, "pace": 1.4,
		 "kinds": {"bike": 4, "car": 4, "van": 1}, "trees": [400, 750], "obstacles": 0.9,
		 "peds": 5, "dogs": 2, "crossings": [0.55], "bus_stops": [], "moto": false, "convoys": 0,
		 "marbles": 5, "coins": 22},
	]},
	{"ch": 3, "title": "공사장", "district": "construction", "start": 16.33, "end": 17.0, "rule": "reverse",
	 "intro": "새로 깐 아스팔트가 뜨거워! 오늘은 거꾸로 놀이", "routes": [
		{"name": "큰길", "desc": "퇴근길 정체! 느린 트럭 그림자를 타고 가요", "length": 5400, "pace": 0.7, "speed_mul": 0.5,
		 "kinds": {"car": 3, "van": 3, "truck": 4, "bus": 2}, "trees": [550, 950], "obstacles": 0.5,
		 "peds": 2, "dogs": 0, "crossings": [0.55], "bus_stops": [0.28], "moto": false, "convoys": 1,
		 "marbles": 5, "coins": 14},
		{"name": "골목길", "desc": "나무 그늘이 징검다리예요", "length": 6400, "pace": 1.0, "speed_mul": 0.55,
		 "kinds": {"car": 4, "van": 3, "truck": 2, "bus": 1}, "trees": [340, 620], "obstacles": 0.7,
		 "peds": 3, "dogs": 1, "crossings": [], "bus_stops": [], "moto": false, "convoys": 1,
		 "marbles": 5, "coins": 18},
	]},
	{"ch": 4, "title": "시장길", "district": "market", "start": 17.0, "end": 17.5,
	 "intro": "노을이 지기 시작한 시장길", "routes": [
		{"name": "큰길", "desc": "버스 정류장과 트럭이 있어요", "length": 6800, "pace": 0.85,
		 "kinds": {"bike": 2, "car": 5, "van": 3, "truck": 2}, "trees": [600, 1050], "obstacles": 0.55,
		 "peds": 5, "dogs": 1, "crossings": [0.65], "bus_stops": [0.35], "moto": false, "convoys": 2,
		 "marbles": 5, "coins": 16},
		{"name": "골목길", "desc": "시장 사람들로 붐벼요", "length": 8200, "pace": 1.3,
		 "kinds": {"bike": 4, "car": 4, "van": 2}, "trees": [420, 800], "obstacles": 1.0,
		 "peds": 8, "dogs": 2, "crossings": [0.6], "bus_stops": [], "moto": false, "convoys": 0,
		 "marbles": 5, "coins": 22},
	]},
	{"ch": 5, "title": "공원", "district": "park", "start": 17.5, "end": 18.0,
	 "intro": "그림자가 길어졌지만 공원엔 나무 그늘이 많아", "routes": [
		{"name": "큰길", "desc": "가끔 배달 오토바이가 쌩!", "length": 7000, "pace": 1.05, "moto_gap": [14, 22],
		 "kinds": {"bike": 1, "car": 5, "van": 2, "truck": 1}, "trees": [420, 760], "obstacles": 0.5,
		 "peds": 3, "dogs": 1, "crossings": [0.5], "bus_stops": [], "moto": true, "convoys": 1,
		 "marbles": 5, "coins": 18},
		{"name": "골목길", "desc": "공원 산책로, 나무 그늘 징검다리", "length": 8200, "pace": 1.45,
		 "kinds": {"bike": 2, "car": 5, "van": 2}, "trees": [300, 560], "obstacles": 0.7,
		 "peds": 4, "dogs": 3, "crossings": [0.5], "bus_stops": [], "moto": false, "convoys": 1,
		 "marbles": 5, "coins": 24},
	]},
	{"ch": 6, "title": "우리 동네", "district": "home", "start": 18.0, "end": 18.5,
	 "intro": "해가 진다! 저녁 먹기 전에 집으로", "routes": [
		{"name": "큰길", "desc": "그림자가 제일 긴 해질녘이에요", "length": 8000, "pace": 0.8,
		 "kinds": {"bike": 1, "car": 5, "van": 3, "truck": 2, "bus": 2}, "trees": [600, 1050], "obstacles": 0.6,
		 "peds": 4, "dogs": 1, "crossings": [0.3, 0.7], "bus_stops": [0.5], "moto": true, "convoys": 2,
		 "marbles": 5, "coins": 20},
		{"name": "골목길", "desc": "구불구불 동네 골목", "length": 9400, "pace": 1.15,
		 "kinds": {"bike": 2, "car": 5, "van": 2, "truck": 1}, "trees": [380, 720], "obstacles": 1.0,
		 "peds": 5, "dogs": 3, "crossings": [0.45], "bus_stops": [0.75], "moto": true, "convoys": 1,
		 "marbles": 5, "coins": 26},
	]},
]

const HATS := {
	"yellow": {"name": "노란 모자", "price": 0, "color": Color("f4c542"), "style": "cap"},
	"red": {"name": "빨간 모자", "price": 15, "color": Color("e0654f"), "style": "cap"},
	"blue": {"name": "파란 모자", "price": 15, "color": Color("6f9fd8"), "style": "cap"},
	"straw": {"name": "밀짚모자", "price": 30, "color": Color("e8c77a"), "style": "straw"},
	"beanie": {"name": "털모자", "price": 30, "color": Color("d98ca8"), "style": "beanie"},
}
const BAGS := {
	"red": {"name": "빨간 가방", "price": 0, "color": Color("e0654f")},
	"blue": {"name": "파란 가방", "price": 10, "color": Color("6f9fd8")},
	"green": {"name": "초록 가방", "price": 10, "color": Color("7fb36a")},
	"pink": {"name": "분홍 가방", "price": 15, "color": Color("e99ab4")},
	"yellow": {"name": "노란 가방", "price": 15, "color": Color("f2c14e")},
}


static func stage_count() -> int:
	return SEASON_ORDER.size() * CHAPTERS.size()


static func season_idx_of(i: int) -> int:
	return i / CHAPTERS.size()


static func chapter_idx_of(i: int) -> int:
	return i % CHAPTERS.size()


## 지금 고른 진행 번호의 계절 키 ("spring" 등)
static func season_key() -> String:
	return SEASON_ORDER[season_idx_of(stage_idx)]


## 지금 고른 장 설정
static func stage() -> Dictionary:
	return CHAPTERS[chapter_idx_of(stage_idx)]


static func route() -> Dictionary:
	return stage()["routes"][route_idx]


static func is_last_chapter(i: int) -> bool:
	return chapter_idx_of(i) == CHAPTERS.size() - 1


## 받침에 맞춰 '로/으로'를 붙인다 (거리로, 공사장으로)
static func with_ro(word: String) -> String:
	var code := word.unicode_at(word.length() - 1)
	if code < 0xAC00 or code > 0xD7A3:
		return word + "로"
	var jong := (code - 0xAC00) % 28
	return word + ("로" if jong == 0 or jong == 8 else "으로")


## 18.5 → "6:30"
static func hour_text(h: float) -> String:
	var hh := int(h)
	var mm := int(roundf((h - hh) * 60.0 / 10.0)) * 10
	if mm >= 60:
		hh += 1
		mm = 0
	return "%d:%02d" % [hh if hh <= 12 else hh - 12, mm]


# ───────────── 저장 ─────────────

static func cfg() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(SAVE_PATH) # 파일이 없으면 빈 상태로 시작
		# 예전 버전의 도전 모드 최고 기록을 옮겨 온다 (원본 파일은 그대로 둔다)
		if not _cfg.has_section_key("endless", "best") and FileAccess.file_exists(OLD_BEST_PATH):
			var f := FileAccess.open(OLD_BEST_PATH, FileAccess.READ)
			if f:
				_cfg.set_value("endless", "best", f.get_32())
				_cfg.save(SAVE_PATH)
	return _cfg


static func save() -> void:
	cfg().save(SAVE_PATH)


static func get_stars(i: int) -> Array:
	return cfg().get_value("stage", "stars_%d" % i, [false, false, false])


static func is_cleared(i: int) -> bool:
	return cfg().get_value("stage", "cleared_%d" % i, false)


static func is_unlocked(i: int) -> bool:
	return i == 0 or is_cleared(i - 1)


static func stage_best(i: int) -> int:
	return cfg().get_value("stage", "best_%d" % i, 0)


## 별은 지금까지 얻은 것과 합친다
static func record_clear(i: int, stars: Array, score: int) -> void:
	var old := get_stars(i)
	var merged := []
	for k in 3:
		merged.append(bool(old[k]) or bool(stars[k]))
	cfg().set_value("stage", "stars_%d" % i, merged)
	cfg().set_value("stage", "cleared_%d" % i, true)
	cfg().set_value("stage", "best_%d" % i, maxi(stage_best(i), score))
	save()


static func endless_best() -> int:
	return cfg().get_value("endless", "best", 0)


static func set_endless_best(v: int) -> void:
	cfg().set_value("endless", "best", v)
	save()


static func coins() -> int:
	return cfg().get_value("wallet", "coins", 0)


static func add_coins(n: int) -> void:
	cfg().set_value("wallet", "coins", coins() + n)
	save()


static func owns(item_id: String) -> bool:
	var parts := item_id.split(":") # "hat:red"
	var table: Dictionary = HATS if parts[0] == "hat" else BAGS
	if int(table[parts[1]]["price"]) == 0:
		return true
	return item_id in cfg().get_value("items", "owned", [])


static func buy(item_id: String) -> bool:
	var parts := item_id.split(":")
	var table: Dictionary = HATS if parts[0] == "hat" else BAGS
	var price: int = table[parts[1]]["price"]
	if owns(item_id) or coins() < price:
		return false
	var owned: Array = cfg().get_value("items", "owned", [])
	owned.append(item_id)
	cfg().set_value("items", "owned", owned)
	cfg().set_value("wallet", "coins", coins() - price)
	save()
	return true


static func hat_id() -> String:
	return cfg().get_value("items", "hat", "yellow")


static func bag_id() -> String:
	return cfg().get_value("items", "bag", "red")


static func equip(item_id: String) -> void:
	var parts := item_id.split(":")
	cfg().set_value("items", parts[0], parts[1])
	save()
