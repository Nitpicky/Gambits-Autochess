class_name BattleUnit
extends AttributeHolder
## A unit inside one battle. All numbers live in Attributes; this class only
## adds board position and convenience getters.

var uid: int = 0
var def: Dictionary = {}
var side: int = 0
var row: int = 0
var col: int = 0
var alive: bool = true
var acted_this_turn: bool = false
var gambits: Array = []
var is_token: bool = false
var level: int = 1
var sim = null  ## BattleSim
var used: Dictionary = {}  ## once-per-battle flags (phoenix, first attack...)


func display_name() -> String:
	return def.get("name", "?") + ("+" if level > 1 else "")


func hp() -> float:
	return current(&"hp")


func max_hp() -> float:
	return value(&"hp")


func hp_ratio() -> float:
	var m := max_hp()
	return hp() / m if m > 0.0 else 0.0


func atk() -> float:
	return value(&"attack")


func initiative() -> float:
	return value(&"initiative")


func ap() -> int:
	return int(current(&"ap"))


func pp() -> int:
	return int(current(&"pp"))


func spend(pool: StringName, n: int = 1) -> void:
	var a := get_attr(pool)
	if a:
		a.current = maxf(0.0, a.current - n)


func gain(pool: StringName, n: float) -> void:
	var a := get_attr(pool)
	if a:
		a.current = minf(a.value() + 99.0, a.current + n)


func refill(pool: StringName) -> void:
	var a := get_attr(pool)
	if a:
		a.current = a.value()


## Flag attributes: items, relics and keywords use them to tweak rules.
func flag(name: StringName, default: float = 0.0) -> float:
	var a := get_attr(name)
	return a.value() if a else default


func has_flag(name: StringName) -> bool:
	return has(name)


func keywords() -> Array:
	var out: Array = []
	for a in attributes.values():
		if &"keyword" in a.tags:
			out.append(a.id)
	return out
