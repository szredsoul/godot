class_name Skills
extends RefCounted
## 붓 기술: 막을 마칠 때마다 3장 중 1장을 고른다. 같은 기술을 다시 고르면 레벨이 오른다.
## 효과는 arena.gd에서 skill_lv(id)로 읽어 적용한다.

## char: 도장에 새길 글자 / max: 최대 레벨 / weight: 나올 확률 가중치 / desc: 레벨별 설명
const ALL := {
	"bleed": {"name": "번짐", "char": "번", "max": 3, "weight": 10,
		"desc": ["한 획이 지나간 자리에 먹물이 4초 남아, 밟은 요괴가 느려지고 다친다",
			"먹물이 6초 남는다", "먹물이 8초 남고 더 아프다"]},
	"double": {"name": "겹획", "char": "겹", "max": 2, "weight": 8,
		"desc": ["멈춘 시간 동안 한 획을 한 번 더 그을 수 있다", "한 획을 세 번까지 그을 수 있다"]},
	"angle": {"name": "꺾음", "char": "꺾", "max": 3, "weight": 10,
		"desc": ["획이 크게 꺾인 자리마다 먹이 터진다", "터지는 범위가 넓어진다", "터지는 범위가 더 넓어지고 더 아프다"]},
	"seal": {"name": "낙관", "char": "인", "max": 3, "weight": 10,
		"desc": ["획이 끝나는 자리에 붉은 도장이 찍히며 터진다", "도장이 커진다", "도장이 더 커지고 보스에게 더 아프다"]},
	"ghost": {"name": "잔영", "char": "영", "max": 1, "weight": 6,
		"desc": ["0.6초 뒤 먹 그림자가 같은 획을 한 번 더 긋는다"]},
	"reflect": {"name": "되받아치기", "char": "반", "max": 1, "weight": 7,
		"desc": ["저스트를 하면 주변 먹 탄이 되돌아가 요괴를 친다"]},
	"fine": {"name": "세필", "char": "세", "max": 2, "weight": 8,
		"desc": ["획 길이 +40%, 대신 베는 폭이 좁아진다", "획 길이 +80%, 폭은 더 좁아진다"]},
	"broad": {"name": "굵은 붓", "char": "굵", "max": 2, "weight": 8,
		"desc": ["베는 폭 +60%, 대신 획이 짧아진다", "베는 폭 +120%, 획은 더 짧아진다"]},
	"inkwell": {"name": "먹 항아리", "char": "먹", "max": 3, "weight": 9,
		"desc": ["먹이 50% 더 잘 차고, 막마다 먹 30을 받는다", "먹이 100% 더 잘 찬다", "먹이 150% 더 잘 찬다"]},
	"slowink": {"name": "느린 먹", "char": "느", "max": 2, "weight": 8,
		"desc": ["멈춘 시간 +0.6초, 저스트 판정이 넉넉해진다", "멈춘 시간 +1.2초, 저스트 판정이 더 넉넉해진다"]},
	"chain": {"name": "연환", "char": "연", "max": 2, "weight": 8,
		"desc": ["셋째 베기가 앞으로 날아가는 먹 칼날을 쏜다", "먹 칼날이 커지고 더 아프다"]},
	"heal": {"name": "먹 보충", "char": "보", "max": 99, "weight": 7,
		"desc": ["체력을 2 채운다 (체력이 깎였을 때만 나온다)"]},
}


## 고를 카드 3장 (최대 레벨인 것은 빼고, 가중치대로)
static func draw_cards(owned: Dictionary, hp: int, max_hp: int, count := 3) -> Array[String]:
	var pool: Array[String] = []
	for id in ALL:
		var lv: int = owned.get(id, 0)
		if lv >= int(ALL[id]["max"]):
			continue
		if id == "heal" and hp >= max_hp:
			continue
		pool.append(id)
	var out: Array[String] = []
	while out.size() < count and not pool.is_empty():
		var total := 0.0
		for id in pool:
			total += float(ALL[id]["weight"])
		var r := randf() * total
		for id in pool:
			r -= float(ALL[id]["weight"])
			if r <= 0.0:
				out.append(id)
				pool.erase(id)
				break
	return out


static func desc_for(id: String, next_lv: int) -> String:
	var d: Array = ALL[id]["desc"]
	return d[clampi(next_lv - 1, 0, d.size() - 1)]
