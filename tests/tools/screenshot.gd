extends SceneTree
## PROTOTYPE: walks one seeded game and saves a screenshot of every screen state.
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
	main.timer_enabled = false
	var m = main.match_ref
	await _frames(10)
	await _save("01_gold_style_pick")
	main._on_pick(0)
	m.buy(main.me, 0)
	m.buy(main.me, 1)
	main.refresh()
	await _frames(5)
	await _save("02_planning")
	main._select_unit(main.me.roster[0].uid)
	await _frames(5)
	await _save("03_unit_selected")
	main.selected = {}
	# Play ahead (bot-driven) until the round-5 choice, with gold top-ups for a fuller board.
	var battle_done := false
	for r in 30:
		if m.over:
			break
		if not main.me.pending_picks.is_empty() and main.me.pending_picks[0].kind == "choice":
			main.refresh()
			await _frames(5)
			await _save("05_choice_r%d" % m.round_no)
			main._on_pick(0)
		if not main.me.pending_picks.is_empty() and main.me.pending_picks[0].kind == "upgrade":
			main.refresh()
			await _frames(5)
			await _save("06_upgrade_pick")
			main._on_pick(0)
		main.me.add_gold(20)
		Bot.play(m, main.me)
		main._clear_overlay()
		main.refresh()
		if m.round_type == &"pvp" and m.round_no >= 6 and not battle_done:
			await _frames(5)
			await _save("04_planning_later")
			main._start_fight()
			await _frames(90)
			await _save("07_battle")
			while main.state == &"battle":
				await process_frame
			battle_done = true
		else:
			main.board.skipping = true
			await main._start_fight()
			main.board.skipping = false
		if m.round_no >= 21:
			break
	main.me.set_current(&"player_hp", 0)
	main.me.alive = false
	main._game_over()
	await _frames(40)
	await _save("08_game_over")
	m.dispose()
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join(shot_name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
