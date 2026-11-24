class_name UnitPool
extends RefCounted
## Shared pool of unit copies (TFT-style). Buying takes copies out, selling puts them back.

var copies: Dictionary = {}  ## def id -> remaining


func _init() -> void:
	for id in UnitCatalog.shop_units():
		copies[id] = UnitCatalog.POOL_SIZE[UnitCatalog.get_def(id).rarity]


## A choice-only unit was picked: from now on it is in the shared pool (minus the picked copy).
func add_choice_unit(id: StringName) -> void:
	var def := UnitCatalog.get_def(id)
	if def.is_empty() or def.rarity > UnitCatalog.Rarity.LEGENDARY or copies.has(id):
		return
	copies[id] = maxi(0, UnitCatalog.POOL_SIZE[def.rarity] - 1)


func available(id: StringName) -> int:
	return copies.get(id, 0)


func take(id: StringName, n: int = 1) -> bool:
	if not copies.has(id):
		return true  # champions / tokens are not pooled
	if copies[id] < n:
		return false
	copies[id] -= n
	return true


func give_back(id: StringName, n: int = 1) -> void:
	if copies.has(id):
		copies[id] += n
