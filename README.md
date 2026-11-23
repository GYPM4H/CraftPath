# CraftPath (WoW Forever)

Finds the cheapest — or fastest — way to level a profession from your current
skill to a target, using live Auction House prices.

**Professions:** Blacksmithing, Leatherworking, Tailoring, Enchanting, Cooking
and First Aid.

## Install

Copy the `CraftPath` folder to:

```
World of Warcraft\_forever_\Interface\AddOns\CraftPath
```

(The exact `_forever_` folder name can differ; it's the folder next to `_retail_`
that the Forever client uses.) The `.toc` targets interface `16001`. If the
addon shows as out of date, check your version with
`/dump select(4, GetBuildInfo())` and change `## Interface:` in `CraftPath.toc`.

## Use

1. Open the planner with the **minimap button** (left-click; right-click
   toggles the tracker), `/cpath`, or the minimap addon menu.
2. **First scan.** CraftPath only plans with real prices. Until a profession
   has prices, it shows a *Scan the Auction House first* screen: go to an
   auctioneer and press **Scan now**. The first scan checks every material for
   that profession, which takes a few minutes. If you use **Auctionator**,
   its prices are used right away and no first scan is needed.
3. Open each profession window once so CraftPath knows which recipes you
   already have. Opening a profession window also switches CraftPath to it;
   so does the **profession dropdown** at the top (your professions are
   listed first, with your skill). Each profession has its own target skill.
4. Scan again every day or two with **Scan AH** (see *Scanning*).
5. Visiting a vendor records the real prices of recipes and supplies (flux,
   thread, dye, spices) automatically.

The minimap button works with minimap collectors such as
MinimapButtonButton. If another addon has loaded LibDBIcon, CraftPath
registers through it; otherwise it adds a normal named minimap button.
Hide it in Options or with `/cpath minimap`.

### Learning recipes is part of the route

CraftPath knows which recipes you have (from the profession window) and
treats learning a new one as a step:

- When the next recipe isn't known, the tracker and the Now card switch to
  **Learn first**. They show how to get it and what it costs: the trainer
  (nearest by zone), the recipe vendor and their zone, the Auction House, or
  a quest. Underneath they say how many crafts follow.
- The Route tab has a **learn** row before every recipe you still need.
- The moment you learn it, CraftPath notices and switches to crafting.
- Recipes you can't get (unknown dungeon drops, unpriced vendor recipes) are
  left out. Recipes you already know cost nothing to use.
- When you open a vendor that sells a recipe, CraftPath remembers who and
  where, and shows that from then on.

### Profession notes

- **Leatherworking / Blacksmithing specializations** are detected from your
  spells; recipes for other specializations are skipped.
- **Cooking and First Aid**: Expert and Artisan come from a book and a quest,
  not a trainer. The Trainers tab names the vendor or quest giver (checked
  against Wowhead's Forever database).
- **Trainers** are listed by the highest rank they actually teach (from
  Wowhead's "Taught by" lists for each rank), not by their title: a trainer's
  title is often one rank above what they teach (e.g. Kitta Firewind
  <Artisan Enchanter> teaches Expert; Artisan Enchanting is only Annora in
  Uldaman, Artisan Blacksmithing only Brikk Keencraft in Booty Bay).
- **Waypoints:** places to learn (trainers) are listed one per line, one per
  city (your current zone first, then Stormwind, Ironforge, Darnassus). Click
  the yellow dot next to a trainer to mark them on your map and minimap. Uses
  TomTom if installed, otherwise the game's own map waypoint; where the game
  can't place one (inside a dungeon), it prints the `/way` coordinates.
  Coordinates come from Wowhead and MetaForge.
- **Enchanting** uses dusts and essences priced from the AH; enchant results
  have no vendor value.
- Cooldown crafts (Mooncloth) are left out of routes.
- Recipe prices marked **~** are estimated (4× the recipe's vendor sell
  price) until you visit the vendor.

### Tracker

A small panel to keep on screen while you craft (shown at login and when you
open your profession window; `/cpath tracker` toggles it, `/cpath lock` locks
it, right-click opens the planner):

- skill progress toward your target
- the current craft, colored by difficulty, and about how many crafts are left
- a have/need checklist of materials, with bags and bank counted
- when you need to train the next rank
- a **Craft** button (opens the profession window first if needed)

### Main window

- **Header:** profession dropdown, Options (gear) and close.
- **Controls:** target skill and planning mode (Balanced / Cheapest / Fastest).
- **Now card:** the recipe to craft now in its difficulty color, your skill,
  about how many crafts are left, a have/need checklist of materials, rank
  warnings and a **Craft** button. Hover it for the skill-up chance and the
  safe (9 in 10 players) number of crafts.
- **Footer:** route total, crafts and crafting time (hover for the breakdown),
  scan status, **Full scan** and **Scan AH**.
- **Options (gear):** sell crafts to vendor, use Auctionator prices, count
  quest recipes, show/lock the tracker, show the minimap button, and text
  size (Normal / Large / Larger).

Below the Now card are three tabs:

- **Route**: every step with skill range, recipe, crafts and cost. Hover a
  recipe for its crafting time and "Recipe" in green (you know it, plus its
  materials) or red (where to get it).
- **Shopping**: this step first (have/need, buy or craft), then the rest of
  the route, with unit price and its source.
- **Trainers**: whether you can learn the next rank yet, and your faction's
  trainers, each listed once (one per zone, nearest first) with the highest
  rank they teach and a waypoint dot.

### Modes

| Mode | Picks |
|---|---|
| Balanced (default) | gold + a value per craft (`/cpath value 0.2` = 20s per craft) |
| Cheapest | least gold, even if it takes many crafts |
| Fastest | fewest crafts, ignores cost |

`/cpath switch <gold>` adds a penalty per recipe change, for routes with fewer
different steps.

### Scanning

Every scan covers **all your professions** at once, not just the one shown.

- **Fast scan (automatic when available):** both buttons first try the
  whole-AH download (`C_AuctionHouse.ReplicateItems`, the same thing
  Auctionator's full scan uses). One request fetches every auction (10–30
  seconds), and CraftPath prices every material of all your professions from
  it. The server allows this once every **15 minutes**; the status line and
  tooltips show when it's ready again. If the server doesn't answer within a
  minute (for example because another addon just used it), CraftPath scans
  item by item instead.
- **Scan AH**, during the cooldown (usually 50–150 searches): scans what the
  best routes use, then re-plans with the new prices. If the cheaper route now
  needs items it hasn't looked at, it scans those too, and repeats until the
  route stops changing (up to 6 rounds).
- **Full scan**, during the cooldown (several hundred searches, a few
  minutes): scans every reagent of every recipe you can get.
- Items with **nothing listed** are left out of routes until a newer scan (or
  a newer Auctionator scan) finds them. They don't fall back to an estimate.

Scans follow Blizzard's rules for addons: they start from your click, run only
while the Auction House is open, use the official API, and respect the
server's throttle and the fast scan's 15-minute cooldown. CraftPath only reads
prices. It never buys or posts.

### Price sources

- **Auction House: the newest price wins.** CraftPath compares its own scan
  with Auctionator's (if installed; can be turned off in Options). Auctionator
  only dates prices by day, so on the same day CraftPath's scan wins: it
  averages the cheapest 30% of listed quantity instead of using the single
  lowest listing. A CraftPath scan that found an item *not listed* holds
  until a newer Auctionator scan sees it.
- **Vendor prices:** recorded when you open a vendor; flux, thread and dye are
  seeded with an approximation until then. Used when cheaper than the AH.
- The Shopping tab shows each price and whether it's from the AH or a vendor.
  Hover an item to see where the price comes from and how old it is, e.g.
  "Auctionator, today" or "CraftPath scan, 3 h ago".

There are no guessed prices: an item without a price is left out of routes
until a scan finds it. A profession counts as unscanned until at least a
quarter of its materials have prices, or if no priced recipe works at your
current skill.

### Commands

```
/cpath                 open/close
/cpath scan            scan the AH, re-planning until the route is stable
/cpath scan full       scan every reagent for this profession
/cpath tracker         show/hide the tracker
/cpath lock            lock/unlock the tracker position
/cpath minimap         show/hide the minimap button
/cpath prof tailoring  switch profession (prefix is enough: /cpath prof lea)
/cpath target 225      target skill for the current profession
/cpath mode cheap|fast|balanced
/cpath value <gold>    balanced mode: what one craft is worth to you
/cpath switch <gold>   penalty per recipe change
/cpath quest           toggle quest-reward plans
/cpath resetprices     forget AH prices for this realm
```

## How it works

Skill-up chance: orange 100%, gray 0%, yellow falls from 100% to 50% where
green starts, green from 50% to 0% at gray. For most recipes (green halfway
between yellow and gray) that's the community formula
`(gray - skill) / (gray - yellow)`; for the rest it keeps a green recipe from
looking like a likely skill-up.

Recipe colours start from Wowhead's data. Every time you open a profession
window, CraftPath compares each known recipe's colour in the game with its
data and moves the thresholds to match (remembered for all characters), so
the chances follow the real game even where Forever changed a recipe.

A dynamic program over every skill
point picks the recipe with the lowest expected cost per point and charges
each recipe's learning cost once. Intermediates such as grinding stones are
crafted when that's cheaper than buying them.

Recipe data (skill colors, reagents, trainer costs, plan vendors) comes from
Wowhead's WoW Forever database. `tools/gen_data.py` regenerates
`Data_Blacksmithing.lua` from a raw export.

## Limits

- Specializations (Armorsmith, Weaponsmith…) are detected from your spells.
- Vendor plans without a known vendor in Wowhead's data are only used once
  you've visited the vendor or seen the plan on the AH.
- Untested in the live client yet; please report Lua errors (BugSack helps).
