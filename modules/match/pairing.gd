class_name Pairing
extends RefCounted
## Round-robin pairing (circle method). One cycle = everyone faces everyone once.
## Players eliminated mid-cycle leave their opponent facing a ghost.

var rounds: Array = []  ## Array of Array of [a, b] (player ids, -1 = ghost)


func new_cycle(alive_ids: Array, rng: RandomNumberGenerator) -> void:
	var ids := alive_ids.duplicate()
	# shuffle with our rng for determinism
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ids[i]; ids[i] = ids[j]; ids[j] = t
	if ids.size() % 2 == 1:
		ids.append(-1)
	var n := ids.size()
	rounds.clear()
	for r in n - 1:
		var pairs: Array = []
		for i in n / 2:
			pairs.append([ids[i], ids[n - 1 - i]])
		rounds.append(pairs)
		# rotate all but the first
		var last = ids.pop_back()
		ids.insert(1, last)


## Next round's pairs, filtered to living players (dead opponents become ghosts).
func next_pairs(alive_ids: Array, rng: RandomNumberGenerator) -> Array:
	if rounds.is_empty():
		new_cycle(alive_ids, rng)
	var pairs: Array = rounds.pop_front()
	var out: Array = []
	for pr in pairs:
		var a = pr[0] if pr[0] in alive_ids else -1
		var b = pr[1] if pr[1] in alive_ids else -1
		if a == -1 and b == -1:
			continue
		if a == -1:
			out.append([b, -1])
		else:
			out.append([a, b])
	return out


func cycle_done() -> bool:
	return rounds.is_empty()
