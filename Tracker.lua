-- CraftPath tracker: compact card to keep on screen while crafting.
local ADDON, ns = ...
local T = ns.T

local W = 310
local Tracker = {}
ns.Tracker = Tracker
local f

---------------------------------------------------------------- shared model
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t "
local SHORT = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t "

-- Materials as a have/need checklist: "✓ Iron Bar  64/64" (bags + bank).
-- An item you'd craft yourself (cheaper than buying) says so.
function ns.Checklist(mats)
  local out = {}
  for _, mat in ipairs(mats or {}) do
    local have = (mat.have or 0) + (mat.bank or 0)
    local ok = (mat.missing or 0) <= 0
    local count = ("%d/%d"):format(math.min(have, mat.need), mat.need)
    local line = (ok and READY or SHORT) .. ns.ItemName(mat.id) .. "  " .. T.Color(ok and "good" or "bad", count)
    if not ok and mat.craft then line = line .. T.Muted("  craft " .. mat.craft.n) end
    table.insert(out, line)
  end
  return out
end
-- What the tracker and the main window's "Now" card show.
function ns.NowModel(p)
  local m = {
    recipe = p.recipe, name = p.recipe.name, color = p.color, diff = p.difficulty,
    chance = p.chance, tries = p.triesPerPoint,
    left = math.ceil(p.left - 1e-9), safe = p.leftSafe, crafted = p.crafted,
    stepFrom = p.stepFrom, stepTo = p.stepTo, stepPct = p.stepPct,
    learn = p.step.learnHow,
    learnFirst = p.learnFirst, learnAlso = p.learnAlso or {},
  }
  m.from = math.max(p.rank or p.stepFrom, p.stepFrom)
  m.checklist = ns.Checklist(p.mats)
  if not p.matsOK then
    local n = 0
    for _, mat in ipairs(p.mats) do if mat.missing > 0 then n = n + 1 end end
    m.missing = ns.MissingSummary(p.mats, 3)
    m.missingCount = n
  end
  local nr = p.nextRank
  if nr then
    local rk = nr.rank
    local where = rk.how or (nr.trainers[1] and (nr.trainers[1].name .. ", " .. nr.trainers[1].zone)) or "a trainer"
    local L = m.learnFirst
    if L and L.kind == "trainer" and not rk.how and (nr.blocking or nr.ready) then
      -- learning the recipe at a trainer anyway: list trainers who teach both,
      -- and don't name them twice
      local spots = ns.TrainerSpots(math.max(L.tier or 1, rk.tier or 1), 3, L.recipe and L.recipe.id)
      local copy = {}
      for k, v in pairs(L) do copy[k] = v end
      copy.where, copy.spots = {}, spots
      for _, t in ipairs(spots) do table.insert(copy.where, t.name .. ", " .. t.zone) end
      m.learnFirst = copy
      where = nil
    end
    if nr.blocking then
      m.rank = { tone = "bad", text = where and ("Capped at %d - learn %s: %s"):format(rk.cap, rk.next, where)
        or ("Capped at %d - learn %s there too"):format(rk.cap, rk.next) }
    elseif nr.ready then
      m.rank = { tone = "info", text = where and ("You can learn %s now: %s"):format(rk.next, where)
        or ("Learn %s there too"):format(rk.next) }
    elseif p.rank >= rk.skill - 10 or p.stepTo > rk.cap then
      m.rank = { tone = "info", text = ("Learn %s at skill %d%s"):format(rk.next, rk.skill,
        rk.level and (", level " .. rk.level) or "") }
    end
  end
  -- learning step: the places are the message; only a cap (red) adds to it
  if m.learnFirst and m.rank and m.rank.tone ~= "bad" then m.rank = nil end
  if p.next then
    local n = p.next
    local how = n.learnHow == "known" and "known" or n.learnHow == "starter" and "starter"
      or (n.learnHow .. (n.learnCost > 0 and (" " .. ns.Money(n.learnCost, true)) or ""))
    m.nextText = ("Then %s at %d  (%s)"):format(n.recipe.name, n.from, how)
  end
  return m
end

-- The detail behind "about N crafts left", for tooltips.
function ns.NowTip(m)
  return ("Skill-up chance: %s (about %.1f crafts per point).\nAbout %d crafts on average; %d covers 9 in 10 players."):format(
    ns.Pct(m.chance), m.tries, m.left, m.safe)
end

---------------------------------------------------------------- crafting
-- Crafting needs the profession's window open (the game's rule for addons).
-- The button opens it first if needed, then crafts on the next click.
local function modernTS() return C_TradeSkillUI and C_TradeSkillUI.CraftRecipe and true or false end

local function classicIndex(recipe)
  if not GetNumTradeSkills then return nil end
  for i = 1, GetNumTradeSkills() do
    local name, kind, avail = GetTradeSkillInfo(i)
    if kind ~= "header" and name == recipe.name then return i, avail or 0 end
  end
end

-- How many you can make with what's in your bags (nil if unknown).
function ns.CanCraft(recipe)
  if ns.tradeOpen ~= ns.Prof().key then return nil end
  if modernTS() then
    local info = C_TradeSkillUI.GetRecipeInfo(recipe.id)
    return info and info.numAvailable or nil
  end
  local _, avail = classicIndex(recipe)
  return avail
end

function ns.OpenProfession()
  local prof = ns.Prof()
  if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
    local ok = pcall(C_TradeSkillUI.OpenTradeSkill, prof.skillLine)
    if ok then return true end
  end
  ns.Print(("Open your %s window, then press Craft."):format(ns.ProfName(prof)))
  return false
end

function ns.CraftNow(recipe, count)
  if InCombatLockdown and InCombatLockdown() then
    ns.Print("Can't craft in combat.")
    return
  end
  if ns.tradeOpen ~= ns.Prof().key then
    ns.OpenProfession()
    return
  end
  count = math.max(1, count or 1)
  if modernTS() then
    C_TradeSkillUI.CraftRecipe(recipe.id, count)
  else
    local i = classicIndex(recipe)
    if not i then return ns.Print(recipe.name .. " isn't in your profession window.") end
    DoTradeSkill(i, count)
  end
end

-- What the main craft button should say: "Open Blacksmithing", "Craft 8",
-- "No materials". nil when you can't craft this recipe yet.
function ns.CraftAction(m)
  if m.learnFirst then return nil end
  local known = ns.Known()[m.recipe.id] ~= nil or (m.recipe.src:find("s") and not next(ns.Known()))
  if not known then return nil end
  if ns.tradeOpen ~= ns.Prof().key then
    return { text = "Open " .. ns.ProfName(ns.Prof()), enabled = true, count = 0 }
  end
  local n = ns.CanCraft(m.recipe)
  local want = math.max(1, m.left)
  local count = n and math.min(n, want) or want
  if n == 0 then return { text = "No materials", enabled = false, count = 0 } end
  return { text = ("Craft %d"):format(count), enabled = true, count = count }
end

function ns.DoCraftAction(m)
  local a = m and ns.CraftAction(m)
  if not a or not a.enabled then return end
  if a.count == 0 then ns.OpenProfession() else ns.CraftNow(m.recipe, a.count) end
end

---------------------------------------------------------------- frame
local function create()
  f = T.Panel(UIParent, { 0.071, 0.078, 0.094, 0.92 }, T.C.border, "Button")
  f:SetSize(W, 160)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("RightButtonUp")
  _G.CraftPathTracker = f
  local pos = ns.settings.trackerPos
  if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("RIGHT", -80, 80) end
  f:SetScript("OnDragStart", function(self) if not ns.settings.trackerLocked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    ns.settings.trackerPos = { point, x, y }
  end)
  f:SetScript("OnClick", function() ns.UI:Toggle() end) -- right-click: planner
  T.Tooltip(f, "CraftPath", "Drag to move - right-click opens the planner.")

  -- left stripe in the difficulty color
  f.stripe = T.Fill(f, T.C.accent, "ARTWORK")
  f.stripe:SetPoint("TOPLEFT", 1, -1)
  f.stripe:SetPoint("BOTTOMLEFT", 1, 1)
  f.stripe:SetWidth(3)

  -- header: profession + skill
  f.profIcon = f:CreateTexture(nil, "ARTWORK")
  f.profIcon:SetSize(16, 16)
  f.profIcon:SetPoint("TOPLEFT", 12, -10)
  f.profIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.prof = T.Text(f, "Small", "muted")
  f.prof:SetPoint("LEFT", f.profIcon, "RIGHT", 6, 0)
  f.skill = T.Text(f, "Small", "text", "RIGHT")
  f.skill:SetPoint("TOPRIGHT", -30, -11)
  f.close = T.CloseButton(f)
  f.close:SetPoint("TOPRIGHT", -8, -9)
  f.close:SetScript("OnClick", function() Tracker:Hide() end)

  f.total = T.Bar(f, T.C.info, 3)
  f.total:SetPoint("TOPLEFT", 12, -32)
  f.total:SetPoint("TOPRIGHT", -12, -32)
  f.total.label:Hide()

  -- recipe
  f.icon = T.Icon(f, 34)
  f.icon:SetPoint("TOPLEFT", 12, -44)
  f.name = T.Text(f, "Header", "text")
  f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -1)
  f.name:SetPoint("RIGHT", -12, 0)
  f.stats = T.Text(f, "Small", "muted")
  f.stats:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
  f.stats:SetPoint("RIGHT", -12, 0)

  f.lines = {}
  for i = 1, 9 do
    local fs = T.Text(f, "Small", "text")
    fs:SetWordWrap(true)
    fs:SetWidth(W - 24)
    f.lines[i] = fs
  end
  -- waypoint dots for lines that name a place
  f.pins = {}
  for i = 1, 9 do f.pins[i] = T.Pin(f, 14); f.pins[i]:Hide() end

  -- the main action (same as the planner's: Open <Prof> / Craft N)
  f.craft = T.Button(f, "Craft", "primary", W - 24, 28)
  f.craft:SetScript("OnClick", function() ns.DoCraftAction(f.model); Tracker:Render() end)
  T.Tooltip(f.craft, "Craft", function()
    local a = f.model and ns.CraftAction(f.model)
    if not a then return nil end
    local s = (a.count == 0 and a.enabled)
      and "Opens your profession window first (the game only lets addons craft while it's open), then click again to craft."
      or "Crafts as many as this step still needs, limited by the materials in your bags. Moving or casting something else stops it."
    if ns.Prof().key == "Enchanting" then s = s .. "\n\nEnchants need a target: click the item to enchant afterwards." end
    return s
  end)

  f.empty = T.Text(f, "Body", "muted")
  f.empty:SetPoint("TOPLEFT", 12, -46)
  f.empty:SetWidth(W - 24)
  f.empty:SetWordWrap(true)
end

function Tracker:IsShown() return f and f:IsShown() end

function Tracker:Show()
  if not f then create() end
  ns.settings.showTracker = true
  f:Show()
  ns.Compute()
  self:Render()
end

function Tracker:Hide()
  ns.settings.showTracker = false
  if f then f:Hide() end
end

function Tracker:Toggle()
  if self:IsShown() then self:Hide() else self:Show() end
end

function Tracker:Render()
  if not f or not f:IsShown() then return end
  local prof = ns.Prof()
  local rank, maxSkill = ns.ReadSkill()
  local target = ns.Target()
  f.profIcon:SetTexture("Interface\\Icons\\" .. (prof.icon or "INV_Misc_QuestionMark"))
  f.prof:SetText(ns.ProfName(prof))
  f.skill:SetText(("%s / %d"):format(rank or "?", target))
  f.total:SetValue(rank and rank / target or 0)

  local p = ns.Progress()
  local shown = p ~= nil
  for _, k in ipairs({ "icon", "name", "stats" }) do f[k]:SetShown(shown) end
  f.empty:SetShown(not shown)
  if not shown then
    for _, fs in ipairs(f.lines) do fs:Hide() end
    f.craft:Hide()
    f.model = nil
    for _, pin in ipairs(f.pins) do pin:SetSpot(nil) end
    f.stripe:SetVertexColor(unpack(T.C.border))
    if ns.needsScan then
      f.empty:SetText("Scan the Auction House to get your route.\n" .. T.Muted("Open the AH and press Scan in CraftPath (/cpath)."))
    else
      f.empty:SetText(ns.computeError or "Open the planner (/cpath) to build a route.")
    end
    f:SetHeight(46 + f.empty:GetStringHeight() + 14)
    return
  end

  local m = ns.NowModel(p)
  f.model = m
  local items = {}
  if m.learnFirst then
    -- step 1 is learning the recipe
    local L = m.learnFirst
    f.stripe:SetVertexColor(unpack(T.C.text))
    f.icon:SetIcon(L.kind == "trainer" and "Interface\\Icons\\INV_Misc_Book_09" or "Interface\\Icons\\INV_Scroll_03")
    f.name:SetText("Learn: " .. m.name)
    f.stats:SetText(("%s  ·  %s"):format(L.title, L.cost > 0 and ns.Money(L.cost, true) or "free"))
    table.insert(items, T.Color("info", "Learn it from:"))
    for i = 1, math.min(3, #L.where) do
      table.insert(items, { text = L.where[i], spot = L.spots and L.spots[i] or false })
    end
  else
    local r, g, b = tonumber(m.color:sub(1, 2), 16) / 255, tonumber(m.color:sub(3, 4), 16) / 255, tonumber(m.color:sub(5, 6), 16) / 255
    f.stripe:SetVertexColor(r, g, b, 1)
    f.icon:SetIcon(m.recipe.make and m.recipe.make[1] or ("Interface\\Icons\\" .. (prof.icon or "")))
    f.name:SetText("|cff" .. m.color .. m.name .. "|r")
    f.stats:SetText(("Skill %d to %d  ·  about %d crafts left"):format(m.from, m.stepTo, m.left))
  end
  if m.rank then table.insert(items, T.Color(m.rank.tone, m.rank.text)) end
  -- materials only once you can craft it
  if not m.learnFirst then
    for _, line in ipairs(m.checklist) do table.insert(items, line) end
  end
  for _, L in ipairs(m.learnAlso) do
    table.insert(items, "Also learn " .. L.recipe.name .. ": " .. L.title .. " " .. ns.Money(L.cost, true))
  end
  local y = -84
  for i, fs in ipairs(f.lines) do
    local item = items[i]
    local pin = f.pins[i]
    pin:SetSpot(nil)
    if item then
      local text, spot = item, nil
      if type(item) == "table" then text, spot = item.text, item.spot end
      local x = 12
      if spot ~= nil then
        -- a place: bullet line, the dot sets a waypoint when we know where it is
        pin:ClearAllPoints()
        pin:SetPoint("TOPLEFT", 10, y + 1)
        pin:SetSpot(spot or nil)
        if not pin:IsShown() then text = T.Muted("- ") .. text end
        x = 28
      end
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", x, y)
      fs:SetWidth(W - 12 - x)
      fs:SetText(text)
      fs:Show()
      y = y - (fs:GetStringHeight() or 13) - 4
    else
      fs:Hide()
    end
  end
  local a = ns.CraftAction(m)
  f.craft:SetShown(a ~= nil)
  if a then
    f.craft:ClearAllPoints()
    f.craft:SetPoint("TOPLEFT", 12, y - 4)
    f.craft:SetText(a.text)
    f.craft:SetEnabled(a.enabled)
    y = y - 4 - 28 - 6
  end
  f:SetHeight(-y + 8)
end

-- plain text of what the tracker shows (for tests / debugging)
function Tracker:Text()
  if not f then return "" end
  local out = { f.prof:GetText() or "", f.skill:GetText() or "" }
  for _, k in ipairs({ "name", "stats", "empty" }) do
    if f[k]:IsShown() then table.insert(out, f[k]:GetText() or "") end
  end
  for i, fs in ipairs(f.lines) do
    if fs:IsShown() then table.insert(out, (f.pins[i]:IsShown() and "(pin) " or "") .. (fs:GetText() or "")) end
  end
  for _, b in ipairs({ f.craft }) do
    if b:IsShown() then table.insert(out, "[" .. (b:GetText() or "") .. (b:IsEnabled() and "" or " (disabled)") .. "]") end
  end
  return table.concat(out, "\n")
end
