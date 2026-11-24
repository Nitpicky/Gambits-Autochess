class_name PvE
extends RefCounted
## Monster teams and PvE rewards. Pure data generators.

const MONSTERS: Array[StringName] = [&"stone_golem", &"saberspine", &"phase_hound", &"ice_golem", &"giant_crab"]


static func monster_team(round_no: int, rng: RandomNumberGenerator) -> Dictionary:
	var count: int
	var scale: float
	if round_no <= 3:
		count = [2, 3, 3][round_no - 1]
		scale = [0.45, 0.55, 0.7][round_no - 1]
	else:
		var n := (round_no - GameConfig.PVE_FROM) / GameConfig.PVE_EVERY
		count = mini(6, 4 + n)
		scale = 1.15 + 0.25 * n
	var units: Array = []
	var cells: Array = [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2]]
	for i in count:
		var id: StringName = MONSTERS[rng.randi() % MONSTERS.size()]
		if round_no > 3 and i == 0:
			id = &"sand_panther"
		units.append({"def": id, "row": cells[i][0], "col": cells[i][1], "scale": scale})
	return {"name": "Monsters", "units": units, "relics": []}


## Pick options for a PvE win.
static func reward_options(round_no: int, rng: RandomNumberGenerator, owned_relics: Array) -> Array:
	var early := round_no <= 3
	var opts: Array = []
	if early:
		opts.append({"kind": "gold", "amount": 10, "label": "10 gold"})
		opts.append({"kind": "item", "id": _random_item(rng, [5, 15]), "label": "Item"})
		opts.append({"kind": "xp", "amount": 6, "label": "6 XP"})
	else:
		var relics: Array = RelicCatalog.all().keys().filter(func(k): return not (k in owned_relics))
		if not relics.is_empty():
			opts.append({"kind": "relic", "id": relics[rng.randi() % relics.size()], "label": "Relic"})
		opts.append({"kind": "item", "id": _random_item(rng, [15, 25]), "label": "Item"})
		opts.append({"kind": "gold", "amount": 20, "label": "20 gold"})
	return opts


static func _random_item(rng: RandomNumberGenerator, prices: Array) -> StringName:
	var ids: Array = ItemCatalog.all().keys().filter(func(k): return ItemCatalog.get_def(k).price in prices)
	return ids[rng.randi() % ids.size()]
