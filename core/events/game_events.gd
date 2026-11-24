class_name GameEvents
extends RefCounted
## Event names shared by every module. Add new ones here; nothing else to register.

const ATTRIBUTE_ADDED := &"attribute_added"
const ATTRIBUTE_REMOVED := &"attribute_removed"

# Battle
const BATTLE_START := &"battle_start"
const TURN_START := &"turn_start"          ## global turn start (every unit)
const OWN_TURN_START := &"own_turn_start"  ## this unit is about to act
const OWN_TURN_END := &"own_turn_end"
const BEFORE_DEAL := &"before_deal"        ## attacker side: ctx.mult, ctx.target
const BEFORE_TAKE := &"before_take"        ## defender side: ctx.mult, ctx.cancel
const DEALT := &"dealt"                    ## attacker side after damage: ctx.amount, ctx.target, ctx.killed
const DAMAGED := &"damaged"                ## defender side after damage: ctx.amount, ctx.source
const KILLED := &"killed"                  ## attacker killed ctx.target
const DIED := &"died"
const PP_SPENT := &"pp_spent"
const HEALED := &"healed"

# Player / economy
const ROUND_INCOME := &"round_income"      ## ctx.gold (mutable)
const ROUND_XP := &"round_xp"              ## ctx.xp (mutable)
const REROLL_COST := &"reroll_cost"        ## ctx.cost (mutable), ctx.reroll_index
