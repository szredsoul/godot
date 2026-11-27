class_name Upgrades
extends RefCounted
## 무기와 보조 능력. 레벨업 때 3장 중 1장을 고른다. 각각 최대 5단계, 무기·보조 능력은 5칸까지.

const MAX_LV := 5
const SLOTS := 5

const WEAPONS := {
	"brush": {"name": "붓 휘두르기", "char": "붓", "desc": [
		"바라보는 쪽으로 붓을 크게 휘두른다", "더 아프고 더 넓게", "앞뒤로 함께 휘두른다", "더 아프고 더 넓게", "훨씬 넓게 휘두른다"]},
	"drop": {"name": "먹 방울", "char": "방", "desc": [
		"가까운 요괴에게 먹 방울을 쏜다", "더 아프게", "두 발씩 쏜다", "한 마리를 뚫고 지나간다", "세 발씩 쏜다"]},
	"orbit": {"name": "먹 고리", "char": "고", "desc": [
		"먹 구슬 두 개가 몸 주위를 돈다", "구슬이 하나 늘어난다", "더 아프고 더 멀리 돈다", "구슬이 하나 늘어난다", "구슬이 하나 늘고 더 빨리 돈다"]},
	"seal": {"name": "낙관 도장", "char": "인", "desc": [
		"요괴 무리에 붉은 도장을 쾅 찍는다", "더 크고 더 아프게", "도장을 두 개씩 찍는다", "더 크고 더 아프게", "도장을 세 개씩 찍는다"]},
	"stroke": {"name": "한 획", "char": "획", "desc": [
		"요괴가 가장 많은 쪽으로 긴 획을 그어 한꺼번에 벤다", "더 자주 긋는다", "획이 길어진다", "더 자주, 더 아프게", "획이 훨씬 길고 굵어진다"]},
}

const PASSIVES := {
	"ink": {"name": "진한 먹", "char": "진", "desc": ["모든 피해 +10%"]},
	"hair": {"name": "새 붓털", "char": "털", "desc": ["무기가 8% 더 자주 나간다"]},
	"stone": {"name": "벼루", "char": "벼", "desc": ["공격 범위 +10%"]},
	"sandal": {"name": "짚신", "char": "짚", "desc": ["이동 속도 +8%"]},
	"pull": {"name": "먹 끌림", "char": "끌", "desc": ["구슬을 줍는 거리 +30%"]},
	"robe": {"name": "두루마기", "char": "두", "desc": ["최대 체력 +20%, 체력을 채운다"]},
}


static func info(id: String) -> Dictionary:
	return WEAPONS[id] if WEAPONS.has(id) else PASSIVES[id]


static func desc(id: String, next_lv: int) -> String:
	var d: Array = info(id)["desc"]
	return d[clampi(next_lv - 1, 0, d.size() - 1)]


## 레벨업 카드 3장
static func draw_cards(weapons: Dictionary, passives: Dictionary) -> Array[String]:
	var pool: Array[String] = []
	var weights: Array[float] = []
	for id in WEAPONS:
		var lv: int = weapons.get(id, 0)
		if lv == 0 and weapons.size() >= SLOTS or lv >= MAX_LV:
			continue
		pool.append(id)
		weights.append(1.3 if lv > 0 else 1.0)
	for id in PASSIVES:
		var lv: int = passives.get(id, 0)
		if lv == 0 and passives.size() >= SLOTS or lv >= MAX_LV:
			continue
		pool.append(id)
		weights.append(0.9)
	var out: Array[String] = []
	while out.size() < 3 and not pool.is_empty():
		var total := 0.0
		for w in weights:
			total += w
		var r := randf() * total
		for i in pool.size():
			r -= weights[i]
			if r <= 0.0:
				out.append(pool[i])
				pool.remove_at(i)
				weights.remove_at(i)
				break
	return out
