class_name BattleView
extends Control
## Replays a BattleSim log: sprites, HP bars, floating numbers, a text log.
## PROTOTYPE: placeholder presentation.

signal finished

var speed: float = 1.0
var skipping: bool = false
var nodes: Dictionary = {}   ## uid -> {"root", "sprite", "bar", "label", "side"}
var names: Dictionary = {}   ## uid -> name
var log_label := RichTextLabel.new()
var title := Label.new()
var turn_label := Label.new()
var field := Control.new()
var done_button := Button.new()
var running := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.1, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field.offset_right = -380
	field.offset_top = 70
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(field)
	title.position = Vector2(20, 12)
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)
	turn_label.position = Vector2(20, 46)
	add_child(turn_label)
	log_label.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	log_label.offset_left = -370
	log_label.offset_top = 60
	log_label.offset_bottom = -70
	log_label.offset_right = -10
	log_label.scroll_following = true
	log_label.bbcode_enabled = true
	add_child(log_label)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.position = Vector2(-370, -60)
	bar.offset_left = -370
	bar.offset_top = -56
	bar.offset_right = -10
	bar.offset_bottom = -16
	add_child(bar)
	for s in [1.0, 2.0, 4.0]:
		var b := Button.new()
		b.text = "%dx" % s
		b.pressed.connect(func(): speed = s)
		bar.add_child(b)
	var skip := Button.new()
	skip.text = "Skip"
	skip.pressed.connect(func(): skipping = true)
	bar.add_child(skip)
	done_button.text = "Continue"
	done_button.disabled = true
	done_button.pressed.connect(func(): finished.emit())
	bar.add_child(done_button)


func _cell_pos(side: int, row: int, col: int) -> Vector2:
	var w := field.size.x if field.size.x > 0.0 else 1200.0
	var h := field.size.y if field.size.y > 0.0 else 900.0
	var xs := [[0.30, 0.14], [0.70, 0.86]]  # [side][row]: front row is closer to the middle
	return Vector2(w * xs[side][row], h * (0.30 + 0.2 * col))


func setup(fight: Dictionary, left_name: String, right_name: String) -> void:
	title.text = "%s  vs  %s" % [left_name, right_name]
	for ev in fight.log:
		if ev.t == "start":
			for info in ev.units:
				_spawn(info)
			break


func _spawn(info: Dictionary) -> void:
	var root := Control.new()
	root.size = Vector2(120, 140)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = _cell_pos(info.side, info.row, info.col) - Vector2(60, 80)
	field.add_child(root)
	var sv := SpriteView.new()
	sv.size = Vector2(120, 110)
	root.add_child(sv)
	sv.show_unit(info.sprite, info.side == 1, 1.5)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.position = Vector2(15, 108)
	bar.size = Vector2(90, 8)
	bar.max_value = info.max
	bar.value = info.hp
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("4caf50") if info.side == 0 else Color("e05050")
	bar.add_theme_stylebox_override("fill", fill)
	root.add_child(bar)
	var lab := Label.new()
	lab.text = info.name
	lab.position = Vector2(0, 118)
	lab.size = Vector2(120, 20)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 12)
	root.add_child(lab)
	nodes[info.uid] = {"root": root, "sprite": sv, "bar": bar, "label": lab, "side": info.side}
	names[info.uid] = info.name


func play(fight: Dictionary) -> void:
	running = true
	for ev in fight.log:
		if not is_inside_tree():
			return
		var d := _apply(ev)
		if d > 0.0 and not skipping:
			await get_tree().create_timer(d / speed).timeout
	running = false
	done_button.disabled = false


func _who(uid) -> String:
	var n: String = names.get(uid, "?")
	var side: int = nodes[uid].side if nodes.has(uid) else 0
	return "[color=%s]%s[/color]" % ["#8fd18f" if side == 0 else "#f08a8a", n]


func _float_text(uid, text: String, color: Color) -> void:
	if skipping or not nodes.has(uid):
		return
	var l := Label.new()
	l.text = text
	l.modulate = color
	l.add_theme_font_size_override("font_size", 18)
	l.position = nodes[uid].root.position + Vector2(40, 0)
	field.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 40, 0.8 / speed)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8 / speed)
	tw.tween_callback(l.queue_free)


func _apply(ev: Dictionary) -> float:
	match ev.t:
		"turn":
			turn_label.text = "Turn %d" % ev.n
			log_label.append_text("[b]Turn %d[/b]\n" % ev.n)
			return 0.3
		"cycle":
			log_label.append_text("[i]Everyone is out of AP: AP and PP refill (cycle %d)[/i]\n" % ev.n)
			return 0.5
		"act":
			log_label.append_text("%s %s%s\n" % [_who(ev.u), "reacts: " if ev.reaction else "", ev.text])
			if nodes.has(ev.u):
				nodes[ev.u].sprite.play(&"attack")
			return 0.35
		"hit":
			if nodes.has(ev.u):
				nodes[ev.u].bar.max_value = ev.max
				nodes[ev.u].bar.value = ev.hp
				nodes[ev.u].sprite.play(&"hit")
			_float_text(ev.u, "-%d" % ev.amount, Color("ff6060"))
			log_label.append_text("   %s takes %d%s\n" % [_who(ev.u), ev.amount, (" (%s)" % ev.text) if ev.text != "" else ""])
			return 0.25
		"heal":
			if nodes.has(ev.u):
				nodes[ev.u].bar.max_value = ev.max
				nodes[ev.u].bar.value = ev.hp
			_float_text(ev.u, "+%d" % ev.amount, Color("70ff70"))
			log_label.append_text("   %s heals %d\n" % [_who(ev.u), ev.amount])
			return 0.2
		"blocked":
			_float_text(ev.u, ev.text, Color("a0d8ff"))
			log_label.append_text("   %s: %s\n" % [_who(ev.u), ev.text])
			return 0.2
		"status":
			_float_text(ev.u, ev.status, Color("b0c8ff"))
			log_label.append_text("   %s: %s\n" % [_who(ev.u), ev.status])
			return 0.1
		"buff":
			_float_text(ev.u, ev.text, Color("ffd070"))
			if ev.has("max") and nodes.has(ev.u):
				nodes[ev.u].bar.max_value = ev.max
				nodes[ev.u].bar.value = ev.hp
			log_label.append_text("   %s: %s\n" % [_who(ev.u), ev.text])
			return 0.1
		"death":
			if nodes.has(ev.u):
				nodes[ev.u].sprite.play(&"death", false)
				var tw := create_tween()
				tw.tween_property(nodes[ev.u].root, "modulate:a", 0.25, 0.6 / speed)
			log_label.append_text("   %s dies\n" % _who(ev.u))
			return 0.35
		"summon":
			_spawn(ev.unit)
			log_label.append_text("   %s is summoned\n" % _who(ev.unit.uid))
			return 0.25
		"move":
			if nodes.has(ev.u):
				var side: int = nodes[ev.u].side
				nodes[ev.u].root.position = _cell_pos(side, ev.row, ev.col) - Vector2(60, 80)
			log_label.append_text("   %s falls back\n" % _who(ev.u))
			return 0.2
		"timeout":
			log_label.append_text("[i]Time! Remaining HP: %d%% vs %d%%[/i]\n" % [ev.ratios[0] * 100, ev.ratios[1] * 100])
			return 0.3
		"end":
			var txt := "Draw" if ev.winner == -1 else ("Victory!" if ev.winner == 0 else "Defeat")
			turn_label.text = txt
			log_label.append_text("[b]%s[/b]\n" % txt)
			return 0.0
	return 0.0
