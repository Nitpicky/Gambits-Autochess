extends SceneTree
## Headless smoke test. Run with tests/run_smoke.sh (it also fails on any script error).
## Exits 0 when every check passes, 1 otherwise.

var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		failures.append(what)


func _init() -> void:
	print("== Attribute system")
	_test_attributes()
	print("== Battle")
	_test_battle()
	print("== Economy")
	_test_economy()
	print("== Full 8-bot game")
	_test_full_game(12345)
	_test_full_game(777)
	print("== UI scene")
	await _test_ui()
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED: ", failures)
		quit(1)


func _test_attributes() -> void:
	var h := AttributeHolder.new()
	h.add(Attribute.make_pool(&"hp", 100))
	h.get_attr(&"hp").add_flat(&"buff", 50)
	check(is_equal_approx(h.value(&"hp"), 150.0), "flat buff applies (100 -> 150)")
	check(is_equal_approx(h.current(&"hp"), 150.0), "current HP follows a max increase")
	h.get_attr(&"hp").add_flat(&"item", 25)
	check(is_equal_approx(h.value(&"hp"), 175.0), "flat buffs stack (100+50+25)")
	var steps_ok := true
	for id in UnitCatalog.all():
		steps_ok = steps_ok and int(UnitCatalog.get_def(id).hp) % GameConfig.HP_STEP == 0
	for id in ItemCatalog.all():
		steps_ok = steps_ok and int(ItemCatalog.get_def(id).stats.get("hp", 0)) % GameConfig.HP_STEP == 0
	check(steps_ok, "every unit and item HP is a multiple of %d" % GameConfig.HP_STEP)
	h.add(Effects.status(&"chill", 1))
	h.add(Effects.status(&"chill", 2))
	check(h.stacks(&"chill") == 3 and h.attributes.size() == 2, "second Chill merges into the first")
	h.dispose()


func _test_battle() -> void:
	var a := {"name": "A", "relics": [&"war_banner", &"sunforge_crest"], "units": [
		{"def": &"squire", "row": 0, "col": 0}, {"def": &"grand_templar", "row": 0, "col": 1, "items": [&"tower_shield", &"iron_band", &"phoenix_feather"]},
		{"def": &"acolyte", "row": 1, "col": 0, "items": [&"healing_charm"]}, {"def": &"sunforger", "row": 1, "col": 1}, {"def": &"winter_queen", "row": 1, "col": 2, "items": [&"glacier_heart"]}]}
	var b := {"name": "B", "relics": [&"abyssal_altar", &"hourglass"], "units": [
		{"def": &"bone_wraith", "row": 0, "col": 0, "items": [&"bone_charm"]}, {"def": &"lord_of_ruin", "row": 0, "col": 1, "items": [&"vampiric_fang", &"berserker_mask"]},
		{"def": &"night_fiend", "row": 0, "col": 2, "items": [&"mirror_blade", &"riposte_blade"]}, {"def": &"shadow_spawner", "row": 1, "col": 0, "items": [&"ritual_dagger"]},
		{"def": &"void_priestess", "row": 1, "col": 1, "level": 2, "cards": [{"hp": 50, "atk": 3, "pp": 1}]}]}
	var r := BattleSim.new().run(a, b, 42)
	check(r.winner in [-1, 0, 1], "battle resolves (winner %d in %d turns)" % [r.winner, r.turns])
	check(r.log.size() > 10 and r.log[r.log.size() - 1].t == "end", "battle log ends with an end event")
	var r2 := BattleSim.new().run(a, b, 42)
	check(r2.log.size() == r.log.size() and r2.winner == r.winner, "same seed gives the same battle")
	# Every unit, champion and item at least builds and fights once.
	var ids := UnitCatalog.all().keys()
	var items := ItemCatalog.all().keys()
	var ok := true
	for i in range(0, ids.size(), 5):
		var team: Array = []
		for k in 5:
			if i + k < ids.size():
				team.append({"def": ids[i + k], "row": k / 3, "col": k % 3, "items": [items[(i + k) % items.size()], items[(i + k + 7) % items.size()]], "level": 2,
					"cards": Upgrades.cards_for(ids[i + k], RandomNumberGenerator.new())})
		var rr := BattleSim.new().run({"name": "X", "units": team, "relics": RelicCatalog.all().keys()}, {"name": "Y", "units": team, "relics": []}, i)
		ok = ok and rr.winner in [-1, 0, 1]
	check(ok, "every unit/item/card/relic combination batch resolves")


func _test_economy() -> void:
	var p := PlayerState.new(0, "T", true)
	p.gold_style = &"interest"
	var inc := Economy.pay_income(p, 1)
	check(p.gold() == 30 and inc.interest == 0, "round 1 pays 30 flat")
	inc = Economy.pay_income(p, 2)
	check(inc.interest == 3 and p.gold() == 43, "Interest style: 1 per 10 banked (30 -> +3)")
	var q := PlayerState.new(1, "S", true)
	q.gold_style = &"bounty"
	q.set_gold(30)
	inc = Economy.pay_income(q, 2)
	check(inc.interest == 0 and Economy.pay_bounty(q, 3, 2) == 5, "Bounty style: no interest, +1 per kill and per survivor")
	q.dispose()
	Economy.add_xp(p, 4)
	check(p.rank() == 2 and p.xp() == 0, "4 XP reaches rank 2")
	p.set_streak(4)
	check(Economy.streak_bonus(p.streak()) == 4, "streak of 4 pays +4")
	check(Economy.reroll_cost(p) == 1, "first manual reroll costs 1")
	Shop.add_relic(p, &"lucky_coin")
	check(Economy.reroll_cost(p) == 0, "Lucky Coin makes it free")
	p.dispose()


func _test_full_game(seed_value: int) -> void:
	var m := Match.new()
	m.new_game(seed_value, false)
	var guard := 0
	var saw := {}
	while not m.over and guard < GameConfig.MAX_ROUNDS + 2:
		guard += 1
		saw[m.round_type] = true
		var rep := m.end_planning()
		for f in rep.fights:
			check_silent(f.winner in [-1, 0, 1])
		m.next_round()
	var alive := m.alive_players()
	check(m.over, "seed %d: game ends (round %d)" % [seed_value, m.round_no])
	check(alive.size() == 1 and alive[0].placement == 1, "seed %d: exactly one winner (%s)" % [seed_value, alive[0].display if alive.size() > 0 else "-"])
	check(saw.has(&"pve") and saw.has(&"pvp"), "seed %d: PvE and PvP rounds both happened" % seed_value)
	var styles := m.players.filter(func(p): return p.gold_style in GameConfig.GOLD_STYLES).size()
	check(styles == m.players.size(), "seed %d: every player has a gold style" % seed_value)
	var choice_held := 0
	for p in m.players:
		for u in p.roster:
			if UnitCatalog.get_def(u.def).choice_only:
				choice_held += 1
	print("     choice-only units held at end: ", choice_held)
	var champs := 0
	for p in m.players:
		for u in p.roster:
			if UnitCatalog.get_def(u.def).rarity == UnitCatalog.Rarity.CHAMPION:
				champs += 1
	print("     placements: ", m.players.map(func(p): return "%s#%d" % [p.display, p.placement]), " champions held at end: ", champs)
	m.dispose()


func check_silent(cond: bool) -> void:
	if not cond:
		failures.append("silent check")


func _test_ui() -> void:
	var scene: PackedScene = load("res://ui/main.tscn")
	check(scene != null, "main scene loads")
	if scene == null:
		return
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# Drive the UI: pick the gold style, buy, end the round, fast-forward the battle on the board.
	var ok: bool = await main.debug_autoplay_round()
	await process_frame
	check(ok, "UI plays one round (pick, buy, fight)")
	for i in 3:
		await main.debug_autoplay_round()
		await process_frame
	check(main.match_ref.round_no >= 4, "UI reaches round 4")
	main.match_ref.dispose()
	main.queue_free()
	await process_frame
	SpriteView._cache.clear()
