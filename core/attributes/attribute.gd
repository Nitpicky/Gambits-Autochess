class_name Attribute
extends Resource
## A single generic attribute attached to an AttributeHolder.
## Stats (HP, Attack...), statuses (Chill, Ward...), keywords (Guard, Grow...),
## player values (Gold, XP...) are all Attributes. Units have no hard-coded stats.
##
## value() = base + sum(flat). Every stat increase is flat (design rule: no % buffs).
## Optional `current` for pool-like values (HP, AP).

enum Merge { ADD_STACKS, ADD_VALUE, KEEP_MAX, REFRESH, REPLACE, IGNORE }

@export var id: StringName
@export var base: float = 0.0
@export var has_current: bool = false
@export var current: float = 0.0
@export var stacks: int = 1
@export var max_stacks: int = 99
@export var duration: int = -1  ## turns left, -1 = permanent
@export var merge: Merge = Merge.ADD_STACKS
@export var tags: Array[StringName] = []
@export var behaviours: Array[AttributeBehaviour] = []
@export var params: Dictionary = {}  ## free-form data for behaviours (e.g. pct per stack)

var flat: Dictionary = {}     ## source -> float
var holder = null             ## AttributeHolder (untyped to avoid cyclic refs)


static func make(p_id: StringName, p_base: float = 0.0, p_merge: Merge = Merge.ADD_STACKS) -> Attribute:
	var a := Attribute.new()
	a.id = p_id
	a.base = p_base
	a.merge = p_merge
	return a


static func make_pool(p_id: StringName, p_max: float) -> Attribute:
	var a := make(p_id, p_max, Merge.ADD_VALUE)
	a.has_current = true
	a.current = p_max
	return a


func value() -> float:
	var f := base
	for v in flat.values():
		f += v
	return f


func set_flat(source: StringName, amount: float) -> void:
	_change(func(): flat[source] = amount)


func add_flat(source: StringName, amount: float) -> void:
	_change(func(): flat[source] = flat.get(source, 0.0) + amount)


func remove_source(source: StringName) -> void:
	_change(func(): flat.erase(source))


## Keeps `current` proportional-safe: when the max grows, current grows by the same amount.
func _change(fn: Callable) -> void:
	var before := value()
	fn.call()
	if has_current:
		var after := value()
		if after > before:
			current += after - before
		current = minf(current, after)


func merge_from(other: Attribute) -> void:
	match merge:
		Merge.ADD_STACKS:
			stacks = mini(max_stacks, stacks + other.stacks)
			duration = maxi(duration, other.duration)
		Merge.ADD_VALUE:
			base += other.base
			if has_current:
				current += other.base
		Merge.KEEP_MAX:
			base = maxf(base, other.base)
			stacks = maxi(stacks, other.stacks)
		Merge.REFRESH:
			duration = maxi(duration, other.duration)
		Merge.REPLACE:
			base = other.base
			stacks = other.stacks
			duration = other.duration
			params = other.params.duplicate()
		Merge.IGNORE:
			pass
	for b in other.behaviours:
		if not _has_behaviour_type(b):
			behaviours.append(b)


func _has_behaviour_type(b: AttributeBehaviour) -> bool:
	for mine in behaviours:
		if mine.get_script() == b.get_script() and mine.key() == b.key():
			return true
	return false


func clone() -> Attribute:
	var a: Attribute = duplicate(false)
	a.tags = tags.duplicate()
	a.params = params.duplicate(true)
	a.behaviours = []
	for b in behaviours:
		a.behaviours.append(b.duplicate(true))
	a.flat = {}
	a.holder = null
	return a
