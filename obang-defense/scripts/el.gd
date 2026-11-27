class_name El
extends RefCounted
## 오행 규칙과 타워 수치, 부적 목록

const WOOD := 0
const FIRE := 1
const EARTH := 2
const METAL := 3
const WATER := 4

const NAMES: Array[String] = ["나무", "불", "흙", "쇠", "물"]
const TOWER: Array[String] = ["솟대", "봉화대", "장승", "종", "우물"]
## 오방색을 부드럽게 다듬은 색 (다섯 기운이 한눈에 구분되게)
const COL: Array[Color] = [Color("3fae6e"), Color("ee5b4b"), Color("f2b33d"), Color("c9d3df"), Color("4a63b8")]
const DARK: Array[Color] = [Color("2a7f4f"), Color("b93a2d"), Color("c28520"), Color("8b97a8"), Color("2e3f80")]

## 상생: GEN[a] = a가 살리는 기운 (나무→불→흙→쇠→물→나무)
const GEN: Array[int] = [FIRE, EARTH, METAL, WATER, WOOD]
## 상극: KE[a] = a가 깨뜨리는 기운 (나무→흙, 불→쇠, 흙→물, 쇠→나무, 물→불)
const KE: Array[int] = [EARTH, METAL, WATER, WOOD, FIRE]

const GEN_BONUS := 0.4 # 상생 이웃 하나마다 +40%
const KE_PENALTY := 0.4 # 상극 이웃 하나마다 −40%
const CYCLE_BONUS := 0.3 # 오행 순환에 든 타워 +30%
const LEVEL_BONUS := 0.35 # 단계마다 +35%

## 타워 기본 수치. dmg 피해, rate 공격 간격(초), range 사거리(px)
const STATS := [
	{"dmg": 7.0, "rate": 0.4, "range": 165.0},                  # 나무 솟대: 빠른 연사
	{"dmg": 16.0, "rate": 1.25, "range": 145.0, "splash": 62.0}, # 불 봉화대: 범위 화염
	{"dmg": 5.0, "rate": 1.3, "range": 125.0, "stun": 0.55},     # 흙 장승: 기절
	{"dmg": 4.0, "rate": 1.6, "range": 130.0, "slow": 0.35},     # 쇠 종: 주변 둔화
	{"dmg": 6.0, "rate": 1.2, "range": 145.0, "push": 46.0},     # 물 우물: 뒤로 밀기
]

## 규칙을 바꾸는 부적
const TALISMANS := {
	"earth_diag": {"name": "흙의 부적", "char": "토", "desc": "흙 타워는 대각선 칸도 이웃으로 친다"},
	"water_guard": {"name": "물의 부적", "char": "수", "desc": "물 타워는 상극으로 약해지지 않는다"},
	"kin": {"name": "같은 핏줄", "char": "동", "desc": "같은 기운끼리 이웃이면 서로 +20%"},
	"short_cycle": {"name": "짧은 순환", "char": "환", "desc": "오행 순환이 네 개만 이어져도 발동한다"},
	"strong_gen": {"name": "깊은 상생", "char": "생", "desc": "상생 효과가 +40%에서 +60%로"},
	"triple": {"name": "천적", "char": "극", "desc": "적을 상극으로 칠 때 피해 ×2 → ×3"},
}


## 타워 기운 t가 적 기운 x를 칠 때 배율
static func vs(t: int, x: int, triple: bool) -> float:
	if KE[t] == x:
		return 3.0 if triple else 2.0
	if GEN[t] == x:
		return 0.5
	return 1.0


static func font(bold := true) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"])
	f.font_weight = 700 if bold else 400
	return f
