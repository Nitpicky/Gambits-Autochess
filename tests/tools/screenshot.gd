extends SceneTree
## PROTOTYPE: grabs 3 screenshots (starter pick, planning, battle) for quick visual checks.
## Needs a display (e.g. xvfb-run). Usage:
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/tools/screenshot.gd -- /output/dir


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	main.new_game(4242)
	for i in 10:
		await process_frame
	await _save(out.path_join("shot_pick.png"))
	main.match_ref.resolve_pick(main.me, 0)
	main.match_ref.buy(main.me, 0)
	main.match_ref.buy(main.me, 3)
	for i in 5:
		await process_frame
	await _save(out.path_join("shot_plan.png"))
	main._on_ready()
	for i in 120:
		await process_frame
	await _save(out.path_join("shot_battle.png"))
	main.match_ref.dispose()
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
