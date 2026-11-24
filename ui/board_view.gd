class_name BoardView
extends Control
## PROTOTYPE: the tilted battle board. Your 2x3 side on the left, the enemy side mirrored on the right.
## During planning it shows your placed units and a dimmed ghost of the next enemy; when the fight
## starts the same board replays the battle log (HP bars, floating numbers, deaths, summons).
## The perspective is faked in 2D: tiles are projected trapezoids, sprites stay upright.

signal cell_pressed(side: int, row: int, col: int)
signal cell_right_pressed(side: int, row: int, col: int)
signal cell_hovered(side: int, row: int, col: int)  ## side -1 = left the board
signal finished

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
				b.mouse_entered.connect(func(): cell_hovered.emit(side, row, col))
				b.mouse_exited.connect(func(): cell_hovered.emit(-1, -1, -1))
				var sb := StyleBoxEmpty.new()
				for st in ["normal", "hover", "pressed", "focus"]:
					b.add_theme_stylebox_override(st, sb)
				add_child(b)
	resized.connect(_place_hit_areas)


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
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			cell_pressed.emit(side, row, col)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			cell_right_pressed.emit(side, row, col)


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


func _apply(ev: Dictionary) -> float:
	match ev.t:
		"start":
			for u in ev.units:
				_spawn(u.uid, _info(u), true)
			return 0.4
		"act":
			if nodes.has(ev.u):
				nodes[ev.u].sprite.play(&"attack")
				if not skipping:
					var r: Control = nodes[ev.u].root
					var tw := create_tween()
					var dx := 14.0 if nodes[ev.u].side == 0 else -14.0
					tw.tween_property(r, "position:x", r.position.x + dx, 0.08 / speed)
					tw.tween_property(r, "position:x", r.position.x, 0.12 / speed)
			return 0.35
		"hit":
			_bar(ev)
			if nodes.has(ev.u):
				nodes[ev.u].sprite.play(&"hit")
			_float(ev.u, "-%d" % ev.amount, Color("ff6060"), ev.amount >= 20)
			return 0.25
		"heal":
			_bar(ev)
			_float(ev.u, "+%d" % ev.amount, Color("70ff70"))
			return 0.2
		"blocked":
			_float(ev.u, "0", Color("a0d8ff"))
			return 0.2
		"buff":
			_bar(ev)
			return 0.05
		"status":
			return 0.05
		"death":
			if nodes.has(ev.u):
				nodes[ev.u].sprite.play(&"death", false)
				var tw := create_tween()
				tw.tween_property(nodes[ev.u].root, "modulate:a", 0.0, 0.6 / speed)
			return 0.35
		"summon":
			_spawn(ev.unit.uid, _info(ev.unit), true)
			return 0.25
		"move":
			if nodes.has(ev.u):
				nodes[ev.u].row = ev.row
				nodes[ev.u].col = ev.col
				_place(nodes[ev.u])
			return 0.2
		"end":
			return 0.0
	return 0.0
