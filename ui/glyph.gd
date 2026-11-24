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
