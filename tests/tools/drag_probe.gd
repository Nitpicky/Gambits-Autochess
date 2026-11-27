extends SceneTree
## PROTOTYPE: checks drag and drop with real mouse events. Needs a display:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 -s tests/tools/drag_probe.gd

var main

func _init() -> void:
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.new_game(4242)
	main.timer_enabled = false
	var m = main.match_ref
	main._on_pick(0)
	m.buy(main.me, 0)
	main.me.item_bench.append(&"whetstone" if ItemCatalog.get_def(&"whetstone").size() > 0 else ItemCatalog.all().keys()[0])
	main.refresh()
	await _frames(5)
	# bench unit 0 centre
	var b: Control = main.bench_box.get_child(0).get_child(main.bench_box.get_child(0).get_child_count() - 1)
	var from := b.get_global_rect().get_center()
	var q: PackedVector2Array = main.board.cell_quad(0, 0, 1)
	var to: Vector2 = main.board.global_position + (q[0] + q[2]) * 0.5
	await _drag(from, to)
	var it: Control = main.items_box.get_child(0)
	await _drag(it.get_global_rect().get_center(), to)
	_check("item dragged onto a board unit is equipped", main.me.roster[0].items.size() == 1)
	_check("unit dragged onto a board cell moves there", main.me.roster[0].row == 0 and main.me.roster[0].col == 1)
	# equipped item -> another unit on the bench
	m.buy(main.me, 1)
	main.refresh()
	await _frames(3)
	var u1: Dictionary = main.me.roster[1]
	var hx: Control = _slot_of(0)
	await _drag(hx.get_global_rect().get_center(), _bench_frame(1).get_global_rect().get_center())
	_check("equipped item dragged onto a bench unit moves to it", u1.items.size() == 1 and main.me.roster[0].items.is_empty())
	# board unit -> bench area (unplace)
	var u0: Dictionary = main.me.roster[0]
	var c: PackedVector2Array = main.board.cell_quad(0, u0.row, u0.col)
	await _drag(main.board.global_position + (c[0] + c[2]) * 0.5, main.bench_box.global_position + Vector2(100, 480))
	_check("board unit dragged onto the bench leaves the board", u0.col < 0)
	# shop offer -> board cell (buy and place)
	var before: int = main.me.roster.size()
	var off: Control = null
	for i in main.shop_box.get_child_count():
		if main.me.shop_offers[i].kind == &"unit" and not main.me.shop_offers[i].sold:
			off = main.shop_box.get_child(i)
			break
	main.me.add_gold(50)
	main.refresh()
	await _frames(3)
	if off:
		off = main.shop_box.get_child(main.shop_box.get_children().find(off)) if off.is_inside_tree() else null
	if off == null:
		for i in main.shop_box.get_child_count():
			if main.me.shop_offers[i].kind == &"unit" and not main.me.shop_offers[i].sold:
				off = main.shop_box.get_child(i)
	var q2: PackedVector2Array = main.board.cell_quad(0, 1, 2)
	await _drag(off.get_global_rect().get_center(), main.board.global_position + (q2[0] + q2[2]) * 0.5)
	_check("shop unit dragged onto a cell is bought and placed", main.me.roster.size() == before + 1 and not main.me.unit_at(1, 2).is_empty())
	# bench unit -> shop (sell)
	var n: int = main.me.roster.size()
	await _drag(_bench_frame(0).get_global_rect().get_center(), main.shop_box.get_child(0).get_global_rect().get_center())
	_check("unit dragged onto the shop is sold", main.me.roster.size() == n - 1)
	# rule rows on the unit card: drag the last rule onto the first
	var k := Shop.new_unit(main.me, &"lightchaser", 0)
	main.refresh()
	await _frames(3)
	main._select_unit(k.uid)
	await _frames(5)
	var card: UnitCard = null
	for cl in main.card_layer.get_children():
		if cl is UnitCard:
			card = cl
	var rows: Array = []
	_rows(card, rows)
	var before_rules: Array = Match.rules_of(k).map(func(r): return r.action)
	var src_r: Rect2 = rows[rows.size() - 1].get_global_rect()
	await _drag(src_r.position + Vector2(25, src_r.size.y * 0.5), rows[0].get_global_rect().get_center())  # grab by the action name
	var after_rules: Array = Match.rules_of(k).map(func(r): return r.action)
	_check("dragging a rule row changes its priority (%s -> %s)" % [before_rules, after_rules], after_rules.size() == before_rules.size() and after_rules[0] == before_rules[before_rules.size() - 1])
	print("DRAG PROBE ", "PASSED" if fails == 0 else "FAILED")
	m.dispose()
	quit()


var fails := 0


func _check(what: String, ok: bool) -> void:
	print("  ", "ok  " if ok else "FAIL", " ", what)
	if not ok:
		fails += 1


func _rows(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is PanelContainer and c.mouse_default_cursor_shape == Control.CURSOR_DRAG:
			out.append(c)
		_rows(c, out)


func _bench_frame(i: int) -> Control:
	var cell: Control = main.bench_box.get_child(i)
	return cell.get_child(cell.get_child_count() - 1)


func _slot_of(i: int) -> Control:
	var cell: Control = main.bench_box.get_child(i)
	for ch in cell.get_children():
		if ch is Glyph and ch.mouse_filter == Control.MOUSE_FILTER_STOP:
			return ch
	return null


func _drag(a: Vector2, b: Vector2) -> void:
	var vp := root
	_mouse(a, true, vp)
	await _frames(2)
	for i in 12:
		var p := a.lerp(b, (i + 1) / 12.0)
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		mm.relative = (b - a) / 12.0
		Input.parse_input_event(mm)
		await _frames(2)
	_mouse(b, false, vp)
	await _frames(4)


func _mouse(p: Vector2, down: bool, _vp) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
