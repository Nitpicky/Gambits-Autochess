class_name AttributeBehaviour
extends Resource
## Behaviour carried by an Attribute. Reacts to events dispatched through the
## owning AttributeHolder. Subclass it and override `events()` + `handle()`.
## `ctx` is a mutable Dictionary: behaviours may modify it (e.g. ctx.mult *= 1.2).


func events() -> Array[StringName]:
	return []


func handle(_event: StringName, _ctx: Dictionary, _attr: Attribute) -> void:
	pass


## Identity used for de-duplicating behaviours when attributes merge.
func key() -> String:
	return ""
