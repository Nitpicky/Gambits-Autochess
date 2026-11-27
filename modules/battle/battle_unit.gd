class_name BattleUnit
extends AttributeHolder
## A unit inside one battle. Every number is an Attribute:
##   stats: hp (pool), attack, initiative (Speed), ap (pool), pp (pool)
##   keywords: "kw_<id>" (value = X, merges by adding; temporary grants are flat sources with a timer)
##   statuses: "st_<id>" (stacks + duration in its own turns, ticks at the end of its turns)
## This class adds board position, the kit (actions, triggers, flags) and small helpers.

var uid: int = 0
var spec_uid: int = -1    ## the roster instance uid (for permanent stacks and gold)
var def: Dictionary = {}
var kit: Dictionary = {}  ## roster kit (JSON dict)
var side: int = 0
var row: int = 0
var col: int = 0
var alive: bool = true
var acted_this_turn: bool = false   ## acted this round (Backstab checks it)
var gambits: Array = []
var actions: Dictionary = {}        ## id -> action
var trigs: Array = []               ## event triggers [{on, fx, ...}]
var flags: Dictionary = {}          ## kit/upgrade/item parameters read by the engine
var is_token: bool = false
var level: int = 1
var sim = null  ## BattleSim
var used: Dictionary = {}           ## once/uses counters
var turn_used: Dictionary = {}      ## per-turn counters
var turns: int = 0                  ## own turns started
var moved_turn := false
var charge_used := false
var stall_mod: int = 0
var cc_count: Dictionary = {}       ## diminishing returns: status id -> times applied
var timers: Array = []              ## [{attr, src, left}] temporary flats
var perm: Dictionary = {}           ## permanent stacks carried between fights (from the team spec)
var form: Dictionary = {}
var forms_taken: int = 0
var below_half_fired := false
var hatch_tok: String = ""          ## eggs: what hatches ("" = the unit it came from)
var egg_of = null                   ## eggs: the BattleUnit that will return
var summoner = null
var buff_seq: int = 0


func display_name() -> String:
	return def.get("name", "?") + ("+" if level > 1 else "")


func hp() -> float:
	return current(&"hp")


func max_hp() -> float:
	return value(&"hp")


func hp_ratio() -> float:
	var m := max_hp()
	return hp() / m if m > 0.0 else 0.0


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
		a.current = clampf(a.current + n, 0.0, a.value())


# ---------------------------------------------------------------- keywords

func hushed() -> bool:
	return st(&"hush") > 0


## Keyword value (0 = doesn't have it). Hush removes keywords for its duration.
func kw(k: String) -> float:
	var a := get_attr(StringName("kw_" + k))
	if a == null:
		return 0.0
	if hushed() and k != "ephemeral":
		return 0.0
	return a.value()


func kw_raw(k: String) -> float:
	var a := get_attr(StringName("kw_" + k))
	return a.value() if a else 0.0


## Adds X of a keyword. dur > 0: for that many of its turns. cap: the total never goes past it.
func add_kw(k: String, n: float, dur: int = -1, cap: float = 0.0) -> void:
	var id := StringName("kw_" + k)
	var a := get_attr(id)
	if a == null:
		a = add(Attribute.make(id, 0.0, Attribute.Merge.ADD_VALUE))
		a.tags = [&"keyword"]
	if cap > 0.0:
		n = minf(n, cap - a.value())
		if n <= 0.0:
			return
	if dur > 0:
		buff_seq += 1
		var src := StringName("buff_%d" % buff_seq)
		a.add_flat(src, n)
		timers.append({"attr": id, "src": src, "left": dur})
	else:
		a.base += n


func del_kw(k: String) -> void:
	remove(StringName("kw_" + k))


## A stat buff (attack, hp, initiative). Temporary ones carry a timer; all are Purge-able ("buff_" sources).
func buff(stat: StringName, n: float, dur: int = -1, purgeable := true) -> void:
	var a := get_attr(stat)
	if a == null:
		return
	buff_seq += 1
	var src := StringName(("buff_%d" if purgeable else "perm_%d") % buff_seq)
	a.add_flat(src, n)
	if dur > 0:
		timers.append({"attr": stat, "src": src, "left": dur})


# ---------------------------------------------------------------- statuses

func st(id: StringName) -> int:
	var a := get_attr(StringName("st_" + String(id)))
	return a.stacks if a else 0


func set_status(id: StringName, n: int, dur: int = -1, max_n: int = 99) -> Attribute:
	var key := StringName("st_" + String(id))
	var a := get_attr(key)
	if a == null:
		a = Attribute.make(key, 0.0, Attribute.Merge.ADD_STACKS)
		a.tags = [&"status"]
		a.stacks = 0
		a.duration = dur
		add(a)
	a.stacks = mini(max_n, a.stacks + n)
	if dur > 0 or a.duration > 0:
		a.duration = maxi(a.duration, dur)
	if a.stacks <= 0:
		remove(key)
	return a


func clear_status(id: StringName) -> void:
	remove(StringName("st_" + String(id)))


func statuses() -> Array:
	var out: Array = []
	for a in attributes.values():
		if &"status" in a.tags:
			out.append(StringName(String(a.id).substr(3)))
	return out


## End of its own turn: temporary keywords/buffs and timed statuses tick down.
func tick() -> void:
	var keep: Array = []
	for t in timers:
		t.left -= 1
		if t.left <= 0:
			var a := get_attr(t.attr)
			if a:
				a.remove_source(t.src)
		else:
			keep.append(t)
	timers = keep
	for a in attributes.values().duplicate():
		if &"status" in a.tags and a.duration > 0:
			a.duration -= 1
			if a.duration <= 0:
				remove(a.id)


## Display keywords for the log/UI: every keyword attribute with a value.
func keywords() -> Array:
	var out: Array = []
	for a in attributes.values():
		if &"keyword" in a.tags and a.value() > 0.0:
			out.append(String(a.id).substr(3))
	return out
