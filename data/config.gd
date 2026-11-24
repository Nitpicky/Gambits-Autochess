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
const UPGRADE_HP := 50     ## flat per upgrade level (stat increases are flat, never %)
const UPGRADE_ATK := 4
const CHAMPION_SELL := 30
const CHAMPION_SKIP_GOLD := 20

# Stat scale: HP comes in steps of HP_STEP (Overwatch-style bars, one segment per step).
const HP_STEP := 25
const HP_SCALE := 0.25    ## catalog HP numbers are multiplied by this, then rounded to HP_STEP
const ATK_SCALE := 0.25   ## catalog Attack / Defense numbers are multiplied by this, then rounded

# Flat buffs (formerly % buffs)
const RALLY_ATK := 2
const GROW_ATK := 2
const GROW_HP := 0         ## max-HP buffs must stay multiples of HP_STEP
const RUIN_ATK := 1
const CHILL_SPEED := 1     ## Speed lost per Chill stack
const ZEALOT_ATK := 3      ## Attack per unspent PP

# Battle
const MAX_BATTLE_CYCLES := 4   ## AP/PP refill cycles before HP% decides
const MAX_BATTLE_TURNS := 40


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
