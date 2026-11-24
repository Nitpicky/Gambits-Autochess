extends Control
## PROTOTYPE: placeholder planning screen. Everything is built in code so it is easy
## to throw away. Talks only to Match (modules/match/match.gd).
##
## Controls: click a shop offer to buy it. Click a unit (roster or board), then a board
## cell to place it. Click a bench item, then a unit to equip it. Hover anything for details.

var match_ref: Match
var me: PlayerState
var selected: Dictionary = {}   ## {"type": "unit", "uid"} | {"type": "item", "idx"}

var top_label := Label.new()
var msg_label := Label.new()
var players_box := VBoxContainer.new()
var board := GridContainer.new()
var roster_box := HBoxContainer.new()
var bench_box := HFlowContainer.new()
var shop_box := VBoxContainer.new()
var relic_label := Label.new()
var detail := RichTextLabel.new()
var detail_buttons := HBoxContainer.new()
var reroll_btn := Button.new()
var lock_btn := Button.new()
var xp_btn := Button.new()
var ready_btn := Button.new()
var overlay: Control = null


func _ready() -> void:
	_build_layout()
	new_game(int(Time.get_unix_time_from_system()))


func new_game(seed_value: int) -> void:
	me = null
	if match_ref:
		match_ref.dispose()
	match_ref = Match.new()
	match_ref.changed.connect(refresh)
	match_ref.new_game(seed_value, true)
	me = match_ref.human()
	selected = {}
	refresh()


func _exit_tree() -> void:
	if match_ref and not match_ref.players.is_empty():
		match_ref.dispose()


# ---------------------------------------------------------------- layout

func _panel(parent: Node, min_size := Vector2.ZERO) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.16)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	return v


func _header(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("e8c35a"))
	parent.add_child(l)


func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)
	# Top bar
	var top := HBoxContainer.new()
	root.add_child(top)
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_label.add_theme_font_size_override("font_size", 18)
	top.add_child(top_label)
	var auto_btn := Button.new()
	auto_btn.text = "Auto-place"
	auto_btn.pressed.connect(func(): match_ref.auto_assign(me))
	top.add_child(auto_btn)
	xp_btn.pressed.connect(func(): _say(match_ref.buy_xp(me)))
	top.add_child(xp_btn)
	ready_btn.text = "Fight!"
	ready_btn.add_theme_font_size_override("font_size", 18)
	ready_btn.pressed.connect(_on_ready)
	top.add_child(ready_btn)
	msg_label.add_theme_color_override("font_color", Color("ffb060"))
	root.add_child(msg_label)
	# Main row
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)
	var left := _panel(row, Vector2(240, 0))
	_header(left, "Players")
	left.add_child(players_box)
	left.add_child(relic_label)
	relic_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	relic_label.custom_minimum_size = Vector2(220, 0)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(center)
	var bp := _panel(center)
	_header(bp, "Battle board (back row | front row)  -  enemies come from the right")
	board.columns = 2
	board.add_theme_constant_override("h_separation", 6)
	board.add_theme_constant_override("v_separation", 6)
	bp.add_child(board)
	var rp := _panel(center)
	_header(rp, "Roster (max 6)")
	rp.add_child(roster_box)
	var ip := _panel(center)
	_header(ip, "Item bench (click an item, then a unit)")
	ip.add_child(bench_box)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(430, 0)
	row.add_child(right)
	var sp := _panel(right)
	_header(sp, "Shop")
	var sbar := HBoxContainer.new()
	sp.add_child(sbar)
	reroll_btn.pressed.connect(func(): _say(match_ref.reroll(me)))
	sbar.add_child(reroll_btn)
	lock_btn.pressed.connect(func(): match_ref.toggle_lock(me))
	sbar.add_child(lock_btn)
	sp.add_child(shop_box)
	var dp := _panel(right)
	dp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_header(dp, "Details")
	detail.fit_content = false
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size = Vector2(0, 220)
	dp.add_child(detail)
	dp.add_child(detail_buttons)


func _card(parent: Node, size: Vector2, tip: String, on_click: Callable, color := Color(0.16, 0.17, 0.22), selected_border := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.tooltip_text = tip
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	if selected_border:
		sb.set_border_width_all(3)
		sb.border_color = Color("ffd84a")
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate()
	hov.bg_color = color.lightened(0.15)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.pressed.connect(on_click)
	parent.add_child(b)
	return b


func _label(parent: Node, text: String, pos: Vector2, size: Vector2, fs := 12, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	parent.add_child(l)
	return l


func _unit_visual(b: Button, u: Dictionary, w: float) -> void:
	var def := UnitCatalog.get_def(u.def)
	var sv := SpriteView.new()
	sv.position = Vector2(0, 0)
	sv.size = Vector2(w, 80)
	b.add_child(sv)
	sv.show_unit(def.sprite)
	_label(b, def.name + (" ★" if u.level > 1 else ""), Vector2(0, 78), Vector2(w, 18), 12, UnitCatalog.RARITY_COLORS[def.rarity])
	var kws := PlayerState.unit_keywords(u).map(func(k): return Keywords.kw_name(k))
	_label(b, ", ".join(kws), Vector2(0, 94), Vector2(w, 16), 10, Keywords.FACTION_COLORS[def.faction])
	if not u.items.is_empty():
		_label(b, "items: %d" % u.items.size(), Vector2(0, 108), Vector2(w, 14), 10, Color("c0c0c0"))


# ---------------------------------------------------------------- refresh

func refresh() -> void:
	if me == null:
		return
	var tier_name: String = GameConfig.CATCHUP_TIER_NAMES[me.catchup_tier]
	var rtype: String = {&"pvp": "PvP", &"pve": "PvE", &"champion": "Champion pick"}[match_ref.round_type]
	var streak := me.streak()
	var streak_txt := ("W%d" % streak) if streak > 0 else (("L%d" % -streak) if streak < 0 else "-")
	top_label.text = "Round %d (%s)   HP %d/%d   Rank %d  XP %d/%d   Gold %d   Streak %s   Catch-up: %s" % [
		match_ref.round_no, rtype, me.hp(), me.max_hp(), me.rank(), me.xp(), GameConfig.xp_to_next(me.rank()),
		me.gold(), streak_txt, tier_name]
	xp_btn.text = "Buy %d XP (%dg)" % [GameConfig.XP_BUY_AMOUNT, GameConfig.XP_BUY_COST]
	xp_btn.disabled = not Economy.can_buy_xp(me)
	reroll_btn.text = "Reroll (%dg)" % Economy.reroll_cost(me)
	lock_btn.text = "Unlock shop" if me.shop_locked else "Lock shop"
	_refresh_players()
	_refresh_board()
	_refresh_roster()
	_refresh_bench()
	_refresh_shop()
	_refresh_detail()
	_refresh_pick()


func _refresh_players() -> void:
	for c in players_box.get_children():
		c.queue_free()
	var ps := match_ref.players.duplicate()
	ps.sort_custom(func(a, b): return a.hp() > b.hp() if a.alive == b.alive else a.alive)
	for p in ps:
		var l := Label.new()
		var tag := "  (you)" if p == me else ""
		l.text = ("%s%s  HP %d  R%d" % [p.display, tag, p.hp(), p.rank()]) if p.alive else ("%s  out (#%d)" % [p.display, p.placement])
		l.add_theme_color_override("font_color", Color("ffd84a") if p == me else (Color.WHITE if p.alive else Color("777777")))
		players_box.add_child(l)
	var lean := me.lean.keys().filter(func(a): return me.lean[a] > 0.0).map(func(a): return Keywords.ARCHETYPES[a].name)
	var build := ShopBias.main_build(me)
	var relics := me.relics.map(func(r): return RelicCatalog.get_def(r).name)
	relic_label.text = "\nStarting lean: %s\nMain build: %s\n\nRelics: %s" % [
		", ".join(lean) if not lean.is_empty() else "faded", Keywords.ARCHETYPES[build].name if build != &"" else "none yet",
		", ".join(relics) if not relics.is_empty() else "none"]


func _refresh_board() -> void:
	for c in board.get_children():
		c.queue_free()
	for col in GameConfig.BOARD_COLS:
		for row in [1, 0]:
			var u := me.unit_at(row, col)
			var tip := Describe.unit_def(UnitCatalog.get_def(u.def), u) if not u.is_empty() else ("Empty %s cell" % ("front" if row == 0 else "back"))
			var sel: bool = not u.is_empty() and selected.get("uid", -1) == u.uid
			var b := _card(board, Vector2(170, 124), tip, _on_cell.bind(row, col), Color(0.14, 0.2, 0.16) if row == 0 else Color(0.14, 0.16, 0.22), sel)
			if u.is_empty():
				_label(b, "Front" if row == 0 else "Back", Vector2(0, 50), Vector2(170, 20), 12, Color("777777"))
			else:
				_unit_visual(b, u, 170)


func _refresh_roster() -> void:
	for c in roster_box.get_children():
		c.queue_free()
	for u in me.roster:
		var sel: bool = selected.get("uid", -1) == u.uid
		var b := _card(roster_box, Vector2(120, 124), Describe.unit_def(UnitCatalog.get_def(u.def), u), _on_unit.bind(u.uid), Color(0.16, 0.17, 0.22), sel)
		_unit_visual(b, u, 120)
		if u.col >= 0:
			_label(b, "in battle", Vector2(0, 0), Vector2(120, 14), 10, Color("8fd18f"))
	for i in GameConfig.ROSTER_MAX - me.roster.size():
		var e := _card(roster_box, Vector2(120, 124), "Empty roster slot", func(): pass, Color(0.12, 0.12, 0.15))
		e.disabled = true


func _refresh_bench() -> void:
	for c in bench_box.get_children():
		c.queue_free()
	for i in me.item_bench.size():
		var it := ItemCatalog.get_def(me.item_bench[i])
		var sel: bool = selected.get("type", "") == "item" and selected.idx == i
		var b := _card(bench_box, Vector2(84, 84), Describe.item(it), _on_item.bind(i), Color(0.16, 0.17, 0.22), sel)
		var sv := SpriteView.new()
		sv.size = Vector2(84, 64)
		b.add_child(sv)
		sv.show_icon(it.icon, 0.8)
		_label(b, it.name, Vector2(0, 64), Vector2(84, 16), 10)
	if me.item_bench.is_empty():
		var l := Label.new()
		l.text = "No items"
		l.add_theme_color_override("font_color", Color("777777"))
		bench_box.add_child(l)


func _refresh_shop() -> void:
	for c in shop_box.get_children():
		c.queue_free()
	var row1 := HBoxContainer.new()
	var row2 := HBoxContainer.new()
	shop_box.add_child(row1)
	shop_box.add_child(row2)
	for i in me.shop_offers.size():
		var o: Dictionary = me.shop_offers[i]
		var parent := row1 if o.kind == &"unit" else row2
		var tip := ""
		var name := ""
		var color := Color(0.16, 0.17, 0.22)
		if o.kind == &"unit":
			var def := UnitCatalog.get_def(o.id)
			tip = Describe.unit_def(def)
			var owned := me.find_by_def(o.id)
			if not owned.is_empty():
				tip = "Buying this UPGRADES your %s.\n\n" % def.name + tip
			name = def.name
		elif o.kind == &"item":
			var it := ItemCatalog.get_def(o.id)
			tip = Describe.item(it)
			name = it.name
		else:
			var r := RelicCatalog.get_def(o.id)
			tip = Describe.relic(r)
			name = r.name
			color = Color(0.2, 0.16, 0.24)
		var b := _card(parent, Vector2(136, 128), tip, _on_offer.bind(i), color)
		b.disabled = o.sold
		var sv := SpriteView.new()
		sv.size = Vector2(136, 80)
		b.add_child(sv)
		if o.sold:
			_label(b, "SOLD", Vector2(0, 50), Vector2(136, 20), 14, Color("888888"))
			continue
		if o.kind == &"unit":
			var def := UnitCatalog.get_def(o.id)
			sv.show_unit(def.sprite)
			_label(b, name, Vector2(0, 78), Vector2(136, 18), 12, UnitCatalog.RARITY_COLORS[def.rarity])
			_label(b, Keywords.FACTION_NAMES[def.faction] + ": " + ", ".join(def.keywords.map(func(k): return Keywords.kw_name(k))), Vector2(0, 94), Vector2(136, 14), 10, Keywords.FACTION_COLORS[def.faction])
			if not me.find_by_def(o.id).is_empty():
				_label(b, "UPGRADE", Vector2(0, 2), Vector2(136, 14), 10, Color("ffd84a"))
		else:
			sv.show_icon(ItemCatalog.get_def(o.id).icon if o.kind == &"item" else RelicCatalog.get_def(o.id).icon, 0.9)
			_label(b, ("Relic: " if o.kind == &"relic" else "") + name, Vector2(0, 80), Vector2(136, 18), 11)
		var price := "%dg" % o.price
		if o.discount > 0:
			price += "  (-%d!)" % o.discount
		_label(b, price, Vector2(0, 108), Vector2(136, 16), 12, Color("ffd84a") if o.discount == 0 else Color("70ff70"))


func _refresh_detail() -> void:
	for c in detail_buttons.get_children():
		c.queue_free()
	detail.clear()
	match selected.get("type", ""):
		"unit":
			var u := me.find_unit(selected.uid)
			if u.is_empty():
				selected = {}
				return
			detail.append_text(Describe.unit_def(UnitCatalog.get_def(u.def), u))
			var def := UnitCatalog.get_def(u.def)
			var refund: int = GameConfig.CHAMPION_SELL if def.rarity == UnitCatalog.Rarity.CHAMPION else u.paid
			_button(detail_buttons, "Sell (+%dg)" % refund, func():
				match_ref.sell_unit(me, u.uid)
				selected = {}
				refresh())
			if u.col >= 0:
				_button(detail_buttons, "Bench it", func(): match_ref.assign(me, u.uid, -1, -1))
			for i in u.items.size():
				_button(detail_buttons, "Unequip " + ItemCatalog.get_def(u.items[i]).name, func(): match_ref.unequip(me, u.uid, i))
		"item":
			if selected.idx >= me.item_bench.size():
				selected = {}
				return
			var iid: StringName = me.item_bench[selected.idx]
			detail.append_text(Describe.item(ItemCatalog.get_def(iid)) + "\n\nClick a unit to equip it.")
			_button(detail_buttons, "Sell (+%dg)" % Shop.item_sell_price(iid), func():
				match_ref.sell_item(me, selected.idx)
				selected = {}
				refresh())
		_:
			detail.append_text("Hover anything for details. Click a shop card to buy.\nClick a unit, then a board cell to place it (your Rank = how many can fight).\nClick an item, then a unit to equip it.\nPress Fight! when ready.")


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ---------------------------------------------------------------- input handlers

func _say(err: String) -> void:
	msg_label.text = err


func _on_offer(i: int) -> void:
	_say(match_ref.buy(me, i))


func _on_unit(uid: int) -> void:
	if selected.get("type", "") == "item":
		_say(match_ref.equip(me, selected.idx, uid))
		selected = {}
	elif selected.get("uid", -1) == uid:
		selected = {}
	else:
		selected = {"type": "unit", "uid": uid}
	refresh()


func _on_item(i: int) -> void:
	selected = {} if (selected.get("type", "") == "item" and selected.idx == i) else {"type": "item", "idx": i}
	refresh()


func _on_cell(row: int, col: int) -> void:
	var occupant := me.unit_at(row, col)
	if selected.get("type", "") == "unit":
		if not occupant.is_empty() and occupant.uid == selected.uid:
			selected = {}
		else:
			_say(match_ref.assign(me, selected.uid, row, col))
			selected = {}
	elif selected.get("type", "") == "item" and not occupant.is_empty():
		_say(match_ref.equip(me, selected.idx, occupant.uid))
		selected = {}
	elif not occupant.is_empty():
		selected = {"type": "unit", "uid": occupant.uid}
	refresh()


# ---------------------------------------------------------------- picks, battles, game over

func _clear_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null


func _make_overlay() -> VBoxContainer:
	_clear_overlay()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var v := _panel(center, Vector2(700, 0))
	return v


func _refresh_pick() -> void:
	if me.pending_picks.is_empty() or not me.alive:
		if overlay and overlay.has_meta("pick"):
			_clear_overlay()
		return
	var pick: Dictionary = me.pending_picks[0]
	var v := _make_overlay()
	overlay.set_meta("pick", true)
	_header(v, pick.title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for i in pick.options.size():
		var o: Dictionary = pick.options[i]
		var tip := ""
		var b := _card(row, Vector2(210, 310), "", _on_pick.bind(i))
		var sv := SpriteView.new()
		sv.size = Vector2(210, 110)
		b.add_child(sv)
		var title := ""
		match o.kind:
			"unit":
				var def := UnitCatalog.get_def(o.id)
				sv.show_unit(def.sprite, false, 1.3)
				title = def.name
				tip = Describe.unit_def(def)
			"card":
				title = o.card.name
				tip = o.card.text
				var u := me.find_unit(pick.uid)
				if not u.is_empty():
					sv.show_unit(UnitCatalog.get_def(u.def).sprite, false, 1.3)
			"item":
				var it := ItemCatalog.get_def(o.id)
				sv.show_icon(it.icon, 1.2)
				title = it.name
				tip = Describe.item(it)
			"relic":
				var r := RelicCatalog.get_def(o.id)
				sv.show_icon(r.icon, 1.2)
				title = r.name
				tip = Describe.relic(r)
			_:
				title = o.label
				tip = o.label
		b.tooltip_text = tip
		_label(b, title, Vector2(0, 110), Vector2(210, 20), 14, Color("ffd84a"))
		var body := Label.new()
		body.text = tip.substr(0, 300)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", 10)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.max_lines_visible = 13
		body.custom_minimum_size = Vector2(194, 0)
		b.add_child(body)
		body.position = Vector2(8, 132)
		body.size = Vector2(194, 170)
	if pick.allow_skip:
		_button(v, pick.get("skip_text", "Skip"), _on_pick.bind(-1))
	if pick.kind == "champion" and me.roster.size() >= GameConfig.ROSTER_MAX:
		var l := Label.new()
		l.text = "Your roster is full: skip, or close this, sell a unit, and press Fight! to pick again."
		v.add_child(l)
		_button(v, "Close (sell a unit first)", func():
			_clear_overlay())


func _on_pick(i: int) -> void:
	_say(match_ref.resolve_pick(me, i))


func _on_ready() -> void:
	if not me.pending_picks.is_empty() and me.pending_picks[0].kind == "champion" and overlay == null:
		_refresh_pick()
		return
	if me.assigned().is_empty() and not me.roster.is_empty():
		match_ref.auto_assign(me)
	var report := match_ref.end_planning()
	selected = {}
	_show_report(report)


func _show_report(report: Dictionary) -> void:
	var mine: Dictionary = {}
	for f in report.fights:
		if f.a == me.id or f.b == me.id:
			mine = f
	if mine.is_empty():
		_show_summary(report, {})
		return
	_clear_overlay()
	var bv := BattleView.new()
	overlay = bv
	add_child(bv)
	var flip: bool = mine.b == me.id
	var fight := mine if not flip else _flip_fight(mine)
	var opp_name: String = mine.b_name if not flip else match_ref.players[mine.a].display
	bv.setup(fight, "You", opp_name)
	bv.finished.connect(func(): _show_summary(report, mine))
	bv.play(fight)


## Mirror a fight so the human is always on the left.
func _flip_fight(f: Dictionary) -> Dictionary:
	var g := f.duplicate(true)
	for ev in g.log:
		if ev.t == "start":
			for u in ev.units:
				u.side = 1 - u.side
		elif ev.t == "summon":
			ev.unit.side = 1 - ev.unit.side
		elif ev.t == "end" and ev.winner >= 0:
			ev.winner = 1 - ev.winner
		elif ev.t == "timeout":
			ev.ratios = [ev.ratios[1], ev.ratios[0]]
	return g


func _show_summary(report: Dictionary, mine: Dictionary) -> void:
	var v := _make_overlay()
	_header(v, "Round %d results" % report.round)
	if report.type == &"champion":
		var l := Label.new()
		l.text = "Champion round: no fights this round."
		v.add_child(l)
	for f in report.fights:
		var l := Label.new()
		var a: String = match_ref.players[f.a].display
		var b: String = f.b_name
		var res := "draw" if f.winner == -1 else ((a if f.winner == 0 else b) + " wins")
		l.text = "%s vs %s: %s, %d damage" % [a, b, res, f.damage]
		if f == mine:
			l.add_theme_color_override("font_color", Color("ffd84a"))
		v.add_child(l)
	for pid in report.get("eliminated", []):
		var l := Label.new()
		l.text = "%s is eliminated (#%d)" % [match_ref.players[pid].display, match_ref.players[pid].placement]
		l.add_theme_color_override("font_color", Color("ff7070"))
		v.add_child(l)
	if match_ref.over:
		var l := Label.new()
		l.text = "GAME OVER - you finished #%d" % (me.placement if me.placement > 0 else 1)
		l.add_theme_font_size_override("font_size", 22)
		v.add_child(l)
		_button(v, "New game", func():
			_clear_overlay()
			new_game(int(Time.get_unix_time_from_system())))
	else:
		_button(v, "Next round", func():
			_clear_overlay()
			match_ref.next_round())


# ---------------------------------------------------------------- test hook

## Used by the headless smoke test: plays one round for the human like a bot would.
func debug_autoplay_round() -> bool:
	if match_ref.over:
		return false
	var before := match_ref.round_no
	_clear_overlay()
	Bot.play(match_ref, me)
	var report := match_ref.end_planning()
	_show_report(report)
	if overlay is BattleView:
		(overlay as BattleView).skipping = true
	_clear_overlay()
	_show_summary(report, {})
	_clear_overlay()
	match_ref.next_round()
	return match_ref.round_no == before + 1 or match_ref.over
