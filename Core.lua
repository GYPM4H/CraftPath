-- CraftPath core: saved data, skill/recipe detection, events, slash commands.
local ADDON, ns = ...

local DEFAULTS = {
  profession = "Blacksmithing",
  targets = {},          -- target skill per profession (default 300)
  mode = "balanced",     -- cheap | fast | balanced
  craftValue = 2000,     -- balanced mode: one craft is worth 20s of your time
  switchCost = 0,        -- extra cost per recipe change (copper)
  sellBack = true,       -- subtract vendor value of what you craft
  useAuctionator = true,
  allowQuest = false,    -- quest-only plans count as obtainable
  tab = "plan",
  showTracker = true,    -- compact tracker on screen
  trackerLocked = false,
  autoTracker = true,    -- show the tracker when the profession window opens
  fontScale = 1,         -- 1 normal, 1.15 large, 1.3 larger
}

local function print_(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffff9933CraftPath|r: " .. msg) end
ns.Print = print_

---------------------------------------------------------------- helpers
function ns.Money(c, short)
  if not c then return "|cff888888?|r" end
  c = math.floor(c + 0.5)
  if c < 0 then return "-" .. ns.Money(-c, short) end
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local G, S, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
  if g > 0 then
    if short or g >= 100 then return g .. G .. (g < 100 and s > 0 and (" " .. s .. S) or "") end
    return g .. G .. " " .. s .. S
  end
  if s > 0 then return s .. S .. (cp > 0 and not short and (" " .. cp .. C) or "") end
  return cp .. C
end

function ns.FactionMask()
  local f = UnitFactionGroup("player")
  return f == "Alliance" and 1 or f == "Horde" and 2 or 3
end

-- Neutral (goblin) auction houses have their own, separate listings. Scanning
-- one would overwrite your faction's prices, so CraftPath doesn't scan there.
ns.NEUTRAL_MSG = "Neutral Auction House: not scanned, so it won't mix with your faction's prices."
local NEUTRAL_TOWNS = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }
local NEUTRAL_SPOTS = {           -- uiMapId, x, y (0-100) of each goblin AH
  { 1434, 26.5, 76.5 },           -- Booty Bay, Stranglethorn Vale
  { 1446, 51.5, 28.0 },           -- Gadgetzan, Tanaris
  { 1452, 61.0, 38.0 },           -- Everlook, Winterspring
}
function ns.IsNeutralAH()
  -- the auctioneer you're talking to: faction auctioneers share your faction,
  -- Steamwheedle goblins have none
  if UnitExists and UnitExists("npc") then
    local f = UnitFactionGroup("npc")
    if f and f == UnitFactionGroup("player") then return false end
    if not f or f == "Neutral" then return true end
  end
  -- fallback: where you are
  if NEUTRAL_TOWNS[GetSubZoneText and GetSubZoneText() or ""] then return true end
  if C_Map and C_Map.GetBestMapForPlayer and C_Map.GetPlayerMapPosition then
    local map = C_Map.GetBestMapForPlayer()
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if pos then
      local x, y = pos:GetXY()
      for _, s in ipairs(NEUTRAL_SPOTS) do
        local dx, dy = x * 100 - s[2], y * 100 - s[3]
        if map == s[1] and dx * dx + dy * dy < 16 then return true end
      end
    end
  end
  return false
end

function ns.Prof()
  return ns.Professions[ns.settings.profession] or ns.Professions.Blacksmithing
end

function ns.Target(key)
  key = key or ns.Prof().key
  return ns.settings.targets[key] or 300
end

function ns.SetTarget(v)
  ns.settings.targets[ns.Prof().key] = math.max(2, math.min(300, v))
end

-- Professions the character has (by key), from the skill list.
function ns.Owned()
  local owned = {}
  if GetProfessions then
    local list = { GetProfessions() }
    for i = 1, 6 do
      local idx = list[i]
      if idx then
        local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
        for key, p in pairs(ns.Professions) do
          if skillLine == p.skillLine or name == p.key then owned[key] = { rank = rank, max = maxRank } end
        end
      end
    end
  elseif GetNumSkillLines then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if not isHeader then
        for key, p in pairs(ns.Professions) do
          if name == p.key or name == ns.ProfName(p) then owned[key] = { rank = rank, max = maxRank } end
        end
      end
    end
  end
  for key, v in pairs(owned) do ns.char.skill[key] = v end
  return owned
end

-- All supported professions, the ones you have first.
function ns.ProfessionList()
  local owned, list = ns.Owned(), {}
  for key in pairs(ns.Professions) do table.insert(list, key) end
  table.sort(list, function(a, b)
    if (owned[a] ~= nil) ~= (owned[b] ~= nil) then return owned[a] ~= nil end
    return a < b
  end)
  return list, owned
end

function ns.SetProfession(key)
  if not ns.Professions[key] or ns.settings.profession == key then return end
  ns.settings.profession = key
  ns.status = nil
  ns.Refresh()
end

local PLAN_PREFIX = { Blacksmithing = "Plans", Leatherworking = "Pattern", Tailoring = "Pattern",
  Enchanting = "Formula", Cooking = "Recipe", ["First Aid"] = "Manual" }
local planNames = {} -- plan item id -> "Plans: Recipe"
local function buildPlanNames()
  for key, prof in pairs(ns.Professions) do
    for _, r in ipairs(prof.recipes) do
      if r.plan then planNames[r.plan] = (PLAN_PREFIX[key] or "Recipe") .. ": " .. r.name end
    end
  end
end

function ns.IsPlan(id) return planNames[id] ~= nil end

local getItemName = (C_Item and C_Item.GetItemNameByID) or (C_Item and C_Item.GetItemInfo) or GetItemInfo
function ns.ItemName(id)
  local name = getItemName and getItemName(id)
  if name then return name end
  if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
  if planNames[id] then return planNames[id] end
  local it = ns.Items[id]
  return it and it[1] ~= "" and it[1] or ("item:" .. id)
end

---------------------------------------------------------- skill & recipes
function ns.ProfName(prof)
  prof = prof or ns.Prof()
  local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(prof.spell))
    or (GetSpellInfo and GetSpellInfo(prof.spell))
  return name or prof.key
end

-- Current and max skill from the character's skill list.
function ns.ReadSkill()
  local prof = ns.Prof()
  local owned = ns.Owned()
  local s = owned[prof.key] or ns.char.skill[prof.key]
  if s then return s.rank, s.max end
end

function ns.Specs()
  local specs = {}
  for id in pairs(ns.Prof().specs or {}) do
    local known = (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id))
    if known then specs[id] = true end
  end
  -- Master *smiths are also Weaponsmiths
  if specs[17039] or specs[17040] or specs[17041] then specs[9787] = true end
  return specs
end

function ns.Known()
  local prof = ns.Prof()
  ns.char.known[prof.key] = ns.char.known[prof.key] or {}
  return ns.char.known[prof.key]
end

-- Read the open profession window: which recipes you know, and your skill.
local function findProf(name, skillLine)
  for _, p in pairs(ns.Professions) do
    if (skillLine and skillLine == p.skillLine) or name == ns.ProfName(p) or name == p.key then return p end
  end
end

------------------------------------------------------------ recipe colours
-- The game knows each recipe's real difficulty at your skill. Whenever the
-- profession window shows a colour our data disagrees with, we move the
-- recipe's thresholds so they match, and remember that (account-wide).
-- 0 orange, 1 yellow, 2 green, 3 gray
local DIFF = { optimal = 0, difficult = 0, medium = 1, easy = 2, trivial = 3 }
local recipeById
local function byId(id)
  if not recipeById then
    recipeById = {}
    for _, p in pairs(ns.Professions) do
      for _, r in ipairs(p.recipes) do recipeById[r.id] = r end
    end
  end
  return recipeById[id]
end

-- difficulty: number (0-3) or the classic string ("optimal", ...)
function ns.ObserveDifficulty(id, difficulty, skill)
  local r = byId(id)
  local k = type(difficulty) == "string" and DIFF[difficulty] or difficulty
  if not (r and type(k) == "number" and k >= 0 and k <= 3 and skill) then return false end
  local c = r.c
  local fix = { c[1], c[2], c[3], c[4] }
  -- colour k at `skill` means: the first k boundaries are <= skill, the rest above it
  for j = 1, 3 do
    if j <= k then fix[j + 1] = math.min(fix[j + 1], skill)
    else fix[j + 1] = math.max(fix[j + 1], skill + 1) end
  end
  if fix[2] == c[2] and fix[3] == c[3] and fix[4] == c[4] then return false end
  r.c = fix
  ns.db.colorFix[id] = { fix[2], fix[3], fix[4] }
  return true
end

function ns.ApplyColorFixes()
  for id, f in pairs(ns.db.colorFix) do
    local r = byId(id)
    if r then r.c = { r.c[1], f[1], f[2], f[3] } end
  end
end

local function reportFixes(n, prof)
  if n > 0 then
    ns.Print(("Matched skill-up colours for %d %s recipe%s to what your profession window shows."):format(
      n, ns.ProfName(prof), n == 1 and "" or "s"))
  end
end

local function readTradeSkillModern()
  local T = C_TradeSkillUI
  local info = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
  local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
  local prof = info and findProf(info.professionName, info.professionID)
  if not prof and child then prof = findProf(child.parentProfessionName, child.parentProfessionID) end
  if not prof then return end
  ns.tradeOpen = prof.key
  ns.SetProfession(prof.key)
  ns.char.known[prof.key] = ns.char.known[prof.key] or {}
  local known = ns.char.known[prof.key]
  local lvl = child and child.skillLevel or info and info.skillLevel
  local max_ = child and child.maxSkillLevel or info and info.maxSkillLevel
  local fixed = 0
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local r = T.GetRecipeInfo(id)
    if r and r.learned then
      known[id] = true
      local d = r.relativeDifficulty
      if d == nil then d = r.difficulty end
      if lvl and lvl > 0 and ns.ObserveDifficulty(id, d, lvl) then fixed = fixed + 1 end
    end
  end
  if lvl and lvl > 0 then ns.char.skill[prof.key] = { rank = lvl, max = max_ } end
  reportFixes(fixed, prof)
  ns.Refresh()
end

local function readTradeSkillClassic()
  local name, rank, maxRank = GetTradeSkillLine()
  local prof = findProf(name)
  if not prof then return end
  ns.tradeOpen = prof.key
  ns.SetProfession(prof.key)
  local byName = {}
  for _, r in ipairs(prof.recipes) do byName[r.name] = r.id end
  -- merge: the window may be filtered, and recipes are never unlearned
  ns.char.known[prof.key] = ns.char.known[prof.key] or {}
  local known = ns.char.known[prof.key]
  local fixed = 0
  for i = 1, GetNumTradeSkills() do
    local rname, kind = GetTradeSkillInfo(i)
    if kind ~= "header" and rname then
      local link = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
      local spell = link and tonumber(link:match("enchant:(%d+)"))
      local id = spell or byName[rname]
      if id then
        known[id] = true
        if rank and rank > 0 and ns.ObserveDifficulty(id, kind, rank) then fixed = fixed + 1 end
      end
    end
  end
  if rank and rank > 0 then ns.char.skill[prof.key] = { rank = rank, max = maxRank } end
  reportFixes(fixed, prof)
  ns.Refresh()
end

local function readTradeSkill()
  if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
    readTradeSkillModern()
  elseif GetTradeSkillLine then
    readTradeSkillClassic()
  end
end

-- Items worth tracking: reagents (and sub-reagents) and plans for recipes
-- that matter between your skill and the target.
function ns.WantedItems(forScan)
  local prof = ns.Prof()
  local from = ns.ReadSkill() or 1
  local to = ns.Target()
  local specs, known = ns.Specs(), ns.Known()
  local makers = {}
  for _, r in ipairs(prof.recipes) do
    if r.make then makers[r.make[1]] = r end
  end
  local wanted = {}
  local function addReagents(r, depth)
    for _, rg in ipairs(r.reag) do
      wanted[rg[1]] = true
      local m = makers[rg[1]]
      if m and depth < 2 then addReagents(m, depth + 1) end
    end
  end
  for _, r in ipairs(prof.recipes) do
    local inRange = r.c[4] > from and r.learn < to and (not r.spec or specs[r.spec])
    if inRange then
      local free = known[r.id] or r.src:find("[st]")
      -- reagents only for recipes you can actually get (trainer, known, or a
      -- plan with a price); otherwise just look for the plan itself on the AH
      if free or ns.Prices:Plan(r) then addReagents(r, 0) end
      if r.plan and not free then wanted[r.plan] = true end
    end
  end
  return wanted
end

-- What to scan on the AH: everything used by the best route in every mode,
-- both as things stand and as if every plan were free (so a cheap plan on
-- the AH can be discovered). Keeps a scan to a few dozen searches.
function ns.ScanList()
  local prof = ns.Prof()
  local from = ns.ReadSkill() or 1
  local to = math.min(ns.Target(), 300)
  local list = {}
  local function addRecipe(r)
    for _, rg in ipairs(r.reag) do list[rg[1]] = true end
  end
  local estimate = function(id) return ns.Prices:Get(id) end
  for _, mode in ipairs({ "cheap", "balanced", "fast" }) do
    for _, freePlans in ipairs({ false, true }) do
      local res = ns.Optimizer.Run({
        prof = prof, from = from, to = to, mode = mode,
        craftValue = ns.settings.craftValue, switchCost = ns.settings.switchCost,
        price = estimate,
        planPrice = freePlans and function() return 0, "?" end or function(r) return ns.Prices:Plan(r) end,
        known = ns.Known(), knownComplete = next(ns.Known()) ~= nil, specs = ns.Specs(), faction = ns.FactionMask(),
        sellBack = ns.settings.sellBack, allowQuest = ns.settings.allowQuest,
        sellPrice = function(id) return ns.Prices:SellPrice(id) end,
      })
      if res.ok then
        for _, st in ipairs(res.steps) do
          addRecipe(st.recipe)
          if st.recipe.plan and st.learnHow ~= "known" and not st.recipe.src:find("[st]") then
            list[st.recipe.plan] = true
          end
        end
        for _, cr in ipairs(res.intermediates) do addRecipe(cr.recipe) end
      else
        -- stuck (a material has no price): scan everything usable at that skill
        local specs = ns.Specs()
        for _, r in ipairs(prof.recipes) do
          if r.learn <= res.stuckAt and r.c[4] > res.stuckAt and (not r.spec or specs[r.spec]) then
            addRecipe(r)
          end
        end
      end
    end
  end
  for id in pairs(ns.VendorSeed) do list[id] = nil end -- vendor-only goods
  return list
end

-- Not enough price data for this profession yet (no scan, no Auctionator)?
-- A few prices shared with another profession don't count: we want at least
-- a quarter of this profession's materials known.
function ns.NeedsFirstScan()
  local _, _, either, n = ns.Prices:Coverage()
  return n > 0 and either < n * 0.25
end

-- Full scan: every reagent (and sub-reagent) of every recipe you can get in
-- range, plus plans you could buy - except goods only vendors sell.
function ns.FullScanList()
  local list = ns.WantedItems()
  for id in pairs(ns.VendorSeed) do list[id] = nil end
  return list
end

-- Professions a scan covers: every supported one you have (the selected one
-- too, even if the skill list hasn't loaded yet).
function ns.ScanProfessions()
  local keys, seen = {}, {}
  for key in pairs(ns.Owned()) do
    if ns.Professions[key] then table.insert(keys, key); seen[key] = true end
  end
  local cur = ns.Prof().key
  if not seen[cur] then table.insert(keys, cur) end
  table.sort(keys)
  return keys
end

-- Run fn with `key` as the selected profession (lists, skill, target and
-- known recipes all follow the selection), then switch back.
function ns.WithProf(key, fn)
  local saved = ns.settings.profession
  ns.settings.profession = key
  local ok, a, b = pcall(fn)
  ns.settings.profession = saved
  if not ok then error(a, 0) end
  return a, b
end

-- Union of a scan list over all your professions. kind: "full" | "smart".
function ns.ScanListAll(kind)
  local all = {}
  for _, key in ipairs(ns.ScanProfessions()) do
    local list = ns.WithProf(key, kind == "full" and ns.FullScanList or ns.ScanList)
    for id in pairs(list) do all[id] = true end
  end
  return all
end

-- Does any of your professions still lack prices?
function ns.AnyNeedsFirstScan()
  for _, key in ipairs(ns.ScanProfessions()) do
    if ns.WithProf(key, ns.NeedsFirstScan) then return true end
  end
  return false
end

---------------------------------------------------------------- compute
function ns.Compute()
  local prof = ns.Prof()
  local s = ns.settings
  local rank = ns.ReadSkill()
  ns.result, ns.computeError, ns.needsScan = nil, nil, nil
  if not rank then
    ns.computeError = ("You don't have %s (or open its window once)."):format(ns.ProfName(prof))
    return
  end
  local to = math.min(ns.Target(), 300)
  if rank >= to then
    ns.computeError = ("Already at %d/%d."):format(rank, to)
    return
  end
  if ns.NeedsFirstScan() then
    ns.needsScan = true
    return
  end
  local res = ns.Optimizer.Run({
    prof = prof, from = rank, to = to, mode = s.mode,
    craftValue = s.craftValue, switchCost = s.switchCost,
    price = function(id) return ns.Prices:Get(id) end,
    planPrice = function(r) return ns.Prices:Plan(r) end,
    known = ns.Known(), knownComplete = next(ns.Known()) ~= nil, specs = ns.Specs(), faction = ns.FactionMask(),
    sellBack = s.sellBack, allowQuest = s.allowQuest,
    sellPrice = function(id) return ns.Prices:SellPrice(id) end,
  })
  if not res.ok then
    if res.stuckAt <= rank then
      -- nothing priced at your current skill: same as having no prices
      ns.needsScan = true
      return
    end
    ns.computeError = ("No recipe with known prices takes you past %d. Try a Full scan."):format(res.stuckAt)
  else
    ns.AddCraftTimes(res)
  end
  ns.result = res
end

------------------------------------------------------------ craft time
-- Seconds per craft: the recipe's cast time from the game, plus a short gap
-- between casts. Falls back to a typical cast time when the game doesn't say.
local CAST_GAP = 0.5
local FALLBACK_CAST = { Enchanting = 5 }
local castCache = {}
function ns.CastTime(r)
  if castCache[r.id] then return castCache[r.id] end
  local ms
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(r.id)
    ms = info and info.castTime
  elseif GetSpellInfo then
    ms = select(4, GetSpellInfo(r.id))
  end
  if ms and ms > 0 then
    castCache[r.id] = ms / 1000 + CAST_GAP
    return castCache[r.id]
  end
  return (FALLBACK_CAST[ns.Prof().key] or 3) + CAST_GAP
end

-- Adds .time (seconds) to steps, intermediates and totals.
function ns.AddCraftTimes(res)
  local total = 0
  for _, st in ipairs(res.steps) do
    st.time = st.crafts * ns.CastTime(st.recipe)
    total = total + st.time
  end
  for _, cr in ipairs(res.intermediates or {}) do
    cr.time = cr.crafts * ns.CastTime(cr.recipe)
    total = total + cr.time
  end
  res.totals.time = total
end

-- "45 sec", "12 min", "1 h 25 min"
function ns.Duration(sec)
  sec = sec or 0
  if sec < 60 then return ("%d sec"):format(math.max(1, math.floor(sec + 0.5))) end
  local m = math.floor(sec / 60 + 0.5)
  if m < 60 then return ("%d min"):format(m) end
  local h = math.floor(m / 60)
  m = m % 60
  return m > 0 and ("%d h %d min"):format(h, m) or ("%d h"):format(h)
end

function ns.Refresh()
  local ui = ns.UI and ns.UI:IsShown()
  local tr = ns.Tracker and ns.Tracker:IsShown()
  if not (ui or tr) then return end
  ns.Compute()
  if ui then ns.UI:Render() end
  if tr then ns.Tracker:Render() end
end

-- Coalesce bursts of events (bag updates, crafting) into one refresh.
local queued
function ns.QueueRefresh()
  if queued then return end
  queued = true
  local run = function() queued = false; ns.Refresh() end
  if C_Timer and C_Timer.After then C_Timer.After(0.3, run) else run() end
end

function ns.SetStatus(msg)
  ns.status = msg
  if ns.UI and ns.UI:IsShown() then ns.UI:RenderStatus() end
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:RegisterEvent("TRADE_SKILL_SHOW")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_LIST_UPDATE") -- modern client
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_CLOSE")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_UPDATE")      -- classic client
pcall(ev.RegisterEvent, ev, "NEW_RECIPE_LEARNED")      -- modern client
pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_TAB")    -- older clients
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:RegisterEvent("CHAT_MSG_SKILL")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

local function initDB()
  CraftPathDB = CraftPathDB or {}
  CraftPathDB.realms = CraftPathDB.realms or {}
  CraftPathDB.vendor = CraftPathDB.vendor or {}
  CraftPathDB.planVendor = CraftPathDB.planVendor or {} -- recipe item -> where you saw it sold
  CraftPathDB.minimap = CraftPathDB.minimap or { hide = false, minimapPos = 210 }
  CraftPathDB.sell = CraftPathDB.sell or {} -- item id -> vendor sell price from the game
  CraftPathDB.colorFix = CraftPathDB.colorFix or {} -- recipe id -> {yellow, green, gray} seen in game
  CraftPathCharDB = CraftPathCharDB or {}
  local c = CraftPathCharDB
  c.known = c.known or {}
  c.skill = c.skill or {}
  c.settings = c.settings or {}
  for k, v in pairs(DEFAULTS) do
    if c.settings[k] == nil then c.settings[k] = v end
  end
  ns.db, ns.char, ns.settings = CraftPathDB, c, c.settings
end

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    initDB()
    buildPlanNames()
    ns.ApplyColorFixes()
    ns.settings.useEstimates = nil -- removed option
    ns.T.ApplyFontScale()
  elseif event == "PLAYER_LOGIN" then
    ns.Minimap:Init()
    -- start on a profession you actually have
    local list, owned = ns.ProfessionList()
    if not owned[ns.settings.profession] and owned[list[1]] then ns.settings.profession = list[1] end
    if ns.settings.showTracker and ns.ReadSkill() then ns.Tracker:Show() end
  elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" or event == "PLAYER_LEVEL_UP"
      or event == "BAG_UPDATE_DELAYED" then
    ns.QueueRefresh()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if ns.OnCraft(arg3) then ns.QueueRefresh() end -- arg3 = spellID
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_UPDATE" then
    readTradeSkill()
    if ns.UI then ns.UI:AttachToTradeSkill() end
    if event == "TRADE_SKILL_SHOW" and ns.settings.autoTracker and ns.settings.showTracker ~= false
        and not ns.Tracker:IsShown() then
      ns.Tracker:Show()
    end
  elseif event == "TRADE_SKILL_CLOSE" then
    ns.tradeOpen = nil
    ns.QueueRefresh()
  elseif event == "NEW_RECIPE_LEARNED" or event == "LEARNED_SPELL_IN_TAB" then
    ns.OnRecipeLearned(arg1)
  elseif event == "MERCHANT_SHOW" then
    ns.Prices:ScanMerchant()
  elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_HOUSE_CLOSED" then
    ns.atAH = event == "AUCTION_HOUSE_SHOW"
    ns.neutralAH = ns.atAH and ns.IsNeutralAH() or nil
    ns.status = nil
    if not ns.atAH then ns.Prices:StopScan() end
    if ns.UI and ns.UI:IsShown() then ns.UI:Render() end
  end
end)

-- A recipe was just learned (trainer, vendor recipe, drop): update the route now.
function ns.OnRecipeLearned(id)
  if not id then return end
  for key, prof in pairs(ns.Professions) do
    for _, r in ipairs(prof.recipes) do
      if r.id == id then
        ns.char.known[key] = ns.char.known[key] or {}
        ns.char.known[key][id] = true
        print_(("Learned %s - route updated."):format(r.name))
        ns.QueueRefresh()
        return
      end
    end
  end
end

-- minimap addon compartment (## AddonCompartmentFunc in the .toc)
function CraftPath_OnCompartmentClick() ns.UI:Toggle() end

---------------------------------------------------------------- slash
SLASH_CRAFTPATH1, SLASH_CRAFTPATH2 = "/craftpath", "/cpath"
SlashCmdList.CRAFTPATH = function(msg)
  local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  local s = ns.settings
  if cmd == "" or cmd == "show" then
    ns.UI:Toggle()
  elseif cmd == "scan" then
    ns.Prices:StartScan(nil, arg == "full" and "full" or nil)
  elseif cmd == "tracker" then
    ns.Tracker:Toggle()
  elseif cmd == "minimap" then
    ns.Minimap:SetShown(ns.db.minimap.hide)
    print_("Minimap button " .. (ns.db.minimap.hide and "hidden." or "shown."))
  elseif cmd == "lock" then
    s.trackerLocked = not s.trackerLocked
    print_("Tracker " .. (s.trackerLocked and "locked." or "unlocked."))
  elseif cmd == "target" and tonumber(arg) then
    ns.SetTarget(tonumber(arg))
    print_(ns.Prof().key .. " target skill: " .. ns.Target())
    ns.Refresh()
  elseif cmd == "prof" then
    for _, key in ipairs(ns.ProfessionList()) do
      if key:lower():find(arg, 1, true) == 1 or key:lower():gsub(" ", "") == arg:gsub(" ", "") then
        ns.SetProfession(key)
        print_("Profession: " .. key)
        return
      end
    end
    print_("Unknown profession. Try: " .. table.concat(ns.ProfessionList(), ", "))
  elseif cmd == "mode" and (arg == "cheap" or arg == "fast" or arg == "balanced") then
    s.mode = arg
    print_("Mode: " .. arg)
    ns.Refresh()
  elseif cmd == "value" and tonumber(arg) then
    s.craftValue = math.floor(tonumber(arg) * 10000)
    print_("Balanced mode: one craft is worth " .. ns.Money(s.craftValue))
    ns.Refresh()
  elseif cmd == "switch" and tonumber(arg) then
    s.switchCost = math.floor(tonumber(arg) * 10000)
    print_("Extra cost per recipe change: " .. ns.Money(s.switchCost))
    ns.Refresh()
  elseif cmd == "quest" then
    s.allowQuest = not s.allowQuest
    print_("Quest plans count as obtainable: " .. tostring(s.allowQuest))
    ns.Refresh()
  elseif cmd == "resetprices" then
    ns.Prices:Realm().ah = {}
    print_("AH prices for this realm cleared.")
    ns.Refresh()
  else
    print_("/cpath - open the planner")
    print_("/cpath scan - scan the Auction House (AH must be open); /cpath scan full - every reagent")
    print_("/cpath tracker - show/hide the progress tracker; /cpath lock - lock it")
    print_("/cpath minimap - show/hide the minimap button")
    print_("/cpath prof <name> - switch profession (also switches when you open one)")
    print_("/cpath target <skill> - target skill for this profession (default 300)")
    print_("/cpath mode cheap|fast|balanced")
    print_("/cpath value <gold> - balanced mode: what one craft is worth to you")
    print_("/cpath switch <gold> - penalty for each recipe change (fewer different steps)")
    print_("/cpath quest - toggle counting quest-reward plans")
    print_("/cpath resetprices - forget AH prices for this realm")
  end
end
