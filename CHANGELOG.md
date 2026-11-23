# CraftPath

## v0.6.0

Known issue: a trainer listed under "Learn it from" may not actually teach that recipe in Forever (e.g. Journeyman trainers don't teach Green Iron Bracers). A fix using each trainer's real recipe list is coming in the next update.

### Cleaner main window and tracker
- **The current craft is the focus:** the main card shows what to craft, about how many crafts are left, and a **have/need checklist** of materials (e.g. Iron Bar 0/64), with a **Craft** button.
- **Each number shown once:** no more stat tiles. Skill appears once, crafts left are counted from your current skill everywhere, and the skill-up chance and safe estimate are in the card's tooltip.
- **Materials and Shopping are one tab:** Shopping lists this step first, then the rest of the route.
- **Route table:** just the skill range, recipe, crafts and cost. Hover a recipe for a small card: "Recipe" in green with its materials if you know it, or in red with where to get it if you don't.
- **Column headers** on the Route (Skill | Recipe | Crafts | Cost), Shopping and Trainers tables. Training a new rank is a row in the route at its skill range (e.g. 50 - 75 Train Journeyman), not a banner.
- **Shopping rows:** price each and AH or Vendor. Hover for the price's source and age.
- **Trainers tab:** the next rank and the trainers, each listed once (one per zone) with the highest rank they teach, instead of the same trainers repeated under every recipe.
- Recipes you still have to learn don't list their materials yet (main card, tracker and route hover).
- **Recipe vendors get waypoint dots too**, and are listed nearest first (your zone, then your faction's capitals), like trainers.
- Learning steps no longer say how many crafts follow: they show only what to learn and where.
- **All hovers use CraftPath's own style** (buttons, totals, route rows, waypoint dots, minimap button) instead of the game's tooltip.
- **Footer:** one total; hover it for materials + recipes − vendor sales.
- **Colour:** recipe names keep their difficulty colour; everything else is neutral, with amber only on the main buttons.
- The tracker matches: one **Craft** button, the same checklist, no step bar.
- The tracker toggle moved to Options (and the minimap button's right-click).

## v0.5.1

### Neutral Auction House
- **CraftPath no longer scans at a neutral (goblin) Auction House** in Booty Bay, Gadgetzan or Everlook. Their listings are separate from your faction's, and one scan there used to overwrite your faction's prices. The scan buttons are disabled there, and the status line explains why.
- Already scanned at a neutral AH? Type `/cpath resetprices` and scan again at your faction's Auction House.
- If you use Auctionator, avoid scanning the neutral AH with it too: Auctionator doesn't record which Auction House a price came from, so CraftPath can't tell those prices apart.

## v0.5.0

Changes since 0.4.0.

### Trainers and waypoints
- **Click to set a waypoint:** every trainer now has a yellow dot. Click it to mark the trainer on your map and minimap. Uses TomTom if you have it, otherwise the game's own map waypoint. Inside dungeons it prints the `/way` coordinates instead.
- **Trainers as a list:** places to learn a recipe are shown one per line instead of in one long row, on the main card, the tracker, the Route tab and the Trainers tab.
- **One trainer per city:** instead of three trainers in the same city, you get your current zone first, then Stormwind, Ironforge and Darnassus (Orgrimmar, Undercity and Thunder Bluff for Horde).
- **Positions for 142 of 143 trainers**, including Forever's new trainers in Alterac Mountains, Riverglades, Zephras Isle, Shen'dralas and Mount Hyjal.

### Crafting from the tracker
- New **Craft** and **Craft N** buttons on the tracker. Craft N makes as many as the current step still needs, limited by the materials in your bags.
- If the profession window is closed, the button opens it first (the game only lets addons craft while it's open).

### More accurate costs
- **Sell-back uses the game's own vendor prices** instead of database values.
- **30 recipes no longer count as selling for nothing:** Forever's new Enchanting wands, staves, orbs and oils, and one Cooking recipe.
- **Items made earlier on the route are kept, not sold and bought again:** grinding stones, cured hides, leather and bolts of cloth. The Shopping tab lists them under "Made earlier on this route".
- Routes that earn more from vendor sales than they cost now show **Profit** instead of a negative total.

### Look
- Text on the amber buttons is sharp again (no smeared shadow).
