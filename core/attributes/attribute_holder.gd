class_name AttributeHolder
extends RefCounted
## Owns a set of Attributes, one per id. Adding an attribute whose id already
## exists merges it into the existing one (a second poison merges into the first).
## Also acts as the event dispatcher for its attributes' behaviours.

signal attribute_added(attr: Attribute)
signal attribute_removed(attr: Attribute)

var attributes: Dictionary = {}  ## StringName -> Attribute
var tag_name: String = ""        ## debug label


func add(attr: Attribute) -> Attribute:
	if attributes.has(attr.id):
		var existing: Attribute = attributes[attr.id]
		existing.merge_from(attr)
		return existing
	attr.holder = self
	attributes[attr.id] = attr
	attribute_added.emit(attr)
	emit(GameEvents.ATTRIBUTE_ADDED, {"attr": attr})
	return attr


func remove(id: StringName) -> void:
	if attributes.has(id):
		var a: Attribute = attributes[id]
		emit(GameEvents.ATTRIBUTE_REMOVED, {"attr": a})
		attributes.erase(id)
		a.holder = null
		attribute_removed.emit(a)


func has(id: StringName) -> bool:
	return attributes.has(id)


func get_attr(id: StringName) -> Attribute:
	return attributes.get(id)


func value(id: StringName, default: float = 0.0) -> float:
	var a: Attribute = attributes.get(id)
	return a.value() if a else default


func current(id: StringName, default: float = 0.0) -> float:
	var a: Attribute = attributes.get(id)
	return a.current if a else default


func set_current(id: StringName, v: float) -> void:
	var a: Attribute = attributes.get(id)
	if a:
		a.current = clampf(v, 0.0, a.value())


func stacks(id: StringName) -> int:
	var a: Attribute = attributes.get(id)
	return a.stacks if a else 0


func has_tag(tag: StringName) -> bool:
	for a in attributes.values():
		if tag in a.tags:
			return true
	return false


## Dispatch an event to every behaviour that listens to it.
## Snapshot first, so behaviours may add/remove attributes while handling.
func emit(event: StringName, ctx: Dictionary = {}) -> Dictionary:
	ctx["holder"] = self
	for a in attributes.values().duplicate():
		if not attributes.has(a.id):
			continue
		for b in a.behaviours:
			if event in b.events():
				b.handle(event, ctx, a)
	return ctx


## Breaks the holder <-> attribute reference cycle. Call when the holder is thrown away.
func dispose() -> void:
	for a in attributes.values():
		a.holder = null
	attributes.clear()
