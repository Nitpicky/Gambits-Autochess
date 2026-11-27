class_name InfoCard
extends Control
## PROTOTYPE: hover card for an item or a relic, same look as the unit card (fixed width, height grows).
## Sprite on top, name, rarity shape at the bottom middle, stat bubbles and the effect text.

const WIDTH := 240.0


## kind: &"item" or &"relic"; d: the catalog definition.
static func build(kind: StringName, d: Dictionary) -> InfoCard:
	var c := InfoCard.new()
	c._kind = kind
	c._def = d
	c.size = Vector2(WIDTH, 200)  # real height is known once laid out in the tree
	return c


var _kind: StringName
var _def: Dictionary


func _ready() -> void:
	_make(_kind, _def)


func _make(kind: StringName, d: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rar: int = d.get("rarity", 0)
	var rc: Color = UnitCatalog.RARITY_COLORS[clampi(rar, 0, UnitCatalog.RARITY_COLORS.size() - 1)]
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c1e28")
	sb.border_color = rc
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12 if kind == &"item" else 4)
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var body := VBoxContainer.new()
	body.position = Vector2(18, 14)
	body.custom_minimum_size = Vector2(WIDTH - 36, 0)
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	var pc := CenterContainer.new()
	pc.custom_minimum_size = Vector2(0, 72)
	body.add_child(pc)
	var sv := SpriteView.new()
	sv.custom_minimum_size = Vector2(72, 72)
	pc.add_child(sv)
	sv.show_icon(d.icon, 1.6)
	var nm := Label.new()
	nm.text = d.name
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 15)
	body.add_child(nm)
	# flat stats as coloured bubbles (items only)
	var stats: Dictionary = d.get("stats", {})
	if not stats.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		body.add_child(row)
		var cols := {"hp": UnitCard.C_HP, "atk": UnitCard.C_ATK, "ini": UnitCard.C_SPD, "ap": UnitCard.C_AP, "pp": UnitCard.C_PP, "dr": Color("c8c8d8")}
		var shapes := {"ap": &"burst", "pp": &"shield"}
		for k in stats:
			var v = stats[k]
			var t := ("-%d%%" % int(v * 100)) if k == "dr" else ("%+d" % int(v))
			var g := Glyph.make(shapes.get(k, &"circle"), cols.get(k, Color.GRAY), Vector2(38, 38), t)
			g.font_size = 12
			row.add_child(g)
	var txt := Label.new()
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD
	txt.custom_minimum_size = Vector2(WIDTH - 36, 0)
	txt.add_theme_font_size_override("font_size", 12)
	txt.add_theme_color_override("font_color", Color("c8c8d8"))
	var lines: Array[String] = []
	if d.get("text", "") != "":
		lines.append(d.text)
	if kind == &"item":
		var req := ItemCatalog.req_text(d)
		if req != "":
			lines.append("Requires " + req)
	elif d.get("effect", {}).get("faction", &"") != &"":
		lines.append("Faction relic: %s units." % Keywords.FACTION_NAMES[d.effect.faction])
	txt.text = "\n".join(lines)
	body.add_child(txt)
	var h := 14.0 + body.get_combined_minimum_size().y + 26.0
	custom_minimum_size = Vector2(WIDTH, h)
	size = custom_minimum_size
	bg.size = size
	var rg := Glyph.rarity(clampi(rar, 0, 4), 26)
	rg.position = Vector2(WIDTH * 0.5 - 13, h - 14)
	add_child(rg)
