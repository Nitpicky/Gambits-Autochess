# modules/economy/

## Architecture
- `economy.gd` (`Economy`, static): income (round 1 = 30 flat; then 10 + interest 1/10 banked capped at 5
  + streak bonus), win/loss streaks, free XP, buy XP, rank ups, reroll cost.
- Economy relics (Merchant's Purse, Mentor's Tome, Lucky Coin) are player Attributes whose behaviour
  reacts to `ROUND_INCOME`, `ROUND_XP`, `REROLL_COST`.

## Recap
- 2026-11-24: Created.
