class_name HpBar
extends Control
## PROTOTYPE: Overwatch-style HP bar: slanted, one block per GameConfig.HP_STEP HP, with gaps.
## White for your units, red for enemies. Animates towards new values.

var max_hp: float = 100.0
var hp: float = 100.0
var shown: float = 100.0
var fill := Color("f4f4f4")
const SKEW := 4.0
const GAP := 2.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(cur: float, mx: float, enemy: bool) -> void:
	max_hp = maxf(1.0, mx)
	hp = cur
	shown = cur
	fill = Color("e0566b") if enemy else Color("f4f4f4")
	queue_redraw()


func set_hp(cur: float, mx: float) -> void:
	max_hp = maxf(1.0, mx)
	hp = cur
	var tw := create_tween()
	tw.tween_method(func(v): shown = v; queue_redraw(), shown, cur, 0.25)


func _draw() -> void:
	var n := maxi(1, int(ceil(max_hp / GameConfig.HP_STEP)))
	var w := (size.x - GAP * (n - 1) - SKEW) / n
	var h := size.y
	for i in n:
		var x := i * (w + GAP)
		var seg_lo := i * GameConfig.HP_STEP
		var frac := clampf((shown - seg_lo) / GameConfig.HP_STEP, 0.0, 1.0)
		_seg(x, w, h, Color(0, 0, 0, 0.55))
		if frac > 0.0:
			_seg(x, w * frac, h, fill)


func _seg(x: float, w: float, h: float, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(x + SKEW, 0), Vector2(x + SKEW + w, 0), Vector2(x + w, h), Vector2(x, h)]), c)
