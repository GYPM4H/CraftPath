-- CraftPath tracker: compact card to keep on screen while crafting.
local ADDON, ns = ...
local T = ns.T

local W = 310
local Tracker = {}
ns.Tracker = Tracker
local f

---------------------------------------------------------------- shared model
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
    if nr.blocking then
      m.rank = { tone = "bad", text = ("Capped at %d - learn %s: %s"):format(rk.cap, rk.next, where) }
    elseif nr.ready then
      m.rank = { tone = "info", text = ("You can learn %s now: %s"):format(rk.next, where) }
    elseif p.rank >= rk.skill - 10 or p.stepTo > rk.cap then
      m.rank = { tone = "info", text = ("Learn %s at skill %d%s"):format(rk.next, rk.skill,
        rk.level and (", level " .. rk.level) or "") }
    end
  end
  if p.next then
    local n = p.next
    local how = n.learnHow == "known" and "known" or n.learnHow == "starter" and "starter"
      or (n.learnHow .. (n.learnCost > 0 and (" " .. ns.Money(n.learnCost, true)) or ""))
    m.nextText = ("Then %s at %d  (%s)"):format(n.recipe.name, n.from, how)
  end
  return m
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

  -- step progress
  f.step = T.Bar(f, T.C.good, 14)
  f.step:SetPoint("TOPLEFT", 12, -88)
  f.step:SetPoint("TOPRIGHT", -12, -88)

  f.lines = {}
  for i = 1, 6 do
    local fs = T.Text(f, "Small", "text")
    fs:SetWordWrap(true)
    fs:SetWidth(W - 24)
    f.lines[i] = fs
  end
  -- waypoint dots for lines that name a place
  f.pins = {}
  for i = 1, 6 do f.pins[i] = T.Pin(f, 14); f.pins[i]:Hide() end

  -- craft buttons
  f.craft = T.Button(f, "Craft", "primary", 136, 28)
  f.craft:SetScript("OnClick", function(self)
    if self.recipe then ns.CraftNow(self.recipe, 1) end
  end)
  T.Tooltip(f.craft, "Craft", function()
    local r = f.craft.recipe
    if not r then return nil end
    local s = (ns.tradeOpen == ns.Prof().key) and ("Crafts one " .. r.name .. ".")
      or ("Opens your " .. ns.ProfName() .. " window first (the game only lets addons craft while it's open), then click again to craft.")
    if ns.Prof().key == "Enchanting" then s = s .. "\n\nEnchants need a target: click the item to enchant afterwards." end
    return s
  end)
  f.craftAll = T.Button(f, "Craft all", "secondary", 136, 28)
  f.craftAll:SetPoint("LEFT", f.craft, "RIGHT", 8, 0)
  f.craftAll:SetScript("OnClick", function(self)
    if self.recipe and self.count and self.count > 0 then ns.CraftNow(self.recipe, self.count) end
  end)
  T.Tooltip(f.craftAll, "Craft all", "Crafts as many as this step still needs, limited by the materials in your bags. Moving or casting something else stops it.")

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
  for _, k in ipairs({ "icon", "name", "stats", "step" }) do f[k]:SetShown(shown) end
  f.empty:SetShown(not shown)
  if not shown then
    for _, fs in ipairs(f.lines) do fs:Hide() end
    f.craft:Hide()
    f.craftAll:Hide()
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
  local items = {}
  f.step:SetValue(m.stepPct)
  f.step.label:SetText(("%d - %d   ·   %d%%"):format(m.stepFrom, m.stepTo, math.floor(m.stepPct * 100 + 0.5)))
  if m.learnFirst then
    -- step 1 is learning the recipe
    local L = m.learnFirst
    f.stripe:SetVertexColor(unpack(T.C.accent))
    f.icon:SetIcon(L.kind == "trainer" and "Interface\\Icons\\INV_Misc_Book_09" or "Interface\\Icons\\INV_Scroll_03")
    f.name:SetText(T.Color("accent", "Learn: ") .. m.name)
    f.stats:SetText(("%s  ·  %s"):format(L.title, ns.Money(L.cost, true)))
    for i = 1, math.min(3, #L.where) do
      table.insert(items, { text = T.Color("text", L.where[i]), spot = L.spots and L.spots[i] or false })
    end
    table.insert(items, T.Muted(("Then craft it about %d times (skill %d to %d)."):format(m.left, m.stepFrom, m.stepTo)))
    if m.missing then table.insert(items, T.Color("bad", "Also buy: ") .. m.missing) end
  else
    local r, g, b = tonumber(m.color:sub(1, 2), 16) / 255, tonumber(m.color:sub(3, 4), 16) / 255, tonumber(m.color:sub(5, 6), 16) / 255
    f.stripe:SetVertexColor(r, g, b, 1)
    f.icon:SetIcon(m.recipe.make and m.recipe.make[1] or ("Interface\\Icons\\" .. (prof.icon or "")))
    f.name:SetText("|cff" .. m.color .. m.name .. "|r")
    f.stats:SetText(("%s chance  ·  about %d left %s%s"):format(
      T.Color("text", ns.Pct(m.chance)), m.left, T.Muted(("(90%%: %d)"):format(m.safe)),
      m.crafted > 0 and ("  ·  crafted " .. m.crafted) or ""))
    if m.missing then
      table.insert(items, T.Color("bad", "Missing: ") .. m.missing)
    else
      table.insert(items, T.Color("good", "Materials ready"))
    end
  end
  for _, L in ipairs(m.learnAlso) do
    table.insert(items, T.Color("accent", "Also learn " .. L.recipe.name .. ": ") .. L.title .. " " .. ns.Money(L.cost, true))
  end
  if m.rank then table.insert(items, T.Color(m.rank.tone, m.rank.text)) end
  if m.nextText then table.insert(items, T.Muted(m.nextText)) end
  local y = -110
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
  -- craft buttons (not while you still have to learn the recipe)
  local canShow = not m.learnFirst and ns.Known()[m.recipe.id] ~= nil
    or (not m.learnFirst and m.recipe.src:find("s") and not next(ns.Known()))
  f.craft:SetShown(canShow)
  f.craftAll:SetShown(canShow and ns.tradeOpen == prof.key)
  if canShow then
    f.craft.recipe, f.craftAll.recipe = m.recipe, m.recipe
    f.craft:ClearAllPoints()
    f.craft:SetPoint("TOPLEFT", 12, y - 4)
    -- alone ("Open Blacksmithing") it spans the card; with "Craft N" they share it
    f.craft:SetWidth(ns.tradeOpen == prof.key and math.floor((W - 24 - 8) / 2) or (W - 24))
    f.craftAll:SetWidth(math.floor((W - 24 - 8) / 2))
    if ns.tradeOpen ~= prof.key then
      f.craft:SetText("Open " .. ns.ProfName(prof))
      f.craft:Enable()
    else
      local n = ns.CanCraft(m.recipe)
      local want = math.max(1, m.left)
      local count = n and math.min(n, want) or want
      f.craftAll.count = count
      if n == 0 then
        f.craft:SetText("No materials")
        f.craft:Disable()
        f.craftAll:SetText("Craft all")
        f.craftAll:Disable()
      else
        f.craft:SetText("Craft")
        f.craft:Enable()
        f.craftAll:SetText(("Craft %d"):format(count))
        f.craftAll:Enable()
      end
    end
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
  if f.step:IsShown() then table.insert(out, f.step.label:GetText() or "") end
  for i, fs in ipairs(f.lines) do
    if fs:IsShown() then table.insert(out, (f.pins[i]:IsShown() and "(pin) " or "") .. (fs:GetText() or "")) end
  end
  for _, b in ipairs({ f.craft, f.craftAll }) do
    if b:IsShown() then table.insert(out, "[" .. (b:GetText() or "") .. (b:IsEnabled() and "" or " (disabled)") .. "]") end
  end
  return table.concat(out, "\n")
end
