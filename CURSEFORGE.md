# CraftPath – Cheapest Profession Leveling for WoW Forever

**Stop following static leveling guides. CraftPath builds a leveling route from the prices on *your* realm, right now.**

Leveling guides assume every material costs the same everywhere. It doesn't. CraftPath scans the Auction House, looks at every recipe you can get, and finds the cheapest (or fastest) path from your current skill to your target. It tells you exactly what to craft, how many times, what to buy, and where to learn each recipe.

---

## Supported professions

- Blacksmithing
- Leatherworking
- Tailoring
- Enchanting
- Cooking
- First Aid

---

## Features

### A route built from live prices
- Plans the whole route from your current skill to any target (up to 300).
- Three modes: **Cheapest**, **Fastest** (fewest crafts) and **Balanced**.
- Crafts intermediates (grinding stones, bars, bolts of cloth) itself when that's cheaper than buying them.
- Optionally subtracts the vendor sell value of what you craft.
- Shows total cost, number of crafts and an estimate of total crafting time.

### Knows which recipes you have
- Reads your profession window, so it never tells you to craft something you don't know.
- If the best route needs a recipe you're missing, **learning it becomes a step on the route**: which trainer (for your faction), which vendor and zone, the Auction House, or a quest.
- Expert/Artisan ranks for Cooking and First Aid point you to the right book or quest.
- Trainers are listed by the rank they actually teach, not by their title.

### Progress tracker
A compact on-screen card that follows you while you craft:
- the current craft and its skill-up chance
- expected attempts left (average and a safe 90% estimate)
- materials you're missing (bags and bank)
- when to train the next rank, and where

### Fast Auction House scanning
- **Fast scan:** downloads the whole Auction House in one request (10–30 seconds) and prices every material for **all your professions** at once.
- The fast scan can run once every 15 minutes (a server limit). In between, a smart scan checks only what your routes use, re-plans, and repeats until the route stops changing.
- Prices use the average of the cheapest 30% of listed quantity, so one cheap single listing doesn't skew the plan.
- Uses **Auctionator** prices automatically if you have it. Whichever price is newer wins, and every price shows its source and age.

### Skill-up chances that follow the game
- Chances follow the recipe's colour: orange always, yellow likely, green unlikely, gray never.
- When you open a profession window, CraftPath compares each recipe's colour with the game and corrects its data if they differ.

### Clean, modern UI
- Dark, flat design with larger, readable text (three text sizes).
- Profession dropdown, tabs for **Plan / Materials / Shopping / Trainers**, item icons and tooltips.
- Minimap button (works with **MinimapButtonButton** and other button collectors) and the addon compartment.

---

## How to use

1. Open each of your profession windows once, so CraftPath learns your recipes.
2. Click the minimap button or type `/cpath`.
3. Pick a profession and a target skill.
4. At an auctioneer, press **Scan AH**.
5. Follow the **Craft now / Learn first** card, or the tracker (right-click the minimap button).

### Commands
| Command | What it does |
|---|---|
| `/cpath` | Open or close the planner |
| `/cpath scan` | Scan the AH (smart, or fast when available) |
| `/cpath scan full` | Scan every material |
| `/cpath tracker` | Show or hide the tracker |
| `/cpath lock` | Lock the tracker in place |
| `/cpath minimap` | Show or hide the minimap button |
| `/cpath help` | List all commands |

---

## Plays by the rules

CraftPath only **reads** prices. It never buys, bids or posts. Scans start only when you click, run only while the Auction House is open, use Blizzard's official API, and respect the server's throttle and the fast scan's cooldown.

---

## Notes

- Recipe, trainer and vendor data comes from the WoW Forever databases on Wowhead and MetaForge, and is corrected in game where possible (recipe colours, vendor prices you've seen).
- Your first scan (or existing Auctionator data) is needed before the planner can build routes. There are no guessed prices.
- Optional: **Auctionator**.

Found a wrong trainer, vendor or recipe? Please leave a comment with the profession, recipe and your faction. Data fixes are quick.
