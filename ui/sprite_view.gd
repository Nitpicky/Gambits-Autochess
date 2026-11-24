class_name SpriteView
extends Control
## Shows a Duelyst SpriteFrames (unit or icon) centred in this Control.

static var _cache: Dictionary = {}

var sprite := AnimatedSprite2D.new()
var sprite_scale: float = 1.0


static func frames_for(kind: String, name: String) -> SpriteFrames:
	var path := "res://art/duelyst/%s/%s.tres" % [kind, name]
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sprite)
	sprite.centered = true
	resized.connect(_place)


func show_unit(sprite_name: String, flip: bool = false, s: float = 1.0) -> void:
	_set_frames(SpriteView.frames_for("units", sprite_name), &"idle", flip, s)


func show_icon(icon_name: String, s: float = 1.0) -> void:
	var f := SpriteView.frames_for("icons", icon_name)
	var anim: StringName = &""
	if f:
		var names := f.get_animation_names()
		anim = names[0] if names.size() > 0 else &""
	_set_frames(f, anim, false, s)


func clear() -> void:
	sprite.sprite_frames = null


func play(anim: StringName, then_idle := true) -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim):
		return
	sprite.play(anim)
	if then_idle and anim != &"idle" and anim != &"death":
		if not sprite.animation_finished.is_connected(_back_to_idle):
			sprite.animation_finished.connect(_back_to_idle, CONNECT_ONE_SHOT)


func _back_to_idle() -> void:
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(&"idle"):
		sprite.play(&"idle")


func _set_frames(f: SpriteFrames, anim: StringName, flip: bool, s: float) -> void:
	sprite.sprite_frames = f
	sprite.flip_h = flip
	sprite_scale = s
	sprite.scale = Vector2(s, s)
	if f and anim != &"" and f.has_animation(anim):
		f.set_animation_loop(anim, true)
		sprite.play(anim)
	_place()


func _place() -> void:
	sprite.position = Vector2(size.x * 0.5, size.y * 0.55)
