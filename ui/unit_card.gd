class_name UnitCard
extends Control
## PROTOTYPE: the one unit card used everywhere (shop hover, selected unit, choices, upgrades).
## Fixed width (WIDTH); the height grows with the unit's rules.
## Corners: Speed top-left (cyan), AP/PP top-right (burst / shield), Attack bottom-left (yellow),
## HP bottom-right (red). Rarity shape bottom middle. Factions down the left edge, archetypes down the right.
## When `editable`, condition chips cycle through Describe.COND_PRESETS, rows can move up or be removed,
## and + adds a rule. Every change emits rules_changed with the full rule list.

signal rules_changed(rules: Array)

const WIDTH := 240.0
const MIN_HEIGHT := 320.0
const C_ATK := Color("e8b83a")
const C_HP := Color("e0566b")
const C_SPD := Color("4fc3d9")
const C_AP := Color("f2c34a")
const C_PP := Color("5aa9e6")
const ARCH_COLORS := {&"fortress": Color("c8c8d8"), &"control": Color("7fc8f0"), &"tempo": Color("e0605a"),
	&"ramp": Color("7ccf6a"), &"attrition": Color("a070d8"), &"swarm": Color("d89a50")}

var def: Dictionary = {}
var inst: Dictionary = {}
var rules: Array = []
var editable := false
var extra_text: String = ""  ## e.g. upgrade path text shown under the rules
var _body: VBoxContainer


static func build(p_def: Dictionary, p_inst: Dictionary = {}, p_editable := false, p_rules: Array = []) -> UnitCard:
	var c := UnitCard.new()
	c.def = p_def
	c.inst = p_inst
	c.editable = p_editable
	c.rules = (p_rules if not p_rules.is_empty() else p_def.gambits).duplicate(true)
	return c


## HP / Attack / Speed / AP / PP of a unit instance (level, items and upgrade cards included).
static func stats(d: Dictionary, u: Dictionary) -> Dictionary:
	var lv: int = u.get("level", 1) - 1
	var s := {"hp": d.hp + GameConfig.UPGRADE_HP * lv, "atk": d.atk + GameConfig.UPGRADE_ATK * lv, "ini": d.ini, "ap": d.ap, "pp": d.pp}
	for i in u.get("items", []):
		var it := ItemCatalog.get_def(i)
		for k in it.stats:
			if s.has(k):
				s[k] += it.stats[k]
	for c in u.get("cards", []):
		for k in ["hp", "atk", "ap", "pp"]:
			if c.has(k):
				s[k] += c[k]
	return s


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, MIN_HEIGHT)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = Describe.unit_def(def, inst)
	_rebuild()


func _rebuild() -> void:
	for ch in get_children():
		ch.queue_free()
	var rc: Color = UnitCatalog.RARITY_COLORS[def.rarity]
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c1e28")
	sb.border_color = rc
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_body = VBoxContainer.new()
	_body.position = Vector2(24, 18)
	_body.custom_minimum_size = Vector2(WIDTH - 48, 0)
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)
	# portrait
	var pc := CenterContainer.new()
	_body.add_child(pc)
	var circle := Glyph.make(&"circle", Color("2b2f45"), Vector2(100, 100))
	pc.add_child(circle)
	var sv := SpriteView.new()
	sv.size = Vector2(100, 100)
	circle.add_child(sv)
	sv.show_unit(def.sprite, false, 1.2)
	var nm := Label.new()
	nm.text = def.name + (" ★" if inst.get("level", 1) > 1 else "")
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 15)
	_body.add_child(nm)
	# keyword row: Melee/Ranged first, then each keyword with its own icon (hover = rule text)
	var kw_row := HBoxContainer.new()
	kw_row.alignment = BoxContainer.ALIGNMENT_CENTER
	kw_row.add_theme_constant_override("separation", 5)
	_body.add_child(kw_row)
	kw_row.add_child(Glyph.attack_range(UnitCatalog.attack_range(def), 26))
	var kws0: Array = PlayerState.unit_keywords(inst) if not inst.is_empty() else def.keywords
	for k in kws0:
		kw_row.add_child(Glyph.keyword(k, 26))
	_build_rules()
	if extra_text != "":
		var ex := Label.new()
		ex.text = extra_text
		ex.autowrap_mode = TextServer.AUTOWRAP_WORD
		ex.custom_minimum_size = Vector2(WIDTH - 48, 0)
		ex.add_theme_font_size_override("font_size", 12)
		ex.add_theme_color_override("font_color", Color("f2c34a"))
		_body.add_child(ex)
	# height: grows with the rules
	var h := maxf(MIN_HEIGHT, 18.0 + _body.get_combined_minimum_size().y + 28.0)
	custom_minimum_size = Vector2(WIDTH, h)
	size = custom_minimum_size
	bg.size = size
	# corner bubbles
	var st := UnitCard.stats(def, inst)
	_bubble(&"circle", C_SPD, Vector2(30, 30), Vector2(-10, -10), str(int(st.ini)))
	_bubble(&"circle", C_ATK, Vector2(34, 34), Vector2(-10, h - 24), str(int(st.atk)))
	_bubble(&"circle", C_HP, Vector2(36, 36), Vector2(WIDTH - 26, h - 26), str(int(st.hp)))
	_bubble(&"burst", C_AP, Vector2(30, 30), Vector2(WIDTH - 44, -14), str(int(st.ap)))
	_bubble(&"shield", C_PP, Vector2(26, 28), Vector2(WIDTH - 14, 6), str(int(st.pp)))
	var rg := Glyph.rarity(def.rarity, 30)
	rg.position = Vector2(WIDTH * 0.5 - 15, h - 16)
	add_child(rg)
	# factions (left edge) and archetypes (right edge)
	var fg := Glyph.faction(def.faction, 26)
	fg.position = Vector2(-13, 92)
	add_child(fg)
	var kws: Array = PlayerState.unit_keywords(inst) if not inst.is_empty() else def.keywords
	var y := 96.0
	for a in Keywords.archetypes_of_keywords(kws):
		var ag := Glyph.make(&"circle", ARCH_COLORS.get(a, Color.GRAY), Vector2(18, 18))
		ag.mouse_filter = Control.MOUSE_FILTER_STOP
		ag.position = Vector2(WIDTH - 9, y)
		ag.tooltip_text = Keywords.ARCHETYPES[a].name
		add_child(ag)
		y += 22.0


func _bubble(k: StringName, c: Color, s: Vector2, pos: Vector2, t: String) -> void:
	var g := Glyph.make(k, c, s, t)
	g.position = pos
	add_child(g)


func _build_rules() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_body.add_child(box)
	for i in rules.size():
		var g: Dictionary = rules[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.tooltip_text = Describe.gambit(g)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var col := C_AP if g.kind == &"ap" else C_PP
		var bgp := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("252837")
		sb.set_content_margin_all(3)
		bgp.add_theme_stylebox_override("panel", sb)
		bgp.add_child(row)
		box.add_child(bgp)
		var act := Label.new()
		act.text = Describe.ACTION_SHORT.get(g.action, String(g.action))
		act.custom_minimum_size = Vector2(58, 0)
		act.add_theme_font_size_override("font_size", 11)
		act.add_theme_color_override("font_color", col)
		row.add_child(act)
		var conds := Describe.rule_conds(g)
		for ci in 2:
			var chip := Button.new()
			chip.text = Describe.cond_short(conds[ci][0], conds[ci][1])
			chip.custom_minimum_size = Vector2(54, 0)
			chip.add_theme_font_size_override("font_size", 10)
			chip.disabled = not editable
			chip.focus_mode = Control.FOCUS_NONE
			chip.pressed.connect(_cycle.bind(i, ci))
			row.add_child(chip)
		var pip := Glyph.make(&"circle", col, Vector2(8, 8))
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pip)
		if editable:
			_tiny(row, &"up", _move_up.bind(i), i > 0)
			_tiny(row, &"cross", _remove.bind(i), rules.size() > 1)
	if editable:
		var add := Button.new()
		add.icon = null
		add.text = "+"
		add.focus_mode = Control.FOCUS_NONE
		add.pressed.connect(_add)
		box.add_child(add)


func _tiny(row: HBoxContainer, k: StringName, cb: Callable, enabled: bool) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(16, 16)
	b.flat = true
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	var g := Glyph.make(k, Color("c8c8d8") if enabled else Color("4e5163"), Vector2(14, 14))
	g.position = Vector2(1, 1)
	b.add_child(g)
	row.add_child(b)


func _cycle(i: int, ci: int) -> void:
	var g: Dictionary = rules[i]
	var key_c := "cond" if ci == 0 else "cond2"
	var key_a := "arg" if ci == 0 else "arg2"
	var cur := {"c": g.get(key_c, &""), "a": g.get(key_a, 0.0)}
	var idx := -1
	for k in Describe.COND_PRESETS.size():
		var p: Dictionary = Describe.COND_PRESETS[k]
		if p.get("c", &"") == cur.c and is_equal_approx(float(p.get("a", 0.0)), float(cur.a)):
			idx = k
	var nxt: Dictionary = Describe.COND_PRESETS[(idx + 1) % Describe.COND_PRESETS.size()]
	g.erase(key_c)
	g.erase(key_a)
	if ci == 0:
		g.erase("arg_kw")
	if nxt.has("c"):
		g[key_c] = nxt.c
		g[key_a] = nxt.get("a", 0.0)
	_changed()


func _move_up(i: int) -> void:
	var t = rules[i]
	rules[i] = rules[i - 1]
	rules[i - 1] = t
	_changed()


func _remove(i: int) -> void:
	rules.remove_at(i)
	_changed()


func _add() -> void:
	var base: Dictionary = UnitCatalog.ROLE_DEFAULT_GAMBIT[def.role].duplicate()
	rules.insert(maxi(0, rules.size() - 1), base)
	_changed()


func _changed() -> void:
	rules_changed.emit(rules.duplicate(true))
	_rebuild()
