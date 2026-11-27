#!/usr/bin/env python3
"""Builds data/roster.json: the 144 kits (126 units + 18 champions), tokens, forms and PvE monsters.

Sources (all in this folder):
  doc_units.json      unit tables exported from the "Keywords & Mechanics" Claude Doc (names, stats, kit and
                      rank-up text). Re-export it when the doc changes.
  board_sprites.json  Kit Sprite Board assignments (kit id -> Duelyst sprite).
  this file           the kits written as engine data (KITS below), read by modules/battle/battle_sim.gd.

Run:  python3 tools/roster/build_roster.py      (writes data/roster.json)

PROTOTYPE: numbers follow the doc's relative 1..9 stats; GameConfig turns them into game numbers
(HP x HP_UNIT, Attack x ATK_UNIT, keyword points x their own unit).
Engine vocabulary (selectors, steps, triggers, conditions) is documented in modules/battle/CLAUDE.md.
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "data", "roster.json")

# ------------------------------------------------------------------ step helpers
def _s(d, on=None, **k):
    if on is not None:
        d["on"] = on
    d.update(k)
    return d

def H(p=1, on=None, **k): return _s({"do": "hit", "p": p}, on, **k)          # attack: Attack x p
def D(n, on=None, **k): return _s({"do": "dmg", "n": n}, on, **k)            # raw damage points
def HEAL(on=None, n=None, **k):
    d = {"do": "heal"}
    if n is not None: d["n"] = n
    return _s(d, on, **k)
def S(id, n=1, on=None, dur=None, **k):
    d = {"do": "status", "id": id, "n": n}
    if dur is not None: d["dur"] = dur
    return _s(d, on, **k)
def BAR(on=None, **k): return _s({"do": "barrier"}, on, **k)
def CLN(on=None, **k): return _s({"do": "cleanse"}, on, **k)
def PRG(on=None, **k): return _s({"do": "purge"}, on, **k)
def BUFF(stat, n, on=None, dur=None, **k):
    d = {"do": "buff", "stat": stat, "n": n}
    if dur is not None: d["dur"] = dur
    return _s(d, on, **k)
def KW(kw, n=1, on=None, dur=None, **k):
    d = {"do": "kw", "k": kw, "n": n}
    if dur is not None: d["dur"] = dur
    return _s(d, on, **k)
def KWDEL(kw, on=None, **k): return _s({"do": "kw_del", "k": kw}, on, **k)
def GAIN(res, n, on=None, **k): return _s({"do": "gain", "res": res, "n": n}, on, **k)
def NUMB(n=1, on=None, **k): return _s({"do": "numb", "n": n}, on, **k)
def SUM(tok, n=1, mod=None, **k):
    d = {"do": "summon", "tok": tok, "n": n}
    if mod: d["mod"] = mod
    return _s(d, None, **k)
def PUSH(on=None, n=1, **k): return _s({"do": "push", "n": n}, on, **k)
def PULL(on=None, **k): return _s({"do": "pull"}, on, **k)
def SWAP(on=None, **k): return _s({"do": "swap"}, on, **k)
def BLINK(on="self", **k): return _s({"do": "blink"}, on, **k)
def REPOS(**k): return _s({"do": "reposition"}, None, **k)
def SOULS(n): return {"do": "souls", "n": n}
def GOLD(n, **k): return _s({"do": "gold", "n": n}, None, **k)
def PERM(key, n, **k): return _s({"do": "perm", "key": key, "n": n}, None, **k)
def TRANS(form, **k): return _s({"do": "transform", "form": form}, None, **k)
def REVIVE(on="dead", pct=0.5, **k): return _s({"do": "revive", "pct": pct}, on, **k)
def SAC(on="adj_victim", **k): return _s({"do": "sacrifice"}, on, **k)
def CREEP(n, cells="target", **k): return _s({"do": "creep", "n": n, "cells": cells}, None, **k)
def EXTRA(**k): return _s({"do": "extra_action"}, None, **k)
def STALLMOD(n, on="self", **k): return _s({"do": "stall_mod", "n": n}, on, **k)
def SPECIAL(name, **k): return _s({"do": "special", "name": name}, None, **k)

def RALLY(n=1, **k): return BUFF("atk", n, "allies", **k)

# ------------------------------------------------------------------ action / trigger helpers
def A(id, name, cost, tgt, fx, cond=None, **k):
    d = {"id": id, "name": name, "kind": "ap", "cost": cost, "tgt": tgt, "fx": fx}
    if cond: d["cond"] = cond
    d.update(k)
    return d

def R(id, name, react, tgt, fx, cost=1, **k):
    d = {"id": id, "name": name, "kind": "pp", "cost": cost, "react": react, "tgt": tgt, "fx": fx}
    d.update(k)
    return d

def T(on, fx, **k):
    d = {"on": on, "fx": fx}
    d.update(k)
    return d

def U(**mod): return mod

def HIT(id="strike", name="Strike", cost=1, p=1, tgt="foe", extra=None, **k):
    return A(id, name, cost, tgt, [H(p)] + (extra or []), **k)

def FORM(fid, hp=0, atk=0, spd=0, kw=None, **k):
    d = {"id": fid, "hp": hp, "atk": atk, "spd": spd, "kw": kw or {}}
    d.update(k)
    return d

def K(kw=None, acts=None, trig=None, ups=None, flags=None, relic=None):
    return {"kw": kw or {}, "acts": acts or [], "trig": trig or [], "ups": ups or [], "flags": flags or {}, "relic": relic}

GUARD_KW = {"guard": 1}
WARCRY = "warcry"

# ------------------------------------------------------------------ KITS
KITS = {}

# ============================== LYONAR
mend = A("mend", "Mend", 1, "ally_lowest", [HEAL()], cond="ally_hurt")
KITS["sunrise-cleric"] = K(acts=[mend, R("prayer", "Prayer", "front_ally_hit", "target", [HEAL()])], ups=[
    U(acts=[A("mend", "Mend", 1, "ally_lowest", [HEAL(), CLN()], cond="ally_hurt")]),
    U(kw={"radiance": 1}),
    U(kw={"zeal": 1}, acts=[A("mend", "Mend", 1, "ally_lowest", [HEAL(), HEAL("ally_front")], cond="ally_hurt", cost_if=[{"rush": 2, "cost": 0}])]),
])
KITS["sun-wisp"] = K(acts=[HIT("sunbolt", "Sunbolt")], trig=[T("deathwish", [HEAL("allies")], id="dw")], ups=[
    U(trig=[T("deathwish", [HEAL("allies"), CLN("allies")], id="dw")]),
    U(acts=[A("sunbolt", "Sunbolt", 1, "foe", [H(), HEAL("ally_lowest", amount="dealt", stall=2)])]),
    U(trig=[T("deathwish", [HEAL("allies"), SOULS(1)], id="dw")]),
])
toll = A("toll", "Toll", 1, "allies_other", [BUFF("atk", 1, dur=1)])
KITS["vigilator"] = K(acts=[toll], ups=[
    U(acts=[A("toll", "Toll", 1, "allies_other", [BUFF("atk", 1, dur=1), HEAL("ally_lowest")])]),
    U(trig=[T("deathwish", [RALLY(1)])]),
    U(acts=[A("toll", "Toll", 1, "allies_other", [BUFF("atk", 1, dur=1), KW("tough", 1, dur=1, stall=2)])]),
])
KITS["decorated-enlistee"] = K(kw=GUARD_KW, acts=[A("swap", "Swap", 1, "ally_low_half", [SWAP()])], ups=[
    U(kw={"strikeback": 1}), U(kw={"tough": 2}), U(trig=[T(WARCRY, [RALLY(1)])]),
])
KITS["silverguard-squire"] = K(kw={"zeal": 1}, acts=[HIT()], ups=[
    U(kw={"guard": 1}),
    U(kw={"taunt": 1, "tough": 1}, kw_del=["zeal"]),
    U(trig=[T("bitemark", [HEAL("self")], rush=2)]),
])
smite = lambda st=3: A("smite", "Smite", 2, "foe", [H(), HEAL("self"), HEAL("adj_allies", stall=st)])
KITS["silverguard-knight"] = K(kw=GUARD_KW, acts=[smite()], ups=[
    U(flags={"guard_tough": 2}),
    U(acts=[smite(1)]),
    U(trig=[T(WARCRY, [BAR("self")]), T("guard", [BAR("self")], once=True)]),
])
KITS["lightchaser"] = K(acts=[A("absolve", "Absolve", 2, "ally_needy", [CLN(), HEAL()], cond="ally_needy"),
                              R("blessing", "Blessing", "status_landing", "target", [CLN()], once=True)], ups=[
    U(acts=[A("absolve", "Absolve", 2, "ally_needy", [CLN(), HEAL(), PRG("foe_buffed")], cond="ally_needy")]),
    U(flags={"heal_tough": 1}),
    U(trig=[T(WARCRY, [KW("regen", 1, "allies")])]),
])
KITS["sunstone-templar"] = K(kw=GUARD_KW, acts=[HIT(cost=2)], trig=[T("guard", [BUFF("atk", 1, "self")])], ups=[
    U(kw={"strikeback": 1}),
    U(kw={"dash": 1, "charge": 2}),
    U(trig=[T("guard", [BUFF("atk", 1, "self"), BUFF("atk", 1, "target")])]),
])
KITS["sunforge-lancer"] = K(kw={"dash": 1, "charge": 2}, acts=[HIT("lance", "Lance", 2)], ups=[
    U(kw={"overwhelm": 1}),
    U(kw={"tough": 2}, kw_del=["dash"]),
    U(trig=[T("charged", [HEAL("adj_allies")])]),
])
sanct = lambda **k: A("sanctuary", "Sanctuary", 3, "allies", [HEAL()], cond="ally_hurt", cost_if=[{"stall": 4, "cost": 2}], **k)
KITS["sol-pontiff"] = K(kw={"radiance": 3}, acts=[sanct()], ups=[
    U(trig=[T("turn", [HEAL("allies")], rush=2, once=True)]),
    U(flags={"heal_cleanse": 1}),
    U(trig=[T(WARCRY, [STALLMOD(-1, "allies")])]),
])
KITS["ironcliffe-guardian"] = K(kw={"taunt": 1, "tough": 2}, acts=[A("bash", "Shield Bash", 2, "foe", [H(), PUSH()])],
    trig=[T("turn", [BUFF("atk", 1, "self")], stall=2, id="ramp")], ups=[
    U(kw={"anchor": 1, "tough": 3}),
    U(trig=[T(WARCRY, [RALLY(1)])], kw_del=["taunt"]),
    U(kw={"grow": 1}, trig_del=["ramp"]),
])
judg = A("judgment", "Judgment", 3, "foe_strongest", [H(2), HEAL("allies", amount="dealt_half")])
KITS["sunbreaker"] = K(acts=[judg], trig=[T(WARCRY, [RALLY(1), KW("tough", 1, "allies"), KW("zeal", 1, "allies")])], ups=[
    U(trig=[T("turn", [RALLY(1), KW("tough", 1, "allies")], every=3)]),
    U(flags={"guard_all_once": 1}),
    U(trig=[T("deathwish", [RALLY(2)])]),
])
# Lyonar Adds
KITS["windcliffe-alarmist"] = K(acts=[A("swap", "Swap", 1, "ally_hurt_front", [SWAP(), KW("tough", 1, "self", dur=1), KW("tough", 1, dur=1)])], ups=[
    U(acts=[A("swap", "Swap", 0, "ally_hurt_front", [SWAP(), KW("tough", 1, "self", dur=1), KW("tough", 1, dur=1)], free=True)]),
    U(acts=[A("swap", "Swap", 1, "ally_hurt_front", [SWAP(), KW("tough", 1, "self", dur=1), KW("tough", 1, dur=1), BUFF("atk", 1, "self"), BUFF("atk", 1)])]),
    U(acts=[A("swap", "Blink", 1, "self", [BLINK(), KW("tough", 1, "self", dur=1)], cond="self_below")]),
])
scint_wc = lambda extra=None, **k: T(WARCRY, [CLN("allies"), KW("tough", 1, "ally_front")] + (extra or []), id="wc", **k)
KITS["scintilla"] = K(acts=[A("bless", "Bless", 1, "ally_lowest", [HEAL()], cond="ally_hurt")], trig=[scint_wc()], ups=[
    U(trig=[scint_wc([HEAL("allies")])]),
    U(trig=[T("stall", [CLN("allies"), KW("tough", 1, "ally_front")], stall=3)]),
    U(trig=[scint_wc([PRG("foe_facing")])]),
])
KITS["windcliffe-protector"] = K(kw={"taunt_high": 1, "strikeback": 1}, ups=[
    U(kw={"tough_low": 1}),
    U(trig=[T("deathwish", [KW("tough", 1, "allies")])]),
    U(kw={"dash": 1, "charge": 1}),
])
holy = lambda extra=None: A("holy", "Holy Strike", 2, "foe", [H(), HEAL("ally_lowest", amount="dealt")] + (extra or []))
KITS["suntide-maiden"] = K(acts=[holy()], ups=[
    U(acts=[holy([HEAL("adj_allies", amount="dealt_half")])]),
    U(kw={"lifesteal": 1}),
    U(kw={"strikeback": 1, "tough": 1}),
])
KITS["peacekeeper"] = K(kw=GUARD_KW, flags={"guard_free_turn": 1}, trig=[T("guard", [KW("tough", 1, "self", cap=3)], id="g"), T("stall", [KW("taunt", 1, "self")], stall=3)], ups=[
    U(trig=[T("guard", [KW("tough", 1, "self", cap=5)], id="g")]),
    U(trig=[T("guard", [KW("tough", 1, "self", cap=3), KW("tough", 1, "target", dur=1)], id="g")]),
    U(trig=[T("guard", [BAR("self")], once=True)]),
])
hymn = lambda d=2, extra=None: A("hymn", "Hymn", 2, "allies", [KW("regen", 2, dur=d)] + (extra or []), cond="ally_hurt")
KITS["sun-sister-sterope"] = K(acts=[hymn()], trig=[T("deathwish", [RALLY(1)], id="dw")], ups=[
    U(acts=[hymn(3)]),
    U(trig=[T("deathwish", [RALLY(1), HEAL("allies")], id="dw")]),
    U(acts=[A("hymn", "Hymn", 2, "allies", [KW("regen", 2, dur=2), BUFF("atk", 1, dur=2)])]),
])
KITS["grandmaster-zir"] = K(kw={"taunt": 1, "tough": 3}, acts=[A("roar", "Lion's Roar", 2, "allies", [RALLY(1), S("hush", 1, "foe_front_row", dur=1)])],
    trig=[T("stall", [KW("overwhelm", 1, "self")], stall=3)], ups=[
    U(kw={"anchor": 1, "guard": 1}, flags={"guard_free": 1}),
    U(kw={"pride": 1}),
    U(kw={"grow": 2}, kw_del=["taunt"]),
])
sol_t = lambda uses=1, extra=None: T("ally_died", [REVIVE("dead", 0.5)] + (extra or []), uses=uses, id="rev")
KITS["solarius"] = K(kw={"radiance": 3}, acts=[A("rmend", "Radiant Mend", 2, "allies", [HEAL()], cond="ally_hurt")], trig=[sol_t()], ups=[
    U(trig=[sol_t(2)]),
    U(trig=[T("ally_died", [REVIVE("dead", 1.0), D(4, "self")], uses=1, id="rev")]),
    U(trig=[sol_t(1, [BUFF("atk", 2, "dead")])]),
])
formation = lambda extra=None: A("formation", "Formation", 2, "allies", [REPOS(), KW("tough", 1, dur=2)] + (extra or []))
KITS["grand-strategos"] = K(acts=[formation()], trig=[T(WARCRY, [KW("zeal_any", 1, "allies")])], ups=[
    U(trig=[T(WARCRY, [SPECIAL("phalanx")])]),
    U(trig=[T(WARCRY, [RALLY(1)])]),
    U(acts=[formation([BAR("front_allies")])]),
])

# ============================== SONGHAI
KITS["jade-monk"] = K(acts=[A("palm", "Palm Strike", 1, "foe", [H(), PUSH()]), R("stance", "Stance", "hit_taken", "self", [KW("tough", 1, dur=1)])], ups=[
    U(kw={"anchor": 1, "tough": 1}),
    U(kw={"strikeback": 1}, flags={"strikeback_push": 1}),
    U(trig=[T("stall", [S("haste", 1, "lane_allies")], stall=2)]),
])
KITS["coalfist"] = K(acts=[HIT("kick", "Tempest Kick"), R("gale", "Gale Step", "ally_targeted_any", "self", [{"do": "redirect"}, SWAP("target")])], ups=[
    U(acts=[A("kick", "Tempest Kick", 1, "foe", [H(), H(1, "foe_adj")])]),
    U(trig=[T(WARCRY, [S("haste", 1, "allies")])]),
    U(kw={"tough": 2}, acts_del=["gale"]),
])
chak = lambda extra=None, bounce=1: A("chakram", "Chakram", 1, "foe", [H(1, combo_each=False)] + (extra or []) + [H(0.5, "foe_adj1")] * bounce)
KITS["chakri-avatar"] = K(acts=[chak()], ups=[
    U(acts=[chak([S("vuln", 1)])]),
    U(acts=[chak(bounce=2)]),
    U(trig=[T("bitemark", [S("haste", 1, "self")], stall=2)]),
])
KITS["widowmaker"] = K(kw={"swift": 1}, acts=[HIT("kunai", "Kunai", tgt="foe_next")], ups=[
    U(kw={"vanish": 1}), U(kw={"bounty": 1}), U(kw={"hit_icehold": 1}),
])
KITS["kaido-assassin"] = K(kw={"swift": 1, "backstab": 1}, acts=[HIT("cut", "Cut")], ups=[
    U(kw={"vanish": 1}), U(kw={"bounty": 2}),
    U(trig=[T("turn", [BLINK("self")], once=True)]),
])
execute = lambda pre=None, post=None: A("execute", "Execute", 2, "foe_lowest", (pre or []) + [H(1, backstab=2)] + (post or []))
KITS["scroll-bandit"] = K(kw={"swift": 1, "bounty": 1, "bounty_grows": 1}, acts=[execute()], ups=[
    U(acts=[execute(post=[GOLD(-2), PERM("atk", 1), BUFF("atk", 1, "self")])]),
    U(acts=[execute(pre=[BLINK("self")], post=[S("vanished", 1, "self")])]),
    U(trig=[T(WARCRY, [SPECIAL("guild_master")])]),
])
KITS["wildfire-tenketsu"] = K(flags={"still_atk": 1}, acts=[A("flurry", "Flurry", 2, "foe", [H(), H()])], ups=[
    U(kw={"anchor": 1}),
    U(kw={"dash": 1}, flags={"still_atk": 1, "still_keep": 1}),
    U(flags={"still_atk": 1, "still_zeal": 1}),
])
KITS["suzumebachi"] = K(kw={"combo": 1}, acts=[HIT("cut", "Flowing Cut")], ups=[
    U(kw={"combo": 2}),
    U(trig=[T("turn", [BLINK("self")], every=3)]),
    U(kw={"hit_chill": 1}),
])
mshot = lambda v=2: A("mark", "Marking Shot", 2, "foe", [H(), S("vuln", v)])
KITS["sparrowhawk"] = K(acts=[mshot()], ups=[
    U(acts=[mshot(3)]),
    U(trig=[T("stall", [KW("blast", 1, "self")], stall=3)]),
    U(kw={"zeal": 1}),
])
repel = lambda extra=None: R("repel", "Repel", "melee_hit", "source", [H(), PUSH()] + (extra or []))
KITS["hundred-handed-rakushi"] = K(kw={"taunt": 1}, acts=[repel()], trig=[T(WARCRY, [GAIN("pp", 1, "row_allies")])], ups=[
    U(acts=[repel([H(1, "foe_adjacent")])]),
    U(trig=[T(WARCRY, [KW("anchor", 1, "row_allies")])]),
    U(trig=[T(WARCRY, [S("haste", 1, "songhai_allies", dur=3)])]),
])
assas = lambda extra=None: A("assassinate", "Assassinate", 3, "foe_back", [H(1, backstab=3)] + (extra or []))
KITS["celestial-phantom"] = K(kw={"elusive": 1, "vanish": 1}, acts=[assas()], ups=[
    U(acts=[A("assassinate", "Assassinate", 3, "foe_back", [H(1, backstab=3, on_kill=[GAIN("ap", 3, "self")])])]),
    U(acts=[assas([S("vanished", 1, "adj_allies", dur=1)])]),
    U(acts=[assas([S("curse", 1)])]),
])
KITS["storm-kage"] = K(kw={"swift": 1, "combo": 1}, acts=[A("dance", "Storm Dance", 3, "foes", [H(1, combo_each=True)])], ups=[
    U(trig=[T(WARCRY, [S("haste", 2, "allies")])]),
    U(flags={"cost_mod_stall": 3}),
    U(acts_del=["dance"], acts=[A("steps", "Empty Hand", 1, "foe", [H(1, combo_each=True), BLINK("self"), H(1, "foe", combo_each=True)])]),
])
palm = lambda extra=None: A("palm", "Kinetic Palm", 1, "allies", [REPOS(haste=1)] + (extra or []), cond="repos")
KITS["ki-beholder"] = K(acts=[palm()], ups=[
    U(acts=[A("gate", "Open Gate", 1, "foe_back", [PULL()])]),
    U(acts=[palm([KW("tough", 1, "front_allies", dur=2)])]),
    U(kw={"strikeback": 1}),
])
KITS["orizuru"] = K(kw={"combo": 1}, acts=[HIT("crane", "Crane Strike")], trig=[T(WARCRY, [GAIN("pp", 1, "allies")], id="wc")], ups=[
    U(trig=[T(WARCRY, [GAIN("pp", 1, "allies"), GAIN("pp", 2, "ally_front")], id="wc")]),
    U(kw={"vanish": 1}),
    U(acts=[A("crane", "Crane Strike", 1, "foe", [H(), S("vuln", 1, stall=2)])]),
])
fblink = lambda cost=1, cap=3, **k: A("blink", "Blink", cost, "self", [BLINK(), GOLD(1)], uses=cap, **k)
KITS["lantern-fox"] = K(kw={"backstab": 1}, acts=[fblink()], ups=[
    U(acts=[fblink(cap=5)]),
    U(acts=[fblink(0, free=True)]),
    U(trig=[T("deathwish", [GOLD(2)])]),
])
KITS["twilight-fox"] = K(kw={"elusive": 1}, trig=[T(WARCRY, [SUM("mirror", 1, copy_self=True)], id="wc")], ups=[
    U(trig=[T(WARCRY, [SUM("mirror", 2, copy_self=True)], id="wc")]),
    U(acts=[R("switch", "Switch", "self_targeted", "token_any", [{"do": "redirect_to_target"}], cost=0, once=True)]),
    U(trig=[T(WARCRY, [SUM("mirror", 1, copy_self=True, mod={"trig": [T("deathwish", [S("vuln", 1, "foe_adjacent")])]})], id="wc")]),
])
arrow = lambda extra=None, **k: A("arrow", "Thunder Arrow", 2, "foe", [H(), PUSH()] + (extra or []), **k)
KITS["xenkai-cannoneer"] = K(kw={"combo": 1}, acts=[arrow()], ups=[
    U(acts=[arrow([H(1, "behind")])]),
    U(acts=[arrow(cost_if=[{"rush": 2, "cost": 1}])]),
    U(acts=[arrow([S("vuln", 2)])]),
])
KITS["gore-horn"] = K(kw={"taunt": 1, "strikeback": 1}, trig=[T("moved_by_enemy", [BUFF("atk", 2, "self")], id="m")], ups=[
    U(kw={"anchor": 1}, trig_del=["m"], trig=[T("hit_taken", [BUFF("atk", 1, "self")])]),
    U(flags={"strikeback_push": 1}),
    U(trig=[T(WARCRY, [KW("strikeback", 1, "row_allies")])]),
])
ring = lambda tgt="foe_row", extra=None: A("ring", "Ring Storm", 2, "foe", [H(1, tgt, combo_each=False)] + (extra or []))
KITS["calligrapher"] = K(kw={"combo": 1}, acts=[ring()], ups=[
    U(acts=[ring("foes")]),
    U(acts=[A("ring", "Ring Storm", 2, "foe", [H(1, "foe_row", combo_each=True)])]),
    U(acts=[ring(extra=[NUMB(1, "foe_row")])]),
])
KITS["hideatsu-the-ebon-ox"] = K(kw={"anchor": 1}, trig=[T("turn_end", [BUFF("atk", 1, "row_allies")], cond="not_moved", id="still")], ups=[
    U(trig=[T("turn_end", [BUFF("atk", 1, "allies")], cond="not_moved", id="still")]),
    U(trig=[T("turn_end", [BUFF("atk", 1, "row_allies"), KW("tough", 1, "row_allies", cap=3)], cond="not_moved", id="still")]),
    U(trig=[T("turn_end", [BUFF("atk", 1, "row_allies")], cond="not_moved", id="still"), T("turn_end", [BUFF("atk", 1, "allies")], stall=3)]),
])
KITS["massacre-artist"] = K(kw={"elusive": 1, "swift": 1, "bounty": 3}, trig=[T(WARCRY, [BLINK("self"), H(1, "foe_back", backstab=3)]), T("kill", [S("vanished", 1, "self")], id="k")], ups=[
    U(trig=[T("kill", [S("vanished", 1, "self"), EXTRA()], id="k")]),
    U(kw={"hit_hush": 1}),
    U(trig=[T("kill", [S("vanished", 1, "self"), SOULS(1)], id="k")]),
])

# ============================== VETRUVIAN
pyro_stall = lambda st=2, extra=None: T("stall", [RALLY(1)] + (extra or []), stall=st, id="st")
KITS["pyromancer"] = K(acts=[HIT("sunray", "Sunray")], trig=[pyro_stall()], ups=[
    U(trig=[pyro_stall(1)]),
    U(trig=[pyro_stall(2, [H(1, "foe_front_row")])]),
    U(trig=[T(WARCRY, [PRG("foe_strongest")])]),
])
obel = lambda mod=None, **k: SUM("obelysk", 1, mod=mod, **k)
KITS["dunecaster"] = K(trig=[T(WARCRY, [obel()], id="wc")], ups=[
    U(trig=[T(WARCRY, [obel({"kw": {"aura_adj_atk": 1}})], id="wc")]),
    U(trig=[T(WARCRY, [obel({"kw": {"taunt": 1}})], id="wc")]),
    U(trig=[T("stall", [obel()], stall=3)]),
])
KITS["falcius"] = K(kw={"taunt": 1, "aura_tok_adj_atk": 1}, acts=[HIT("spear", "Spear")], ups=[
    U(kw={"tough": 1}), U(kw={"aura_tok_haste": 1}), U(kw={"aura_tok_adj_tough": 1}),
])
KITS["dustdrinker"] = K(acts=[A("whirl", "Whirl", 1, "foe", [H(), H(1, "foe_adj1")])], trig=[T("deathwish", [SUM("sand-wisp")], id="dw")], ups=[
    U(trig=[T("deathwish", [SUM("sand-wisp", 2)], id="dw")]),
    U(kw={"dash": 1}),
    U(trig=[T(WARCRY, [SUM("sand-wisp")])]),
])
call = lambda n=1, mod=None: A("call", "Call", 1, "self", [SUM("sand-wisp", n, mod=mod)], cond="empty_cell")
KITS["zephyr"] = K(acts=[call()], ups=[
    U(acts=[call(2)]),
    U(acts=[call(1, {"kw": {"tough": 1}})]),
    U(acts=[call(1, {"trig": [T("bitemark", [D(1, "target")])]})]),
])
aym = lambda st=3, extra=None: T("stall", [RALLY(2), KW("regen", 1, "allies")] + (extra or []), stall=st, id="st")
KITS["aymara-healer"] = K(acts=[A("rite", "Sun Rite", 2, "allies", [STALLMOD(-1, "allies")], cond="stall_pending")], trig=[aym()], ups=[
    U(trig=[aym(2)]),
    U(trig=[aym(3, [PRG("foes")])]),
    U(trig=[T("stall", [KW("blast", 1, "self")], stall=4)]),
])
decree = lambda tgt="foe_buffed", extra=None: A("decree", "Decree", 2, tgt, [PRG()] + (extra or []), cond="foe_buffed")
KITS["fate-watcher"] = K(acts=[decree()], trig=[T(WARCRY, [STALLMOD(-1, "allies")], id="wc")], ups=[
    U(trig=[T(WARCRY, [STALLMOD(-2, "allies")], id="wc")]),
    U(acts=[decree("foe_buffed2")]),
    U(acts=[decree(extra=[S("vuln", 1)])]),
])
KITS["sand-howler"] = K(kw={"dash": 1, "atk_per_token": 1}, acts=[A("whirlwind", "Whirlwind", 2, "foe_front_row", [H()])], ups=[
    U(trig=[T(WARCRY, [S("haste", 2, "self")])]),
    U(kw={"vanish": 1}),
    U(kw={"overwhelm": 1}),
])
KITS["portal-guardian"] = K(kw={"taunt": 1, "tough": 1}, trig=[T("deathwish", [SUM("sand-wisp", 2)], id="dw")], ups=[
    U(trig=[T("deathwish", [SUM("sand-wisp", 3)], id="dw")]),
    U(kw={"strikeback": 1}),
    U(kw={"grow": 1}),
])
nimb = lambda st=2, extra=None: T("turn", [RALLY(1)] + (extra or []), stall=st, id="st")
KITS["nimbus"] = K(trig=[nimb()], ups=[
    U(trig=[nimb(1)]),
    U(trig=[nimb(2, [S("haste", 1, "tokens")])]),
    U(trig=[nimb(2, [KW("tough", 1, "allies", cap=3)])]),
])
KITS["oserix"] = K(acts=[A("command", "Command", 2, "foe", [SPECIAL("tokens_hit")], cond="has_token")], trig=[T(WARCRY, [SUM("sand-wisp", 2)], id="wc")], ups=[
    U(trig=[T(WARCRY, [SUM("sand-wisp", 2, mod={"stats": {"hp": 1, "atk": 1}})], id="wc")]),
    U(trig=[T("stall", [obel()], stall=3)]),
    U(trig=[T("token_died", [SOULS(1)])]),
])
KITS["grandmaster-nosh-rak"] = K(kw={"aura_tok_atk": 1, "aura_tok_tough": 1}, acts=[A("decree", "Royal Decree", 3, "foes", [PRG()], cond="foe_buffed")],
    trig=[T(WARCRY, [SUM("sand-wisp", 6)])], ups=[
    U(kw={"aura_tok_noeph": 1}),
    U(trig=[T("stall", [RALLY(2)], stall=3)]),
    U(kw={"aura_tok_dash": 1, "aura_tok_haste": 1}),
])
# Vetruvian Adds
dream = lambda st=2, n=2: T("stall", [KW("regen", n, "allies")], stall=st, id="st")
KITS["dreamshaper"] = K(acts=[A("rite", "Water Rite", 1, "foe_buffed", [PRG()], cond="foe_buffed")], trig=[dream()], ups=[
    U(trig=[dream(2, 3)]),
    U(trig=[dream(1)]),
    U(kw={"aura_tok_regen": 1}),
])
scarab = lambda mod=None: T("turn", [SUM("scarab", 1, mod=mod)], id="t")
KITS["starfire-scarab"] = K(trig=[scarab()], ups=[
    U(trig=[scarab({"stats": {"hp": 1}})]),
    U(trig=[scarab({"kw": {"ephemeral": 2}})]),
    U(trig=[scarab({"kw": {"hit_curse": 1}})]),
])
mirage = lambda cost=1, **k: R("mirage", "Mirage", "self_targeted", "token_any", [{"do": "redirect_to_target"}, SWAP("target")], cost=cost, **k)
KITS["mirage-master"] = K(acts=[mirage()], ups=[
    U(acts=[mirage(0, per_turn=1)]),
    U(acts=[R("mirage", "Mirage", "self_targeted", "token_any", [{"do": "redirect_to_target"}, SWAP("target"), BUFF("atk", 1, "self")])]),
    U(trig=[T(WARCRY, [SUM("sand-wisp")])]),
])
allo = lambda mod: T(WARCRY, [obel(mod), obel(mod)], id="wc")
KITS["allomancer"] = K(trig=[allo({"kw": {"tough": 1}})], ups=[
    U(trig=[allo({"kw": {"tough": 1}, "flags": {"obelysk_n": 2}})]),
    U(trig=[allo({"kw": {"tough": 1}, "trig": [T("turn", [D(1, "foe_random")])]})]),
    U(trig=[allo({"kw": {"tough": 1, "strikeback": 1}})]),
])
KITS["gust"] = K(kw={"blast": 1, "aura_tok_blast_once": 1}, ups=[
    U(kw={"aura_tok_blast": 1}),
    U(trig=[T(WARCRY, [S("weaken", 1, "foes")])]),
    U(kw={"aura_tok_tough": 1}),
])
KITS["sandswirl-reader"] = K(acts=[A("star", "Star Rite", 2, "self", [STALLMOD(-1)], cond="stall_pending")], trig=[T("stall", [H(2, "foes")], stall=4, id="st")], ups=[
    U(trig=[T("stall", [H(2, "foes")], stall=4, id="st"), T("turn", [H(2, "foes")], stall=4, every=2)]),
    U(acts=[A("star", "Star Rite", 2, "self", [STALLMOD(-1, "allies")], cond="stall_pending")]),
    U(trig=[T(WARCRY, [STALLMOD(-1)])]),
])
riddle = lambda extra=None: A("riddle", "Riddle", 2, "foe_strongest", [S("hush", 1, dur=2), PRG()] + (extra or []))
KITS["pantheran"] = K(kw={"taunt": 1}, acts=[riddle()], ups=[
    U(trig=[T(WARCRY, [STALLMOD(-1, "allies")])]),
    U(trig=[T("deathwish", [SUM("sand-wisp", 4)])]),
    U(acts=[riddle([NUMB(1)])]),
])
KITS["khanuum-ka"] = K(kw={"dash": 1, "blast": 1, "atk_per_token": 1}, trig=[T("kill", [SUM("sand-wisp")], id="k")], ups=[
    U(trig=[T("kill", [SUM("sand-wisp", 1, mod={"stats": {"hp": 1, "atk": 1}})], id="k")]),
    U(kw={"overwhelm": 1}),
    U(trig=[T("deathwish", [SUM("sand-wisp", 6)])]),
])
keeper = lambda extra=None: T("stall", [RALLY(2)] + (extra or []), stall=2, id="st")
KITS["keeper-of-ages"] = K(flags={"side_stall_cap": 1}, trig=[keeper()], ups=[
    U(flags={"side_stall_cap": 0}),
    U(trig=[keeper([KW("tough", 2, "allies")])]),
    U(trig=[T("stall", [KW("blast", 1, "self")], stall=3)]),
])

# ============================== ABYSSIAN
hex_ = lambda extra=None: A("hex", "Hex", 1, "foe_strongest", [S("weaken", 1)] + (extra or []))
KITS["blood-siren"] = K(acts=[hex_()], trig=[T("deathwish", [SOULS(1)])], ups=[
    U(acts=[hex_([S("curse", 1)])]),
    U(trig=[T("sacrificed", [SOULS(3)])]),
    U(kw={"lifesteal": 1}),
])
creep = lambda n=1, cells="target": A("creep", "Creep", 1, "foe_nocreep", [CREEP(n, cells)])
KITS["abyssal-crawler"] = K(acts=[creep()], ups=[
    U(acts=[creep(2)]),
    U(acts=[creep(1, "two")]),
    U(acts=[A("grasp", "Grasp", 1, "foe_back", [PULL()], cond="creep_front")]),
])
KITS["darkspine-elemental"] = K(acts=[HIT("claw", "Claw")], trig=[T("deathwish", [SUM("shade")], id="dw")], ups=[
    U(kw={"taunt": 1}),
    U(kw={"undying": 1}),
    U(trig=[T("deathwish", [SUM("shade", 2)], id="dw")]),
])
shade_dw = lambda mod=None: T("deathwatch", [SUM("shade", 1, mod=mod)], per_round=1, id="dw")
KITS["skullprophet"] = K(trig=[shade_dw()], ups=[
    U(trig=[shade_dw({"stats": {"hp": 1}})]),
    U(trig=[shade_dw({"kw_del": ["ephemeral"]})]),
    U(acts=[A("hook", "Corpse Hook", 1, "foe_back", [PULL()])]),
])
gor_dw = lambda extra=None: T("deathwatch", [BUFF("atk", 1, "self")] + (extra or []), id="dw")
KITS["gor"] = K(acts=[HIT("maul", "Maul")], trig=[gor_dw()], ups=[
    U(trig=[gor_dw([BUFF("hp", 1, "self")])]),
    U(kw={"lifesteal": 1}),
    U(kw={"dash": 1}),
])
offering = lambda extra=None: A("offering", "Offering", 1, "adj_victim", [SAC(), SOULS(3)] + (extra or []), cond="adj_victim")
KITS["bloodtide-priestess"] = K(acts=[A("bolt", "Soul Bolt", 1, "foe", [H(), S("curse", 1)], souls=2), offering()], ups=[
    U(acts=[offering([HEAL("self", amount="victim")])]),
    U(acts=[offering([BUFF("atk", 1, "allies", dur=1)])]),
    U(trig=[T("deathwish", [RALLY(1)])]),
])
cstrike = lambda extra=None: A("cstrike", "Curse Strike", 2, "foe", [H(), S("curse", 1)] + (extra or []))
KITS["shadowdancer"] = K(acts=[cstrike()], ups=[
    U(acts=[cstrike([S("weaken", 1)])]),
    U(acts=[A("cstrike", "Curse Strike", 2, "foe", [H(), S("curse", 2)])]),
    U(acts=[cstrike([S("vuln", 1)])]),
])
raise_ = lambda n=1, mod=None, **k: A("raise", "Raise", 2, "self", [SUM("shade", n, mod=mod)], cond="empty_cell", **k)
KITS["desolator"] = K(acts=[raise_()], trig=[T("deathwatch", [SOULS(1)])], ups=[
    U(acts=[raise_(2)]),
    U(acts=[raise_(1, {"kw": {"tough": 1}})]),
    U(acts=[raise_(cost_if=[{"souls": 3, "cost": 1}])]),
])
KITS["nightshroud"] = K(kw={"lifesteal": 1}, trig=[T("deathwatch", [BUFF("atk", 1, "self"), BUFF("hp", 1, "self")])], ups=[
    U(acts=[A("devour", "Devour", 1, "adj_token", [SAC(), BUFF("atk", 2, "self"), BUFF("hp", 2, "self")], cond="adj_token")]),
    U(trig=[T("deathwish", [H(1, "foe_adjacent"), H(1, "adj_allies")])]),
    U(trig=[T(WARCRY, [BAR("self")])]),
])
reap = lambda souls=3, extra=None: A("reap", "Reap", 2, "foes", [H()] + (extra or []), souls=souls)
KITS["reaper-of-the-nine-moons"] = K(acts=[reap()], trig=[T("deathwatch", [SOULS(1)])], ups=[
    U(acts=[reap(2)]),
    U(acts=[reap(3, [S("curse", 1)])]),
    U(trig=[T("stall", [H(1, "foes")], stall=3)]),
])
feast = lambda extra=None, cost=2, **k: A("feast", "Feast", cost, "adj_victim", [SAC(), BUFF("hp", 0, "self", from_victim=True)] + (extra or []), cond="adj_victim", **k)
KITS["horror"] = K(kw={"taunt": 1}, acts=[feast()], trig=[T("deathwatch", [BUFF("atk", 1, "self"), BUFF("hp", 1, "self")])], ups=[
    U(kw={"overwhelm": 1}),
    U(acts=[feast([SOULS(2)])]),
    U(kw={"grow": 1}),
])
gate = lambda souls=5: A("gate", "Abyssal Gate", 3, "self", [SUM("abomination")], souls=souls, cond="empty_cell")
KITS["vorpal-reaver"] = K(acts=[gate()], trig=[T(WARCRY, [CREEP(1, "front")], id="wc")], ups=[
    U(trig=[T(WARCRY, [CREEP(1, "all")], id="wc")]),
    U(acts=[gate(3)]),
    U(trig=[T("deathwatch", [BUFF("atk", 1, "allies")])]),
])
# Abyssian Adds
carrion = lambda tgt="foe_adjacent", n=1: T("deathwish", [S("curse", n, tgt)], id="dw")
KITS["carrion-collector"] = K(acts=[A("cough", "Cough", 1, "foe_facing", [S("weaken", 1)])], trig=[carrion()], ups=[
    U(trig=[carrion("foe_front_row")]),
    U(kw={"taunt": 1}),
    U(trig=[carrion(n=2)]),
])
weave = lambda n=1, mod=None: A("weave", "Weave", 1, "self", [SUM("shade", n, mod=dict({"kw": {"lifesteal": 1}}, **(mod or {})))], cond="empty_cell")
KITS["nocturne"] = K(acts=[weave()], ups=[
    U(acts=[weave(2)]),
    U(acts=[weave(1, {"kw": {"lifesteal": 1, "tough": 1}})]),
    U(acts=[weave(1, {"trig": [T("deathwish", [SOULS(1)])]})]),
])
bite = lambda extra=None: A("bite", "Drain Bite", 1, "foe", [H(), SOULS(1) | {"if": "target_cursed"}] + (extra or []))
KITS["deepfire-devourer"] = K(kw={"lifesteal": 1}, acts=[bite()], ups=[
    U(acts=[bite([BUFF("hp", 1, "self", **{"if": "target_cursed"})])]),
    U(trig=[T("bitemark", [S("weaken", 1, "target")])]),
    U(trig=[T("deathwish", [SUM("shade", 2)])]),
])
unlife = lambda souls=2, extra=None: A("unlife", "Unlife", 2, "dead_ally", [SUM("shade", 1, from_dead=True)] + (extra or []), souls=souls, cond="dead_ally")
KITS["death-knell"] = K(acts=[unlife()], ups=[
    U(kw={"undying": 1}, flags={"undying_pct": 0.5}),
    U(acts=[unlife(1)]),
    U(acts=[A("unlife", "Unlife", 2, "dead_ally", [SUM("shade", 1, from_dead=True, mod={"kw": {"barrier_start": 1}})], souls=2, cond="dead_ally")]),
])
KITS["abyssal-juggernaut"] = K(kw={"taunt": 1}, trig=[T("deathwatch", [BUFF("atk", 1, "self")]), T("deathwish", [SPECIAL("jugg_shades")], id="dw")], ups=[
    U(kw={"tough": 1}),
    U(trig=[T("deathwish", [SPECIAL("jugg_shades"), D(2, "foes")], id="dw")]),
    U(stats={"atk": 2}, kw_del=["taunt"]),
])
veil = A("veil", "Night Veil", 2, "foe_nocreep", [CREEP(2, "two")])
KITS["klaxon"] = K(kw={"creep_weaken": 1}, acts=[veil], ups=[
    U(kw={"creep_curse": 1}),
    U(acts=[A("puppets", "Shadow Puppets", 1, "foe_back", [PULL()], cond="creep_front")]),
    U(trig=[T(WARCRY, [CREEP(2, "two")])]),
])
doom = lambda extra=None: A("doomsay", "Doomsay", 2, "foe_strongest", [S("curse", 2)] + (extra or []))
KITS["black-solus"] = K(acts=[doom()], trig=[T("deathwatch", [D(1, "foes")], id="dw")], ups=[
    U(trig=[T("deathwatch", [D(2, "foes")], id="dw")]),
    U(trig=[T("deathwish", [S("curse", 2, "foes")])]),
    U(acts=[doom([S("vuln", 2)])]),
])
baron = lambda souls=2, pre=None: T("turn", (pre or []) + [SAC("token_lowest", then=[SOULS(souls), RALLY(1)])], id="t")
KITS["blood-baronette"] = K(trig=[T(WARCRY, [SUM("shade", 2)]), baron()], ups=[
    U(trig=[baron(2, [SUM("shade")])]),
    U(trig=[T(WARCRY, [KW("lifesteal", 1, "allies")])]),
    U(trig=[baron(3)]),
])
KITS["underlord-xorxuul"] = K(kw={"taunt": 1, "perm_deaths_atk": 1}, ups=[
    U(kw={"perm_deaths_hp": 1}),
    U(trig=[T(WARCRY, [SPECIAL("throne_of_souls")])]),
    U(trig=[T(WARCRY, [BAR("self")])]),
])

# ============================== MAGMAR
goad = lambda n=1, extra=None: A("goad", "Goad", 1, "ally_strongest", [BUFF("atk", n)] + (extra or []))
KITS["moloki-huntress"] = K(acts=[goad()], ups=[
    U(acts=[goad(2)]),
    U(acts=[goad(1, [KW("regen", 1)])]),
    U(trig=[T(WARCRY, [BUFF("atk", 1, "allies_other")])]),
])
KITS["wild-inceptor"] = K(acts=[A("warm", "Warm", 1, "egg", [SPECIAL("hatch")], cond="egg")], trig=[T(WARCRY, [KW("rebirth", 1, "ally_near")], id="wc")], ups=[
    U(trig=[T(WARCRY, [KW("rebirth", 1, "ally_near2")], id="wc")]),
    U(flags={"side_egg_hp": 3}),
    U(flags={"side_hatch_atk": 1}),
])
bear = FORM("bear", hp=3, atk=2, sprite="form-bear", name="Bear form")
KITS["earth-walker"] = K(trig=[T("stall", [TRANS(bear)], stall=2, id="st")], ups=[
    U(trig=[T("stall", [TRANS(FORM("wolf", kw={"dash": 1, "charge": 2}, sprite="form-wolf", name="Wolf form"))], stall=2, id="st")]),
    U(trig=[T("stall", [TRANS(bear)], stall=1, id="st")]),
    U(trig=[T("stall", [TRANS(bear), BAR("self")], stall=2, id="st")]),
])
KITS["young-silithar"] = K(kw={"dash": 1, "grow": 1}, acts=[HIT("bite", "Bite")], ups=[
    U(kw={"atk_per_adj_ally": 1}), U(kw={"frenzy": 1}), U(kw={"charge": 1}),
])
KITS["grimrock"] = K(kw={"grow": 1, "overwhelm": 1}, acts=[HIT("slam", "Slam")], ups=[
    U(acts=[A("slam", "Slam", 1, "foe", [H(), PUSH()])]), U(kw={"tough": 1}), U(kw={"charge": 2}),
])
raptor_wc = lambda n=1, mod=None: T(WARCRY, [SUM("raptor", n, mod=mod)], id="wc")
KITS["beastclad-hunter"] = K(acts=[goad(2)], trig=[raptor_wc()], ups=[
    U(trig=[raptor_wc(2)]),
    U(trig=[raptor_wc(1, {"kw_del": ["ephemeral"]})]),
    U(acts=[goad(2, [S("haste", 1)])]),
])
KITS["kujata"] = K(flags={"side_egg_taunt": 1}, trig=[T(WARCRY, [KW("rebirth", 1, "adj_allies")], id="wc")], ups=[
    U(trig=[T(WARCRY, [KW("rebirth", 1, "adj_allies"), KW("rebirth", 1, "row_allies_other")], id="wc")]),
    U(flags={"side_egg_taunt": 1, "side_hatch_atk": 2}),
    U(trig=[T("stall", [KW("rebirth", 1, "self")], stall=2)]),
])
feral = lambda extra=None: FORM("feral", atk=3, kw=dict({"regen": 2, "frenzy": 1}, **(extra or {})), sprite="form-feral", name="Feral form")
KITS["ragebinder"] = K(trig=[T("below_half", [TRANS(feral())], id="t")], ups=[
    U(trig_del=["t"], trig=[T(WARCRY, [TRANS(feral())])]),
    U(trig=[T("below_half", [TRANS(feral({"grow": 1}))], id="t")]),
    U(trig=[T("below_half", [TRANS(feral({"overwhelm": 1}))], id="t")]),
])
KITS["warpup"] = K(kw={"frenzy": 1}, trig=[T("bitemark", [BUFF("atk", 1, "self"), BUFF("hp", 1, "self", grow=True)], id="b", per_turn=1)], ups=[
    U(trig=[T("bitemark", [BUFF("atk", 2, "self"), BUFF("hp", 2, "self", grow=True)], id="b", per_turn=1)]),
    U(kw={"dash": 1, "charge": 1}),
    U(trig=[T("kill", [EXTRA()], per_turn=1)]),
])
colossus = lambda extra=None: FORM("colossus", hp=4, atk=2, spd=-1, kw=dict({"overwhelm": 1}, **(extra or {})), sprite="form-colossus", name="Colossus form")
shift = lambda cost=2, extra=None, **k: A("shift", "Shift", cost, "self", [TRANS(colossus(extra))], cond="not_form", **k)
KITS["rancour"] = K(acts=[shift()], ups=[
    U(acts=[shift(0, free=True)]),
    U(acts=[shift(2, {"grow": 1})]),
    U(acts=[shift(2, {"barrier_start": 1})]),
])
KITS["kolossus"] = K(kw={"grow": 2, "overwhelm": 1}, acts=[A("stomp", "Stomp", 2, "foe", [H(), PUSH()])], ups=[
    U(acts=[A("stomp", "Stomp", 2, "foe", [H(), H(1, "behind"), PUSH()])]),
    U(kw={"charge": 2}),
    U(kw={"rebirth": 1}),
])
elder_wc = lambda extra=None: T(WARCRY, [BUFF("atk", 2, "allies")] + (extra or []), id="wc")
KITS["silithar-elder"] = K(kw={"grow": 1, "rebirth": 1}, trig=[elder_wc()], ups=[
    U(trig=[elder_wc([SUM("raptor", 2)])]),
    U(trig=[elder_wc([KW("grow", 1, "allies")])]),
    U(flags={"side_rebirth_keep": 1}),
])
# Magmar Adds
rizen = lambda n=2: T(WARCRY, [SUM("egg", n, hatch="raptor")], id="wc")
KITS["rizen"] = K(trig=[rizen()], ups=[
    U(trig=[rizen(3)]),
    U(flags={"side_egg_taunt": 1}),
    U(flags={"side_raptor_grow": 1}),
])
gore = lambda n=1: A("gore", "Gore", 1, "foe", [H()] + [PUSH()] * n)
KITS["makantor-warbeast"] = K(kw={"dash": 1, "charge": 3}, acts=[gore()], ups=[
    U(kw={"charge": 4}), U(kw={"anchor": 1}), U(acts=[gore(2)]),
])
magma = lambda extra=None, hp=0: FORM("magma", atk=2, hp=hp, kw=extra or {}, sprite="form-magma", name="Magma form", bitemark_grow=1)
KITS["lavaslasher"] = K(trig=[T("stall", [TRANS(magma())], stall=2, id="st")], ups=[
    U(trig_del=["st"], trig=[T(WARCRY, [TRANS(magma())])]),
    U(trig=[T("stall", [TRANS(magma(hp=3))], stall=2, id="st")]),
    U(trig=[T("stall", [TRANS(magma({"frenzy": 1}))], stall=2, id="st")]),
])
terr = lambda c=1, extra=None: T(WARCRY, [KW("charge", c, "allies"), KW("dash", 1, "allies")] + (extra or []), id="wc")
KITS["terradon"] = K(trig=[terr()], ups=[
    U(trig=[terr(2)]),
    U(trig=[terr(1, [KW("push_first", 1, "allies")])]),
    U(kw={"atk_per_faction_ally": 1}),
])
KITS["erratic-raptyr"] = K(flags={"raptyr": 1}, trig=[T("turn", [SPECIAL("raptyr")])], ups=[
    U(flags={"raptyr": 1, "raptyr_keep": 1}),
    U(flags={"raptyr": 1, "raptyr_charge": 2}),
    U(flags={"raptyr": 1, "raptyr_regen": 2}),
])
quake = lambda tgt="foe_front_row": A("quake", "Quake", 3, tgt, [H(), PUSH()])
KITS["krater"] = K(kw={"grow": 1}, acts=[quake()], ups=[
    U(flags={"aftershock": 1}),
    U(kw={"grow": 2}),
    U(acts=[quake("foes")]),
])
KITS["unstable-leviathan"] = K(kw={"grow": 3, "overwhelm": 1, "rebirth": 1}, ups=[
    U(kw={"anchor": 1}), U(kw={"frenzy": 1}),
    U(trig=[T("kill", [KW("grow", 1, "self")])]),
])
KITS["progenitor"] = K(kw={"atk_per_hatch": 2}, trig=[T(WARCRY, [KW("rebirth", 1, "allies")], id="wc")], ups=[
    U(flags={"side_hatch_atk": 2}),
    U(flags={"side_hatch_grow": 1}),
    U(trig=[T(WARCRY, [KW("rebirth", 2, "allies")], id="wc")]),
])
def avatar(cost=2, extra_kw=None):
    ek = extra_kw or {}
    return [
        A("bear", "Bear Avatar", cost, "self", [TRANS(FORM("g_bear", hp=3, atk=3, kw=dict({"taunt": 1}, **ek), sprite="form-bear", name="Bear form", stack=True))], cond="avatar_bear"),
        A("wyrm", "Wyrm Avatar", cost, "self", [TRANS(FORM("g_wyrm", hp=3, atk=3, kw=dict({"frenzy": 1}, **ek), sprite="form-wyrm", name="Wyrm form", stack=True))], cond="avatar_wyrm"),
        A("wolf", "Wolf Avatar", cost, "self", [TRANS(FORM("g_wolf", hp=3, atk=3, kw=dict({"dash": 1, "charge": 2}, **ek), sprite="form-wolf", name="Wolf form", stack=True))], cond="avatar_wolf"),
    ]
KITS["gigaloth"] = K(acts=avatar(), ups=[
    U(acts=avatar(1)),
    U(acts=avatar(2, {"barrier_start": 1})),
    U(flags={"apex": 1}),
])

# ============================== VANAR
breath = lambda n=1: A("breath", "Frost Breath", 1, "foe_strongest", [S("chill", n)])
KITS["winter-maerid"] = K(acts=[breath()], ups=[
    U(acts=[breath(2)]),
    U(trig=[T(WARCRY, [BAR("ally_front_or_adj")])]),
    U(kw={"solitary_atk": 2}),
])
KITS["snow-chaser"] = K(kw={"solitary_atk": 1}, acts=[A("bite", "Bite", 1, "foe", [H(), S("chill", 1)])], ups=[
    U(kw_del=["solitary_atk"], kw={"atk_per_adj_ally": 1}),
    U(trig=[T(WARCRY, [S("chill", 1, "foes")])]),
    U(trig=[T("below_half", [BAR("self")])]),
])
ward = lambda tgt="ally_nobarrier", extra=None: A("ward", "Ward", 1, tgt, [BAR()] + (extra or []), cond="ally_nobarrier")
KITS["thicket-augur"] = K(acts=[ward()], ups=[
    U(acts=[ward(extra=[GAIN("pp", 1)])]),
    U(trig=[T("stall", [TRANS(FORM("frost_wolf", atk=2, kw={"dash": 1}, sprite="tok-frost-wolf", name="Frost Wolf form"))], stall=3)]),
    U(acts=[ward("ally_nobarrier2")]),
])
snare = lambda d=1, tgt="foe": A("snare", "Snare", 1, tgt, [H(), S("icehold", 1, dur=d)])
KITS["freeblade"] = K(acts=[snare()], ups=[
    U(acts=[snare(2)]), U(kw={"raid": 1}), U(acts=[snare(1, "foe_back")]),
])
KITS["cryoblade"] = K(kw={"fearless": 1}, acts=[HIT("axe", "Axe")], ups=[
    U(kw={"raid": 1}), U(kw={"berserk": 1}), U(trig=[T(WARCRY, [BAR("self")])]),
])
gale = lambda c=1, extra=None: A("gale", "Numbing Gale", 2, "foe_strongest", [NUMB(1), S("chill", c)] + (extra or []))
KITS["cloudcaller"] = K(acts=[gale()], ups=[
    U(acts=[gale(2)]),
    U(acts=[gale(1, [{"do": "drain_pp", "n": 1}])]),
    U(trig=[T("stall", [TRANS(FORM("c_bear", hp=3, kw={"taunt": 1}, sprite="form-spirit-bear", name="Bear form"))], stall=3)]),
])
saga = lambda extra=None: A("saga", "Saga", 1, "allies_other", [GAIN("pp", 1)] + (extra or []))
KITS["hearth-sister"] = K(acts=[saga()], trig=[T(WARCRY, [BAR("front_allies")])], ups=[
    U(acts=[saga([BUFF("atk", 1, dur=1)])]),
    U(kw={"raid_vikings": 1}),
    U(trig=[T("deathwish", [GAIN("pp", 2, "allies")])]),
])
KITS["night-howler"] = K(kw={"solitary_atk": 2, "hit_chill": 1}, ups=[
    U(kw_del=["hit_chill"], kw={"hit_numb": 1}),
    U(kw={"solitary_barrier": 1}),
    U(kw={"hit_curse": 1}),
])
KITS["fenrir-berserker"] = K(kw={"fearless": 1}, acts=[A("cleave", "Cleave", 2, "foe", [H(), H(1, "behind")])], ups=[
    U(kw={"raid": 2}),
    U(trig=[T(WARCRY, [BAR("adj_allies")])]),
    U(kw={"berserk": 1}),
])
nlight = lambda d=1, extra=None: A("nlight", "Northern Light", 2, "foe_strongest", [S("hush", 1, dur=d), S("chill", 2)] + (extra or []))
KITS["crystal-arbiter"] = K(acts=[nlight()], ups=[
    U(acts=[nlight(2)]),
    U(acts=[nlight(1, [BAR("ally_nobarrier")])]),
    U(trig=[T(WARCRY, [S("hush", 1, "foe_strongest", dur=1), S("chill", 2, "foe_strongest")])]),
])
KITS["draugar-lord"] = K(kw={"fearless": 1}, acts=[A("smash", "Ice Smash", 3, "foe", [H(), SPECIAL("freeze_if_chilled")])], trig=[T(WARCRY, [BAR("self")])], ups=[
    U(kw={"raid": 3}),
    U(trig=[T(WARCRY, [KW("hit_chill", 1, "allies")])]),
    U(trig=[T("turn", [BAR("self")], every=3)]),
])
ygg_bear = lambda extra=None: FORM("ygg", hp=4, atk=2, kw=dict({"taunt": 1, "barrier_start": 1}, **(extra or {})), sprite="form-great-spirit-bear", name="Great Spirit Bear")
KITS["disciple-of-yggdra"] = K(trig=[T(WARCRY, [S("chill", 1, "foes"), NUMB(1, "foes")]), T("stall", [TRANS(ygg_bear())], stall=2, id="st")], ups=[
    U(trig=[T("turn", [S("chill", 1, "foes"), NUMB(1, "foes")], every=3)]),
    U(trig=[T("stall", [TRANS(ygg_bear())], stall=1, id="st")]),
    U(trig=[T("stall", [TRANS(ygg_bear({"grow": 1}))], stall=2, id="st")]),
])
# Vanar Adds
KITS["glacial-elemental"] = K(kw={"taunt": 1}, trig=[T("turn", [BAR("self")], every=2, id="b")], ups=[
    U(trig=[T("turn", [BAR("self")], id="b")]),
    U(trig=[T("hit_taken", [S("chill", 1, "source")])]),
    U(trig=[T("deathwish", [BAR("adj_allies")])]),
])
KITS["ursaplomb"] = K(trig=[T(WARCRY, [GAIN("pp", 1, "allies")])], ups=[
    U(kw={"raid": 2}),
    U(trig=[T(WARCRY, [GAIN("pp", 2, "ally_front_or_adj")])]),
    U(trig=[T(WARCRY, [KW("fearless", 1, "allies", dur=2)])]),
])
dive = lambda extra=None: A("dive", "Dive", 1, "foe_back", [H(), S("chill", 1)] + (extra or []))
KITS["wolfraven"] = K(acts=[dive()], ups=[
    U(acts=[dive([S("icehold", 1, dur=1)])]),
    U(kw={"hit_numb": 1}),
    U(kw={"raid": 1}),
])
wisp_t = lambda extra=None: T("turn", [S("icehold", 1, "foe_adjacent", dur=1)] + (extra or []), id="t")
KITS["malicious-wisp"] = K(trig=[wisp_t()], ups=[
    U(trig=[wisp_t([S("chill", 1, "foe_adjacent")])]),
    U(trig=[wisp_t([S("curse", 1, "foe_adjacent")])]),
    U(trig=[wisp_t([BAR("self", **{"if": "iceheld_any"})])]),
])
KITS["matron-elveiti"] = K(acts=[A("aurora", "Aurora Ward", 2, "allies", [BAR()], cond="ally_nobarrier")], ups=[
    U(trig=[T(WARCRY, [STALLMOD(-1, "allies")])]),
    U(trig=[T(WARCRY, [S("hush", 1, "foe_strongest", dur=1)])]),
    U(trig=[T("stall", [TRANS(FORM("owl", atk=2, kw={"hit_chill": 1}, sprite="form-wyrm", name="Owl form"))], stall=2)]),
])
harpoon = lambda extra=None: A("harpoon", "Harpoon", 2, "foe_back", [PULL(), S("icehold", 1, dur=1)] + (extra or []))
KITS["kindred-hunter"] = K(acts=[harpoon()], ups=[
    U(acts=[harpoon([H()])]),
    U(kw={"raid": 2}),
    U(acts=[harpoon([NUMB(1)])]),
])
KITS["seismic-elemental"] = K(kw={"fearless": 1, "hit_chill": 2}, trig=[T(WARCRY, [S("frozen", 1, "foe_front_row", dur=1)])], ups=[
    U(kw={"frozen_bonus": 2}),
    U(trig=[T("turn", [BAR("self")], every=2)]),
    U(kw={"overwhelm": 1}),
])
KITS["fenrir-warmaster"] = K(kw={"fearless": 1, "raid": 1, "raid_grows": 1}, ups=[
    U(trig=[T(WARCRY, [KW("raid", 1, "viking_allies")])]),
    U(kw={"raid_atk": 1}),
    U(trig=[T(WARCRY, [NUMB(1, "foes")])]),
])
KITS["ghost-wolf"] = K(kw={"solitary_atk": 3, "solitary_barrier": 1, "hit_chill": 1}, ups=[
    U(kw_del=["solitary_atk", "solitary_barrier"], trig=[T(WARCRY, [BUFF("atk", 2, "spirit_allies")])]),
    U(trig=[T(WARCRY, [S("hush", 1, "foes", dur=1)])]),
    U(flags={"side_freeze_extra": 1}),
])

# ============================== CHAMPIONS (no rank-up; "relic" is always on)
KITS["ziran-sunforge"] = K(kw={"radiance": 3}, acts=[A("dawnsong", "Dawnsong", 2, "allies", [HEAL()], cond="ally_hurt")],
    trig=[T("stall", [REVIVE("dead_allies", 0.01)], stall=4, id="st")],
    relic=U(trig=[T("stall", [REVIVE("dead_allies", 0.01, then=[BUFF("atk", 2)])], stall=3, id="st")]))
KITS["argeon-highmayne"] = K(acts=[A("dawnstrike", "Dawnstrike", 3, "foe_front_row", [H(), HEAL("allies", amount="dealt")])],
    trig=[T(WARCRY, [RALLY(1), KW("tough", 1, "allies")])],
    relic=U(trig=[T("turn", [RALLY(1), KW("tough", 1, "allies")], every=3)]))
KITS["indominus"] = K(kw={"taunt": 1, "tough": 3}, trig=[T("hit_taken", [HEAL("ally_lowest", n=1)], id="h"),
    T("deathwish", [KW("tough", 2, "allies"), KW("taunt", 1, "ally_highest_hp")])],
    relic=U(kw={"anchor": 1}, trig=[T("hit_taken", [HEAL("ally_lowest", n=2)], id="h")]))
KITS["grandmaster-zendo"] = K(acts=[A("swap", "Swap", 0, "allies", [REPOS()], cond="repos", free=True, per_turn=1)],
    trig=[T(WARCRY, [KW("strikeback", 1, "row_allies")]), T("turn_end", [GAIN("pp", 1, "allies")], cond="not_moved", id="still")],
    relic=U(kw={"anchor": 1}, trig=[T("turn_end", [GAIN("pp", 1, "allies"), BUFF("atk", 2, "self")], cond="not_moved", id="still")]))
KITS["reva-eventide"] = K(kw={"swift": 1, "combo": 1}, flags={"side_combo_keep": 1}, acts=[A("tempest", "Tempest", 2, "foes", [H(1, combo_each=True)])],
    relic=U(acts=[A("tempest", "Tempest", 1, "foes", [H(1, combo_each=True)])]))
KITS["shidai-stormblossom"] = K(kw={"swift": 1, "elusive": 1, "bounty": 2}, trig=[T("kill", [S("vanished", 1, "self"), BLINK("self"), EXTRA()], per_turn=3)],
    relic=U(kw={"bounty": 4, "hit_vuln": 1}))
KITS["scioness-sajj"] = K(flags={"side_stall_twice": 1}, relic=U(flags={"side_stall_twice": 1, "side_stall_third": 6}))
KITS["zirix-starstrider"] = K(kw={"aura_tok_noeph": 1, "aura_tok_atk": 1}, acts=[A("decree", "Royal Decree", 3, "foes", [PRG()], cond="foe_buffed")],
    trig=[T(WARCRY, [SUM("sand-wisp", 6)], id="wc")],
    relic=U(trig=[T(WARCRY, [obel(), SUM("sand-wisp", 6, mod={"stats": {"hp": 1, "atk": 1}})], id="wc")]))
KITS["ciphyron-ascendant"] = K(kw={"dash": 1, "blast": 1, "atk_per_token": 1},
    relic=U(trig=[T("bitemark", [SUM("sand-wisp")], per_turn=1)]))
KITS["lilithe-blightchaser"] = K(trig=[T(WARCRY, [S("curse", 2, "foes"), CREEP(1, "all")], id="wc")],
    relic=U(trig=[T(WARCRY, [S("curse", 2, "foes"), CREEP(2, "all"), S("weaken", 1, "foes")], id="wc")]))
KITS["cassyva-soulreaper"] = K(acts=[A("gate", "Abyss Gate", 3, "self", [SUM("abomination")], souls=4, cond="empty_cell")],
    trig=[T("deathwatch", [SOULS(1), SUM("shade")], id="dw")],
    relic=U(acts=[A("gate", "Abyss Gate", 3, "self", [SUM("abomination")], souls=2, cond="empty_cell")],
            trig=[T("deathwatch", [SOULS(1), SUM("shade", 1, mod={"kw_del": ["ephemeral"]})], id="dw")]))
KITS["grandmaster-variax"] = K(kw={"taunt": 1}, acts=[feast(cost=0, free=True, per_turn=1)],
    trig=[T("deathwatch", [BUFF("atk", 2, "self"), BUFF("hp", 2, "self")])],
    relic=U(kw={"overwhelm": 1, "lifesteal": 1}))
KITS["ragnora-the-relentless"] = K(trig=[T(WARCRY, [SUM("raptor", 6, mod={"kw_del": ["ephemeral"]}), BUFF("atk", 2, "allies"), KW("rebirth", 1, "allies")], id="wc")],
    relic=U(trig=[T(WARCRY, [SUM("raptor", 6, mod={"kw_del": ["ephemeral"], "kw": {"grow": 1}}), BUFF("atk", 2, "allies"), KW("rebirth", 2, "allies")], id="wc")]))
KITS["starhorn-the-seeker"] = K(trig=[T("turn", [SPECIAL("starhorn")])], relic=U(flags={"starhorn_idol": 1}))
KITS["grandmaster-kraigon"] = K(kw={"grow": 3, "overwhelm": 1, "frenzy": 1, "rebirth": 1}, relic=U(kw={"charge": 3}, flags={"rebirth_keep_self": 1}))
KITS["voice-of-the-wind"] = K(trig=[T(WARCRY, [S("chill", 2, "foes")], id="wc"), T("turn", [NUMB(1, "foes")])],
    relic=U(trig=[T(WARCRY, [S("chill", 3, "foes"), S("hush", 1, "foes", dur=1)], id="wc")]))
spirit_bear = FORM("spirit_bear", hp=4, atk=2, kw={"taunt": 1}, sprite="form-spirit-bear", name="Spirit Bear")
KITS["faie-bloodwing"] = K(trig=[T(WARCRY, [S("hush", 1, "foes", dur=1)]), T("turn", [BAR("allies")], every=3, id="b"), T("stall", [TRANS(spirit_bear)], stall=2, id="st")],
    relic=U(trig_del=["st"], trig=[T(WARCRY, [TRANS(spirit_bear)]), T("turn", [BAR("allies")], every=2, id="b")]))
KITS["kara-winterblade"] = K(kw={"fearless": 1, "raid": 1, "raid_grows": 1}, trig=[T(WARCRY, [S("frozen", 1, "foe_front_row", dur=1), BAR("self")]), T("turn", [BAR("self")], every=3)],
    relic=U(kw={"raid_atk": 1}, trig=[T(WARCRY, [KW("hit_chill", 1, "allies")])]))

# ------------------------------------------------------------------ tokens and monsters
TOKENS = {
    # id: (name, faction, sprite kit, hp, atk, spd, range, kw, extra)
    "sand-wisp": ("Sand Wisp", "vetruvian", "tok-sand-wisp", 1, 1, 3, "melee", {"ephemeral": 2}, {}),
    "shade": ("Shade", "abyssian", "tok-shade", 1, 1, 3, "melee", {"ephemeral": 2}, {}),
    "raptor": ("Raptor", "magmar", "tok-raptor", 2, 2, 3, "melee", {"ephemeral": 2}, {}),
    "scarab": ("Scarab", "vetruvian", "tok-scarab", 1, 1, 4, "melee", {"ephemeral": 1}, {}),
    "obelysk": ("Obelysk", "vetruvian", "tok-obelysk", 3, 0, 1, "melee", {"anchor": 1}, {"trig": [T("turn", [SUM("sand-wisp", 1)])], "no_attack": True}),
    "abomination": ("Abomination", "abyssian", "tok-abomination", 4, 4, 2, "melee", {}, {}),
    "egg": ("Egg", "magmar", "tok-egg", 1, 0, 0, "melee", {}, {"no_attack": True}),
    "mirror": ("Mirror image", "songhai", "tok-mirror", 1, 1, 3, "melee", {"taunt": 1, "ephemeral": 2}, {}),
}
MONSTERS = {
    "stone_golem": ("Stone Golem", "neutral_golemstone", 6, 2, 1, "melee", {"taunt": 1}),
    "saberspine": ("Saberspine Tiger", "neutral_beastsaberspinetiger", 3, 3, 4, "melee", {}),
    "phase_hound": ("Phase Hound", "neutral_beastphasehound", 2, 3, 5, "melee", {"swift": 1}),
    "ice_golem": ("Ice Golem", "neutral_golemice", 5, 2, 1, "melee", {"hit_chill": 1}),
    "giant_crab": ("Giant Crab", "neutral_giantcrab", 4, 2, 2, "melee", {"tough": 1}),
    "sand_panther": ("Sand Panther", "boss_sandpanther", 7, 4, 3, "melee", {"frenzy": 1}),
}

# Keyword registry (doc "Keyword registry (agreed)" + timing keywords). Owner -> faction id or common.
REGISTRY = [
    ("taunt", "Taunt", "common", "Enemy single-target attacks must hit this unit if they can reach it."),
    ("barrier", "Barrier", "vanar", "Negates the next damage instance."),
    ("tough", "Tough", "lyonar", "Takes X less damage per hit."),
    ("lifesteal", "Lifesteal", "abyssian", "Heals for the damage it deals."),
    ("regen", "Regenerate", "common", "Heals X at the start of each of its turns."),
    ("overwhelm", "Overwhelm", "magmar", "Damage past the target's HP spills onto the unit behind."),
    ("elusive", "Elusive", "songhai", "Only Ranged or Elusive units can target it."),
    ("swift", "Swift", "songhai", "Acts first."),
    ("warcry", "Warcry", "common", "Fires at battle start."),
    ("deathwish", "Deathwish", "common", "Fires when this unit dies."),
    ("bitemark", "Bitemark", "common", "Fires each time this unit lands an attack."),
    ("strikeback", "Strikeback", "common", "When hit by melee, spends PP to hit back."),
    ("ephemeral", "Ephemeral", "common", "Dies at the end of its turn (Ephemeral X: after X turns)."),
    ("summon", "Summon", "common", "Puts a token in an empty cell; nothing if none is empty."),
    ("transform", "Transform", "magmar", "Turns into another form."),
    ("solitary", "Solitary", "vanar", "Bonus while no ally is adjacent."),
    ("anchor", "Anchor", "common", "Can't be moved by Push, Pull or Swap."),
    ("push", "Push", "common", "Moves the target back a row, or deals X if it can't move."),
    ("pull", "Pull", "common", "Drags a back-row target to the front of its lane."),
    ("swap", "Swap", "lyonar", "Trades places with an ally."),
    ("dash", "Dash", "common", "Moves one cell for free before attacking."),
    ("blink", "Blink", "songhai", "Moves to any empty cell on its side."),
    ("icehold", "Icehold", "vanar", "Can't move or be moved."),
    ("charge", "Charge", "magmar", "+X damage on its first attack after moving this turn."),
    ("zeal", "Zeal", "lyonar", "Bonus while an ally is directly in front."),
    ("guard", "Guard", "lyonar", "Takes a hit meant for an adjacent ally (1 PP)."),
    ("rally", "Rally", "lyonar", "All allies gain X for the fight."),
    ("backstab", "Backstab", "songhai", "+X damage on targets that haven't acted this turn."),
    ("vanish", "Vanish", "songhai", "After acting, Elusive until hit."),
    ("combo", "Combo", "songhai", "Each consecutive Songhai action gains +1 damage."),
    ("vuln", "Vulnerable", "songhai", "Prime target for its next X hits taken; those hits deal bonus damage."),
    ("haste", "Haste", "songhai", "+X Speed."),
    ("bounty", "Bounty", "songhai", "Earns X gold on kill."),
    ("blast", "Blast", "common", "Its attack hits the whole enemy row."),
    ("purge", "Purge", "vetruvian", "Removes an enemy's buffs."),
    ("deathwatch", "Deathwatch", "abyssian", "Fires whenever any unit dies."),
    ("creep", "Creep", "abyssian", "Marks an enemy cell; its occupant takes X at turn start."),
    ("souls", "Souls", "abyssian", "Gained on deaths, spent to empower actions (shared by the team)."),
    ("sacrifice", "Sacrifice", "abyssian", "Kills an ally for value."),
    ("curse", "Curse", "abyssian", "Loses X x 5% of its max HP at the end of each of its turns."),
    ("weaken", "Weaken", "abyssian", "Deals X less damage per hit."),
    ("grow", "Grow", "magmar", "+X Attack and HP at the start of each of its turns."),
    ("frenzy", "Frenzy", "magmar", "Attacks hit all adjacent enemies."),
    ("rebirth", "Rebirth", "magmar", "On death, leaves an Egg that hatches next turn unless killed. Once per fight."),
    ("goad", "Goad", "magmar", "One ally gains X for the fight."),
    ("chill", "Chill", "vanar", "-X Speed; at 3 stacks, Frozen (skips a turn)."),
    ("numb", "Numb", "vanar", "Removes X AP or PP from an enemy."),
    ("hush", "Hush", "vanar", "Loses keywords and PP reactions for one turn."),
    ("fearless", "Fearless", "vanar", "+1 Attack while in the front row."),
    ("raid", "Raid", "vanar", "Earns X gold when it survives the fight."),
    ("rush", "Rush", "common", "The effect is active during its first X turns, then ends."),
    ("stall", "Stall", "common", "The effect turns on after X of its turns and stays on."),
    ("cleanse", "Cleanse", "lyonar", "Removes a harmful status from an ally."),
]
REG_NAMES = {k: n for k, n, _, _ in REGISTRY}
# Keyword ids found in kit text -> shown as icons on the card (display only).
SCAN = [(n, k) for k, n, _, _ in REGISTRY] + [("Vulnerable", "vuln"), ("Regenerate", "regen"), ("Freeze", "chill"), ("Frozen", "chill"),
       ("Soul", "souls"), ("Earner", "bounty")]

FACTIONS = {"Lyonar": "lyonar", "Songhai": "songhai", "Vetruvian": "vetruvian", "Abyssian": "abyssian", "Magmar": "magmar", "Vanar": "vanar"}
RARITY = {"Common": 0, "Rare": 1, "Epic": 2, "Legendary": 3, "Champion": 4}


def scan_keywords(text):
    out = []
    for name, k in SCAN:
        if re.search(r"\b" + re.escape(name), text) and k not in out:
            out.append(k)
    return out


def split_ups(text):
    out = []
    for part in [p.strip() for p in text.split(" · ") if p.strip()]:
        if ":" in part:
            nm, tx = part.split(":", 1)
            out.append((nm.strip(), tx.strip()))
        else:
            out.append((part, part))
    return out


def action_text(kit_text, name):
    for sent in re.split(r"(?<=\.)\s+", kit_text):
        if sent.startswith(name) or name in sent[:40]:
            return sent
    return kit_text


def build():
    doc = json.load(open(os.path.join(HERE, "doc_units.json")))
    board = json.load(open(os.path.join(HERE, "board_sprites.json")))
    units, problems = {}, []
    for u in doc:
        uid = u["id"]
        if uid not in KITS:
            problems.append("no kit for " + uid)
            continue
        kit = KITS[uid]
        hp, atk, spd = [int(x) for x in re.findall(r"\d+", u["stats"])[:3]]
        rng = "ranged" if "ranged" in u["stats"] else "melee"
        rar = RARITY[u["rarity"]]
        ups_txt = split_ups(u["ranks"])
        for a in kit["acts"]:
            a.setdefault("text", action_text(u["kit"], a["name"]))
        d = {
            "id": uid, "name": u["name"], "faction": FACTIONS[u["faction"]], "rarity": rar, "add": u["add"], "spot": u["spot"],
            "sprite": board[uid]["sprite"], "hp": hp, "atk": atk, "spd": spd, "range": rng,
            "kit_text": u["kit"], "keywords": scan_keywords(u["kit"]) + [k for k in kit["kw"] if k in REG_NAMES and k not in scan_keywords(u["kit"])],
            "kw": kit["kw"], "acts": kit["acts"], "trig": kit["trig"], "flags": kit["flags"], "ups": [],
        }
        if rar == 4:
            nm, tx = ups_txt[0]
            d["relic_name"], d["relic_text"], d["relic_mod"] = nm, tx, kit["relic"] or {}
        else:
            if len(kit["ups"]) != 3 or len(ups_txt) != 3:
                problems.append("%s: %d ups / %d texts" % (uid, len(kit["ups"]), len(ups_txt)))
            for i, mod in enumerate(kit["ups"]):
                nm, tx = ups_txt[i] if i < len(ups_txt) else ("Upgrade", "")
                for a in mod.get("acts", []):
                    a.setdefault("text", tx)
                d["ups"].append({"id": "%s-%d" % (uid, i), "name": nm, "text": tx, "mod": mod,
                                 "keywords": [k for k in scan_keywords(tx) if k not in d["keywords"]]})
        units[uid] = d
    tokens = {}
    for tid, (nm, fac, spr, hp, atk, spd, rng, kw, extra) in TOKENS.items():
        tokens[tid] = {"id": tid, "name": nm, "faction": fac, "rarity": 5, "sprite": board[spr]["sprite"], "hp": hp, "atk": atk, "spd": spd,
                       "range": rng, "kw": kw, "acts": [], "trig": extra.get("trig", []), "flags": {}, "no_attack": extra.get("no_attack", False),
                       "keywords": [k for k in kw if k in REG_NAMES], "kit_text": ""}
    monsters = {}
    for mid, (nm, spr, hp, atk, spd, rng, kw) in MONSTERS.items():
        monsters[mid] = {"id": mid, "name": nm, "faction": "neutral", "rarity": 6, "sprite": spr, "hp": hp, "atk": atk, "spd": spd,
                         "range": rng, "kw": kw, "acts": [], "trig": [], "flags": {}, "keywords": [k for k in kw if k in REG_NAMES], "kit_text": ""}
    forms = {k[5:]: v["sprite"] for k, v in board.items() if k.startswith("form-")}
    forms.update({k: v["sprite"] for k, v in board.items() if k.startswith("tok-")})
    registry = [{"id": k, "name": n, "owner": o, "text": t} for k, n, o, t in REGISTRY]
    out = {"units": units, "tokens": tokens, "monsters": monsters, "form_sprites": {**{"form-" + k: v for k, v in forms.items()}}, "keywords": registry}
    # sprite ids by board kit id, for forms written as "form-bear" / "tok-frost-wolf"
    out["form_sprites"] = {k: v["sprite"] for k, v in board.items() if k.startswith("form-") or k.startswith("tok-")}
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print("units", len(units), "tokens", len(tokens), "monsters", len(monsters))
    for p in problems:
        print("PROBLEM", p)
    return problems


if __name__ == "__main__":
    raise SystemExit(1 if build() else 0)
