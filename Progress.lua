-- CraftPath progress: where you are on the route, the current craft, its
-- skill-up chance, attempts left, materials in your bags, and rank training.
local ADDON, ns = ...

local Opt = ns.Optimizer
local ceil, max, sqrt = math.ceil, math.max, math.sqrt
local Z90 = 1.2816

local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount

-- bags, bags + bank
function ns.Count(id)
  if not getCount then return 0, 0 end
  local bags = getCount(id, false) or 0
  local all = getCount(id, true) or bags
  return bags, max(bags, all)
end

local COLORS = { orange = "ff8040", yellow = "ffff00", green = "40c040", gray = "808080" }
function ns.Difficulty(recipe, skill)
  local c = recipe.c
  local d = skill < c[2] and "orange" or skill < c[3] and "yellow" or skill < c[4] and "green" or "gray"
  return d, COLORS[d]
end

-- Attempts needed to go from skill a to b with a recipe (mean, 90%).
function ns.Attempts(recipe, a, b)
  local mean, var = 0, 0
  for s = a, b - 1 do
    local p = Opt.Chance(recipe, s)
    if not p or p <= 0 then return math.huge, math.huge end
    mean = mean + 1 / p
    var = var + (1 - p) / (p * p)
  end
  return mean, mean + Z90 * sqrt(var)
end

local function track()
  local key = ns.Prof().key
  ns.char.track = ns.char.track or {}
  ns.char.track[key] = ns.char.track[key] or {}
  return ns.char.track[key]
end

-- Called after every craft: count attempts at the current step.
function ns.OnCraft(spellId)
  local t = track()
  if t.recipe and spellId == t.recipe then
    t.crafted = (t.crafted or 0) + 1
    return true
  end
end

local function materialsFor(res, recipe, crafts, safe)
  local mats, ok = {}, true
  for _, rg in ipairs(recipe.reag) do
    local id, q = rg[1], rg[2]
    local bags, all = ns.Count(id)
    local need, needSafe = q * crafts, q * safe
    local m = {
      id = id, per = q, need = need, needSafe = needSafe,
      have = bags, bank = all - bags, missing = max(0, need - all),
    }
    if m.missing > 0 then
      ok = false
      local _, how, via = res.itemCost(id, recipe.learn)
      if how == "craft" and via then
        local yield = Opt.Yield(via)
        local n = ceil(m.missing / yield - 1e-9)
        m.craft = { recipe = via, n = n, sub = {} }
        for _, srg in ipairs(via.reag) do
          local sb, sa = ns.Count(srg[1])
          local sneed = srg[2] * n
          table.insert(m.craft.sub, { id = srg[1], need = sneed, have = sb, bank = sa - sb, missing = max(0, sneed - sa) })
        end
      end
    end
    table.insert(mats, m)
  end
  return mats, ok
end

-- Sort order for places: your current zone, then your faction's capitals
-- (in this order), then everything else.
local function placeOrder()
  local here = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
  local CAPITALS = ns.FactionMask() == 2
    and { ["Orgrimmar"] = 1, ["Undercity"] = 2, ["Thunder Bluff"] = 3 }
    or { ["Stormwind City"] = 1, ["Ironforge"] = 2, ["Darnassus"] = 3 }
  return function(zone)
    if here ~= "" and zone:find(here, 1, true) then return 0 end
    return CAPITALS[zone] or 10
  end
end

-- Trainers who can teach a rank tier, for your faction.
function ns.TrainersFor(tier)
  local list = {}
  local faction = ns.FactionMask()
  for _, t in ipairs(ns.Prof().trainers or {}) do
    local name, ttier, side, zone = t[1], t[2], t[3], t[4]
    if bit.band(side, faction) ~= 0 and (ttier >= tier or ttier == 0) then
      table.insert(list, { name = name, zone = zone, tier = ttier, maybe = ttier == 0, map = t[5], x = t[6], y = t[7] })
    end
  end
  local order = placeOrder()
  local function rank_(t)
    if t.maybe then return 100 end
    return order(t.zone)
  end
  table.sort(list, function(a, b)
    local ra, rb = rank_(a), rank_(b)
    if ra ~= rb then return ra < rb end
    if a.zone ~= b.zone then return a.zone < b.zone end
    return a.name < b.name
  end)
  return list
end

-- Up to n trainers for a rank, one per zone: "where can I go" rather than
-- three names in the same city.
-- Does this trainer teach this recipe? Uses the trainer's real list
-- (Data_TrainerRecipes.lua, from Wowhead) when we have it: in Forever a
-- Journeyman trainer may teach a recipe learned at 150 but not one at 140.
function ns.Teaches(t, recipeId)
  local list = recipeId and ns.TrainerTeaches and ns.TrainerTeaches[t.name]
  if not list then return true end
  return list[recipeId] == true
end

-- recipeId (optional): only trainers who actually teach that recipe.
function ns.TrainerSpots(tier, n, recipeId)
  local out, zones = {}, {}
  for _, t in ipairs(ns.TrainersFor(tier)) do
    if not zones[t.zone] and ns.Teaches(t, recipeId) then
      zones[t.zone] = true
      table.insert(out, t)
      if #out >= (n or 3) then break end
    end
  end
  return out
end

-- Mark a spot ({ name, zone, map, x, y }; x/y in 0-100) on the map and
-- minimap: TomTom if installed, else the game's own map waypoint.
function ns.Waypoint(s)
  if not (s and s.map and s.x and s.y) then return false end
  local label = ("%s (%s %.1f, %.1f)"):format(s.name, s.zone, s.x, s.y)
  if TomTom and TomTom.AddWaypoint then
    local ok = pcall(TomTom.AddWaypoint, TomTom, s.map, s.x / 100, s.y / 100,
      { title = s.name, persistent = false, minimap = true, world = true, from = "CraftPath" })
    if ok then ns.Print("Waypoint: " .. label .. " (TomTom)"); return true end
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local can = not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(s.map)
    if can then
      local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(s.map, s.x / 100, s.y / 100))
      if ok then
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
          pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
        ns.Print("Waypoint set on your map and minimap: " .. label)
        return true
      end
    end
  end
  ns.Print(("Can't set a waypoint here. Location: %s  -  /way %.1f %.1f %s"):format(label, s.x, s.y, s.name))
  return false
end

-- Trainer rank that teaches a recipe learned at `learn` skill.
local function tierFor(learn)
  if learn < 75 then return 1 end
  if learn < 150 then return 2 end
  if learn < 225 then return 3 end
  return 4
end
local TIER_NAME = { [1] = "", [2] = "Journeyman ", [3] = "Expert ", [4] = "Artisan " }

-- Where and how to learn a recipe you don't know yet.
-- how: "Trainer", "Vendor (...)", "Auction House", "Quest". Returns
-- { kind, title, cost, where = { "Name, Zone", ... }, text }.
function ns.LearnInfo(r, how, cost)
  local info = { recipe = r, cost = cost or 0, where = {}, spots = {} }
  how = how or "Trainer"
  if how == "Trainer" then
    info.kind = "trainer"
    info.tier = tierFor(r.learn)
    info.title = ("%s%s trainer"):format(TIER_NAME[tierFor(r.learn)], ns.Prof().key)
    for _, t in ipairs(ns.TrainerSpots(tierFor(r.learn), 3, r.id)) do
      table.insert(info.where, t.name .. ", " .. t.zone)
      table.insert(info.spots, t)
    end
  elseif how == "Auction House" then
    info.kind = "ah"
    info.title = "Auction House"
    table.insert(info.where, "Buy " .. ns.ItemName(r.plan))
  elseif how == "Quest" then
    info.kind = "quest"
    info.title = "Quest reward"
    if r.quest then
      table.insert(info.where, "Quest: " .. r.quest)
    else
      table.insert(info.where, "Look up the quest for " .. r.name .. " on Wowhead")
    end
  else
    info.kind = "vendor"
    info.title = "Recipe vendor"
    local seen = r.plan and ns.db.planVendor and ns.db.planVendor[r.plan]
    if seen then
      table.insert(info.where, seen.name .. (seen.zone and seen.zone ~= "" and (", " .. seen.zone) or ""))
      local sp = ns.VendorSpots and ns.VendorSpots[seen.name]
      info.spots[1] = sp and { name = seen.name, zone = sp[4], map = sp[1], x = sp[2], y = sp[3] } or false
    end
    -- your faction's vendors, nearest first (current zone, then capitals)
    local faction, order, list = ns.FactionMask(), placeOrder(), {}
    for i, v in ipairs(r.vendors or {}) do
      local name, side, zone = v[1], v[4], v[6] or ""
      if bit.band(side or 3, faction) ~= 0 and name ~= "vendor" then
        table.insert(list, { name = name, zone = zone, rank = order(zone) + (side == 3 and 5 or 0), i = i })
      end
    end
    table.sort(list, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.i < b.i end)
    for _, v in ipairs(list) do
      if #info.where >= 3 then break end
      if not (seen and seen.name == v.name) then
        table.insert(info.where, v.name .. (v.zone ~= "" and (", " .. v.zone) or ""))
        -- map position (Data_Vendors.lua), for the waypoint dot
        local sp = ns.VendorSpots and ns.VendorSpots[v.name]
        info.spots[#info.where] = sp and { name = v.name, zone = sp[4], map = sp[1], x = sp[2], y = sp[3] } or false
      end
    end
    if #info.where == 0 then
      table.insert(info.where, "Wowhead has no location for this vendor - check the " .. ns.ItemName(r.plan) .. " page")
    end
  end
  info.text = ("%s %s - %s"):format(info.title, ns.Money(info.cost, true), table.concat(info.where, "  /  "))
  return info
end

-- The rank you must train next (nil when nothing is left to train).
function ns.NextRank(rank, maxSkill)
  local level = UnitLevel and UnitLevel("player") or 0
  for _, rk in ipairs(ns.Prof().ranks or {}) do
    local capped = maxSkill and maxSkill <= rk.cap or (not maxSkill and rank < rk.cap)
    if capped then
      return {
        rank = rk, ready = rank >= rk.skill and level >= (rk.level or 0),
        blocking = rank >= rk.cap, level = level,
        trainers = ns.TrainersFor(rk.tier),
      }
    end
  end
end

-- Everything the tracker and the "Now" panel show.
function ns.Progress()
  local res = ns.result
  local rank, maxSkill = ns.ReadSkill()
  if not (res and res.ok and rank) then return nil end
  local step = res.steps[1]
  if not step then return nil end
  local r = step.recipe

  local t = track()
  if t.recipe ~= r.id then
    -- announce only when you finished the previous step (not on a mode change)
    local finished = t.recipe ~= nil and t.to and rank >= t.to
    t.recipe, t.from, t.to, t.crafted = r.id, rank, step.to, 0
    if finished then
      if step.mustLearn and not ns.Known()[r.id] then
        ns.Print(("Next: learn |cffffffff%s|r, then craft it (%d -> %d, about %d attempts)."):format(r.name, step.from, step.to, step.crafts))
      else
        ns.Print(("Next: craft |cffffffff%s|r (%d -> %d, about %d attempts)."):format(r.name, step.from, step.to, step.crafts))
      end
    end
  end
  local from = math.min(t.from or rank, rank)

  local chance = Opt.Chance(r, rank) or 0
  local mats, matsOK = materialsFor(res, r, step.crafts, step.safe)
  local nextStep = res.steps[2]

  -- you can't craft this yet: learning it is the step right now
  local known = ns.Known()
  local learnFirst
  if step.mustLearn and not known[r.id] then
    learnFirst = ns.LearnInfo(r, step.learnHow, step.learnCost)
  end
  -- materials you'd craft yourself with a recipe you don't have yet
  local learnAlso = {}
  for _, m in ipairs(mats) do
    if m.craft and not known[m.craft.recipe.id] and not (m.craft.recipe.src:find("s") and not next(known)) then
      table.insert(learnAlso, ns.LearnInfo(m.craft.recipe, "Trainer", m.craft.recipe.cost))
    end
  end

  -- next recipe you still have to learn somewhere
  local learnNext
  for _, st in ipairs(res.steps) do
    if st.learnCost > 0 or st.learnHow == "Quest" then learnNext = st; break end
  end

  local diff, color = ns.Difficulty(r, rank)
  return {
    rank = rank, max = maxSkill, target = res.to,
    step = step, next = nextStep, recipe = r, difficulty = diff, color = color,
    chance = chance, triesPerPoint = chance > 0 and 1 / chance or math.huge,
    stepFrom = from, stepTo = step.to,
    stepPct = step.to > from and (rank - from) / (step.to - from) or 1,
    left = step.mean, leftSafe = step.safe, crafted = t.crafted or 0,
    mats = mats, matsOK = matsOK,
    nextMats = nextStep and (materialsFor(res, nextStep.recipe, nextStep.crafts, nextStep.safe)) or nil,
    learnNext = learnNext, learnFirst = learnFirst, learnAlso = learnAlso,
    nextRank = ns.NextRank(rank, maxSkill),
  }
end

------------------------------------------------------------ text helpers
function ns.Bar(pct, width)
  width = width or 20
  pct = math.min(1, math.max(0, pct or 0))
  local full = math.floor(pct * width + 0.5)
  return "|cff40c040" .. string.rep("|", full) .. "|r|cff444444" .. string.rep("|", width - full) .. "|r"
end

function ns.MissingSummary(mats, limit)
  local parts = {}
  for _, m in ipairs(mats) do
    if m.missing > 0 then
      table.insert(parts, m.missing .. " " .. ns.ItemName(m.id))
      if limit and #parts >= limit then break end
    end
  end
  return table.concat(parts, ", ")
end

function ns.Pct(p) return ("%d%%"):format(math.floor(p * 100 + 0.5)) end
