extends Control
## PROTOTYPE: the single game screen (layout "take B" from the screens canvas).
## Planning, fights and picks all happen on it: the board plays the fight, picks dim it.
## Built entirely in code; talks only to Match (modules/match/match.gd).
##
## Controls (drag and drop): the bench lists ALL your units (the ones on the board are lit).
## Drag a unit onto a board cell to place it (swaps with an occupant), off the board onto the bench
## to take it off, onto the shop to sell it. Drag an item onto a unit to equip it, an equipped item
## back to the stash to take it off, an item onto the shop to sell it. Drag a shop offer out to buy it
## (or click it). A click on a unit opens its card (rules editable). Fights start when the timer runs
## out (Space = now). A narrator line at the top tells what happens during the fight.

const SHOP_TILE := Vector2(130, 130)
const STYLE_ICONS := {&"interest": &"coin_bag", &"bounty": &"blade", &"streak": &"flame"}
const STYLE_COLORS := {&"interest": Color("f2c34a"), &"bounty": Color("e0566b"), &"streak": Color("ef8a3a")}

var match_ref: Match
var me: PlayerState
var selected: Dictionary = {}   ## {"type": "unit", "uid"}: the unit whose card is open
var state: StringName = &"planning"  ## planning | battle | over
var time_left: float = GameConfig.PLANNING_SECONDS
var timer_enabled := true        ## the smoke test turns the real-time timer off

var board := BoardView.new()
var relics_box := Control.new()
var rounds_box := HBoxContainer.new()
var timer_bar := ProgressBar.new()
var count_label := Label.new()
var bench_box := Control.new()
var items_box := VBoxContainer.new()
var shop_box := HBoxContainer.new()
var shop_line := HBoxContainer.new()
var gold_label := Label.new()
var rank_label := Label.new()
var xp_label := Label.new()
var xp_bar := HBoxContainer.new()
var lock_btn := Button.new()
var reroll_btn := Button.new()
var xp_btn := Button.new()
var players_col := Control.new()
var card_layer := Control.new()
var msg_label := Label.new()
var overlay: Control = null
var avatars: Dictionary = {}  ## player id -> Avatar
var _shop_hover: Control = null
var narrator := RichTextLabel.new()
var _last_gold := -1
var _hover_card: Control = null


func _ready() -> void:
	_build_layout()
	new_game(int(Time.get_unix_time_from_system()))


func new_game(seed_value: int) -> void:
	me = null
	if match_ref:
		match_ref.dispose()
	_clear_overlay()
	for a in avatars.values():
		a.queue_free()
	avatars.clear()
	match_ref = Match.new()
	match_ref.changed.connect(refresh)
	match_ref.new_game(seed_value, true)
	me = match_ref.human()
	_last_gold = -1
	selected = {}
	state = &"planning"
	time_left = GameConfig.PLANNING_SECONDS
	refresh()


func _exit_tree() -> void:
	if match_ref and not match_ref.players.is_empty():
		match_ref.dispose()


# ---------------------------------------------------------------- layout

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color("14151c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_deselect())
	add_child(bg)
	# relics, top left
	relics_box.position = Vector2(12, 10)
	add_child(relics_box)
	# round strip + timer, top centre
	rounds_box.add_theme_constant_override("separation", 8)
	add_child(rounds_box)
	timer_bar.show_percentage = false
	timer_bar.size = Vector2(300, 4)
	timer_bar.position = Vector2(650, 74)
	timer_bar.max_value = GameConfig.PLANNING_SECONDS
	var tb_bg := StyleBoxFlat.new()
	tb_bg.bg_color = Color("2a2c38")
	var tb_fill := StyleBoxFlat.new()
	tb_fill.bg_color = Color("f2c34a")
	timer_bar.add_theme_stylebox_override("background", tb_bg)
	timer_bar.add_theme_stylebox_override("fill", tb_fill)
	add_child(timer_bar)
	narrator.position = Vector2(350, 84)
	narrator.size = Vector2(900, 34)
	narrator.bbcode_enabled = true
	narrator.fit_content = false
	narrator.scroll_active = false
	narrator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	narrator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	narrator.add_theme_font_size_override("normal_font_size", 20)
	add_child(narrator)
	msg_label.position = Vector2(500, 652)
	msg_label.size = Vector2(600, 20)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.add_theme_color_override("font_color", Color("ffb060"))
	add_child(msg_label)
	# board, centred
	var bs := Vector2(860, 460)
	board.position = Vector2((1600 - bs.x) * 0.5, 118)
	board.size = bs
	add_child(board)
	board.cell_pressed.connect(_on_cell)
	board.narrate.connect(func(t): narrator.text = "[center]%s[/center]" % t if t != "" else "")
	board.drag_from_cell = _drag_from_cell
	board.can_drop_on_cell = _can_drop_on_cell
	board.drop_on_cell = _drop_on_cell
	board.cell_hovered.connect(_on_cell_hover)
	count_label.position = board.position + Vector2(30, 96)
	count_label.add_theme_font_size_override("font_size", 16)
	add_child(count_label)
	var person := Glyph.make(&"person", Color("e8e8ee"), Vector2(16, 16))
	person.position = Vector2(-20, 2)
	count_label.add_child(person)
	# bench (zigzag) and items, left of the board
	bench_box.position = Vector2(board.position.x - 200, 130)
	bench_box.size = Vector2(214, 540)
	_drop_zone(bench_box, &"bench")
	add_child(bench_box)
	items_box.position = Vector2(board.position.x - 280, 160)
	items_box.custom_minimum_size = Vector2(60, 400)
	items_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_drop_zone(items_box, &"stash")
	items_box.add_theme_constant_override("separation", 8)
	add_child(items_box)
	# shop line + shop + rank/xp, bottom centre
	shop_line.position = Vector2(390, 682)
	shop_line.size = Vector2(820, 36)
	shop_line.add_theme_constant_override("separation", 6)
	add_child(shop_line)
	reroll_btn.custom_minimum_size = Vector2(64, 34)
	reroll_btn.pressed.connect(func(): _say(match_ref.reroll(me)))
	_icon_btn(reroll_btn, &"reroll")
	shop_line.add_child(reroll_btn)
	lock_btn.custom_minimum_size = Vector2(64, 34)
	lock_btn.pressed.connect(func(): match_ref.toggle_lock(me))
	shop_line.add_child(lock_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_line.add_child(sp)
	gold_label.add_theme_font_size_override("font_size", 20)
	gold_label.add_theme_color_override("font_color", Color("f2c34a"))
	shop_line.add_child(gold_label)
	var coin := Glyph.make(&"coin", Color("f2c34a"), Vector2(16, 16))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shop_line.add_child(coin)
	shop_box.position = Vector2(386, 728)
	_drop_zone(shop_box, &"shop")
	_drop_zone(shop_line, &"shop")
	shop_box.add_theme_constant_override("separation", 12)
	add_child(shop_box)
	var rk := VBoxContainer.new()
	rk.position = Vector2(206, 732)
	rk.custom_minimum_size = Vector2(160, 0)
	rk.add_theme_constant_override("separation", 10)
	add_child(rk)
	var rk_top := HBoxContainer.new()
	rk.add_child(rk_top)
	rank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_label.add_theme_font_size_override("font_size", 15)
	rk_top.add_child(rank_label)
	xp_label.add_theme_color_override("font_color", Color("8a8da0"))
	rk_top.add_child(xp_label)
	xp_bar.add_theme_constant_override("separation", 3)
	xp_bar.custom_minimum_size = Vector2(160, 6)
	rk.add_child(xp_bar)
	xp_btn.pressed.connect(func(): _say(match_ref.buy_xp(me)))
	rk.add_child(xp_btn)
	# players column, right edge
	players_col.position = Vector2(1490, 0)
	players_col.size = Vector2(102, 900)
	add_child(players_col)
	card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(card_layer)


func _icon_btn(b: Button, k: StringName, c := Color("e8e8ee")) -> void:
	for ch in b.get_children():
		ch.queue_free()
	var g := Glyph.make(k, c, Vector2(18, 18))
	g.position = (b.custom_minimum_size - g.size) * 0.5
	b.add_child(g)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_SPACE and state == &"planning" and overlay == null:
		_start_fight()


func _process(delta: float) -> void:
	if state != &"planning" or overlay != null or not timer_enabled or match_ref == null:
		return
	time_left -= delta
	timer_bar.value = maxf(0.0, time_left)
	if time_left <= 0.0:
		_start_fight()


# ---------------------------------------------------------------- refresh

func refresh() -> void:
	if me == null:
		return
	_hover_off()
	_refresh_relics()
	_refresh_rounds()
	_refresh_players()
	_refresh_board()
	_refresh_bench()
	_refresh_items()
	_refresh_shop()
	_refresh_card()
	timer_bar.value = maxf(0.0, time_left)
	if state == &"planning" and overlay == null and not me.pending_picks.is_empty():
		_show_pick()


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _refresh_relics() -> void:
	_clear(relics_box)
	for i in me.relics.size():
		var r := RelicCatalog.get_def(me.relics[i])
		var sv := SpriteView.new()
		sv.size = Vector2(44, 44)
		sv.position = Vector2(i * 46, 22 if i % 2 == 1 else 0)
		sv.mouse_filter = Control.MOUSE_FILTER_STOP
		_hover(sv, func(): return InfoCard.build(&"relic", r))
		relics_box.add_child(sv)
		sv.show_icon(r.icon, 0.9)


func _refresh_rounds() -> void:
	_clear(rounds_box)
	var cur := match_ref.round_no
	for rn in range(maxi(1, cur - 4), cur + 5):
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(44, 0)
		v.add_theme_constant_override("separation", 2)
		rounds_box.add_child(v)
		var now := rn == cur
		var s := 40.0 if now else 32.0
		var done := rn < cur
		var res := ""
		for h in me.history:
			if h.round == rn:
				res = h.result
		var bgc := Color("f2c34a") if now else (Color("2f5a3b") if res == "W" else (Color("6a2f2f") if res == "L" else Color("1c1e28")))
		var fg := Color("14151c") if now else (Color("e8e8ee") if done else Color("8a8da0"))
		var holder := CenterContainer.new()
		holder.custom_minimum_size = Vector2(44, 40)
		v.add_child(holder)
		var circ := Glyph.make(&"circle", bgc, Vector2(s, s))
		holder.add_child(circ)
		var kind: StringName = &"skull" if GameConfig.is_pve(rn) else &"swords"
		if GameConfig.CHOICE_ROUNDS.has(rn):
			kind = &"crown"
		var ic := Glyph.make(kind, fg, Vector2(18, 18))
		ic.position = Vector2(s - 18, s - 18) * 0.5
		circ.add_child(ic)
		var under := Label.new()
		under.text = match_ref.opponent_name(me) if now else ""
		under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		under.add_theme_font_size_override("font_size", 12)
		under.add_theme_color_override("font_color", Color("f2c34a"))
		v.add_child(under)
	rounds_box.reset_size()
	rounds_box.position = Vector2(800 - rounds_box.size.x * 0.5, 8)


func _refresh_players() -> void:
	var order: Array = match_ref.players.duplicate()
	order.sort_custom(func(a, b):
		if a.alive != b.alive:
			return a.alive
		return a.hp() > b.hp() if a.hp() != b.hp() else a.id < b.id)
	var step := 900.0 / order.size()
	for i in order.size():
		var p: PlayerState = order[i]
		var av: Avatar = avatars.get(p.id)
		if av == null:
			av = Avatar.new()
			av.setup(p.display, p.id == me.id)
			av.position = Vector2(15, step * i + (step - 90) * 0.5)
			players_col.add_child(av)
			avatars[p.id] = av
		av.set_hp(p.hp(), p.max_hp(), p.alive)
		var target := Vector2(15, step * i + (step - 90) * 0.5)
		if av.position != target:
			var tw := create_tween()
			tw.tween_property(av, "position", target, 0.4).set_trans(Tween.TRANS_CUBIC)


func _refresh_board() -> void:
	count_label.text = "%d/%d" % [me.assigned().size(), me.rank()]
	if state != &"planning":
		return
	var spec := match_ref.preview_spec(me)
	board.show_planning(me.assigned(), spec.get("units", []))
	board.selected = Vector3i(-1, -1, -1)
	if selected.get("type") == "unit":
		var u := me.find_unit(selected.uid)
		if not u.is_empty() and u.col >= 0:
			board.selected = Vector3i(0, u.row, u.col)
	board.queue_redraw()


## The bench lists ALL your units; the ones on the board are lit (gold ring + board pip), the others dimmed.
func _refresh_bench() -> void:
	_clear(bench_box)
	for i in me.roster.size():
		var u: Dictionary = me.roster[i]
		var d := UnitCatalog.get_def(u.def)
		var on_board: bool = u.col >= 0
		var cell := Control.new()
		cell.size = Vector2(96, 118)
		cell.position = Vector2((i % 2) * 118, (i / 2) * 128 + (56 if i % 2 == 1 else 0))
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		bench_box.add_child(cell)
		# item slots: 2 rows of hexes above the frame, bottom row fills first; drag one out to unequip
		var cap := PlayerState.item_capacity(u)
		for sl in cap:
			var row := sl / 3
			var colx := sl % 3
			var hx := Glyph.make(&"hex_slot", Color("2a2c38") if sl >= u.items.size() else Color(0, 0, 0, 0), Vector2(22, 24))
			hx.position = Vector2(15 + colx * 24, 26 - row * 22)
			cell.add_child(hx)
			if sl < u.items.size():
				var it := ItemCatalog.get_def(u.items[sl])
				hx.mouse_filter = Control.MOUSE_FILTER_STOP
				var isv := SpriteView.new()
				isv.size = Vector2(22, 24)
				hx.add_child(isv)
				isv.show_icon(it.icon, 0.35)
				_hover(hx, func(): return InfoCard.build(&"item", it))
				var uid: int = u.uid
				var slot: int = sl
				hx.set_drag_forwarding(
					func(_p): return _start_drag(hx, {"type": "equipped", "uid": uid, "slot": slot}, it.icon, true),
					func(_p, dd): return _can_drop_unit(uid, dd),
					func(_p, dd): _drop_on_unit(uid, dd))
		var b := Control.new()
		b.position = Vector2(18, 54)
		b.size = Vector2(60, 60)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var sel: bool = selected.get("type") == "unit" and selected.uid == u.uid
		var frame := Glyph.make(&"circle", Color("2b2f45") if on_board else Color("16171e"), Vector2(60, 60))
		frame.outline = Color("f2c34a") if sel else UnitCatalog.RARITY_COLORS[d.rarity]
		b.add_child(frame)
		var sv := SpriteView.new()
		sv.size = Vector2(60, 60)
		frame.add_child(sv)
		sv.show_unit(d.sprite, false, 0.75)
		if not on_board:
			sv.modulate = Color(0.6, 0.6, 0.65)
		else:
			var pip := Glyph.make(&"diamond", Color("f2c34a"), Vector2(14, 14))
			pip.position = Vector2(48, 46)
			pip.tooltip_text = "On the board"
			b.add_child(pip)
		var uid2: int = u.uid
		b.gui_input.connect(_on_unit_click.bind(uid2))
		b.set_drag_forwarding(
			func(_p): return _start_drag(b, {"type": "unit", "uid": uid2}, d.sprite, false),
			func(_p, dd): return _can_drop_unit(uid2, dd),
			func(_p, dd): _drop_on_unit(uid2, dd))
		cell.add_child(b)


func _refresh_items() -> void:
	_clear(items_box)
	for i in me.item_bench.size():
		var it := ItemCatalog.get_def(me.item_bench[i])
		var b := Control.new()
		b.custom_minimum_size = Vector2(56, 56)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.mouse_default_cursor_shape = Control.CURSOR_DRAG
		var sv := SpriteView.new()
		sv.size = Vector2(56, 56)
		b.add_child(sv)
		sv.show_icon(it.icon, 0.8)
		_hover(b, func(): return InfoCard.build(&"item", it))
		var idx := i
		b.set_drag_forwarding(
			func(_p): return _start_drag(b, {"type": "item", "idx": idx}, it.icon, true),
			func(_p, dd): return _can_drop_zone(&"stash", dd),
			func(_p, dd): _drop_zone_do(&"stash", dd))
		items_box.add_child(b)


func _refresh_shop() -> void:
	_clear(shop_box)
	_shop_hover = null
	var dim := state != &"planning"
	shop_box.modulate = Color(1, 1, 1, 0.35 if dim else 1.0)
	shop_line.modulate = shop_box.modulate
	for i in me.shop_offers.size():
		var o: Dictionary = me.shop_offers[i]
		var b := Button.new()
		b.custom_minimum_size = SHOP_TILE
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = o.sold or dim
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("2b2f45") if not o.sold else Color("1a1b24")
		for st in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(_on_offer.bind(i))
		shop_box.add_child(b)
		b.set_drag_forwarding(func(_p): return null, func(_p, dd): return _can_drop_zone(&"shop", dd), func(_p, dd): _drop_zone_do(&"shop", dd))
		if o.sold:
			continue
		var drag_icon := ""
		var drag_unit := false
		var name := ""
		var rar := 0
		var icon := Control.new()
		icon.position = Vector2(32, 12)
		icon.size = Vector2(66, 66)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		match o.kind:
			&"unit":
				var d := UnitCatalog.get_def(o.id)
				name = d.name
				rar = d.rarity
				var circle := Glyph.make(&"circle", Color("1c1e28"), Vector2(66, 66))
				circle.outline = UnitCatalog.RARITY_COLORS[rar]
				icon.add_child(circle)
				var sv := SpriteView.new()
				sv.size = Vector2(66, 66)
				circle.add_child(sv)
				sv.show_unit(d.sprite, false, 0.85)
				drag_icon = d.sprite
				drag_unit = true
				b.mouse_entered.connect(_shop_card.bind(b, d))
				b.mouse_exited.connect(_shop_card_off)
				if not me.find_by_def(o.id).is_empty():
					b.add_child(_badge_up())
			&"item":
				var it := ItemCatalog.get_def(o.id)
				name = it.name
				rar = it.rarity
				_hover(b, func(): return InfoCard.build(&"item", it), true)
				drag_icon = it.icon
				var sv := SpriteView.new()
				sv.size = Vector2(66, 66)
				icon.add_child(sv)
				sv.show_icon(it.icon, 0.9)
			&"relic":
				var r := RelicCatalog.get_def(o.id)
				name = r.name
				rar = r.rarity
				_hover(b, func(): return InfoCard.build(&"relic", r), true)
				drag_icon = r.icon
				var sv := SpriteView.new()
				sv.size = Vector2(66, 66)
				icon.add_child(sv)
				sv.show_icon(r.icon, 0.9)
		if not dim:
			var oi := i
			var di := drag_icon
			var du := drag_unit
			b.set_drag_forwarding(
				func(_p): return _start_drag(b, {"type": "offer", "idx": oi}, di, not du),
				func(_p, dd): return _can_drop_zone(&"shop", dd),
				func(_p, dd): _drop_zone_do(&"shop", dd))
		var badge := Glyph.rarity(rar, 16)
		badge.position = Vector2(6, 6)
		b.add_child(badge)
		var nl := Label.new()
		nl.text = name
		nl.position = Vector2(0, 82)
		nl.size = Vector2(130, 18)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.add_theme_font_size_override("font_size", 12)
		nl.clip_text = true
		b.add_child(nl)
		var price := Label.new()
		price.text = str(o.price - o.get("discount", 0))
		price.position = Vector2(84, 104)
		price.size = Vector2(26, 20)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.add_theme_color_override("font_color", Color("7ce08a") if o.get("discount", 0) > 0 else Color("f2c34a"))
		b.add_child(price)
		var pc := Glyph.make(&"coin", Color("f2c34a"), Vector2(11, 11))
		pc.position = Vector2(113, 109)
		b.add_child(pc)
	# shop line
	gold_label.text = str(me.gold())
	if _last_gold >= 0 and me.gold() > _last_gold:
		_gold_pop(me.gold() - _last_gold)
	_last_gold = me.gold()
	var rc := Economy.reroll_cost(me)
	reroll_btn.text = ""
	reroll_btn.tooltip_text = "Reroll (%d)" % rc
	_icon_btn(lock_btn, &"lock" if me.shop_locked else &"unlock", Color("f2c34a") if me.shop_locked else Color("e8e8ee"))
	rank_label.text = "Rank %d" % me.rank()
	var need := GameConfig.xp_to_next(me.rank())
	xp_label.text = "%d/%d" % [me.xp(), need] if need > 0 else "max"
	_clear(xp_bar)
	var blocks := maxi(1, int(ceil(float(need) / GameConfig.XP_BUY_AMOUNT)))
	for k in blocks:
		var seg := ProgressBar.new()
		seg.show_percentage = false
		seg.custom_minimum_size = Vector2(0, 6)
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.max_value = GameConfig.XP_BUY_AMOUNT
		seg.value = clampf(me.xp() - k * GameConfig.XP_BUY_AMOUNT, 0, GameConfig.XP_BUY_AMOUNT)
		var bgs := StyleBoxFlat.new()
		bgs.bg_color = Color("2a2c38")
		var fs := StyleBoxFlat.new()
		fs.bg_color = Color("5aa9e6")
		seg.add_theme_stylebox_override("background", bgs)
		seg.add_theme_stylebox_override("fill", fs)
		xp_bar.add_child(seg)
	xp_btn.text = "XP · %d" % GameConfig.XP_BUY_COST
	xp_btn.disabled = not Economy.can_buy_xp(me) or dim
	reroll_btn.disabled = dim


func _badge_up() -> Control:
	var g := Glyph.make(&"up", Color("7ce08a"), Vector2(18, 18))
	g.position = Vector2(106, 6)
	return g


func _shop_card(b: Control, d: Dictionary) -> void:
	_shop_card_off()
	var c := UnitCard.build(d)
	card_layer.add_child(c)
	c.position = Vector2(b.global_position.x + 65 - UnitCard.WIDTH * 0.5, b.global_position.y - c.size.y - 30)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_hover = c


func _shop_card_off() -> void:
	if is_instance_valid(_shop_hover):
		_shop_hover.queue_free()
	_shop_hover = null


## The selected unit's card, right next to the unit; its rules are edited on it.
func _refresh_card() -> void:
	for c in card_layer.get_children():
		if c != _shop_hover:
			c.queue_free()
	if state != &"planning" or selected.get("type") != "unit":
		return
	var u := me.find_unit(selected.uid)
	if u.is_empty():
		return
	var c := UnitCard.build(UnitCatalog.get_def(u.def), u, true, Match.rules_of(u))
	c.rules_changed.connect(func(r): match_ref.set_rules(me, u.uid, r))
	card_layer.add_child(c)
	var pos: Vector2
	if u.col >= 0:
		var q := board.cell_quad(0, u.row, u.col)
		pos = board.position + Vector2(maxf(q[1].x, q[2].x) + 12, q[0].y - 30)
	else:
		pos = Vector2(board.position.x + 10, 110)
	c.position = Vector2(clampf(pos.x, 10, 1480 - UnitCard.WIDTH), clampf(pos.y, 90, 660 - c.size.y))


# ---------------------------------------------------------------- input

func _say(err: String) -> void:
	msg_label.text = err
	if err != "":
		var tw := create_tween()
		msg_label.modulate.a = 1.0
		tw.tween_interval(1.6)
		tw.tween_property(msg_label, "modulate:a", 0.0, 0.5)


func _deselect() -> void:
	if not selected.is_empty():
		selected = {}
		refresh()


func _on_offer(i: int) -> void:
	_shop_card_off()
	_hover_off()
	_say(match_ref.buy(me, i))


## Click (no drag) on a unit: open / close its card.
func _select_unit(uid: int) -> void:
	if selected.get("type") == "unit" and selected.uid == uid:
		selected = {}
	else:
		selected = {"type": "unit", "uid": uid}
	refresh()


func _on_unit_click(ev: InputEvent, uid: int) -> void:
	if state == &"planning" and ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_select_unit(uid)


func _on_cell(side: int, row: int, col: int) -> void:
	if state != &"planning" or side != 0:
		return
	var occ := me.unit_at(row, col)
	if occ.is_empty():
		_deselect()
	else:
		_select_unit(occ.uid)


func _on_cell_hover(_side: int, _row: int, _col: int) -> void:
	pass


# ---------------------------------------------------------------- drag and drop
# Drag data: {"type": "unit", "uid"} | {"type": "item", "idx"} (stash) | {"type": "equipped", "uid", "slot"}
# | {"type": "offer", "idx"} (shop). Drop zones: board cells, bench units, the bench, the stash, the shop.

func _start_drag(src: Control, data: Dictionary, icon: String, is_icon: bool):
	if state != &"planning" or overlay != null:
		return null
	_hover_off()
	_shop_card_off()
	var p := Control.new()
	var sv := SpriteView.new()
	sv.size = Vector2(80, 80)
	sv.position = Vector2(-40, -40)
	p.add_child(sv)
	if is_icon:
		sv.show_icon(icon, 0.8)
	else:
		sv.show_unit(icon, false, 1.0)
	p.modulate = Color(1, 1, 1, 0.85)
	src.set_drag_preview(p)
	return data


func _drag_from_cell(side: int, row: int, col: int):
	if side != 0:
		return null
	var occ := me.unit_at(row, col)
	if occ.is_empty():
		return null
	return _start_drag(board, {"type": "unit", "uid": occ.uid}, UnitCatalog.get_def(occ.def).sprite, false)


func _can_drop_on_cell(side: int, row: int, col: int, d) -> bool:
	if side != 0 or state != &"planning" or not (d is Dictionary):
		return false
	var occ := me.unit_at(row, col)
	match d.get("type"):
		"unit", "offer":
			return true
		"item", "equipped":
			return not occ.is_empty()
	return false


func _drop_on_cell(_side: int, row: int, col: int, d: Dictionary) -> void:
	var occ := me.unit_at(row, col)
	match d.type:
		"unit":
			_say(match_ref.assign(me, d.uid, row, col))
		"offer":
			var o: Dictionary = me.shop_offers[d.idx]
			var before := me.roster.size()
			var err := match_ref.buy(me, d.idx)
			_say(err)
			if err == "" and o.kind == &"unit" and me.roster.size() > before:
				_say(match_ref.assign(me, me.roster[-1].uid, row, col))
		_:
			if not occ.is_empty():
				_drop_on_unit(occ.uid, d)
	refresh()


func _can_drop_unit(_uid: int, d) -> bool:
	if state != &"planning" or not (d is Dictionary):
		return false
	return d.get("type") in ["unit", "item", "equipped", "offer"]


## Dropped on a bench unit: items equip to it; a unit dropped on the bench leaves the board.
func _drop_on_unit(uid: int, d: Dictionary) -> void:
	match d.type:
		"item":
			_say(match_ref.equip(me, d.idx, uid))
		"equipped":
			if d.uid == uid:
				return
			match_ref.unequip(me, d.uid, d.slot)
			var err := match_ref.equip(me, me.item_bench.size() - 1, uid)
			_say(err)
		"unit", "offer":
			_drop_zone_do(&"bench", d)
	refresh()


func _drop_zone(c: Control, zone: StringName) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.set_drag_forwarding(func(_p): return null, func(_p, d): return _can_drop_zone(zone, d), func(_p, d): _drop_zone_do(zone, d))


func _can_drop_zone(zone: StringName, d) -> bool:
	if state != &"planning" or overlay != null or not (d is Dictionary):
		return false
	match zone:
		&"shop":
			return d.get("type") in ["unit", "item", "equipped"]
		&"bench":
			return d.get("type") == "unit" or d.get("type") == "offer"
		&"stash":
			return d.get("type") == "equipped" or d.get("type") == "offer"
	return false


func _drop_zone_do(zone: StringName, d: Dictionary) -> void:
	match zone:
		&"shop":  # sell
			match d.type:
				"unit":
					selected = {}
					match_ref.sell_unit(me, d.uid)
				"item":
					match_ref.sell_item(me, d.idx)
				"equipped":
					match_ref.unequip(me, d.uid, d.slot)
					match_ref.sell_item(me, me.item_bench.size() - 1)
		&"bench":
			if d.type == "unit":
				var u := me.find_unit(d.uid)
				if not u.is_empty() and u.col >= 0:
					match_ref.assign(me, d.uid, -1, -1)
			elif d.type == "offer":
				_say(match_ref.buy(me, d.idx))
		&"stash":
			if d.type == "equipped":
				match_ref.unequip(me, d.uid, d.slot)
			elif d.type == "offer":
				_say(match_ref.buy(me, d.idx))
	refresh()


# ---------------------------------------------------------------- hover cards

## Shows a card (built by `make`) next to `c` while the mouse is over it.
func _hover(c: Control, make: Callable, above := false) -> void:
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.mouse_entered.connect(func():
		_hover_off()
		if not is_instance_valid(c) or not c.is_inside_tree():
			return
		var card: Control = make.call()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_layer.add_child(card)  # _ready() lays it out and sets its final size
		var r := c.get_global_rect()
		var pos: Vector2
		if above:
			pos = Vector2(r.get_center().x - card.size.x * 0.5, r.position.y - card.size.y - 12)
		else:
			pos = Vector2(r.end.x + 12, r.get_center().y - card.size.y * 0.5)
			if pos.x + card.size.x > 1480:
				pos.x = r.position.x - card.size.x - 12
		card.position = Vector2(clampf(pos.x, 8, 1592 - card.size.x), clampf(pos.y, 8, 892 - card.size.y))
		_hover_card = card)
	c.mouse_exited.connect(_hover_off)


func _hover_off() -> void:
	if is_instance_valid(_hover_card):
		_hover_card.queue_free()
	_hover_card = null


func _gold_pop(n: int) -> void:
	var l := Label.new()
	l.text = "+%d" % n
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color("f2c34a"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.position = shop_line.position + Vector2(shop_line.size.x - 70, -6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 40, 1.2)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.tween_callback(l.queue_free)


# ---------------------------------------------------------------- picks

func _clear_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null


func _dim_overlay() -> Control:
	_clear_overlay()
	var o := ColorRect.new()
	o.color = Color(0.04, 0.045, 0.06, 0.78)
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(o)
	overlay = o
	return o


func _show_pick() -> void:
	_shop_card_off()
	var pick: Dictionary = me.pending_picks[0]
	var o := _dim_overlay()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	o.add_child(row)
	for i in pick.options.size():
		var opt: Dictionary = pick.options[i]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 26)
		row.add_child(col)
		match pick.kind:
			"gold_style":
				col.add_child(_style_card(opt.id, i))
			"choice":
				var c := UnitCard.build(UnitCatalog.get_def(opt.id))
				_clickable(c, i)
				col.add_child(c)
				var icon_name := ""
				if opt.has("item"):
					icon_name = ItemCatalog.get_def(opt.item).icon
				elif opt.has("relic"):
					icon_name = RelicCatalog.get_def(opt.relic).icon
				if icon_name != "":
					var holder := CenterContainer.new()
					holder.custom_minimum_size = Vector2(UnitCard.WIDTH, 52)
					var o_kind: StringName = &"item" if opt.has("item") else &"relic"
					var o_def: Dictionary = ItemCatalog.get_def(opt.item) if opt.has("item") else RelicCatalog.get_def(opt.relic)
					_hover(holder, func(): return InfoCard.build(o_kind, o_def))
					holder.mouse_filter = Control.MOUSE_FILTER_STOP
					col.add_child(holder)
					var sv := SpriteView.new()
					sv.custom_minimum_size = Vector2(64, 64)
					holder.add_child(sv)
					sv.show_icon(icon_name, 1.2)
			"upgrade":
				var u := me.find_unit(pick.uid)
				var cu := u.duplicate(true)
				cu.cards = cu.cards + [opt.card]
				cu.level = cu.level + 1
				var c := UnitCard.build(UnitCatalog.get_def(u.def), cu)
				c.extra_text = opt.card.name + "\n" + opt.card.text
				_clickable(c, i)
				col.add_child(c)
			_:
				var b := Button.new()
				b.text = str(opt.get("label", opt.kind))
				b.pressed.connect(_on_pick.bind(i))
				col.add_child(b)
	row.reset_size()
	await get_tree().process_frame
	if is_instance_valid(row):
		row.reset_size()
		row.position = (Vector2(1600, 900) - row.size) * 0.5


func _clickable(c: Control, i: int) -> void:
	c.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_pick(i))
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _style_card(style: StringName, i: int) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(UnitCard.WIDTH, 300)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c1e28")
	sb.border_color = STYLE_COLORS[style]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	var sbh := sb.duplicate()
	sbh.bg_color = Color("252837")
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.tooltip_text = {&"interest": "+1 gold per %d banked (max %d) each round." % [GameConfig.INTEREST_PER, GameConfig.INTEREST_CAP],
		&"bounty": "+%d gold per enemy unit killed and per unit left standing after each fight (max %d)." % [GameConfig.BOUNTY_PER_KILL, GameConfig.BOUNTY_CAP],
		&"streak": "Bonus gold for consecutive wins or losses."}[style]
	var g := Glyph.make(STYLE_ICONS[style], STYLE_COLORS[style], Vector2(110, 110))
	g.position = Vector2((UnitCard.WIDTH - 110) * 0.5, 60)
	b.add_child(g)
	var l := Label.new()
	l.text = String(style).capitalize()
	l.position = Vector2(0, 210)
	l.size = Vector2(UnitCard.WIDTH, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	b.add_child(l)
	b.pressed.connect(_on_pick.bind(i))
	return b


func _on_pick(i: int) -> void:
	var err := match_ref.resolve_pick(me, i)
	if err != "":
		_say(err)
		return
	_clear_overlay()
	refresh()


# ---------------------------------------------------------------- fights

func _start_fight() -> void:
	if state != &"planning":
		return
	_clear_overlay()
	selected = {}
	state = &"battle"
	_shop_card_off()
	var report := match_ref.end_planning()
	refresh()
	var mine := _my_fight(report)
	if not mine.is_empty():
		board.play(mine.log, mine.b == me.id)
		if board.playing:
			await board.finished
	_after_fight()


func _my_fight(report: Dictionary) -> Dictionary:
	for f in report.fights:
		if f.a == me.id or f.b == me.id:
			return f
	return {}


func _after_fight() -> void:
	if not is_inside_tree():
		return
	_refresh_players()  # HP gauges animate the round's damage (no results screen)
	if match_ref.over or not me.alive:
		_game_over()
		return
	match_ref.next_round()
	state = &"planning"
	time_left = GameConfig.PLANNING_SECONDS
	refresh()


func _game_over() -> void:
	state = &"over"
	var o := _dim_overlay()
	var win := me.alive and me.placement == 1
	var l := Label.new()
	l.text = "VICTORY" if win else "DEFEAT"
	l.add_theme_font_size_override("font_size", 120)
	l.add_theme_color_override("font_color", Color("f2c34a") if win else Color("e0566b"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(1600, 160)
	l.position = Vector2(0, 370)
	l.pivot_offset = Vector2(800, 80)
	l.scale = Vector2(0.2, 0.2)
	o.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	o.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			new_game(int(Time.get_unix_time_from_system())))


# ---------------------------------------------------------------- test hook

## Used by the headless smoke test: plays one round for the human like a bot would.
func debug_autoplay_round() -> bool:
	if match_ref.over:
		return false
	timer_enabled = false
	var before := match_ref.round_no
	_clear_overlay()
	Bot.play(match_ref, me)
	board.skipping = true
	await _start_fight()
	return match_ref.round_no == before + 1 or match_ref.over


# ---------------------------------------------------------------- avatar

## A player in the right column: ring HP gauge (animated), initials, HP badge at the bottom.
class Avatar extends Control:
	var initials := ""
	var is_me := false
	var hp_shown := 100.0
	var hp_max := 100.0
	var alive := true

	func setup(display: String, mine: bool) -> void:
		initials = display.substr(0, 2)
		is_me = mine
		size = Vector2(72, 90)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_hp(hp: float, mx: float, p_alive: bool) -> void:
		hp_max = maxf(1.0, mx)
		alive = p_alive
		var tw := create_tween()
		tw.tween_method(func(v): hp_shown = v; queue_redraw(), hp_shown, hp, 0.8).set_trans(Tween.TRANS_CUBIC)
		modulate.a = 1.0 if alive else 0.35

	func _draw() -> void:
		var c := Vector2(36, 36)
		draw_circle(c, 30, Color("4a3f1a") if is_me else Color("2b2f45"))
		draw_arc(c, 33, 0, TAU, 48, Color("2a2c38"), 5.0, true)
		var frac := clampf(hp_shown / hp_max, 0.0, 1.0)
		var col := Color("f2c34a") if is_me else (Color("4caf7a") if frac > 0.7 else Color("e07b3a"))
		if frac > 0.0:
			# gauge starts and ends at the bottom centre
			draw_arc(c, 33, PI / 2, PI / 2 + TAU * frac, 48, col, 5.0, true)
		var f := get_theme_default_font()
		var ts := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_string(f, c + Vector2(-ts.x * 0.5, 6), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("e8e8ee"))
		var badge := Rect2(Vector2(20, 62), Vector2(32, 16))
		draw_rect(badge, col)
		var t := str(int(round(hp_shown)))
		var bs := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(f, badge.position + Vector2((32 - bs.x) * 0.5, 13), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("0d0e13"))
