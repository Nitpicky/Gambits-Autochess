class_name PvE
extends RefCounted
## Monster teams for PvE rounds. Pure data generators.

const MONSTERS: Array[StringName] = [&"stone_golem", &"saberspine", &"phase_hound", &"ice_golem", &"giant_crab"]


static func monster_team(round_no: int, rng: RandomNumberGenerator) -> Dictionary:
	var count: int
	var scale: float
	if round_no <= GameConfig.PVE_EARLY.size():
		count = GameConfig.PVE_EARLY[round_no - 1][0]
		scale = GameConfig.PVE_EARLY[round_no - 1][1]
	else:
		var n := maxi(0, (round_no - GameConfig.PVE_FROM) / GameConfig.PVE_EVERY)
		count = mini(6, GameConfig.PVE_LATE_COUNT + n)
		scale = GameConfig.PVE_LATE_SCALE + GameConfig.PVE_LATE_SCALE_STEP * n
	var units: Array = []
	var cells: Array = [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2]]
	for i in count:
		var id: StringName = MONSTERS[rng.randi() % MONSTERS.size()]
		if round_no > 3 and i == 0:
			id = &"sand_panther"
		units.append({"def": id, "row": cells[i][0], "col": cells[i][1], "scale": scale})
	return {"name": "Monsters", "units": units, "relics": []}
