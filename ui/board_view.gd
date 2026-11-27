class_name BoardView
extends Control
## PROTOTYPE: the tilted battle board. Your 2x3 side on the left, the enemy side mirrored on the right.
## During planning it shows your placed units and a dimmed ghost of the next enemy; when the fight
## starts the same board replays the battle log (HP bars, floating numbers, deaths, summons).
## The perspective is faked in 2D: tiles are projected trapezoids, sprites stay upright.

signal cell_pressed(side: int, row: int, col: int)
signal cell_hovered(side: int, row: int, col: int)  ## side -1 = left the board
signal finished
signal fight_clock(seconds: float, overtime: int)  ## fight time elapsed (speed-1 seconds), for the timer bar
signal narrate(text: String)  ## BBCode line describing the current action (shown at the top of the screen)

const TILE := Vector2(165, 150)
const GAP := 10.0
const MID_GAP := 130.0
const DEPTH := 0.85      ## vertical squash of the board plane
const NEAR := 1.0        ## scale at the bottom row
const FAR := 0.8         ## scale at the top row

var speed: float = 1.0
var skipping := false
var playing := false
var selected := Vector3i(-1, -1, -1)   ## side, row, col
var units_layer := Control.new()
var fx_layer := Control.new()
var nodes: Dictionary = {}   ## key -> {"root", "sprite", "bar", "side"}  (key = uid in battle, "r_c_s" in planning)
var _flip := false
var _names: Dictionary = {}    ## uid -> [name, side shown]
var _actor = null              ## uid of the unit acting now
var _line := ""
var _overtime := 0
var _elapsed := 0.0                ## narrator line being built for the current action
## Drag and drop hooks, set by the screen: (side, row, col) -> drag data | null; (side, row, col, data) -> bool; -> void
var drag_from_cell: Callable
var can_drop_on_cell: Callable
var drop_on_cell: Callable

const C_MINE := "f4f4f4"
const C_FOE := "ff7a7a"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	units_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(units_layer)
	add_child(fx_layer)
	_build_hit_areas()


func board_size() -> Vector2:
	return Vector2(TILE.x * 4 + GAP * 2 + MID_GAP, (TILE.y * 3 + GAP * 2) * DEPTH)


## Flat-plane rect of a cell. side 0 = left (you), 1 = right. row 0 = front (towards the middle).
func _flat_rect(side: int, row: int, col: int) -> Rect2:
	var cx := size.x * 0.5
	var x: float
	if side == 0:
		x = cx - MID_GAP * 0.5 - TILE.x - (TILE.x + GAP) * row
	else:
		x = cx + MID_GAP * 0.5 + (TILE.x + GAP) * row
	return Rect2(Vector2(x, col * (TILE.y + GAP)), TILE)


func _project(p: Vector2) -> Vector2:
	var h := TILE.y * 3 + GAP * 2
	var t := clampf(p.y / h, 0.0, 1.0)
	var s := lerpf(FAR, NEAR, t)
	var cx := size.x * 0.5
	return Vector2(cx + (p.x - cx) * s, 30.0 + p.y * DEPTH)


func cell_quad(side: int, row: int, col: int) -> PackedVector2Array:
	var r := _flat_rect(side, row, col)
	return PackedVector2Array([_project(r.position), _project(r.position + Vector2(r.size.x, 0)),
		_project(r.end), _project(r.position + Vector2(0, r.size.y))])


## Screen point where a unit standing on the cell has its feet.
func cell_foot(side: int, row: int, col: int) -> Vector2:
	var r := _flat_rect(side, row, col)
	return _project(r.get_center() + Vector2(0, TILE.y * 0.25))


func _cell_scale(col: int) -> float:
	return lerpf(FAR, NEAR, (col + 0.5) / 3.0)


func _draw() -> void:
	for side in 2:
		for row in 2:
			for col in 3:
				var c := Color("252837") if row == 1 else Color("23332a")
				if side == 1:
					c = Color("3a2526")
				draw_colored_polygon(cell_quad(side, row, col), c)
				if selected == Vector3i(side, row, col):
					var q := cell_quad(side, row, col)
					q.append(q[0])
					draw_polyline(q, Color("f2c34a"), 2.0, true)


func _build_hit_areas() -> void:
	for side in 2:
		for row in 2:
			for col in 3:
				var b := Button.new()
				b.flat = true
				b.focus_mode = Control.FOCUS_NONE
				b.mouse_filter = Control.MOUSE_FILTER_STOP
				b.set_meta("cell", Vector3i(side, row, col))
				b.gui_input.connect(_on_cell_input.bind(side, row, col))
				b.set_drag_forwarding(
					func(_p): return null if playing or not drag_from_cell.is_valid() else drag_from_cell.call(side, row, col),
					func(_p, d): return not playing and can_drop_on_cell.is_valid() and can_drop_on_cell.call(side, row, col, d),
					func(_p, d): drop_on_cell.call(side, row, col, d))
				b.mouse_entered.connect(func(): cell_hovered.emit(side, row, col))
				b.mouse_exited.connect(func(): cell_hovered.emit(-1, -1, -1))
				var sb := StyleBoxEmpty.new()
				for st in ["normal", "hover", "pressed", "focus"]:
					b.add_theme_stylebox_override(st, sb)
				add_child(b)
	resized.connect(_place_hit_areas)
	_place_hit_areas()  # the size is usually set before _ready, so `resized` never fires for it


func _place_hit_areas() -> void:
	for ch in get_children():
		if ch is Button and ch.has_meta("cell"):
			var c: Vector3i = ch.get_meta("cell")
			var q := cell_quad(c.x, c.y, c.z)
			var mn := q[0]
			var mx := q[0]
			for p in q:
				mn = mn.min(p)
				mx = mx.max(p)
			ch.position = mn
			ch.size = mx - mn
	queue_redraw()
	_relayout_units()


func _on_cell_input(ev: InputEvent, side: int, row: int, col: int) -> void:
	if playing:
		return
	if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		cell_pressed.emit(side, row, col)


# ---------------------------------------------------------------- units

func clear_units() -> void:
	for n in nodes.values():
		n.root.queue_free()
	nodes.clear()
	for ch in fx_layer.get_children():
		ch.queue_free()


## info: {"sprite", "side", "row", "col", "hp", "max"}; ghost = dimmed preview.
func _spawn(key, info: Dictionary, with_bar: bool, ghost := false) -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(190, 170)
	units_layer.add_child(root)
	var sv := SpriteView.new()
	sv.size = Vector2(190, 160)
	root.add_child(sv)
	var side: int = info.side
	sv.show_unit(info.sprite, side == 1, 2.6)
	var bar: HpBar = null
	if with_bar:
		bar = HpBar.new()
		bar.position = Vector2(50, 14)
		bar.size = Vector2(90, 12)
		bar.setup(info.get("hp", 1.0), info.get("max", 1.0), side == 1)
		root.add_child(bar)
	if ghost:
		root.modulate = Color(1, 1, 1, 0.5)
	nodes[key] = {"root": root, "sprite": sv, "bar": bar, "side": side, "row": info.row, "col": info.col}
	_place(nodes[key])


func _place(n: Dictionary) -> void:
	var foot := cell_foot(n.side, n.row, n.col)
	var s := _cell_scale(n.col)
	n.root.scale = Vector2(s, s)
	n.root.position = foot - Vector2(95, 150) * s


func _relayout_units() -> void:
	for n in nodes.values():
		_place(n)


## Planning: your placed units + the ghost of who you face next (spec units, may be empty).
func show_planning(mine: Array, ghost_units: Array) -> void:
	if playing:
		return
	clear_units()
	for u in mine:
		var d := UnitCatalog.get_def(u.def)
		_spawn("m%d" % u.uid, {"sprite": d.sprite, "side": 0, "row": u.row, "col": u.col}, false)
	for i in ghost_units.size():
		var g: Dictionary = ghost_units[i]
		var d := UnitCatalog.get_def(g.def)
		if d.is_empty():
			continue
		_spawn("g%d" % i, {"sprite": d.sprite, "side": 1, "row": g.get("row", d.row), "col": g.get("col", i % 3)}, false, true)
	queue_redraw()


# ---------------------------------------------------------------- battle replay

## flip = the human is side 1 of the fight (show it on the left anyway).
func play(fight_log: Array, flip: bool) -> void:
	_flip = flip
	playing = true
	selected = Vector3i(-1, -1, -1)
	_names.clear()
	_overtime = 0
	_elapsed = 0.0
	speed = 1.0
	_actor = null
	_line = ""
	queue_redraw()
	clear_units()
	for ev in fight_log:
		if not is_inside_tree():
			return
		var d := _apply(ev)
		if d > 0.0 and not skipping:
			await get_tree().create_timer(d / speed).timeout
	if not skipping and is_inside_tree():
		await get_tree().create_timer(0.6 / speed).timeout
	playing = false
	_actor = null
	queue_redraw()
	narrate.emit("")
	finished.emit()


func _side(s: int) -> int:
	return 1 - s if _flip else s


func _info(u: Dictionary) -> Dictionary:
	var i := u.duplicate()
	i.side = _side(u.side)
	return i


func _float(uid, text: String, color: Color, big := false) -> void:
	if skipping or not nodes.has(uid):
		return
	var l := Label.new()
	l.text = text
	l.modulate = color
	l.add_theme_font_size_override("font_size", 24 if big else 16)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	var root: Control = nodes[uid].root
	l.position = root.position + Vector2(75, 6)
	fx_layer.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 44, 0.8 / speed)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8 / speed)
	tw.tween_callback(l.queue_free)


func _bar(ev: Dictionary) -> void:
	if nodes.has(ev.u) and nodes[ev.u].bar and ev.has("max"):
		nodes[ev.u].bar.set_hp(ev.hp, ev.max)


func _nm(uid) -> String:
	if not _names.has(uid):
		return "?"
	var n: Array = _names[uid]
	return "[color=#%s]%s[/color]" % [C_MINE if n[1] == 0 else C_FOE, n[0]]


func _say(part: String, fresh := false) -> void:
	_line = part if fresh else (_line + "   " + part)
	if not skipping:
		narrate.emit(_line)


## A short line from the attacker to its target and a red flash on the target.
func _strike_fx(src, dst, col: Color) -> void:
	if skipping or not nodes.has(src) or not nodes.has(dst) or src == dst:
		return
	var a: Control = nodes[src].root
	var b: Control = nodes[dst].root
	var ln := Line2D.new()
	ln.width = 4.0
	ln.default_color = col
	ln.add_point(a.position + Vector2(95, 90) * a.scale.x)
	ln.add_point(b.position + Vector2(95, 90) * b.scale.x)
	fx_layer.add_child(ln)
	var tw := create_tween()
	tw.tween_property(ln, "modulate:a", 0.0, 0.45 / speed)
	tw.tween_callback(ln.queue_free)


func _flash(uid, col: Color) -> void:
	if skipping or not nodes.has(uid):
		return
	var sv: Control = nodes[uid].sprite
	sv.modulate = col
	var tw := create_tween()
	tw.tween_property(sv, "modulate", Color.WHITE, 0.35 / speed)


## Playback time of an event at speed 1. The sim uses the same table for its fight clock,
## so overtime starts when the fight timer runs out on screen.
func _dur(ev: Dictionary) -> float:
	var d: float = GameConfig.EVENT_SECONDS.get(ev.t, 0.0)
	_elapsed += d
	fight_clock.emit(_elapsed, _overtime)
	return d


func _apply(ev: Dictionary) -> float:
	match ev.t:
		"start":
			for u in ev.units:
				_spawn(u.uid, _info(u), true)
				_names[u.uid] = [u.name, _side(u.side)]
			_say("Fight!", true)
			return _dur(ev)
		"overtime":
			_overtime = ev.n
			_say("[color=#ff5a3c]OVERTIME %s[/color]  [color=#8a8da0]heals cut, hits ignore armour and grow[/color]" % ("!" if ev.n == 1 else "x%d" % ev.n), true)
			return _dur(ev)
		"act":
			if _overtime > 0:
				speed = minf(GameConfig.OVERTIME_MAX_SPEED, speed * (1.0 + GameConfig.OVERTIME_SPEEDUP))
			_actor = ev.u
			queue_redraw()
			_say("%s  %s%s" % [_nm(ev.u), ev.text, "  [color=#5aa9e6](reaction)[/color]" if ev.get("reaction", false) else ""], not ev.get("reaction", false))
			if nodes.has(ev.u):
				nodes[ev.u].sprite.play(&"attack")
				if not skipping:
					var r: Control = nodes[ev.u].root
					var home := r.position
					var tw := create_tween()
					var dx := 18.0 if nodes[ev.u].side == 0 else -18.0
					tw.tween_property(r, "position:x", home.x + dx, 0.1 / speed)
					tw.tween_property(r, "position:x", home.x, 0.15 / speed)
			return _dur(ev)
		"hit":
			_bar(ev)
			if nodes.has(ev.u):
				nodes[ev.u].sprite.play(&"hit")
			_strike_fx(ev.get("src"), ev.u, Color(1, 0.85, 0.4, 0.9))
			_flash(ev.u, Color(1, 0.4, 0.4))
			_float(ev.u, "-%d" % ev.amount, Color("ff6060"), ev.amount >= 20)
			var why: String = ev.get("text", "")
			_say("→ %s [color=#ff6060]−%d[/color]%s" % [_nm(ev.u), ev.amount, (" (%s)" % why) if why != "" else ""])
			return _dur(ev)
		"heal":
			_bar(ev)
			_strike_fx(ev.get("src"), ev.u, Color(0.45, 1, 0.45, 0.9))
			_flash(ev.u, Color(0.5, 1, 0.5))
			_float(ev.u, "+%d" % ev.amount, Color("70ff70"))
			_say("→ %s [color=#70ff70]+%d[/color]" % [_nm(ev.u), ev.amount])
			return _dur(ev)
		"blocked":
			_float(ev.u, ev.get("text", "Blocked"), Color("a0d8ff"))
			_say("→ %s [color=#a0d8ff]%s[/color]" % [_nm(ev.u), ev.get("text", "Blocked")])
			return _dur(ev)
		"buff":
			_bar(ev)
			_float(ev.u, ev.get("text", ""), Color("f2c34a"))
			_say("%s [color=#f2c34a]%s[/color]" % [_nm(ev.u), ev.get("text", "")])
			return _dur(ev)
		"status":
			_float(ev.u, ev.status, Color("c8a8ff"))
			_say("%s [color=#c8a8ff]%s[/color]" % [_nm(ev.u), ev.status])
			return _dur(ev)
		"death":
			if nodes.has(ev.u):
				nodes[ev.u].sprite.play(&"death", false)
				if nodes[ev.u].bar:
					nodes[ev.u].bar.visible = false
				var tw := create_tween()
				tw.tween_interval(0.3 / speed)
				tw.tween_property(nodes[ev.u].root, "modulate:a", 0.0, 0.5 / speed)
			_say("%s [color=#8a8da0]falls[/color]" % _nm(ev.u))
			return _dur(ev)
		"summon":
			if nodes.has(ev.unit.uid):  # revived / reborn: drop the old body
				nodes[ev.unit.uid].root.queue_free()
				nodes.erase(ev.unit.uid)
			_spawn(ev.unit.uid, _info(ev.unit), true)
			_names[ev.unit.uid] = [ev.unit.name, _side(ev.unit.side)]
			_say("%s [color=#f2c34a]appears[/color]" % _nm(ev.unit.uid))
			return _dur(ev)
		"move":
			if nodes.has(ev.u):
				nodes[ev.u].row = ev.row
				nodes[ev.u].col = ev.col
				var n: Dictionary = nodes[ev.u]
				var foot := cell_foot(n.side, n.row, n.col)
				var s := _cell_scale(n.col)
				if skipping:
					_place(n)
				else:
					var tw := create_tween()
					tw.tween_property(n.root, "position", foot - Vector2(95, 150) * s, 0.25 / speed)
			return _dur(ev)
		"transform":
			_bar(ev)
			if nodes.has(ev.u) and ev.get("sprite", "") != "":
				nodes[ev.u].sprite.show_unit(ev.sprite, nodes[ev.u].side == 1, 2.6)
			_float(ev.u, ev.get("name", "Form"), Color("f2c34a"))
			_say("%s [color=#f2c34a]becomes %s[/color]" % [_nm(ev.u), ev.get("name", "a new form")])
			return _dur(ev)
		"cycle":
			_say("[color=#8a8da0]Everyone recovers AP and PP[/color]", true)
			return _dur(ev)
		"end":
			_actor = null
			queue_redraw()
			var w: int = ev.get("winner", -1)
			var mine_won := w >= 0 and _side(w) == 0
			_say("[color=#%s]%s[/color]" % ["f2c34a" if mine_won else ("e0566b" if w >= 0 else "c8c8d8"), "Won" if mine_won else ("Lost" if w >= 0 else "Draw")], true)
			return _dur(ev)
	return _dur(ev)
