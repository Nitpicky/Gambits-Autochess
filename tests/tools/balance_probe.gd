extends SceneTree
## PROTOTYPE: random 5v5 roster fights; prints fight length, clock and per-faction win rates.
## Usage: godot --headless --path . -s tests/tools/balance_probe.gd


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var ids: Array = UnitCatalog.shop_units()
	var wins := {}
	var games := {}
	var rounds: Array = []
	var clocks: Array = []
	var warn := {}
	for n in 300:
		var teams: Array = []
		for s in 2:
			var fac: StringName = Keywords.FACTIONS[rng.randi() % 6]
			var pool := ids.filter(func(i): return UnitCatalog.get_def(i).faction == fac)
			var units: Array = []
			for k in 5:
				var id: StringName = pool[rng.randi() % pool.size()]
				var d := UnitCatalog.get_def(id)
				units.append({"def": id, "row": d.row if k < 4 else 1, "col": k % 3})
			# fix duplicate cells
			var used := {}
			for u in units:
				var c := Vector2i(u.row, u.col)
				while used.has(c):
					c = Vector2i((c.x + (1 if c.y == 2 else 0)) % 2, (c.y + 1) % 3)
				used[c] = true
				u.row = c.x
				u.col = c.y
			teams.append({"name": String(fac), "units": units, "relics": [], "fac": fac})
		var sim := BattleSim.new()
		var r := sim.run(teams[0], teams[1], n)
		rounds.append(r.turns)
		clocks.append(sim.clock)
		for s in 2:
			games[teams[s].fac] = games.get(teams[s].fac, 0) + 1
			if r.winner == s:
				wins[teams[s].fac] = wins.get(teams[s].fac, 0) + 1
	rounds.sort()
	clocks.sort()
	print("rounds median ", rounds[150], " max ", rounds[299], "  clock median ", clocks[150], " p90 ", clocks[270])
	for f in games:
		print(f, " ", wins.get(f, 0), "/", games[f])
	quit(0)
