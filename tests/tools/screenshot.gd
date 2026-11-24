extends SceneTree
## PROTOTYPE: walks one seeded game and saves a screenshot of every screen, for the screen notes board.
## Needs a display (e.g. xvfb-run). Usage:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 -s tests/tools/screenshot.gd -- /output/dir
## Gold is topped up for the human so later screens show a fuller board.

var out := "user://"
var main


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame  # let main._ready() start its own game first, then replace it
	main.new_game(4242)
	var m = main.match_ref
	await _frames(10)
	await _save("01_starter_pick")
	m.resolve_pick(main.me, 0)
	m.buy(main.me, 0)
	m.buy(main.me, 3)
	main.refresh()
	await _frames(5)
	if _pending("upgrade"):
		await _save("07_upgrade_pick")
		m.resolve_pick(main.me, 0)
	while not main.me.pending_picks.is_empty():
		m.resolve_pick(main.me, 0)
	main.refresh()
	await _frames(5)
	await _save("02_planning")
	main._on_unit(main.me.roster[0].uid)
	await _frames(5)
	await _save("03_planning_unit_selected")
	main.selected = {}
	main._on_ready()
	await _frames(60)
	await _save("04_battle_pve")
	await _results()
	await _save("05_round_results")
	main._clear_overlay()
	m.next_round()
	await _frames(5)
	if _pending("reward"):
		main.refresh()
		await _frames(5)
		await _save("06_pve_reward_pick")
	m.resolve_pick(main.me, 0)
	# Force an upgrade: buy a copy of an owned unit.
	main.me.add_gold(300)
	for i in 60:
		var idx := _owned_offer()
		if idx >= 0:
			m.buy(main.me, idx)
			break
		m.reroll(main.me)
	main.refresh()
	await _frames(5)
	if _pending("upgrade"):
		await _save("07_upgrade_pick")
	while not main.me.pending_picks.is_empty():
		m.resolve_pick(main.me, 0)
	# Play ahead until a PvP round with a fuller board.
	var battle_done := false
	var champ_done := false
	var reward_done := false
	for r in 60:
		if m.over:
			break
		main._clear_overlay()
		if _pending("reward") and not reward_done:
			main.refresh()
			await _frames(5)
			await _save("06_pve_reward_pick")
			reward_done = true
		if m.round_type == &"champion" and _pending("champion") and not champ_done:
			main.refresh()
			await _frames(5)
			await _save("09_champion_pick")
			champ_done = true
		main.me.add_gold(20)
		Bot.play(m, main.me)
		if m.round_type == &"pvp" and m.round_no >= 6 and not battle_done:
			main.refresh()
			await _frames(5)
			await _save("02b_planning_later")
			main._on_ready()
			await _frames(90)
			await _save("08_battle_pvp")
			battle_done = true
			main._clear_overlay()
		else:
			m.end_planning()
		if m.over:
			break
		m.next_round()
	main._clear_overlay()
	if m.last_report:
		main._show_summary(m.last_report, {})
		await _frames(5)
		await _save("10_game_over" if m.over else "10_late_results")
	m.dispose()
	quit()


func _results() -> void:
	main._clear_overlay()
	main._show_summary(main.match_ref.last_report, {})
	await _frames(5)


func _pending(kind: String) -> bool:
	return not main.me.pending_picks.is_empty() and main.me.pending_picks[0].kind == kind


func _owned_offer() -> int:
	for i in main.me.shop_offers.size():
		var o: Dictionary = main.me.shop_offers[i]
		if o.kind == &"unit" and not o.sold and not main.me.find_by_def(o.id).is_empty():
			return i
	return -1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join(shot_name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
