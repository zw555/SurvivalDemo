class_name NoiseEvent
extends RefCounted
## 声响传播：把一次响动广播给半径内的所有丧尸。
## 声音可以穿过墙体（声波绕射的简化模型），只按半径衰减——
## 这让隔墙玩家开枪/挥砍会引来丧尸"前来调查"，但没有透视。
## 典型声源：近战挥击 240、枪声 520、手雷爆炸 600、丧尸受击惨叫 300。

const MELEE_LOUDNESS := 240.0
const GUNSHOT_LOUDNESS := 520.0
const EXPLOSION_LOUDNESS := 600.0
const SCREAM_LOUDNESS := 300.0


## 在 pos 处发出一次响动，半径内的丧尸会记住该声源位置并前往调查。
static func emit(host: Node, pos: Vector2, radius: float) -> void:
	if host == null or not host.is_inside_tree():
		return
	for node in host.get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie != null and zombie.global_position.distance_to(pos) <= radius:
			zombie.hear_noise(pos)
