"""Generate CraftPath/Data_<Profession>.lua for every profession from a raw
Wowhead (WoW Forever) export.

Usage: python gen_data.py            (reads raw/all_professions.json)

Raw format, per skill line id (exported from wowhead.com/forever/skill=<id> listviews):
  R: [spellId, name, colors[o,y,g,gray], learnedAt, creates[item,min,max], reagents[[item,n]], sources[], trainingCost, specSpell, envStatus]
  I: {itemId: [name, avgBuyout, vendorSellPrice]}
  P: [planItemId, planName, skill, sources[], sourcemore[[type, name, zone]]]
  T: [trainerName, title, react[Alliance, Horde], zoneId]
  S: rank spells (not used directly)

raw/blacksmithing.json (older export) adds exact plan vendor prices for Blacksmithing.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..")

CRAFT_RANKS = [
    # cap, next rank, skill needed, character level
    (75, "Journeyman", 50, 10, None),
    (150, "Expert", 125, 20, None),
    (225, "Artisan", 200, 35, None),
]

PROFESSIONS = {
    164: dict(key="Blacksmithing", spell=2018, icon="Trade_BlackSmithing", ranks=CRAFT_RANKS,
              specs={9788: "Armorsmith", 9787: "Weaponsmith", 17039: "Master Swordsmith",
                     17040: "Master Hammersmith", 17041: "Master Axesmith"}),
    165: dict(key="Leatherworking", spell=2108, icon="Trade_LeatherWorking", ranks=CRAFT_RANKS,
              specs={10656: "Dragonscale Leatherworking", 10658: "Elemental Leatherworking",
                     10660: "Tribal Leatherworking"}),
    197: dict(key="Tailoring", spell=3908, icon="Trade_Tailoring", ranks=CRAFT_RANKS, specs={}),
    333: dict(key="Enchanting", spell=7411, icon="Trade_Engraving", ranks=CRAFT_RANKS, specs={}),
    185: dict(key="Cooking", spell=2550, icon="INV_Misc_Food_15", specs={}, ranks=[
        (75, "Journeyman", 50, 10, None),
        (150, "Expert", 125, None, "Book \"Expert Cookbook\" (about 1g): Shandrina, Ashenvale (Alliance) / Wulan, Desolace (Horde)"),
        (225, "Artisan", 200, None, "Quest \"Clamlette Surprise\": Dirge Quikcleave, Gadgetzan (Tanaris)"),
    ]),
    129: dict(key="First Aid", spell=3273, icon="Spell_Holy_SealOfSacrifice", specs={}, ranks=[
        (75, "Journeyman", 50, 10, None),
        (150, "Expert", 125, None, "Book \"Expert First Aid - Under Wraps\" (about 1g 11s): Deneb Walker, Arathi Highlands (Alliance) / Balai Lok'Wein, Dustwallow Marsh (Horde)"),
        (225, "Artisan", 200, None, "Quest \"Triage\": Doctor Gustaf VanHowzen, Theramore (Alliance) / Doctor Gregory Victor, Arathi Highlands (Horde)"),
    ]),
}

# Reagents sold by vendors. Wowhead's Forever data has no vendor info for
# them, so we seed 4x the vendor sell price (the usual buy/sell ratio) or a
# known price. The addon replaces these with real prices when you visit a vendor.
VENDOR_REAGENTS = {
    # Blacksmithing
    2880: None, 3466: None, 18567: None,
    # threads, dyes, bleach, salt
    2320: None, 2321: None, 4291: None, 8343: None, 14341: None,
    2604: None, 2605: None, 6260: None, 4340: None, 2325: None, 4341: None, 4342: None,
    6261: None, 10290: None, 2324: None, 4289: None,
    # enchanting supplies
    4470: None, 11291: None, 3371: None, 3372: None, 8925: None, 18256: None,
    # cooking: spices, drinks, misc.
    2678: 10, 2692: None, 3713: None, 159: 25, 1179: None, 4536: None,
    1205: None, 1708: None, 1645: None, 2594: None, 2596: None, 2686: None, 2723: None,
}

ZONES = {
    1: "Dun Morogh", 3: "Badlands", 40: "Westfall", 4: "Blasted Lands", 8: "Swamp of Sorrows", 10: "Duskwood",
    11: "Wetlands", 12: "Elwynn Forest", 14: "Durotar", 15: "Dustwallow Marsh", 16: "Azshara",
    17: "The Barrens", 28: "Western Plaguelands", 33: "Stranglethorn Vale (Booty Bay)",
    36: "Alterac Mountains", 38: "Loch Modan", 41: "Deadwind Pass", 44: "Redridge Mountains",
    45: "Arathi Highlands", 46: "Burning Steppes", 47: "The Hinterlands", 51: "Searing Gorge",
    85: "Tirisfal Glades", 130: "Silverpine Forest", 139: "Eastern Plaguelands", 141: "Teldrassil",
    148: "Darkshore", 209: "Shadowfang Keep", 215: "Mulgore", 267: "Hillsbrad Foothills",
    331: "Ashenvale", 357: "Feralas", 361: "Felwood", 400: "Thousand Needles", 405: "Desolace",
    406: "Stonetalon Mountains", 440: "Tanaris", 490: "Un'Goro Crater", 493: "Moonglade",
    616: "Mount Hyjal", 618: "Winterspring", 718: "Wailing Caverns", 721: "Gnomeregan",
    796: "Scarlet Monastery", 1337: "Uldaman", 1377: "Silithus", 1477: "Sunken Temple",
    1497: "Undercity", 1519: "Stormwind City", 1537: "Ironforge", 1581: "The Deadmines",
    1583: "Blackrock Spire", 1584: "Blackrock Depths", 1637: "Orgrimmar", 1638: "Thunder Bluff",
    1657: "Darnassus", 2017: "Stratholme", 2057: "Scholomance", 2557: "Dire Maul",
    2717: "Molten Core", 3428: "Ahn'Qiraj", 3429: "Ruins of Ahn'Qiraj",
    16554: "Blackmaw Hold", 16591: "Riverglades", 16593: "Zephras Isle", 16651: "Shen'dralas",
}

# Trainer titles that don't teach the profession's ranks (specialists, vendors)
SKIP_TITLE = re.compile(r"Weapon|Armor|Crafter|Mining|Innkeeper|Butcher|Dragonscale|Tribal|Elemental|"
                        r"Shadoweave|Swordsmith|Hammersmith|Axesmith|Spellfire|Mooncloth")

SRC_FLAGS = {6: "t", 5: "v", 2: "d", 4: "q"}


# Rank spells per profession: Journeyman, Expert, Artisan. Who teaches each
# one comes from raw/rank_trainers.json (Wowhead "Taught by"); NPC titles are
# NOT reliable (e.g. Kitta Firewind <Artisan Enchanter> teaches Expert).
RANK_SPELLS = {
    164: [3100, 3538, 9785], 165: [3104, 3811, 10662], 197: [3909, 3910, 12180],
    333: [7412, 7413, 13920], 185: [3102, 3413, 18260], 129: [3274, 7924, 10846],
}


def rank_trainers():
    path = os.path.join(HERE, "raw", "rank_trainers.json")
    return json.load(open(path, encoding="utf-8"))


def trainer_coords():
    """name -> (uiMapId, x, y) from raw/trainer_coords_*.json: compact
    {npcId: [name, uiMapId, x, y, zone]}, or Wowhead's NPC map data
    {npcId: {name, map: {areaId: [{coords, uiMapId, count}]}}} (the map with
    the most spawn points wins)."""
    out = {}
    rows = []
    # Wowhead first (Forever's own data), MetaForge fills the gaps
    for fname in ("trainer_coords_wowhead.json", "trainer_coords_metaforge.json"):
        path = os.path.join(HERE, "raw", fname)
        if os.path.exists(path):
            rows += list(json.load(open(path, encoding="utf-8")).items())
    for _id, e in rows:
        if _id.startswith("_"):
            continue
        if isinstance(e, list):  # compact: [name, uiMapId, x, y, zone]
            out.setdefault(e[0], (e[1], e[2], e[3]))
            continue
        if not e.get("map"):
            continue
        best = None
        for entries in e["map"].values():
            for m in entries:
                if m.get("coords") and m.get("uiMapId") and (best is None or m.get("count", 1) > best.get("count", 1)):
                    best = m
        if best:
            x, y = best["coords"][0]
            out.setdefault(e["name"], (best["uiMapId"], x, y))
    return out


def trainer_tiers(skill, T):
    """name -> (tier, react, zone). tier: highest rank taught (1 Apprentice
    only, 2 Journeyman, 3 Expert, 4 Artisan)."""
    rt = rank_trainers()
    out = {}
    for name, title, react, zone in T:
        if SKIP_TITLE.search(title or "") or "Skinning" in (title or ""):
            continue
        out.setdefault(name, [1, react, zone])
    for i, spell in enumerate(RANK_SPELLS[skill]):
        for _npc, name, _title, react, zone in rt.get(str(spell), []):
            e = out.setdefault(name, [1, react, zone])
            e[0] = max(e[0], i + 2)
    return out


def side_mask(react):
    if not react:
        return 3
    a, h = (react + [None, None])[:2]
    m = (1 if a is not None and a >= 0 else 0) + (2 if h is not None and h >= 0 else 0)
    return m or 3


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


# Crafts with a long cooldown can't be repeated for skill-ups
COOLDOWN = {"Mooncloth"}


def excluded(r):
    spell, reagents = r[0], r[5]
    if r[1] in COOLDOWN:
        return True
    if 400000 <= spell < 500000:  # Season of Discovery leftovers in Wowhead's dataset
        return True
    if any(211000 <= it < 222000 for it, _ in reagents):
        return True
    return not r[2] or not reagents  # no skill colors / nothing to craft with


def exact_bs_vendors():
    """Exact plan vendor prices from the first Blacksmithing export."""
    path = os.path.join(HERE, "raw", "blacksmithing.json")
    if not os.path.exists(path):
        return {}
    d = json.load(open(path, encoding="utf-8"))
    out = {p[0]: p[4] for p in d["P"] if p[4]}
    out.setdefault(251468, [["Pexmit", 90000, -1, 3, 616]])  # Plans: Bold Dirk (checked by hand)
    return out


def metaforge():
    """Recipe sources from metaforge.app (raw/metaforge_vendors.json):
    {planId: {v: [[name, copper, zoneText, npcHref, currencyOnly]], o: otherSourcesText}},
    npcs: {href: "Alliance"|"Horde"|...}. Returns (vendors, quests, nosource)."""
    path = os.path.join(HERE, "raw", "metaforge_vendors.json")
    if not os.path.exists(path):
        return {}, {}, set()
    d = json.load(open(path, encoding="utf-8"))
    npcs = d.get("npcs", {})
    side_of = {"Alliance": 1, "Horde": 2}
    vendors, quests, nosource = {}, {}, set()
    for k, e in d["recipes"].items():
        pid = int(k)
        vs = []
        for name, copper, zone, href, currency in e.get("v", []):
            stock = -1
            m = re.search(r",\s*Limited stock:\s*(\d+)", zone or "")
            if m:
                stock = int(m.group(1))
                zone = zone[:m.start()]
            if currency or not copper:
                continue  # sold for a special currency, not gold
            vs.append([name, copper, stock, side_of.get(npcs.get(href, ""), 3), zone.strip()])
        if vs:
            vendors[pid] = vs
        elif e.get("v"):
            nosource.add(pid)  # only sold for currency: can't plan with gold
        else:
            o = e.get("o") or ""
            m = re.search(r"reward from (.+)$", o)
            if m:
                quests[pid] = m.group(1).strip()
            # no "How to get" section at all = metaforge has no data yet, which
            # is not the same as "can't be bought": keep the Wowhead source
    return vendors, quests, nosource


def exact_route_vendors():
    """Exact vendors for recipes that appear on routes (raw/plan_vendors.json,
    fetched from Wowhead item pages). Same tuple shape as exact_bs_vendors."""
    path = os.path.join(HERE, "raw", "plan_vendors.json")
    if not os.path.exists(path):
        return {}
    d = json.load(open(path, encoding="utf-8"))
    out = {}
    for k, vs in d.items():
        if k.startswith("_"):
            continue
        out[int(k)] = [[n, price, stock, side_mask(react), zone] for n, price, stock, react, zone in vs]
    return out


def generate(skill, prof, d, exact, quests=None, nosource=None):
    quests, nosource = quests or {}, nosource or set()
    R, I, P, T = d["R"], d["I"], d["P"], d["T"]
    by_name = {r[1]: r[0] for r in R}

    # plan item -> recipe, with vendor names / prices
    plans = {}
    for plan_id, pname, _skill, sources, more in P:
        rname = re.sub(r"^(Plans|Recipe|Pattern|Formula|Schematic|Manual|Design): ", "", pname)
        spell = by_name.get(rname)
        if not spell or spell in plans:
            continue
        vendors = []
        if plan_id in exact:  # exact price/side known
            vendors = [[v[0], v[1], v[2], v[3] or 3, 0, v[4] if len(v) > 4 else 0] for v in exact[plan_id]]
        elif 5 in sources:
            sell = (I.get(str(plan_id)) or [None, 0, 0])[2]
            npcs = [(m[1], m[2]) for m in more if m[0] == 1 and m[1]] or [("vendor", 0)]
            if sell:
                vendors = [[n, sell * 4, -1, 3, 1, z] for n, z in npcs[:3]]  # approx price
        plans[spell] = (plan_id, vendors)

    out = []
    w = out.append
    w("-- Generated by tools/gen_data.py from Wowhead (WoW Forever). Do not edit by hand.")
    w("local _, ns = ...")
    w("ns.Professions = ns.Professions or {}")
    w("ns.Items = ns.Items or {}")
    w("ns.VendorSeed = ns.VendorSeed or {}")
    w("")
    w("local P = {")
    w(f'  key = {lua_str(prof["key"])}, skillLine = {skill}, spell = {prof["spell"]}, icon = {lua_str(prof["icon"])},')
    w("  specs = { " + ", ".join(f"[{k}] = {lua_str(v)}" for k, v in prof["specs"].items()) + " },")
    w("  -- rank caps; `how` = learned from a book/quest instead of a trainer")
    w("  ranks = {")
    for i, (cap, name, sk, level, how) in enumerate(prof["ranks"]):
        parts = [f"cap = {cap}", f"next = {lua_str(name)}", f"skill = {sk}", f"tier = {i + 2}"]
        if level:
            parts.append(f"level = {level}")
        if how:
            parts.append(f"how = {lua_str(how)}")
        w("    { " + ", ".join(parts) + " },")
    w("  },")
    w("  -- { name, tier (highest rank taught: 1 Apprentice, 2 Journeyman, 3 Expert, 4 Artisan), side (1 A, 2 H, 3 both), zone, uiMapId, x, y }")
    w("  -- from Wowhead's 'Taught by' lists of the rank spells, not NPC titles")
    w("  trainers = {")
    seen = trainer_tiers(skill, T)
    coords = trainer_coords()
    for name, (tier, react, zone) in sorted(seen.items(), key=lambda kv: (-kv[1][0], kv[0])):
        c = coords.get(name)
        where = f", {c[0]}, {c[1]}, {c[2]}" if c else ""
        w(f"    {{ {lua_str(name)}, {tier}, {side_mask(react)}, "
          f"{lua_str(ZONES.get(zone, 'zone ' + str(zone)))}{where} }},")
    w("  },")
    w("  recipes = {")

    used = set()
    n = 0
    for r in sorted(R, key=lambda r: (r[3] or 0, r[1])):
        if excluded(r):
            continue
        spell, name, colors, learn, creates, reagents, sources, cost, spec, env = r
        o, y, g, gray = colors
        learn = learn or o or y
        flags = "".join(sorted({SRC_FLAGS[s] for s in sources if s in SRC_FLAGS}))
        if not sources and learn <= 20:
            flags = "s"  # starter recipe, known when you learn the profession
            if not o:
                learn, o = 1, 1
        elif not sources and env == 0 and spell not in plans and (learn < 250 or "Bandage" in name):
            # original recipe, no source listed and no recipe item teaches it:
            # in the original game these are trainer recipes (cost unknown).
            # Above 250 they're raid/reputation recipes, so those stay unavailable.
            flags = "t"
        parts = [f"id = {spell}", f"name = {lua_str(name)}", f"learn = {learn}",
                 f"c = {{ {o or learn}, {y}, {g}, {gray} }}", f'src = "{flags}"']
        if cost:
            parts.append(f"cost = {cost}")
        if spec:
            parts.append(f"spec = {spec}")
        if creates:
            # Wowhead lists some Forever recipes as making 0: they make 1
            lo, hi = max(1, creates[1] or 0), max(1, creates[2] or 0)
            parts.append(f"make = {{ {creates[0]}, {lo}, {max(lo, hi)} }}")
            used.add(creates[0])
        parts.append("reag = { " + ", ".join(f"{{ {it}, {q} }}" for it, q in reagents) + " }")
        used.update(it for it, _ in reagents)
        if spell in plans:
            plan_id, vendors = plans[spell]
            if plan_id in quests:
                # actually a quest reward (metaforge), not a vendor recipe
                vendors = []
                flags = "".join(sorted(set(flags.replace("v", "")) | {"q"}))
                parts[4] = f'src = "{flags}"'
                parts.append(f"quest = {lua_str(quests[plan_id])}")
            elif plan_id in nosource and not plan_id in exact:
                vendors = []  # no gold vendor anywhere: only usable if you have it
                flags = flags.replace("v", "")
                parts[4] = f'src = "{flags}"'
            parts.append(f"plan = {plan_id}")
            if vendors:
                # { name, copper, stock, side, approx, zone }  approx = 4x sell price, not checked
                vs = ", ".join(f"{{ {lua_str(v[0])}, {v[1]}, {v[2]}, {v[3]}, {v[4]}, "
                               f"{lua_str(v[5] if isinstance(v[5], str) else (ZONES.get(v[5], '') if v[5] else ''))} }}"
                               for v in vendors)
                parts.append(f"vendors = {{ {vs} }}")
        w("    { " + ", ".join(parts) + " },")
        n += 1
    w("  },")
    w("}")
    w(f'ns.Professions[{lua_str(prof["key"])}] = P')
    w("")
    w("-- itemId = { name, wowheadAvgBuyout, vendorSellPrice }")
    w("local items = {")
    for it in sorted(used):
        v = I.get(str(it))
        if v:
            w(f"  [{it}] = {{ {lua_str(v[0] or '')}, {v[1] or 0}, {v[2] or 0} }},")
    w("}")
    w("for id, v in pairs(items) do ns.Items[id] = v end")
    w("")
    for it, known in VENDOR_REAGENTS.items():
        v = I.get(str(it))
        if it in used and v:
            price = known or max(1, v[2]) * 4
            w(f"ns.VendorSeed[{it}] = {price} -- {v[0]} (approx.)")
    fname = "Data_" + prof["key"].replace(" ", "") + ".lua"
    open(os.path.join(OUT, fname), "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print(f"{fname}: {n} recipes, {len(used)} items, {len(seen)} trainers")
    return fname


def main():
    A = json.load(open(os.path.join(HERE, "raw", "all_professions.json"), encoding="utf-8"))
    exact_bs = exact_bs_vendors()
    exact_routes = exact_route_vendors()
    mf_vendors, mf_quests, mf_none = metaforge()
    files = []
    for skill, prof in PROFESSIONS.items():
        exact = dict(mf_vendors)
        exact.update(exact_routes)
        if skill == 164:
            exact.update(exact_bs)
        files.append(generate(skill, prof, A[str(skill)], exact, mf_quests, mf_none))
    print(f"metaforge: {len(mf_vendors)} vendor recipes, {len(mf_quests)} quest rewards, {len(mf_none)} without a gold source")
    print("TOC files:\n" + "\n".join(sorted(files)))


if __name__ == "__main__":
    main()
