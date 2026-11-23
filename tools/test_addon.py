"""Load the whole CraftPath addon against a mocked WoW (modern client) API and
simulate a play session: first-scan gate, Auctionator prices, AH scans,
vendor visit, profession window, crafting, tracker, dropdown, options,
minimap button, every profession.

Usage (needs `pip install lupa`):  python test_addon.py
"""
import os
import re

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..")

MOCK = r"""
bit = { band = function(a, b)
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end }
local clock = 1000
function GetTime() return clock end
function _advance(dt) clock = clock + dt end
time = os.time
_frames = {}
local function newRegion()
  local o = { shown = true, text = "", scripts = {}, events = {} }
  local mt = {}
  mt.__index = function(t, k)
    local fn = function(self, ...) return nil end
    if k == "CreateFontString" or k == "CreateTexture" then fn = function() return newRegion() end
    elseif k == "SetScript" then fn = function(self, n, f) self.scripts[n] = f end
    elseif k == "GetScript" then fn = function(self, n) return self.scripts[n] end
    elseif k == "HookScript" then fn = function(self, n, f)
      local old = self.scripts[n]
      self.scripts[n] = old and function(...) old(...); f(...) end or f
    end
    elseif k == "RegisterEvent" or k == "RegisterUnitEvent" then fn = function(self, e) self.events[e] = true end
    elseif k == "UnregisterAllEvents" then fn = function(self) self.events = {} end
    elseif k == "UnregisterEvent" then fn = function(self, e) self.events[e] = nil end
    elseif k == "Show" then fn = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    elseif k == "Hide" then fn = function(self) self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
    elseif k == "SetShown" then fn = function(self, v) if v then self:Show() else self:Hide() end end
    elseif k == "IsShown" then fn = function(self) return self.shown end
    elseif k == "SetText" then fn = function(self, t) self.text = tostring(t) end
    elseif k == "GetText" then fn = function(self) return self.text end
    elseif k == "Enable" then fn = function(self) self.enabled = true end
    elseif k == "Disable" then fn = function(self) self.enabled = false end
    elseif k == "SetEnabled" then fn = function(self, v) self.enabled = v and true or false end
    elseif k == "IsEnabled" then fn = function(self) return self.enabled ~= false end
    elseif k == "GetStringHeight" then fn = function() return 14 end
    elseif k == "GetStringWidth" then fn = function() return 60 end
    elseif k == "GetFrameLevel" then fn = function() return 1 end
    elseif k == "GetWidth" or k == "GetHeight" then fn = function() return 100 end
    elseif k == "GetCenter" then fn = function() return 0, 0 end
    elseif k == "GetVerticalScroll" then fn = function() return 0 end
    elseif k == "HasFocus" or k == "GetChecked" then fn = function() return false end
    end
    rawset(t, k, fn)
    return fn
  end
  return setmetatable(o, mt)
end
_newRegion = newRegion
function CreateFrame(kind, name, parent, template)
  local f = newRegion()
  table.insert(_frames, f)
  if name then _G[name] = f end
  return f
end
function CreateFont(name) local f = newRegion(); _G[name] = f; return f end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UIParent = newRegion()
Minimap = newRegion()
GameTooltip = newRegion()
function GameTooltip_Hide() end
function GetCursorPosition() return 10, 10 end
UISpecialFrames = {}
SlashCmdList = {}
_chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) table.insert(_chat, m) end }
function GetRealmName() return "TestRealm" end
function UnitFactionGroup() return "Alliance" end
C_Spell = { GetSpellName = function(id) if id == 2018 then return "Blacksmithing" end end }
function IsPlayerSpell(id) return false end
_skill = 1
-- prof1 Blacksmithing, prof2 Tailoring, (archaeology, fishing nil), cooking
_tail, _tailMax, _cook, _cookMax = 1, 75, 1, 75
function GetProfessions() return 1, 2, nil, nil, 3, nil end
function GetProfessionInfo(i)
  if i == 1 then return "Blacksmithing", 0, _skill, _maxSkill, 0, 0, 164 end
  if i == 2 then return "Tailoring", 0, _tail, _tailMax, 0, 0, 197 end
  if i == 3 then return "Cooking", 0, _cook, _cookMax, 0, 0, 185 end
end
_open = { "Blacksmithing", 164 }
_bags, _bank = {}, {}
C_Item = { GetItemNameByID = function(id) return nil end, RequestLoadItemDataByID = function() end,
  GetItemIconByID = function(id) return 134400 end,
  GetItemCount = function(id, bank) return (_bags[id] or 0) + (bank and (_bank[id] or 0) or 0) end }
C_Timer = { After = function(_, fn) fn() end }
_level = 12
function UnitLevel() return _level end
_maxSkill = 75

-- Auctionator mock (switched on/off by the test)
function _auctionatorOn()
  Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id)
    local it = _ns.Items[id]; if it and it[2] > 0 then return it[2] end end } } }
end

-- modern auction house mock
_ah = {}           -- itemId -> list of {unitPrice, quantity}
_ahSent = 0
_ahDefault = true  -- anything not in _ah is listed at Wowhead's average price
_ahQueried = {}
function _ahList(id)
  if _ah[id] then return _ah[id] end
  local it = _ahDefault and _ns.Items[id]
  if it and it[2] > 0 then return { { it[2], 200 } } end
  return {}
end
C_AuctionHouse = {
  IsThrottledMessageSystemReady = function() return true end,
  MakeItemKey = function(id) return { itemID = id } end,
  SendSearchQuery = function(key) _ahSent = _ahSent + 1; _lastQuery = key.itemID; _ahQueried[key.itemID] = true end,
  GetNumCommoditySearchResults = function(id) return #(_ahList(id)) end,
  GetCommoditySearchResultInfo = function(id, i) local l = _ahList(id)[i]; return { unitPrice = l[1], quantity = l[2] } end,
  GetNumItemSearchResults = function() return 0 end,
}
Enum = { AuctionHouseSortOrder = { Price = 0 } }

-- merchant mock
_merchant = {}
function GetMerchantNumItems() return #_merchant end
function GetMerchantItemLink(i) return "|Hitem:" .. _merchant[i][1] .. "::|h" end
C_MerchantFrame = { GetItemInfo = function(i) return { price = _merchant[i][2], stackCount = 1, numAvailable = -1 } end }

-- trade skill mock
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionName = _open[1], professionID = _open[2], skillLevel = _skill, maxSkillLevel = 75 } end,
  GetAllRecipeIDs = function() return { 2660, 2663, 3115 } end,
  GetRecipeInfo = function(id) return { learned = true } end,
  OpenRecipe = function(id) _opened = id end,
}

function _fire(event, ...)
  for _, f in ipairs(_frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
function _tick(n)
  for _ = 1, n or 1 do
    _advance(0.1)
    for _, f in ipairs(_frames) do
      if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.1) end
    end
  end
end
function _click(widget, button) widget.scripts.OnClick(widget, button or "LeftButton") end
"""

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
lua.execute("_ns = {}")
# record every global the addon's own files create (Ketho-style audit)
lua.execute("""
  _addonGlobals = {}
  setmetatable(_G, { __newindex = function(t, k, v)
    local info = debug.getinfo(2, "S")
    local src = info and info.source or ""
    if src:match("^@[%w_]+%.lua$") then _addonGlobals[k] = src:sub(2) end
    rawset(t, k, v)
  end })
""")
toc = open(os.path.join(ADDON, "CraftPath.toc"), encoding="utf-8").read()
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
loadstring = lua.eval("function(s, n) local c, e = loadstring(s, n); return c or false, e or \"\" end")
for fn in files:
    src = open(os.path.join(ADDON, fn), encoding="utf-8").read()
    chunk, err = loadstring(src, "@" + fn)
    if not chunk:
        raise SystemExit(f"SYNTAX {fn}: {err}")
    lua.execute("local c = ...; c('CraftPath', _ns)", chunk)
print("loaded:", ", ".join(files))

strip = lambda s: re.sub(r"\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t", "", s or "")
ui_text = lambda: strip(lua.eval("_ns.UI:ContentText()"))
card_text = lambda: strip(lua.eval("_ns.UI:CardText()"))
footer = lambda: strip(lua.eval("_ns.UI:FooterText()"))
tracker_text = lambda: strip(lua.eval("_ns.Tracker:Text()"))
chat = lambda: [strip(m) for m in lua.eval("_chat").values()]


def show(title, text, n=14):
    print(f"\n--- {title} ---")
    print("\n".join(text.splitlines()[:n]))


def run_scan(cmd):
    lua.execute("_ahSent = 0; _ahQueried = {}; _lastQuery = nil")
    lua.execute(f"SlashCmdList.CRAFTPATH('{cmd}')")
    for _ in range(20000):
        if not lua.eval("_ns.Prices.scanning"):
            break
        lua.execute("_tick(1)")
        if lua.eval("_lastQuery") is not None and lua.eval("_ns.Prices.scanning"):
            lua.execute("_fire('COMMODITY_SEARCH_RESULTS_UPDATED', _lastQuery); _lastQuery = nil")
    return lua.eval("_ahSent"), strip(lua.eval("_ns.status") or "")


# ---- login, first-scan gate --------------------------------------------------
lua.execute("_fire('ADDON_LOADED', 'CraftPath'); _fire('PLAYER_LOGIN')")
assert lua.eval("CraftPathMinimapButton ~= nil"), "minimap button created"
lua.execute("SlashCmdList.CRAFTPATH('')")  # open window
assert lua.eval("CraftPathFrame:IsShown()")
assert lua.eval("_ns.needsScan") is True, "no prices yet -> gate"
show("GATE (no prices)", ui_text())
assert "Scan the Auction House first" in ui_text() and "Open the Auction House" in ui_text()
assert "Scan the Auction House" in tracker_text()
show("TRACKER (no prices)", tracker_text())

# ---- Auctionator prices unlock the planner without a scan ----------------------
lua.execute("_auctionatorOn(); _ns.Refresh()")
assert not lua.eval("_ns.needsScan") and lua.eval("_ns.result.ok"), "Auctionator prices are enough"
assert "Auctionator" in strip(lua.eval("CraftPathFrame.status:GetText()"))
show("STATUS with Auctionator only", strip(lua.eval("CraftPathFrame.status:GetText()")))
lua.execute("Auctionator = nil; _ns.Refresh()")
assert lua.eval("_ns.needsScan") is True

# ---- first scan is a full scan --------------------------------------------------
lua.execute("""
_ah[2835] = { {5, 20}, {6, 100}, {50, 1} }   -- Rough Stone: cheap
_ah[2840] = { {40, 200} }                    -- Copper Bar
_ah[2841] = { {300, 100} }                   -- Bronze Bar
_fire('AUCTION_HOUSE_SHOW'); CraftPathFrame:Render()
""")
assert "Scan now" in ui_text(), "button enabled at the AH"
full_n = len(list(lua.eval("_ns.FullScanList()").keys()))
sent, status = run_scan("scan")
print("\nfirst scan:", sent, "searches |", status, "| full list", full_n)
assert sent >= full_n, "first scan ran as a full scan"
assert lua.eval("_ns.db.realms['TestRealm-Alliance'].ah[2835].p") == 5  # cheapest 30% of 121 units
assert not lua.eval("_ns.needsScan")

# vendor visit sells Strong Flux for 15s
lua.execute("_merchant = { {3466, 1500} }; _fire('MERCHANT_SHOW')")
assert lua.eval("_ns.db.vendor[3466].p") == 1500

# profession window: known recipes + skill
lua.execute("_skill = 40; _fire('TRADE_SKILL_SHOW')")
assert lua.eval("_ns.char.known.Blacksmithing[2660]")

lua.execute("_ns.settings.tab = 'plan'; CraftPathFrame:Render()")
show("ROUTE (skill 40)", ui_text())
print("FOOTER:", footer())
show("NOW CARD", card_text())
lua.execute("_ns.settings.tab = 'shop'; CraftPathFrame:Render()")
show("SHOPPING", ui_text(), 8)

for cmd in ["mode cheap", "mode fast", "target 150", "value 1", "switch 0.5", "quest", "help", "resetprices", "minimap", "minimap"]:
    lua.execute(f"SlashCmdList.CRAFTPATH('{cmd}')")
lua.execute("CraftPath_OnCompartmentClick(); CraftPath_OnCompartmentClick()")
lua.execute("_fire('AUCTION_HOUSE_CLOSED')")

# resetprices emptied our scan -> back to the gate; rescan
assert lua.eval("_ns.needsScan") is True
lua.execute("_ns.SetTarget(300); _fire('AUCTION_HOUSE_SHOW')")
run_scan("scan")
lua.execute("_fire('AUCTION_HOUSE_CLOSED')")

# ---- tracker + progress ---------------------------------------------------------
lua.execute("_ns.SetTarget(300); _ns.settings.mode = 'balanced'; _ns.settings.switchCost = 0; _ns.settings.allowQuest = false; _ns.Refresh()")
assert lua.eval("CraftPathTracker ~= nil and CraftPathTracker:IsShown()"), "tracker shown at login"
show("TRACKER (skill 40, recipe not learned yet)", tracker_text())

# ---- learn-first: Rough Grinding Stone isn't known -> learning it is the step
p = lua.eval("_ns.Progress()")
assert p.recipe.name == "Rough Grinding Stone", p.recipe.name
assert p.learnFirst is not None and p.learnFirst.kind == "trainer"
assert "Learn: Rough Grinding Stone" in tracker_text() and "crafts" not in tracker_text(), "learning step: no craft count"
assert "Ironforge" in tracker_text() or "Stormwind" in tracker_text(), "names a trainer"
lua.execute("_ns.UI:Toggle()") if not lua.eval("CraftPathFrame:IsShown()") else None
lua.execute("_ns.settings.tab = 'plan'; CraftPathFrame:Render()")
show("ROUTE with learn steps", ui_text(), 8)
route_line = lambda name: next(l for l in ui_text().splitlines() if name in l)
def route_hover(name):
    lua.execute(f"""for _, r in ipairs(CraftPathFrame.rows.pool) do
      if r:IsShown() and r.title:GetText():find("{name}", 1, true) then r:GetScript("OnEnter")(r); break end end""")
    return strip(lua.eval("_ns.T.HoverText()"))
line = route_line("Rough Grinding Stone")
assert "learn first" not in line and "Rough Stone" not in line, "route row: just the recipe"
h = route_hover("Rough Grinding Stone")
show("ROUTE HOVER", h, 12)
assert "Materials" not in h and "Recipe" in h and "Stormwind" in h, "not learned: where to get it, no materials"
assert "Learn it first" not in h and "trainer" not in h, "just 'Recipe' and the places"
lua.execute("_ns.T.HideHover()")
assert "LEARN FIRST" in card_text()
show("NOW CARD (learn first)", card_text())
# starter recipes the profession window says you DON'T have aren't assumed known
assert not lua.eval("_ns.Known()[12260]"), "Rough Copper Vest not in the known list"
# learning it (trainer) -> instantly switches to crafting
lua.execute("_fire('NEW_RECIPE_LEARNED', 3320)")
assert any("Learned Rough Grinding Stone" in m for m in chat())
p = lua.eval("_ns.Progress()")
assert p.learnFirst is None and "Learn:" not in tracker_text()
lua.execute("_ns.settings.tab = 'plan'; CraftPathFrame:Render()")
h = route_hover("Rough Grinding Stone")
assert "Recipe" in h and "Stormwind" not in h and "Rough Stone" in h, "known recipe: green, materials, no places"
lua.execute("_ns.T.HideHover()")
show("TRACKER (after learning)", tracker_text())

p = lua.eval("_ns.Progress()")
step_recipe, step_to = p.recipe.id, p.stepTo
assert 0 < p.chance <= 1
first = p.mats[1]
lua.execute(f"_bags[{first.id}] = {first.need}; _bank[{first.id}] = 3; _fire('BAG_UPDATE_DELAYED')")
p = lua.eval("_ns.Progress()")
assert p.mats[1].missing == 0 and p.mats[1].bank == 3, "bag counting"
for _ in range(3):
    lua.execute(f"_fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', {step_recipe})")
assert lua.eval("_ns.Progress()").crafted == 3, "craft counting"
assert "crafts left" in tracker_text() and "crafts left" in card_text()
lua.execute(f"_skill = {step_to}; _fire('CHAT_MSG_SKILL')")
assert any("Next: craft" in m or "Next: learn" in m for m in chat()), "step change announced"
print("announce:", [m for m in chat() if "Next:" in m][-1])

lua.execute("_skill = 75; _maxSkill = 75; _level = 12; _fire('SKILL_LINES_CHANGED')")
show("TRACKER (capped at 75)", tracker_text())
assert "Capped at 75" in tracker_text()

if not lua.eval("CraftPathFrame:IsShown()"):
    lua.execute("_ns.UI:Toggle()")
for tab in ["plan", "mats", "shop", "train"]:
    lua.execute(f"_ns.settings.tab = '{tab}'; CraftPathFrame:Render()")
    show(f"MAIN: {tab}", ui_text(), 10)
show("NOW CARD (capped)", card_text())
assert "Capped at 75" in card_text()
assert "learn Journeyman there too" in card_text(), "trainers named once"

lua.execute("UnitFactionGroup = function() return 'Horde' end; _ns.settings.tab = 'train'; CraftPathFrame:Render()")
assert "Orgrimmar" in ui_text() or "Undercity" in ui_text() or "Thunder Bluff" in ui_text()
assert "Stormwind" not in ui_text()
lua.execute("UnitFactionGroup = function() return 'Alliance' end")
lua.execute("SlashCmdList.CRAFTPATH('lock'); SlashCmdList.CRAFTPATH('tracker'); SlashCmdList.CRAFTPATH('tracker')")

# ---- profession dropdown -----------------------------------------------------------
lua.execute("_click(CraftPathFrame.prof)")
assert lua.eval("CraftPathFrame.prof.list:IsShown()")
labels = [strip(lua.eval(f"CraftPathFrame.prof.list.rows[{i}].text:GetText()")) for i in range(1, 7)]
print("\ndropdown:", labels)
assert labels[:3] == ["Blacksmithing", "Cooking", "Tailoring"] and "Skinning" not in labels
lua.execute("_click(CraftPathFrame.prof.list.rows[3])")  # Tailoring
assert lua.eval("_ns.Prof().key") == "Tailoring" and not lua.eval("CraftPathFrame.prof.list:IsShown()")
assert "Tailoring" in strip(lua.eval("CraftPathFrame.prof.label:GetText()"))
# the first scan covered every profession you have, Tailoring included
assert not lua.eval("_ns.needsScan") and lua.eval("_ns.result and _ns.result.ok"), "Tailoring priced by the shared scan"

# ---- options popover --------------------------------------------------------------
lua.execute("_click(CraftPathFrame.gear)")
assert lua.eval("CraftPathFrame.options:IsShown()")
lua.execute("_click(CraftPathFrame.options.toggles[1])")  # sell crafts to vendor -> off
assert lua.eval("_ns.settings.sellBack") is False
lua.execute("_click(CraftPathFrame.options.toggles[1])")
lua.execute("_click(CraftPathFrame.options.size.buttons[2])")  # Large text
assert lua.eval("_ns.settings.fontScale") == 1.15
lua.execute("_click(CraftPathFrame.options.toggles[6])")  # hide minimap button
assert lua.eval("_ns.db.minimap.hide") is True and not lua.eval("CraftPathMinimapButton:IsShown()")
lua.execute("_click(CraftPathFrame.options.toggles[6])")
assert lua.eval("CraftPathMinimapButton:IsShown()")
lua.execute("_click(CraftPathFrame.gear)")

# ---- minimap button -----------------------------------------------------------------
lua.execute("CraftPathFrame:Hide(); _click(CraftPathMinimapButton, 'LeftButton')")
assert lua.eval("CraftPathFrame:IsShown()"), "left-click opens the planner"
was = lua.eval("CraftPathTracker:IsShown()")
lua.execute("_click(CraftPathMinimapButton, 'RightButton')")
assert lua.eval("CraftPathTracker:IsShown()") != was, "right-click toggles the tracker"
# with LibDBIcon loaded by another addon, CraftPath registers through it instead
lua.execute("""
_registered = nil
LibStub = { GetLibrary = function(_, name)
  if name == 'LibDataBroker-1.1' then return { NewDataObject = function(_, n, o) return o end } end
  if name == 'LibDBIcon-1.0' then return { Register = function(_, n, o, db) _registered = n end } end
end }
_ns.Minimap:Init()
LibStub = nil
""")
assert lua.eval("_registered") == "CraftPath", "LibDBIcon registration"

# ---- other professions (prices from Auctionator) -----------------------------------
lua.execute("_auctionatorOn(); _ns.Tracker:Show()")
lua.execute("_open = { 'Cooking', 185 }; _cook = 130; _cookMax = 150; _fire('TRADE_SKILL_SHOW')")
assert lua.eval("_ns.Prof().key") == "Cooking"
lua.execute("_ns.settings.tab = 'plan'; CraftPathFrame:Render()")
show("COOKING route", ui_text(), 8)
lua.execute("_cook = 150; _fire('SKILL_LINES_CHANGED'); _ns.settings.tab = 'train'; CraftPathFrame:Render()")
show("COOKING trainers (capped at 150)", ui_text(), 6)
assert "Not taught by trainers" in ui_text() and "Expert Cookbook" in ui_text()
assert "Capped at 150" in tracker_text()
lua.execute("SlashCmdList.CRAFTPATH('target 225')")
assert lua.eval("_ns.Target('Cooking')") == 225 and lua.eval("_ns.Target('Blacksmithing')") == 300

for key in ["First Aid", "Tailoring", "Enchanting", "Leatherworking"]:
    lua.execute(f"_ns.settings.profession = '{key}'; _ns.char.skill['{key}'] = {{ rank = 1, max = 300 }}")
    lua.execute("_ns.Compute()")
    res = lua.eval("_ns.result")
    assert res is not None and res.ok, key
    print(f"{key:15s} route ok: {len(list(res.steps.values()))} steps, ~{res.totals.crafts} crafts")
    lua.execute("CraftPathFrame:Render(); _ns.Tracker:Render()")
lua.execute("Auctionator = nil")

# ---- scan modes --------------------------------------------------------------------
def route_items():
    lua.execute("_ns.Compute()")
    ids = set()
    for st in lua.eval("_ns.result").steps.values():
        for rg in st.recipe.reag.values():
            ids.add(rg[1])
    return ids


def points_using(items):
    n = 0
    for st in lua.eval("_ns.result").steps.values():
        if any(rg[1] in items for rg in st.recipe.reag.values()):
            n += st.to - st["from"]
    return n


# Blacksmithing from skill 1: scan at normal prices, then Copper Bar and Rough
# Stone jump to 50g each and a smart scan re-plans around them
lua.execute("""
_ns.settings.profession = 'Blacksmithing'; _skill = 1; _maxSkill = 300; _ns.SetTarget(300)
_ns.Prices:Realm().ah = {}
_ah = {}; _ahDefault = true
_fire('AUCTION_HOUSE_SHOW')
""")
run_scan("scan full")
before = route_items()
pts_before = points_using({2840, 2835})
lua.execute("_ah[2840] = { { 500000, 500 } }; _ah[2835] = { { 500000, 500 } }; _ns.Prices:Realm().ah[2840] = nil; _ns.Prices:Realm().ah[2835] = nil")
sent, status = run_scan("scan")
after = route_items()
pts_after = points_using({2840, 2835})
print("\nsmart scan:", sent, "searches |", status)
print(f"skill points made with copper/rough stone: {pts_before} at normal prices -> {pts_after} at 50g")
assert pts_after < pts_before, "re-planned around the expensive items"
assert all(lua.eval(f"_ns.Prices:Realm().ah[{i}] ~= nil") for i in after if not lua.eval(f"_ns.VendorSeed[{i}] ~= nil")), \
    "every AH item on the final route has a scanned price"

# "none listed" is remembered and never replaced by a guess
lua.execute("_ah[2841] = {}; _ns.Prices:Realm().ah = {}")
run_scan("scan full")
assert lua.eval("_ns.Prices:Realm().ah[2841].none == true")
assert lua.eval("_ns.Prices:AuctionPrice(2841) == nil")

# AH closing mid-scan stops cleanly
lua.execute("_ns.Prices:Realm().ah = {}; SlashCmdList.CRAFTPATH('scan full'); _tick(3); _fire('AUCTION_HOUSE_CLOSED'); _tick(1)")
assert not lua.eval("_ns.Prices.scanning")
print("stop on close:", strip(lua.eval("_ns.status")))

# ---- newest price wins: CraftPath scan vs Auctionator ------------------------------
lua.execute("""
  _aucAge = {}
  Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(_, id) return 777 end,
    GetAuctionAgeByItemID = function(_, id) return _aucAge[id] end } } }
  local ah = _ns.Prices:Realm().ah
  local now = time()
  ah[2840] = { p = 100, t = now - 3600, n = 50 }          -- ours 1 h old
  ah[2835] = { p = 100, t = now - 40 * 3600, n = 50 }     -- ours 40 h old
  ah[2836] = { p = 100, t = now - 3 * 86400, n = 50 }     -- ours 3 days old
  ah[2841] = { none = true, t = now - 2 * 86400 }         -- none listed, 2 days ago
  _aucAge[2840] = 0; _aucAge[2835] = 0; _aucAge[2836] = 5; _aucAge[2841] = 0
""")
def src(i):
    return lua.eval(f"(select(2, _ns.Prices:AuctionPrice({i})))")
assert src(2840) == "ah", "same day: CraftPath scan wins"
assert src(2835) == "auctionator", "Auctionator today beats our scan from yesterday"
assert src(2836) == "ah", "our 3-day-old scan beats Auctionator's 5-day-old price"
assert src(2841) == "auctionator", "Auctionator saw it listed after our 'none listed' scan"
lua.execute("_aucAge[2841] = 3")
assert lua.eval("_ns.Prices:AuctionPrice(2841)") is None, "older Auctionator doesn't override a newer 'none listed'"
for i in (2840, 2835, 2836):
    print("source", i, "->", strip(lua.eval(f"_ns.Prices:SourceText({i}, 'ah')")))
assert "Auctionator, today" in lua.eval("_ns.Prices:SourceText(2835, 'ah')")
assert "CraftPath scan, 1 h ago" in lua.eval("_ns.Prices:SourceText(2840, 'ah')")
# no age API (old Auctionator): fall back to the 48 h rule
lua.execute("Auctionator.API.v1.GetAuctionAgeByItemID = nil")
assert src(2835) == "ah" and src(2836) == "auctionator"
lua.execute("Auctionator = nil")

# ---- fast scan: whole AH in one request (ReplicateItems), all professions --------
lua.execute("""
  _rep = nil
  _repCalls = 0
  C_AuctionHouse.ReplicateItems = function()
    _repCalls = _repCalls + 1
    _rep = {}
    -- 5000 unrelated auctions, then the ones we care about
    for i = 1, 5000 do table.insert(_rep, { 99999, 5, 500 }) end
    table.insert(_rep, { 2840, 20, 20 * 35 })   -- Copper Bar 35c
    table.insert(_rep, { 2840, 100, 100 * 38 })
    table.insert(_rep, { 2589, 40, 40 * 12 })   -- Linen Cloth (Tailoring) 12c
    table.insert(_rep, { 2589, 60, 60 * 15 })
    table.insert(_rep, { nil, 1, 100, 2592 })   -- Wool Cloth, only known by link
  end
  C_AuctionHouse.GetNumReplicateItems = function() return _rep and #_rep or 0 end
  C_AuctionHouse.GetReplicateItemInfo = function(i)
    local a = _rep[i + 1]   -- 0-based like the real API
    return nil, nil, a[2], nil, nil, nil, nil, nil, nil, a[3], nil, nil, nil, nil, nil, nil, a[1], true
  end
  C_AuctionHouse.GetReplicateItemLink = function(i)
    local a = _rep[i + 1]
    return a[4] and ("|Hitem:" .. a[4] .. "::|h") or nil
  end
  _ns.db.replicateAt = nil
  _ns.Prices:Realm().ah = {}
  _fire('AUCTION_HOUSE_SHOW')
""")
assert lua.eval("_ns.Prices:FastScanIn()") == 0
lua.execute("_ahSent = 0; SlashCmdList.CRAFTPATH('scan'); _tick(2); _fire('REPLICATE_ITEM_LIST_UPDATE')")
ticks = 0
while lua.eval("_ns.Prices.scanning") and ticks < 100:
    lua.execute("_tick(1)"); ticks += 1
status = strip(lua.eval("_ns.status"))
print("\nfast scan:", ticks, "frames |", status)
assert lua.eval("_repCalls") == 1 and lua.eval("_ahSent") == 0, "one request, no item searches"
assert ticks >= 3, "auctions are read over several frames"
assert "Fast scan complete" in status and "5005 auctions" in status
assert "Blacksmithing" in status and "Tailoring" in status, "covers all your professions"
ah = "_ns.Prices:Realm().ah"
assert lua.eval(f"{ah}[2840].p") == 36 and lua.eval(f"{ah}[2840].n") == 120   # cheapest 36 of 120: 20 at 35c + 16 at 38c
assert lua.eval(f"{ah}[2589].p") == 12, "Tailoring material priced"
assert lua.eval(f"{ah}[2592].p") == 100, "auction identified by its link"
assert lua.eval(f"{ah}[2841].none") is True, "wanted but not listed"
assert lua.eval(f"{ah}[99999]") is None, "items no profession needs aren't stored"

# right after: the server cooldown -> item-by-item scan instead
wait = lua.eval("_ns.Prices:FastScanIn()")
assert 0 < wait <= 900
lua.execute("_ns.status = nil; CraftPathFrame:Render()")
print("status during cooldown:", strip(lua.eval("CraftPathFrame.status:GetText()")))
assert "Fast scan ready in 15 min" in strip(lua.eval("CraftPathFrame.status:GetText()"))
sent, status = run_scan("scan")
assert lua.eval("_repCalls") == 1 and sent > 0, "fell back to searches during cooldown"

# server never answers -> item-by-item after the wait
lua.execute("_ns.db.replicateAt = nil; C_AuctionHouse.ReplicateItems = function() _repCalls = _repCalls + 1 end")
lua.execute("SlashCmdList.CRAFTPATH('scan'); _tick(605)")
assert lua.eval("_ns.Prices.mode") == "smart" and lua.eval("_ns.Prices.scanning"), "fallback started"
lua.execute("_ns.Prices:StopScan()")

# ---- trainers: who really teaches each rank (Alliance) ----------------------------
def trainers(prof, tier):
    return lua.eval(f"""(function()
      local names = {{}}
      _ns.WithProf('{prof}', function()
        for _, t in ipairs(_ns.TrainersFor({tier})) do table.insert(names, t.name) end
      end)
      return table.concat(names, ', ')
    end)()""")
for prof, tier in [("Enchanting", 3), ("Enchanting", 4), ("Blacksmithing", 3), ("Blacksmithing", 4),
                   ("Leatherworking", 3), ("Leatherworking", 4), ("Tailoring", 3), ("Tailoring", 4)]:
    print(f"{prof} {['', '', 'Journeyman', 'Expert', 'Artisan'][tier]}: {trainers(prof, tier)}")
assert "Kitta Firewind" in trainers("Enchanting", 3) and "Gimble" not in trainers("Enchanting", 3)
assert "Gimble Thistlefuzz" in trainers("Enchanting", 2)
assert trainers("Enchanting", 4) == "Annora"
assert trainers("Blacksmithing", 4) == "Brikk Keencraft" and "Bengus Deepforge" in trainers("Blacksmithing", 3)
assert "Saru Steelfury" not in trainers("Blacksmithing", 3), "Horde trainer hidden for Alliance"

# ---- skill-up chance follows the colours -------------------------------------------
chance = lambda r, s: lua.eval(f"_ns.Optimizer.Chance({r}, {s})")
mid = "{ learn = 70, c = { 70, 110, 130, 150 } }"           # Greater Magic Wand
assert abs(chance(mid, 120) - (150 - 120) / 40) < 1e-9, "same as the community formula"
odd = "{ learn = 210, c = { 210, 210, 215, 225 } }"         # Heavy Mithril Pants
assert chance(odd, 215) == 0.5 and chance(odd, 220) == 0.25 and chance(odd, 212) > 0.5

# ---- colours: match what the profession window shows ------------------------------
# Data says Rough Sharpening Stone is yellow at 30 (15/35/55); the game says green.
lua.execute("""
  _diff = { [2660] = 2 }
  C_TradeSkillUI.GetRecipeInfo = function(id) return { learned = true, relativeDifficulty = _diff[id] } end
  _open = { 'Blacksmithing', 164 }; _skill = 30; _chat = {}
  _fire('TRADE_SKILL_SHOW')
""")
c = lua.eval("(function() local r; for _, x in ipairs(_ns.Professions.Blacksmithing.recipes) do if x.id == 2660 then r = x end end; return r end)()")
print("Rough Sharpening Stone after window:", list(c.c.values()), "| chance at 30:", lua.eval("_ns.Optimizer.Chance(...)", c, 30))
assert c.c[3] == 30 and c.c[2] == 15 and c.c[4] == 55
assert lua.eval("_ns.Optimizer.Chance(...)", c, 30) <= 0.5, "green -> low chance"
assert lua.eval("_ns.db.colorFix[2660][2]") == 30, "remembered"
assert any("skill-up colours" in m for m in chat())
# gray in game at 50 -> gray boundary moves down; orange at 16 -> yellow starts later
lua.execute("_diff = { [2660] = 3, [3115] = 0 }; _skill = 50; _fire('TRADE_SKILL_SHOW')")
assert c.c[4] == 50
r3115 = lua.eval("(function() for _, x in ipairs(_ns.Professions.Blacksmithing.recipes) do if x.id == 3115 then return x end end end)()")
assert r3115.c[2] == 51 and r3115.c[3] == 51 and r3115.c[4] == 55, list(r3115.c.values())
# re-applied after a reload
lua.execute("_ns.ApplyColorFixes()")
assert c.c[4] == 50

# ---- learn-where: one trainer per city ---------------------------------------------
lua.execute("GetRealZoneText = function() return 'Dun Morogh' end")
spots = lua.eval("""(function()
  local r; for _, x in ipairs(_ns.Professions.Blacksmithing.recipes) do if x.id == 3320 then r = x end end
  return table.concat(_ns.WithProf('Blacksmithing', function() return _ns.LearnInfo(r, 'Trainer', 0).where end), ' / ')
end)()""")
print("\nlearn where:", spots)
zones = [w.split(", ", 1)[1] for w in spots.split(" / ")]
assert len(zones) == len(set(zones)), "one trainer per city"
assert zones == ["Dun Morogh", "Stormwind City", "Ironforge"], zones  # current zone, then capitals

# ---- tracker: Craft / Craft all ------------------------------------------------------
lua.execute("""
  _crafted, _openedLine = {}, nil
  local ids = {}
  for _, r in ipairs(_ns.Professions.Blacksmithing.recipes) do table.insert(ids, r.id) end
  C_TradeSkillUI.GetAllRecipeIDs = function() return ids end
  C_TradeSkillUI.GetRecipeInfo = function(id) return { learned = true, numAvailable = 7 } end
  C_TradeSkillUI.CraftRecipe = function(id, n) table.insert(_crafted, { id, n }) end
  C_TradeSkillUI.OpenTradeSkill = function(line) _openedLine = line; _fire('TRADE_SKILL_SHOW') end
  _ns.settings.profession = 'Blacksmithing'; _open = { 'Blacksmithing', 164 }; _skill = 60; _maxSkill = 150
  _ns.Tracker:Show()
  _fire('TRADE_SKILL_SHOW'); _fire('TRADE_SKILL_CLOSE'); _ns.Refresh()
""")
show("TRACKER window closed", tracker_text(), 20)
assert "[Open Blacksmithing]" in tracker_text()
lua.execute("_click(CraftPathTracker.craft)")   # opens the window instead of crafting
assert lua.eval("_openedLine") == 164 and lua.eval("#_crafted") == 0
lua.execute("_ns.Refresh()")
show("TRACKER window open", tracker_text(), 20)
rid = lua.eval("_ns.Progress().recipe.id")
left = lua.eval("math.ceil(_ns.Progress().left - 1e-9)")
assert f"[Craft {min(7, left)}]" in tracker_text()
lua.execute("_click(CraftPathTracker.craft)")
assert lua.eval("_crafted[1][1]") == rid and lua.eval("_crafted[1][2]") == min(7, left)
# the planner's card has the same button
lua.execute("if not CraftPathFrame:IsShown() then _ns.UI:Toggle() end; CraftPathFrame:Render()")
assert f"[Craft {min(7, left)}]" in card_text()
lua.execute("_click(CraftPathFrame.card.craft)")
assert lua.eval("_crafted[2][2]") == min(7, left)
# nothing craftable -> disabled
lua.execute("C_TradeSkillUI.GetRecipeInfo = function(id) return { learned = true, numAvailable = 0 } end; _ns.Refresh()")
assert "[No materials (disabled)]" in tracker_text()
lua.execute("CraftPathFrame:Render()")
assert "[No materials (disabled)]" in card_text()
# in combat: refuses
lua.execute("C_TradeSkillUI.GetRecipeInfo = function(id) return { learned = true, numAvailable = 3 } end; _ns.Refresh()")
lua.execute("InCombatLockdown = function() return true end; _click(CraftPathTracker.craft); InCombatLockdown = nil")
assert lua.eval("#_crafted") == 2 and any("combat" in m for m in chat())

# ---- sell-back ------------------------------------------------------------------------
assert strip(lua.eval("_ns.Money(-25873)")) == "-2g 58s"
# the game's sell price wins over the data file, and is cached
lua.execute("""
  _sellAsked = 0
  C_Item = C_Item or {}
  C_Item.GetItemInfo = function(id)
    _sellAsked = _sellAsked + 1
    if id == 2852 then return 'Copper Chain Pants', nil, nil, nil, nil, nil, nil, nil, nil, nil, 999 end
  end
""")
assert lua.eval("_ns.Prices:SellPrice(2852)") == 999 and lua.eval("_ns.db.sell[2852]") == 999
asked = lua.eval("_sellAsked")
assert lua.eval("_ns.Prices:SellPrice(2852)") == 999 and lua.eval("_sellAsked") == asked, "cached"
assert lua.eval("_ns.Prices:SellPrice(1)") is None, "unknown to the client -> data file"
# yield is never 0
assert lua.eval("_ns.Optimizer.Yield({ make = { 1, 0, 0 } })") == 1
# items made earlier are kept, not sold and re-bought: step 1 makes X, step 2 uses 2 X
res = lua.eval("""_ns.Optimizer.Run({
  prof = { recipes = {
    { id = 1, name = 'Make X', learn = 1, c = { 1, 10, 15, 20 }, src = 't', cost = 0, make = { 100, 1, 1 }, reag = { { 200, 1 } } },
    { id = 2, name = 'Use X', learn = 10, c = { 10, 20, 25, 30 }, src = 't', cost = 0, make = { 101, 1, 1 }, reag = { { 100, 2 } } },
  } },
  items = { [100] = { 'X', 0, 5 }, [101] = { 'Y', 0, 5 }, [200] = { 'M', 0, 0 } },
  from = 1, to = 30, mode = 'cheap', price = function(id) if id == 200 then return 10, 'ah' end end,
  known = {}, specs = {}, faction = 1, sellBack = true })""")
assert res.ok, "route"
reused = {u.id: u.qty for u in res.reused.values()}
made = sum(st.crafts for st in res.steps.values() if st.recipe.id == 1)
print("made X:", made, "| reused:", reused, "| sell back:", res.totals.sellBack)
assert reused.get(100) == made, "all X from step 1 go into step 2"
crafts_y = sum(st.crafts for st in res.steps.values() if st.recipe.id == 2)
assert res.totals.sellBack == crafts_y * 5, "only Y is sold"
lua.execute("_ns.result.reused = { { id = 3470, qty = 12 } }; _ns.settings.tab = 'shop'; CraftPathFrame:Render()")
assert "Made earlier on this route" in ui_text() and "keep 12" in ui_text()
# ---- waypoints to trainers -------------------------------------------------------------
kitta = lua.eval("""(function()
  for _, t in ipairs(_ns.Professions.Enchanting.trainers) do if t[1] == 'Kitta Firewind' then return t end end
end)()""")
assert kitta is not None and kitta[5] == 1429 and abs(kitta[6] - 64.8) < 0.5, "Kitta Firewind: Elwynn Forest 64.8, 70.x"
lua.execute("""
  _wp = nil; _super = nil
  UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
  C_Map = C_Map or {}
  C_Map.CanSetUserWaypointOnMap = function(map) return map ~= 1337 end
  C_Map.SetUserWaypoint = function(p) _wp = p end
  C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) _super = v end }
  _chat = {}
""")
assert lua.eval("_ns.Waypoint({ name = 'Kitta Firewind', zone = 'Elwynn Forest', map = 1429, x = 64.8, y = 70.6 })")
assert lua.eval("_wp.map") == 1429 and abs(lua.eval("_wp.x") - 0.648) < 1e-9 and lua.eval("_super") is True
assert any("Waypoint set" in m for m in chat())
# a map the game won't put a waypoint on (inside a dungeon): prints /way instead
assert not lua.eval("_ns.Waypoint({ name = 'Annora', zone = 'Uldaman', map = 1337, x = 50, y = 50 })")
assert any("/way 50.0 50.0 Annora" in m for m in chat())
# TomTom, if installed, wins
lua.execute("""_tt = nil; TomTom = { AddWaypoint = function(self, map, x, y, opts) _tt = { map, x, y, opts.title } end }""")
lua.execute("_ns.Waypoint({ name = 'Kitta Firewind', zone = 'Elwynn Forest', map = 1429, x = 64.8, y = 70.6 })")
assert lua.eval("_tt[1]") == 1429 and lua.eval("_tt[4]") == "Kitta Firewind"
lua.execute("TomTom = nil")

# learn-first: places as a bullet list with clickable dots (main card + tracker + route tab)
lua.execute("""
  _ns.settings.profession = 'Blacksmithing'; _ns.char.known.Blacksmithing = { [2660] = true }
  GetRealZoneText = function() return 'Elwynn Forest' end
  _skill = 1; _ns.Refresh()
  _ns.settings.tab = 'plan'; CraftPathFrame:Render()
""")
show("CARD (learn first, places)", card_text(), 20)
assert card_text().count("(pin) ") >= 2, "places in the card, each with a pin"
show("TRACKER (learn first, places)", tracker_text(), 20)
assert tracker_text().count("(pin) ") >= 2
tip = lua.eval("""(function()
  for _, r in ipairs(CraftPathFrame.rows.pool) do if r:IsShown() and type(r.hover) == "table" and r.hover.lines[1]:find("Stormwind", 1, true) == nil and table.concat(r.hover.lines, " / "):find("Stormwind", 1, true) then return table.concat(r.hover.lines, " / ") end end
  end)()""")
assert tip and "Stormwind" in tip, "route tab: trainers in the row's tooltip"
# clicking a pin in the tracker sets the waypoint
lua.execute("_wp = nil; for _, p in ipairs(CraftPathTracker.pins) do if p:IsShown() then _click(p); break end end")
assert lua.eval("_wp ~= nil")

# ---- neutral (goblin) auction house: never scanned, faction prices stay -------
lua.execute("""
  _fire('AUCTION_HOUSE_CLOSED')
  _ns.Prices:Realm().ah[2840] = { 123, time() }
  UnitExists = function(u) return u == 'npc' end
  UnitFactionGroup = function(u) if u == 'npc' then return nil end return 'Alliance' end
  _fire('AUCTION_HOUSE_SHOW'); CraftPathFrame:Render()
""")
assert lua.eval("_ns.neutralAH") is True
sent, status = run_scan("scan")
assert sent == 0 and not lua.eval("_ns.Prices.scanning"), "no scan at a neutral AH"
assert "Neutral Auction House" in status
assert lua.eval("_ns.Prices:Realm().ah[2840][1]") == 123, "faction prices untouched"
assert not lua.eval("CraftPathFrame.scan:IsEnabled()") and not lua.eval("CraftPathFrame.fullScan:IsEnabled()")
assert "Neutral Auction House" in strip(lua.eval("CraftPathFrame.status:GetText()"))
# faction auctioneer: scanning allowed again
lua.execute("""
  _fire('AUCTION_HOUSE_CLOSED')
  UnitFactionGroup = function() return 'Alliance' end
  _fire('AUCTION_HOUSE_SHOW'); CraftPathFrame:Render()
""")
assert not lua.eval("_ns.neutralAH") and lua.eval("CraftPathFrame.scan:IsEnabled()")
# no auctioneer unit (fallback): Booty Bay by sub-zone, then by map position
lua.execute("""
  UnitExists = function() return false end
  GetSubZoneText = function() return 'Booty Bay' end
""")
assert lua.eval("_ns.IsNeutralAH()") is True
lua.execute("""
  GetSubZoneText = function() return '' end
  C_Map.GetBestMapForPlayer = function() return 1446 end
  C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.515, 0.285 end } end
""")
assert lua.eval("_ns.IsNeutralAH()") is True, "Gadgetzan by position"
lua.execute("C_Map.GetBestMapForPlayer = function() return 1453 end")
assert lua.eval("_ns.IsNeutralAH()") is False, "Stormwind"
lua.execute("UnitExists = nil; C_Map.GetBestMapForPlayer = nil; C_Map.GetPlayerMapPosition = nil")
print("neutral AH: not scanned, faction prices kept")

# ---- every hover uses CraftPath's own card ------------------------------------
lua.execute("if not CraftPathFrame:IsShown() then _ns.UI:Toggle() end; CraftPathFrame:Render()")
lua.execute("CraftPathFrame.scan:GetScript('OnEnter')(CraftPathFrame.scan)")
h = strip(lua.eval("_ns.T.HoverText()"))
assert h.startswith("Scan AH") and "all your professions" in h, h
lua.execute("CraftPathFrame.scan:GetScript('OnLeave')(CraftPathFrame.scan)")
assert lua.eval("_ns.T.HoverText()") == ""
lua.execute("CraftPathFrame.totalHit:GetScript('OnEnter')(CraftPathFrame.totalHit)")
h = strip(lua.eval("_ns.T.HoverText()"))
assert h.startswith("Route cost") and "Materials" in h, h
lua.execute("_ns.T.HideHover()")
print("hovers: themed card for buttons and the total")

# ---- recipe vendors: your faction's, nearest first ---------------------------
lua.execute("_prevProf = _ns.settings.profession; _ns.settings.profession = 'Cooking'")
r = lua.eval("(function() for _, r in ipairs(_ns.Professions.Cooking.recipes) do if r.id == 7827 then return r end end end)()")
where = list(lua.eval("_ns.LearnInfo")(r, "Vendor", 400).where.values())
print("Rainbow Fin Albacore vendors:", where)
assert where[0] == "Catherine Leland, Stormwind City", "capital first"
spot = lua.eval("_ns.LearnInfo")(r, "Vendor", 400).spots[1]
assert spot and spot.map == 1453 and abs(spot.x - 55.1) < 0.01, "vendor waypoint dot"
assert not any("Durotar" in w or "Orgrimmar" in w for w in where)
lua.execute("_ns.settings.profession = _prevProf")

# ---- globals: only the ones WoW needs ---------------------------------------
ALLOWED = {"CraftPathDB", "CraftPathCharDB", "SLASH_CRAFTPATH1", "SLASH_CRAFTPATH2",
           "CraftPath_OnCompartmentClick", "CraftPathFrame", "CraftPathTracker"}
made = dict(lua.eval("_addonGlobals").items())
print("globals created by the addon:", sorted(made))
extra = {k: v for k, v in made.items() if k not in ALLOWED}
assert not extra, f"unexpected globals: {extra}"
print("\nALL CHECKS PASSED")
