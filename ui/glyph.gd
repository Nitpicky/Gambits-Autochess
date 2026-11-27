class_name Glyph
extends Control
## PROTOTYPE: draws the small vector shapes the screens use instead of text
## (rarity shapes, stat bubbles, round icons, hex slots, coin, buttons' icons).
## Optional centred `text` on top (stat numbers).

var kind: StringName = &"circle"
var color: Color = Color.WHITE
var text: String = ""
var text_color: Color = Color("14151c")
var font_size: int = 13
var outline: Color = Color(0, 0, 0, 0)


static func make(k: StringName, c: Color, s: Vector2, t: String = "") -> Glyph:
	var g := Glyph.new()
	g.kind = k
	g.color = c
	g.text = t
	g.custom_minimum_size = s
	g.size = s
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## Rarity -> shape (index = UnitCatalog.Rarity).
const RARITY_SHAPES: Array[StringName] = [&"tri_down", &"diamond", &"pentagon", &"hexagon", &"star", &"circle", &"circle"]


static func rarity(r: int, s: float) -> Glyph:
	return make(RARITY_SHAPES[r], UnitCatalog.RARITY_COLORS[r], Vector2(s, s))


## A faction emblem on a dark disc, hover shows the faction name.
static func faction(f: StringName, s: float) -> Glyph:
	var g := make(&"disc", Color("14151c"), Vector2(s, s))
	g.outline = Keywords.FACTION_COLORS.get(f, Color.GRAY)
	var e := make(StringName("f_" + String(f)), Keywords.FACTION_COLORS.get(f, Color.GRAY), Vector2(s, s) * 0.62)
	e.position = Vector2(s, s) * 0.19
	g.add_child(e)
	g.mouse_filter = Control.MOUSE_FILTER_STOP
	g.tooltip_text = Keywords.FACTION_NAMES.get(f, String(f))
	return g


const DRAWN_KEYWORDS := [&"guard", &"chill", &"swift", &"grow", &"sacrifice", &"deathwatch"]


## A keyword icon on a dark disc (faction-coloured), hover shows its name and rule.
static func keyword(k: StringName, s: float) -> Glyph:
	var kd: Dictionary = Keywords.get_kw(k)
	var col: Color = Keywords.FACTION_COLORS.get(kd.get("faction", &"neutral"), Color.GRAY)
	var g := make(&"disc", Color("2b2f45"), Vector2(s, s))
	if StringName(k) in DRAWN_KEYWORDS:
		var e := make(StringName("k_" + String(k)), col, Vector2(s, s) * 0.66)
		e.position = Vector2(s, s) * 0.17
		g.add_child(e)
	else:  # PROTOTYPE: no icon yet, the keyword's first two letters
		g.text = String(kd.get("name", String(k))).substr(0, 2)
		g.text_color = col
		g.font_size = int(s * 0.42)
	g.mouse_filter = Control.MOUSE_FILTER_STOP
	g.tooltip_text = "%s\n%s" % [kd.get("name", String(k)), kd.get("text", "")]
	return g


## Melee (sword) or Ranged (bow) badge, shown first in a unit's keyword row.
static func attack_range(r: StringName, s: float) -> Glyph:
	var g := make(&"disc", Color("2b2f45"), Vector2(s, s))
	g.outline = Color("e8e8ee")
	var e := make(&"k_ranged" if r == &"ranged" else &"k_melee", Color("e8e8ee"), Vector2(s, s) * 0.62)
	e.position = Vector2(s, s) * 0.19
	g.add_child(e)
	g.mouse_filter = Control.MOUSE_FILTER_STOP
	g.tooltip_text = "Ranged\nAttacks any enemy, from the back row." if r == &"ranged" else "Melee\nAttacks the enemy front row."
	return g


func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x * size.x, p.y * size.y))
	return out


func _ngon(n: int, rot: float, r := 0.5) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := rot + TAU * i / n
		out.append(size * 0.5 + Vector2(cos(a), sin(a)) * size * r)
	return out


func _draw() -> void:
	var c := size * 0.5
	match kind:
		&"disc":
			draw_circle(c, minf(size.x, size.y) * 0.5, color)
		# ---- faction emblems
		&"f_lyonar":  ## sun
			draw_circle(c, size.x * 0.22, color)
			for i in 8:
				var a := TAU * i / 8
				draw_line(c + Vector2(cos(a), sin(a)) * size.x * 0.3, c + Vector2(cos(a), sin(a)) * size.x * 0.48, color, 2.0, true)
		&"f_vanar":  ## ice crystal
			draw_colored_polygon(_poly([Vector2(0.5, 0), Vector2(0.72, 0.35), Vector2(0.5, 1), Vector2(0.28, 0.35)]), color)
			draw_colored_polygon(_poly([Vector2(0.12, 0.3), Vector2(0.26, 0.45), Vector2(0.18, 0.8)]), color)
			draw_colored_polygon(_poly([Vector2(0.88, 0.3), Vector2(0.74, 0.45), Vector2(0.82, 0.8)]), color)
		&"f_songhai":  ## crescent moon
			draw_circle(c, size.x * 0.46, color)
			draw_circle(c + size * Vector2(0.2, -0.12), size.x * 0.38, Color("14151c"))
		&"f_magmar":  ## three claw marks
			for i in 3:
				var x := 0.25 + i * 0.25
				draw_colored_polygon(_poly([Vector2(x - 0.02, 0.0), Vector2(x + 0.09, 0.05), Vector2(x - 0.03, 1.0), Vector2(x - 0.1, 0.9)]), color)
		&"f_abyssian":  ## horns
			draw_colored_polygon(_poly([Vector2(0.05, 0.0), Vector2(0.3, 0.45), Vector2(0.45, 0.6), Vector2(0.3, 0.75), Vector2(0.12, 0.45)]), color)
			draw_colored_polygon(_poly([Vector2(0.95, 0.0), Vector2(0.7, 0.45), Vector2(0.55, 0.6), Vector2(0.7, 0.75), Vector2(0.88, 0.45)]), color)
			draw_circle(c + Vector2(0, size.y * 0.22), size.x * 0.14, color)
		&"f_vetruvian":  ## pyramid
			draw_colored_polygon(_poly([Vector2(0.5, 0.05), Vector2(1, 0.92), Vector2(0, 0.92)]), color)
			draw_line(size * Vector2(0.5, 0.05), size * Vector2(0.62, 0.92), Color("14151c"), 1.5, true)
		# ---- keywords
		&"k_guard":  ## shield
			draw_colored_polygon(_poly([Vector2(0.1, 0.05), Vector2(0.9, 0.05), Vector2(0.9, 0.55), Vector2(0.5, 1), Vector2(0.1, 0.55)]), color)
		&"k_rally":  ## banner
			draw_rect(Rect2(size * Vector2(0.15, 0.0), size * Vector2(0.1, 1.0)), color)
			draw_colored_polygon(_poly([Vector2(0.25, 0.05), Vector2(0.95, 0.2), Vector2(0.25, 0.55)]), color)
		&"k_ward":  ## bubble
			draw_arc(c, size.x * 0.44, 0, TAU, 32, color, 2.5, true)
			draw_arc(c, size.x * 0.24, PI * 1.1, PI * 1.6, 8, color, 2.0, true)
		&"k_chill":  ## snowflake
			for i in 3:
				var a := PI / 2 + PI * i / 3
				draw_line(c + Vector2(cos(a), sin(a)) * size.x * 0.48, c - Vector2(cos(a), sin(a)) * size.x * 0.48, color, 2.0, true)
		&"k_swift":  ## double chevron
			for x in [0.1, 0.45]:
				draw_colored_polygon(_poly([Vector2(x, 0.1), Vector2(x + 0.18, 0.1), Vector2(x + 0.45, 0.5), Vector2(x + 0.18, 0.9), Vector2(x, 0.9), Vector2(x + 0.27, 0.5)]), color)
		&"k_mark":  ## crosshair
			draw_arc(c, size.x * 0.34, 0, TAU, 32, color, 2.0, true)
			draw_line(size * Vector2(0.5, 0.0), size * Vector2(0.5, 0.35), color, 2.0)
			draw_line(size * Vector2(0.5, 0.65), size * Vector2(0.5, 1.0), color, 2.0)
			draw_line(size * Vector2(0.0, 0.5), size * Vector2(0.35, 0.5), color, 2.0)
			draw_line(size * Vector2(0.65, 0.5), size * Vector2(1.0, 0.5), color, 2.0)
		&"k_grow":  ## sprout
			draw_line(size * Vector2(0.5, 1.0), size * Vector2(0.5, 0.35), color, 2.5)
			draw_colored_polygon(_poly([Vector2(0.5, 0.5), Vector2(0.1, 0.3), Vector2(0.15, 0.05), Vector2(0.45, 0.25)]), color)
			draw_colored_polygon(_poly([Vector2(0.5, 0.4), Vector2(0.9, 0.15), Vector2(0.95, 0.45), Vector2(0.6, 0.55)]), color)
		&"k_feast":  ## fangs
			draw_colored_polygon(_poly([Vector2(0.05, 0.1), Vector2(0.45, 0.1), Vector2(0.28, 0.95)]), color)
			draw_colored_polygon(_poly([Vector2(0.55, 0.1), Vector2(0.95, 0.1), Vector2(0.72, 0.95)]), color)
		&"k_sacrifice":  ## blood drop
			draw_circle(c + Vector2(0, size.y * 0.15), size.x * 0.32, color)
			draw_colored_polygon(_poly([Vector2(0.5, 0.0), Vector2(0.8, 0.55), Vector2(0.2, 0.55)]), color)
		&"k_deathwatch":  ## eye
			draw_colored_polygon(_poly([Vector2(0.0, 0.5), Vector2(0.3, 0.2), Vector2(0.7, 0.2), Vector2(1.0, 0.5), Vector2(0.7, 0.8), Vector2(0.3, 0.8)]), color)
			draw_circle(c, size.x * 0.16, Color("14151c"))
		&"k_construct":  ## cube
			draw_colored_polygon(_ngon(6, -PI / 2, 0.48), color)
			draw_line(c, c + Vector2(0, size.y * 0.48), Color("14151c"), 1.5)
			draw_line(c, c + Vector2(-size.x * 0.42, -size.y * 0.24), Color("14151c"), 1.5)
			draw_line(c, c + Vector2(size.x * 0.42, -size.y * 0.24), Color("14151c"), 1.5)
		&"k_melee":  ## sword
			draw_line(size * Vector2(0.85, 0.05), size * Vector2(0.25, 0.65), color, 3.0, true)
			draw_line(size * Vector2(0.12, 0.48), size * Vector2(0.45, 0.82), color, 2.5, true)
			draw_line(size * Vector2(0.28, 0.68), size * Vector2(0.08, 0.92), color, 3.0, true)
		&"k_ranged":  ## bow and arrow
			draw_arc(size * Vector2(0.25, 0.5), size.x * 0.48, -PI * 0.42, PI * 0.42, 16, color, 2.5, true)
			draw_line(size * Vector2(0.38, 0.06), size * Vector2(0.38, 0.94), color, 1.2, true)
			draw_line(size * Vector2(0.1, 0.5), size * Vector2(0.95, 0.5), color, 2.0, true)
			draw_colored_polygon(_poly([Vector2(1.0, 0.5), Vector2(0.8, 0.38), Vector2(0.8, 0.62)]), color)
		&"k_fortify":  ## tower
			draw_rect(Rect2(size * Vector2(0.2, 0.3), size * Vector2(0.6, 0.7)), color)
			for x in [0.2, 0.44, 0.68]:
				draw_rect(Rect2(size * Vector2(x, 0.1), size * Vector2(0.12, 0.2)), color)
		&"circle":
			draw_circle(c, minf(size.x, size.y) * 0.5, color)
		&"ring":
			draw_arc(c, minf(size.x, size.y) * 0.5 - 2, 0, TAU, 48, color, 3.0, true)
		&"tri_down":
			draw_colored_polygon(_poly([Vector2(0, 0.1), Vector2(1, 0.1), Vector2(0.5, 1)]), color)
		&"diamond":
			draw_colored_polygon(_poly([Vector2(0.5, 0), Vector2(1, 0.5), Vector2(0.5, 1), Vector2(0, 0.5)]), color)
		&"pentagon":
			draw_colored_polygon(_ngon(5, -PI / 2), color)
		&"hexagon":
			draw_colored_polygon(_ngon(6, 0), color)
		&"hex_slot":  ## pointy-top hexagon (item slots)
			draw_colored_polygon(_ngon(6, -PI / 2), color)
		&"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + TAU * i / 10
				var r := 0.5 if i % 2 == 0 else 0.22
				pts.append(c + Vector2(cos(a), sin(a)) * size * r)
			draw_colored_polygon(pts, color)
		&"burst":  ## AP: four-point burst
			draw_colored_polygon(_poly([Vector2(0.5, 0), Vector2(0.64, 0.36), Vector2(1, 0.5), Vector2(0.64, 0.64), Vector2(0.5, 1), Vector2(0.36, 0.64), Vector2(0, 0.5), Vector2(0.36, 0.36)]), color)
		&"shield":  ## PP
			draw_colored_polygon(_poly([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.58), Vector2(0.5, 1), Vector2(0, 0.58)]), color)
		&"square":
			draw_rect(Rect2(Vector2.ZERO, size), color)
		&"coin":
			draw_circle(c, size.x * 0.5, Color("b8861f"))
			draw_circle(c - Vector2(1, 1), size.x * 0.42, color)
		&"swords":  ## PvP round
			draw_line(size * Vector2(0.2, 0.2), size * Vector2(0.8, 0.8), color, 2.5, true)
			draw_line(size * Vector2(0.8, 0.2), size * Vector2(0.2, 0.8), color, 2.5, true)
			draw_line(size * Vector2(0.15, 0.6), size * Vector2(0.4, 0.85), color, 2.0, true)
			draw_line(size * Vector2(0.85, 0.6), size * Vector2(0.6, 0.85), color, 2.0, true)
		&"skull":  ## PvE round
			draw_circle(c - Vector2(0, size.y * 0.06), size.x * 0.34, color)
			draw_rect(Rect2(size * Vector2(0.32, 0.55), size * Vector2(0.36, 0.25)), color)
			draw_circle(c + size * Vector2(-0.13, -0.08), size.x * 0.08, Color("14151c"))
			draw_circle(c + size * Vector2(0.13, -0.08), size.x * 0.08, Color("14151c"))
		&"crown":  ## choice round
			draw_colored_polygon(_poly([Vector2(0.1, 0.8), Vector2(0.9, 0.8), Vector2(0.95, 0.25), Vector2(0.7, 0.5), Vector2(0.5, 0.15), Vector2(0.3, 0.5), Vector2(0.05, 0.25)]), color)
		&"person":  ## unit count
			draw_circle(c - Vector2(0, size.y * 0.2), size.x * 0.2, color)
			draw_colored_polygon(_poly([Vector2(0.15, 1), Vector2(0.85, 1), Vector2(0.75, 0.55), Vector2(0.25, 0.55)]), color)
		&"reroll":
			draw_arc(c, size.x * 0.32, 0.3, TAU - 0.6, 24, color, 2.0, true)
			draw_colored_polygon(_poly([Vector2(0.75, 0.15), Vector2(0.95, 0.45), Vector2(0.6, 0.45)]), color)
		&"lock", &"unlock":
			draw_rect(Rect2(size * Vector2(0.22, 0.45), size * Vector2(0.56, 0.45)), color)
			var x_off := 0.12 if kind == &"unlock" else 0.0
			draw_arc(c + Vector2(size.x * x_off, -size.y * 0.05), size.x * 0.2, PI, TAU, 16, color, 2.0, true)
		&"coin_bag":  ## Interest
			draw_circle(c + Vector2(0, size.y * 0.1), size.x * 0.36, color)
			draw_colored_polygon(_poly([Vector2(0.35, 0.05), Vector2(0.65, 0.05), Vector2(0.58, 0.3), Vector2(0.42, 0.3)]), color)
		&"blade":  ## Bounty
			draw_colored_polygon(_poly([Vector2(0.5, 0), Vector2(0.62, 0.15), Vector2(0.58, 0.7), Vector2(0.42, 0.7), Vector2(0.38, 0.15)]), color)
			draw_rect(Rect2(size * Vector2(0.25, 0.7), size * Vector2(0.5, 0.08)), color)
			draw_rect(Rect2(size * Vector2(0.45, 0.78), size * Vector2(0.1, 0.2)), color)
		&"flame":  ## Streak
			draw_colored_polygon(_poly([Vector2(0.5, 0), Vector2(0.8, 0.45), Vector2(0.75, 0.85), Vector2(0.5, 1), Vector2(0.25, 0.85), Vector2(0.2, 0.5), Vector2(0.38, 0.55)]), color)
		&"up":
			draw_colored_polygon(_poly([Vector2(0.5, 0.2), Vector2(0.85, 0.75), Vector2(0.15, 0.75)]), color)
		&"cross":
			draw_line(size * 0.25, size * 0.75, color, 2.0, true)
			draw_line(size * Vector2(0.75, 0.25), size * Vector2(0.25, 0.75), color, 2.0, true)
		&"plus":
			draw_line(size * Vector2(0.5, 0.2), size * Vector2(0.5, 0.8), color, 2.0, true)
			draw_line(size * Vector2(0.2, 0.5), size * Vector2(0.8, 0.5), color, 2.0, true)
	if outline.a > 0.0:
		draw_arc(c, minf(size.x, size.y) * 0.5, 0, TAU, 32, outline, 2.0, true)
	if text != "":
		var f := get_theme_default_font()
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(f, Vector2((size.x - ts.x) * 0.5, (size.y + ts.y * 0.62) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
