class_name GameConfig
extends RefCounted
## Every tunable number of the game loop. Change values here, never in module code.

const PLAYERS := 8
const START_HP := 100.0
const MAX_RANK := 6
const ROSTER_MAX := 6
const ITEM_SLOTS := 3
const BOARD_COLS := 3

# Economy
const INCOME := 10
const FIRST_ROUND_GOLD := 30
# Gold styles: each player picks one at the start (random if they don't). Only that style pays.
const GOLD_STYLES := [&"interest", &"bounty", &"streak"]
const INTEREST_PER := 10
const INTEREST_CAP := 5
const STREAK_BONUS := [[6, 6], [4, 4], [2, 2]]  ## [min streak, gold], checked in order
const BOUNTY_PER_KILL := 1       ## gold per enemy unit your team kills (tokens excluded)
const BOUNTY_PER_SURVIVOR := 1   ## gold per unit of yours still standing at the end
const BOUNTY_CAP := 8            ## per round
const XP_BUY_COST := 5
const XP_BUY_AMOUNT := 5
const FREE_XP := 2
const XP_TO_NEXT := [4, 8, 20, 40, 80]  ## index = rank - 1
const ITEM_SELL_RATIO := 0.5

# Shop
const SHOP_UNITS := 3
const SHOP_ITEMS := 2
const SHOP_RELICS := 1
const RARITY_ODDS := [  ## index = rank - 1: common, rare, epic, legendary (percent)
	[100, 0, 0, 0], [80, 20, 0, 0], [60, 30, 10, 0], [45, 35, 17, 3], [30, 38, 25, 7], [20, 35, 30, 15],
]
const ITEM_TIER_ODDS := [  ## by rank: 5g, 15g, 25g
	[70, 30, 0], [60, 35, 5], [45, 45, 10], [35, 45, 20], [25, 45, 30], [20, 40, 40],
]

# Bias (see plan doc, Shop section)
const START_LEAN := 0.15
const LEAN_DECAY := 0.03
const PURSUIT_PER_UNIT := 0.08
const PURSUIT_CAP := 0.4
const PITY_STEP := 0.1
const PITY_CAP := 0.5
const PITY_MIN_UNITS := 2
const CATCHUP_THRESHOLDS := [0.1, 0.25, 0.45]
const CATCHUP_TIER_NAMES := ["Leading", "In the pack", "Behind", "Far behind"]
const CATCHUP_MULT := [1.0, 1.25, 1.5, 2.0]
const DISCOUNT_CHANCE := [0.03, 0.08, 0.18, 0.30]
const DISCOUNT_GOLD := 5

# Round schedule
const PVE_ROUNDS := [1, 2, 3]
const PVE_EVERY := 5
const PVE_FROM := 15
## PvE monster teams. Early rounds: [count, stat scale] for rounds 1..3 (you field 1-2 units then).
const PVE_EARLY := [[1, 0.5], [1, 0.65], [2, 0.6]]
## Later PvE (round PVE_FROM, then every PVE_EVERY): count = BASE + n, scale = BASE + STEP x n (n = 0, 1, ...).
const PVE_LATE_COUNT := 3
const PVE_LATE_SCALE := 0.9
const PVE_LATE_SCALE_STEP := 0.15
## Unit choice rounds (pick 1 of 3 new units + paired item/relic), offered when the round starts.
## 16 = right after the round-15 PvE fight. PROTOTYPE: temporary schedule.
const CHOICE_ROUNDS := {5: 1, 10: 2, 16: 4, 20: 3}  ## round -> UnitCatalog.Rarity (RARE, EPIC, CHAMPION, LEGENDARY)
const CHOICE_OPTIONS := 3
## Item rarity paired with a unit choice (index = unit rarity): items only go up to epic for now.
const CHOICE_ITEM_RARITY := [0, 1, 2, 2]
const PLANNING_SECONDS := 30.0  ## the fight starts when the planning timer runs out
const MAX_ROUNDS := 80  ## PROTOTYPE: safety cap

# Damage to the loser
const LOSS_BASE := 2
const DRAW_DAMAGE := 2

# Upgrades / champions
const MAX_UPGRADE_LEVEL := 1
const UPGRADE_HP := 20     ## flat per upgrade level (stat increases are flat, never %)
const UPGRADE_ATK := 5
const CHAMPION_SELL := 30
const CHAMPION_SKIP_GOLD := 20

# Stat scale: the roster's stats are 1..9 points; game numbers = points x unit.
const HP_UNIT := 20.0      ## HP per HP point (and per "+X HP" in kit texts)
const ATK_UNIT := 5.0      ## Attack per Attack point (and per "+X Attack")
const HP_STEP := 20        ## HP bar segment size (Overwatch-style bars, one segment per step)
const HP_SCALE := 0.25     ## PROTOTYPE: old item numbers x this
const ATK_SCALE := 0.25

# Keyword numbers (each "X" of a keyword is worth this many game points)
const AP_MAX := 3
const PP_MAX := 2
const START_AP := 0
const START_PP := 1
const AP_PER_TURN := 1
const PP_PER_TURN := 1
const TOUGH_UNIT := 3.0     ## damage removed per Tough
const WEAKEN_UNIT := 3.0    ## damage removed per Weaken stack
const DMG_UNIT := 5.0       ## "deal X damage"
const HEAL_BASE := 10.0     ## a plain heal = HEAL_BASE + healer's Attack
const HEAL_UNIT := 5.0      ## "heal X"
const REGEN_UNIT := 5.0
const CREEP_UNIT := 5.0
const CURSE_PCT := 0.05     ## of max HP per Curse stack, at the end of its turns
const VULN_BONUS := 5.0
const GROW_HP_UNIT := 10.0  ## Grow: +1 Attack point and this much HP per X
const PUSH_UNIT := 5.0      ## damage when a push is blocked
const OVERHEAL_PER_TOUGH := 10.0
const FEARLESS_ATK := 1.0   ## Attack points in the front row
const SWIFT_INI := 100.0
const REBIRTH_PCT := 0.5
const FREEZE_AT := 3        ## Chill stacks that turn into Frozen
const HURT_RATIO := 0.7     ## "hurt ally" for heal conditions
const SACRIFICE_BELOW := 0.35
const MIN_DAMAGE := 1.0

# Battle
const MAX_BATTLE_CYCLES := 30  ## AP/PP refill cycles: fights go on until a side is wiped; this is only a stalemate guard
const MAX_BATTLE_TURNS := 40  ## rounds; stalemate guard only
## Fight timer: FIGHT_SECONDS of playback (speed 1). The sim keeps the same clock from EVENT_SECONDS.
## Past it (from the next turn), healing is cut and every hit ignores damage reduction and grows by
## OVERTIME_DMG_STEP per overtime turn. Playback speeds up per action.
const FIGHT_SECONDS := 45.0
## Playback seconds per battle log event (the UI waits this long; the sim's fight clock adds them up).
const EVENT_SECONDS := {"start": 0.8, "act": 0.45, "hit": 0.5, "heal": 0.45, "blocked": 0.45, "buff": 0.3,
	"status": 0.25, "death": 0.6, "summon": 0.35, "move": 0.3, "cycle": 0.5, "transform": 0.5, "turn": 0.0, "timeout": 0.0, "overtime": 0.3, "end": 0.6}
const OVERTIME_HEAL_MULT := 0.25
const OVERTIME_DMG_STEP := 0.3
const OVERTIME_SPEEDUP := 0.08   ## playback speed +8% per action in overtime
const OVERTIME_MAX_SPEED := 5.0


static func is_pve(round_no: int) -> bool:
	return round_no in PVE_ROUNDS or (round_no >= PVE_FROM and (round_no - PVE_FROM) % PVE_EVERY == 0)


static func round_hp(v: float) -> float:
	if v <= 0.0:
		return 0.0
	return maxf(HP_STEP, roundf(v / HP_STEP) * HP_STEP)


static func xp_to_next(rank: int) -> int:
	if rank >= MAX_RANK:
		return 0
	return XP_TO_NEXT[rank - 1]
