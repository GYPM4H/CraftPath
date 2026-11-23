-- CraftPath main window.
--   header:   title, profession dropdown, options, close
--   controls: target skill, planning mode, tracker toggle
--   now card: current craft, crafts left, have/need checklist, Craft button
--   tabs:     Route / Shopping / Trainers (table rows)
--   footer:   totals, scan status, Scan AH / Full scan
local ADDON, ns = ...
local T = ns.T

local W, H = 820, 760
local PAD = 16
local MODES = {
  { "balanced", "Balanced", "Least gold, weighing each craft as worth some of your time (/cpath value <gold>)." },
  { "cheap", "Cheapest", "Least gold, even if it takes many more crafts." },
  { "fast", "Fastest", "Fewest crafts, whatever it costs." },
}
local MODE_LABEL = { balanced = "Balanced", cheap = "Cheapest", fast = "Fastest" }

local f

local function profIcon(prof)
  return "Interface\\Icons\\" .. ((prof and prof.icon) or "INV_Misc_QuestionMark")
end

---------------------------------------------------------------- options popover
local function createOptions(anchor)
  local o = T.Panel(f, T.C.panel, T.C.border)
  o:SetSize(300, 300)
  o:SetFrameStrata("DIALOG")
  o:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 6, -8)
  o:EnableMouse(true)
  o:Hide()
  local title = T.Text(o, "Header", "text")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("Options")

  local s = function() return ns.settings end
  local items = {
    { "Sell crafts to vendor", function() return s().sellBack end, function(v) s().sellBack = v; ns.Refresh() end,
      "Subtract the vendor sell value of what you craft from the cost." },
    { "Use Auctionator prices", function() return s().useAuctionator end, function(v) s().useAuctionator = v; ns.Refresh() end,
      "Use Auctionator's prices when your own CraftPath scan is older than 2 days, or before your first scan." },
    { "Count quest recipes", function() return s().allowQuest end, function(v) s().allowQuest = v; ns.Refresh() end,
      "Treat recipes that are quest rewards as obtainable (for free)." },
    { "Show tracker", function() return ns.Tracker:IsShown() end, function(v) if v then ns.Tracker:Show() else ns.Tracker:Hide() end end,
      "The small progress card you keep on screen while crafting." },
    { "Lock tracker position", function() return s().trackerLocked end, function(v) s().trackerLocked = v end },
    { "Show minimap button", function() return not ns.db.minimap.hide end, function(v) ns.Minimap:SetShown(v) end },
  }
  o.toggles = {}
  for i, it in ipairs(items) do
    local t = T.Toggle(o, it[1], it[2], it[3], it[4])
    t:SetPoint("TOPLEFT", 14, -40 - (i - 1) * 28)
    o.toggles[i] = t
  end
  local sizeLabel = T.Text(o, "Small", "muted")
  sizeLabel:SetPoint("TOPLEFT", 14, -40 - #items * 28 - 8)
  sizeLabel:SetText("TEXT SIZE")
  o.size = T.Segmented(o, { { 1, "Normal" }, { 1.15, "Large" }, { 1.3, "Larger" } },
    function() return s().fontScale end,
    function(v) s().fontScale = v; T.ApplyFontScale(); f:Render(); ns.Tracker:Render() end, 90)
  o.size:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -6)
  o:SetHeight(40 + #items * 28 + 8 + 16 + 26 + 18)
  function o:Refresh()
    for _, t in ipairs(self.toggles) do t:Refresh() end
    self.size:Refresh()
  end
  return o
end

---------------------------------------------------------------- first-scan screen
local function createOnboarding(parent)
  local o = CreateFrame("Frame", nil, parent)
  o:SetAllPoints()
  o.icon = T.Icon(o, 56)
  o.icon:SetPoint("TOP", 0, -46)
  o.icon:SetIcon("Interface\\Icons\\INV_Misc_Coin_01")
  o.title = T.Text(o, "Title", "text", "CENTER")
  o.title:SetPoint("TOP", o.icon, "BOTTOM", 0, -16)
  o.title:SetText("Scan the Auction House first")
  o.body = T.Text(o, "Body", "muted", "CENTER")
  o.body:SetWordWrap(true)
  o.body:SetWidth(520)
  o.body:SetPoint("TOP", o.title, "BOTTOM", 0, -10)
  o.button = T.Button(o, "Scan now", "primary", 200, 34)
  o.button:SetPoint("TOP", o.body, "BOTTOM", 0, -20)
  o.button:SetScript("OnClick", function() ns.Prices:StartScan(nil, "full"); f:Render() end)
  o.hint = T.Text(o, "Small", "muted", "CENTER")
  o.hint:SetWordWrap(true)
  o.hint:SetWidth(520)
  o.hint:SetPoint("TOP", o.button, "BOTTOM", 0, -14)
  function o:Refresh()
    local wait = ns.Prices:FastScanIn()
    if wait == 0 then
      self.body:SetText("CraftPath plans with real prices from your realm. Go to an auctioneer and press Scan now - "
        .. "it downloads the whole Auction House at once (10-30 seconds) and prices all your professions.")
    else
      local n = 0
      for _ in pairs(ns.ScanListAll("full")) do n = n + 1 end
      self.body:SetText(("CraftPath plans with real prices from your realm. Go to an auctioneer and press Scan now - the first scan checks every material of all your professions (about %d searches, a few minutes)."):format(n))
    end
    if ns.Prices.scanning then
      self.button:SetText("Scanning...")
      self.button:Disable()
    elseif ns.neutralAH then
      self.button:SetText("Neutral AH - not scanned")
      self.button:Disable()
    elseif ns.atAH then
      self.button:SetText("Scan now")
      self.button:Enable()
    else
      self.button:SetText("Open the Auction House")
      self.button:Disable()
    end
    self.hint:SetText("Have Auctionator? Its prices are used automatically as soon as it has scanned.")
  end
  return o
end

---------------------------------------------------------------- window
local function create()
  f = T.Panel(UIParent, T.C.bg, T.C.border)
  _G.CraftPathFrame = f
  f:SetSize(W, H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()
  table.insert(UISpecialFrames, "CraftPathFrame") -- Escape closes it

  -- header ------------------------------------------------------------------
  f.logo = T.Icon(f, 30)
  f.logo:SetPoint("TOPLEFT", PAD, -12)
  f.logo:SetIcon("Interface\\AddOns\\CraftPath\\Media\\Icon")
  f.logo.tex:SetTexCoord(0, 1, 0, 1)
  f.title = T.Text(f, "Title", "text")
  f.title:SetPoint("LEFT", f.logo, "RIGHT", 10, 0)
  f.title:SetText("CraftPath")

  f.close = T.CloseButton(f)
  f.close:SetPoint("TOPRIGHT", -PAD, -19)
  f.close:SetScript("OnClick", function() f:Hide() end)

  f.gear = T.IconButton(f, "Interface\\Buttons\\UI-OptionsButton", 18)
  f.gear:SetPoint("RIGHT", f.close, "LEFT", -12, 0)
  T.Tooltip(f.gear, "Options")

  f.prof = T.Dropdown(f, 240,
    function()
      local list, owned = ns.ProfessionList()
      local out = {}
      for _, key in ipairs(list) do
        local o = owned[key]
        table.insert(out, { value = key, label = key, icon = profIcon(ns.Professions[key]),
          right = o and (o.rank .. " / " .. o.max) or "not learned", dim = not o })
      end
      return out
    end,
    function() return ns.Prof().key end,
    function(key) ns.SetProfession(key); f:Render() end)
  f.prof:SetPoint("RIGHT", f.gear, "LEFT", -14, 0)

  local rule = T.Fill(f, T.C.border, "ARTWORK")
  rule:SetPoint("TOPLEFT", 1, -54)
  rule:SetPoint("TOPRIGHT", -1, -54)
  rule:SetHeight(1)

  f.options = createOptions(f.gear)
  f.gear:SetScript("OnClick", function()
    if f.options:IsShown() then f.options:Hide() else f.options:Refresh(); f.options:Show() end
  end)

  -- controls ----------------------------------------------------------------
  local targetLabel = T.Text(f, "Small", "muted")
  targetLabel:SetPoint("TOPLEFT", PAD, -72)
  targetLabel:SetText("TARGET")
  f.target = T.Input(f, 60, true)
  f.target:SetPoint("LEFT", targetLabel, "RIGHT", 10, 0)
  f.target:SetMaxLetters(3)
  local function applyTarget(self)
    local v = tonumber(self:GetText())
    if v then ns.SetTarget(v) end
    self:SetText(ns.Target())
    self:ClearFocus()
    ns.Refresh()
  end
  f.target:SetScript("OnEnterPressed", applyTarget)
  f.target:HookScript("OnEditFocusLost", applyTarget)
  f.target:SetScript("OnEscapePressed", function(self) self:SetText(ns.Target()); self:ClearFocus() end)

  local modeLabel = T.Text(f, "Small", "muted")
  modeLabel:SetPoint("LEFT", f.target, "RIGHT", 28, 0)
  modeLabel:SetText("MODE")
  f.mode = T.Segmented(f, MODES, function() return ns.settings.mode end,
    function(v) ns.settings.mode = v; ns.Refresh() end, 96)
  f.mode:SetPoint("LEFT", modeLabel, "RIGHT", 10, 0)


  -- now card ----------------------------------------------------------------
  -- One job: what to craft now, how many, and what you still need.
  local CARD_H = 196
  local card = T.Panel(f, T.C.panel, T.C.border)
  card:SetPoint("TOPLEFT", PAD, -100)
  card:SetPoint("TOPRIGHT", -PAD, -100)
  card:SetHeight(CARD_H)
  card:EnableMouse(true)
  f.card = card

  card.icon = T.Icon(card, 46)
  card.icon:SetPoint("TOPLEFT", 14, -14)
  card.kicker = T.Text(card, "Tiny", "muted")
  card.kicker:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, 0)
  card.name = T.Text(card, "Big", "text")
  card.name:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -3)
  card.name:SetPoint("RIGHT", -150, 0)
  card.sub = T.Text(card, "Body", "text")
  card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
  card.sub:SetPoint("RIGHT", -150, 0)

  -- overall progress: the one place your skill is shown
  card.skill = T.Text(card, "Title", "text", "RIGHT")
  card.skill:SetPoint("TOPRIGHT", -14, -18)
  card.total = T.Bar(card, T.C.info, 4)
  card.total:SetPoint("TOPLEFT", 14, -72)
  card.total:SetPoint("TOPRIGHT", -14, -72)
  card.total.label:Hide()
  T.Tooltip(card, function() return card.tipTitle or "" end, function() return card.tip end)

  -- left: have/need checklist (+ one notice line)
  card.lines = {}
  for i = 1, 5 do
    local fs = T.Text(card, "Body", "text")
    fs:SetPoint("TOPLEFT", 16, -88 - (i - 1) * 20)
    fs:SetPoint("RIGHT", card, "LEFT", 470, 0)
    card.lines[i] = fs
  end

  -- right: where to learn it (learn first), one place per line, dot = waypoint
  card.spotsTitle = T.Text(card, "Body", "info")
  card.spotsTitle:SetPoint("TOPLEFT", 480, -88)
  card.spotsTitle:SetText("Learn it from:")
  card.spots = {}
  for i = 1, 3 do
    local sp = CreateFrame("Frame", nil, card)
    sp:SetHeight(18)
    sp:SetPoint("TOPLEFT", 480, -110 - (i - 1) * 20)
    sp:SetPoint("RIGHT", -14, 0)
    sp.pin = T.Pin(sp, 14)
    sp.pin:SetPoint("LEFT", -4, 0)
    sp.text = T.Text(sp, "Small", "text")
    sp.text:SetPoint("LEFT", 16, 0)
    sp.text:SetPoint("RIGHT")
    card.spots[i] = sp
  end

  -- the main action
  card.craft = T.Button(card, "Craft", "primary", 200, 32)
  card.craft:SetPoint("BOTTOMRIGHT", -14, 14)
  card.craft:SetScript("OnClick", function() ns.DoCraftAction(card.model); f:Render() end)
  T.Tooltip(card.craft, "Craft", function()
    local a = card.model and ns.CraftAction(card.model)
    if not a then return nil end
    if a.count == 0 and a.enabled then
      return "Opens your profession window first (the game only lets addons craft while it's open), then click again to craft."
    end
    return "Crafts as many as this step still needs, limited by the materials in your bags. Moving or casting something else stops it."
  end)

  card.empty = T.Text(card, "Body", "muted", "CENTER")
  card.empty:SetPoint("CENTER")
  card.empty:SetWordWrap(true)
  card.empty:SetWidth(W - 120)

  -- tabs + content ------------------------------------------------------------
  f.tabs = T.Tabs(f, { { "plan", "Route" }, { "shop", "Shopping" }, { "train", "Trainers" } },
    function() return ns.settings.tab end,
    function(v) ns.settings.tab = v; f:Render() end)
  f.tabs:SetPoint("TOPLEFT", PAD, -100 - CARD_H - 10)
  f.tabs:SetPoint("TOPRIGHT", -PAD, -100 - CARD_H - 10)

  local area = CreateFrame("Frame", nil, f)
  area:SetPoint("TOPLEFT", PAD, -100 - CARD_H - 46)
  area:SetPoint("BOTTOMRIGHT", -PAD, 104)
  f.area = area

  local scroll = CreateFrame("ScrollFrame", nil, area)
  scroll:SetAllPoints()
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxY = math.max(0, (self.child:GetHeight() or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.min(maxY, math.max(0, self:GetVerticalScroll() - delta * 60)))
  end)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(W - PAD * 2, 10)
  scroll:SetScrollChild(child)
  scroll.child = child
  f.scroll = scroll
  f.rows = T.Rows(child, W - PAD * 2)
  f.onboarding = createOnboarding(area)

  -- footer --------------------------------------------------------------------
  local frule = T.Fill(f, T.C.border, "ARTWORK")
  frule:SetPoint("BOTTOMLEFT", 1, 96)
  frule:SetPoint("BOTTOMRIGHT", -1, 96)
  frule:SetHeight(1)

  -- row 1: the total (breakdown on hover)
  f.totalText = T.Text(f, "Header", "text")
  f.totalText:SetPoint("BOTTOMLEFT", PAD, 68)
  f.totalHit = CreateFrame("Frame", nil, f)
  f.totalHit:SetPoint("TOPLEFT", f.totalText, "TOPLEFT", -4, 4)
  f.totalHit:SetPoint("BOTTOMRIGHT", f.totalText, "BOTTOMRIGHT", 4, -4)
  f.totalHit:EnableMouse(true)
  f.totalHit:SetScript("OnEnter", function(self) if f.totalTip then T.ShowHover(self, "Route cost", f.totalTip) end end)
  f.totalHit:SetScript("OnLeave", function() T.HideHover() end)

  -- row 2: scan status + scan buttons
  local brule = T.Fill(f, T.C.border, "ARTWORK")
  brule:SetPoint("BOTTOMLEFT", PAD, 56)
  brule:SetPoint("BOTTOMRIGHT", -PAD, 56)
  brule:SetHeight(1)

  local function ahHint()
    if ns.Prices.scanning then return "" end
    if ns.neutralAH then
      return "\n\n|cffff9966This is a neutral Auction House.|r Its listings are separate from your faction's, "
        .. "so CraftPath doesn't scan here. Scan at your faction's Auction House instead."
    end
    if ns.atAH then return "" end
    return "\n\n|cffff9966Open the Auction House to use this.|r"
  end

  f.scan = T.Button(f, "Scan AH", "primary", 130, 34)
  f.scan:SetPoint("BOTTOMRIGHT", -PAD, 12)
  f.scan:SetScript("OnClick", function()
    if ns.Prices.scanning then ns.Prices:StopScan() else ns.Prices:StartScan() end
    f:Render()
  end)
  local function profList()
    local names = {}
    for _, key in ipairs(ns.ScanProfessions()) do table.insert(names, ns.ProfName(ns.Professions[key])) end
    return table.concat(names, ", ")
  end
  local function fastLine()
    local wait = ns.Prices:FastScanIn()
    if not wait then return "" end
    if wait == 0 then
      return "\n\n|cff66dd66Fast scan ready:|r downloads the whole Auction House in one go (10-30 seconds) and prices everything at once."
    end
    return ("\n\n|cffffcc66Fast scan available again in %d min|r (the server allows it once every 15 minutes). Until then this scans item by item."):format(math.ceil(wait / 60))
  end

  T.Tooltip(f.scan, "Scan AH  -  price update", function()
    return "Updates prices for all your professions: " .. profList() .. ".\n\n"
      .. "Uses the fast whole-AH scan when it's ready. Otherwise it looks up only the materials your best routes use, "
      .. "re-plans, and checks anything new the route needs, until the route stops changing."
      .. fastLine() .. ahHint()
  end)

  f.fullScan = T.Button(f, "Full scan", "secondary", 110, 34)
  f.fullScan:SetPoint("RIGHT", f.scan, "LEFT", -10, 0)
  f.fullScan:SetScript("OnClick", function()
    if ns.Prices.scanning then ns.Prices:StopScan() else ns.Prices:StartScan(nil, "full") end
    f:Render()
  end)
  T.Tooltip(f.fullScan, "Full scan  -  every material", function()
    local n = 0
    for _ in pairs(ns.ScanListAll("full")) do n = n + 1 end
    return ("Prices every material of every recipe in all your professions (%s, %d items). "):format(profList(), n)
      .. "This finds cheap items on recipes the route doesn't use yet, which can open up a cheaper route.\n\n"
      .. "Uses the fast whole-AH scan when it's ready. Otherwise it searches item by item, which takes a few minutes."
      .. fastLine() .. ahHint()
  end)

  f.status = T.Text(f, "Small", "muted", "LEFT")
  f.status:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, 29)
  f.status:SetPoint("RIGHT", f.fullScan, "LEFT", -16, 0)
  f.status:SetWordWrap(true)

  f:SetScript("OnShow", function() ns.Compute(); f:Render() end)
  f:SetScript("OnHide", function() f.options:Hide(); f.prof.list:Hide() end)

  ------------------------------------------------------------------ render
  function f:RenderStatus()
    local msg = ns.status
    if not msg then
      msg = "Open the Auction House to scan prices."
      if ns.neutralAH then
        msg = ns.NEUTRAL_MSG
      elseif ns.atAH then
        local wait = ns.Prices:FastScanIn()
        msg = wait == 0 and "Ready: fast scan prices all your professions at once."
          or wait and ("Fast scan ready in %d min. Scan AH checks route items one by one."):format(math.ceil(wait / 60))
          or "Ready to scan."
      end
      if not ns.atAH and not ns.needsScan then
        local own, auc = ns.Prices:Coverage()
        if own == 0 and auc > 0 then msg = "Using Auctionator prices. Scan at the AH for fresher ones." end
      end
    end
    self.status:SetText(msg)
  end

  function f:RenderCard(p, rank, maxSkill)
    local c = self.card
    local target = ns.Target()
    c.skill:SetText(("%s / %d"):format(rank or "?", target))
    c.total:SetValue(rank and rank / target or 0)
    c.model, c.tip, c.tipTitle = nil, nil, nil
    local shown = p ~= nil
    for _, k in ipairs({ "icon", "kicker", "name", "sub" }) do c[k]:SetShown(shown) end
    c.empty:SetShown(not shown)
    if not shown then
      for _, fs in ipairs(c.lines) do fs:Hide() end
      for _, sp in ipairs(c.spots) do sp:Hide() end
      c.spotsTitle:Hide()
      c.craft:Hide()
      if ns.needsScan then
        c.empty:SetText("Waiting for prices - see below.")
      else
        c.empty:SetText(ns.computeError or "No route yet.")
      end
      return
    end
    local m = ns.NowModel(p)
    c.model = m
    local prof = ns.Prof()
    local L = m.learnFirst
    local lines = {}
    if L then
      c.kicker:SetText("LEARN FIRST")
      c.icon:SetIcon(L.kind == "trainer" and "Interface\\Icons\\INV_Misc_Book_09" or "Interface\\Icons\\INV_Scroll_03")
      c.name:SetText(m.name)
      c.sub:SetText(("%s  ·  %s"):format(L.title, L.cost > 0 and ns.Money(L.cost, true) or "free"))
    else
      c.kicker:SetText("CRAFT NOW")
      c.icon:SetIcon(m.recipe.make and m.recipe.make[1] or profIcon(prof))
      c.name:SetText("|cff" .. m.color .. m.name .. "|r")
      c.sub:SetText(("Skill %d to %d  ·  about %d crafts left"):format(m.from, m.stepTo, m.left))
      c.tipTitle, c.tip = m.name, ns.NowTip(m)
    end
    if m.rank then table.insert(lines, T.Color(m.rank.tone, m.rank.text)) end
    if not L then
      for _, line in ipairs(m.checklist) do table.insert(lines, line) end
    end
    for _, A in ipairs(m.learnAlso) do
      table.insert(lines, ("Also learn %s: %s %s"):format(A.recipe.name, A.title, ns.Money(A.cost, true)))
    end
    for i, fs in ipairs(c.lines) do
      fs:SetText(lines[i] or "")
      fs:SetShown(lines[i] ~= nil)
    end
    -- learn first: where, on the right
    local spots = L and L.where or {}
    c.spotsTitle:SetShown(#spots > 0)
    for i, sp in ipairs(c.spots) do
      local w = spots[i]
      if w then
        sp.pin:SetSpot(L.spots and L.spots[i])
        sp.text:SetText(sp.pin:IsShown() and w or (T.Muted("-  ") .. w))
        sp:Show()
      else
        sp:Hide()
      end
    end
    local a = ns.CraftAction(m)
    c.craft:SetShown(a ~= nil)
    if a then
      c.craft:SetText(a.text)
      c.craft:SetEnabled(a.enabled)
    end
  end

  function f:Render()
    local s = ns.settings
    local prof = ns.Prof()
    local rank, maxSkill = ns.ReadSkill()
    local owned = ns.Owned()[prof.key]
    self.prof:SetValue(ns.ProfName(prof), profIcon(prof), not owned and "not learned" or nil)
    if s.tab == "mats" then s.tab = "shop" end
    if not self.target:HasFocus() then self.target:SetText(ns.Target()) end
    self.mode:Refresh()
    self.tabs:Refresh()

    local scanning = ns.Prices.scanning
    self.scan:SetText(scanning and ns.Prices.mode ~= "full" and "Stop" or "Scan AH")
    self.fullScan:SetText(scanning and ns.Prices.mode == "full" and "Stop" or "Full scan")
    self.scan:SetEnabled((scanning and ns.Prices.mode ~= "full") or (not scanning and ns.atAH and not ns.neutralAH) or false)
    self.fullScan:SetEnabled((scanning and ns.Prices.mode == "full") or (not scanning and ns.atAH and not ns.neutralAH) or false)
    self:RenderStatus()

    local p = ns.Progress()
    self:RenderCard(p, rank, maxSkill)

    local res = ns.result
    local gated = ns.needsScan
    self.onboarding:SetShown(gated)
    self.scroll:SetShown(not gated)
    self.tabs:SetShown(not gated)
    if gated then
      self.onboarding:Refresh()
      self.totalText:SetText("")
      self.totalTip = nil
      return
    end

    local entries
    if not (res and res.ok) then
      entries = { { kind = "callout", tone = "bad", text = ns.computeError or "Nothing to show." } }
      self.totalText:SetText("")
      self.totalTip = nil
    else
      local build = ns.UI.Lines[s.tab] or ns.UI.Lines.plan
      entries = build(res, prof, p)
      local t = res.totals
      local totalLabel = t.total < 0 and ("Profit " .. T.Color("good", ns.Money(-t.total, true)))
        or ("Total " .. ns.Money(t.total, true))
      self.totalText:SetText(("%s   ·   about %d crafts   ·   about %s"):format(totalLabel, t.crafts, ns.Duration(t.time)))
      local back = (s.sellBack and (t.sellBack or 0) > 0) and t.sellBack or 0
      -- the breakdown, amounts right-aligned
      self.totalTip = { { "Materials", ns.Money(t.materials, true) }, { "Recipes", "+ " .. ns.Money(t.learn, true) } }
      if back > 0 then table.insert(self.totalTip, { "Sold to vendor", "- " .. ns.Money(back, true) }) end
      table.insert(self.totalTip, "---")
      table.insert(self.totalTip, t.total < 0 and { "Profit", ns.Money(-t.total, true) } or { "Total", ns.Money(t.total, true) })
    end
    self.rows:Set(entries)
  end

  T.ApplyFontScale()
  return f
end

------------------------------------------------------------- row builders
local Lines = {}

-- tooltip lines: where to learn a recipe
local function learnTip(L)
  local out = { L.title .. "  ·  " .. ns.Money(L.cost, true) }
  for _, w in ipairs(L.where) do table.insert(out, "-  " .. w) end
  table.insert(out, "Trainers tab: click a dot to set a waypoint.")
  return out
end

-- Hover card for a recipe on the route: materials, time, and where to learn it.
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t "
local SHORT = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t "

-- L: where to get the recipe (nil when you already know it)
local function recipeHover(r, crafts, time, L, color)
  local known = ns.Known()[r.id] ~= nil or not L
  local lines = {}
  -- materials only once you know the recipe
  if known then
    table.insert(lines, T.Muted("Materials"))
    for _, rg in ipairs(r.reag) do
      table.insert(lines, ("|T%s:16:16|t  %d  %s"):format(T.ItemIcon(rg[1]), rg[2] * crafts, ns.ItemName(rg[1])))
    end
    table.insert(lines, "")
  end
  table.insert(lines, T.Muted(("%d crafts  ·  about %s"):format(crafts, ns.Duration(time))))
  -- the recipe: green if you know it, red (with where to get it) if not
  table.insert(lines, "")
  table.insert(lines, known and (READY .. T.Color("good", "Recipe")) or (SHORT .. T.Color("bad", "Recipe")))
  if not known then
    for _, w in ipairs(L.where) do table.insert(lines, "-  " .. w) end
  end
  return { title = color and ("|cff" .. color .. r.name .. "|r") or r.name, lines = lines }
end

-- Route: one row per step: skill range | recipe | crafts | cost.
-- Materials, time and where to learn it are in the hover card.
function Lines.plan(res, prof, p)
  local out = { { kind = "header", range = "Skill", icon = true, title = "Recipe", c2 = "Crafts", c3 = "Cost" } }
  local ranks, noted = prof.ranks or {}, {}
  for i, st in ipairs(res.steps) do
    for k, rk in ipairs(ranks) do
      if not noted[k] and res.from < rk.cap and st.to > rk.skill then
        noted[k] = true
        -- training is a step too: at this skill, learn the next rank
        table.insert(out, { kind = "row", range = T.Color("info", ("%d - %d"):format(rk.skill, rk.cap)),
          icon = "Interface\\Icons\\INV_Misc_Book_09",
          title = T.Color("info", "Train " .. rk.next) .. (rk.level and T.Muted(("  ·  level %d"):format(rk.level)) or ""),
          hover = { title = "Train " .. rk.next, lines = {
            ("Needs skill %d%s. Raises your cap from %d."):format(rk.skill, rk.level and (" and level " .. rk.level) or "", rk.cap),
            T.Muted(rk.how or "Any trainer in the Trainers tab teaches it.") } } })
      end
    end
    local r = st.recipe
    local _, color = ns.Difficulty(r, st.from)
    local L = (st.mustLearn and not ns.Known()[r.id]) and ns.LearnInfo(r, st.learnHow, st.learnCost) or nil
    table.insert(out, {
      kind = "row", active = i == 1, range = ("%d - %d"):format(st.from, st.to),
      item = r.make and r.make[1], icon = not r.make and profIcon(prof) or nil,
      title = "|cff" .. color .. r.name .. "|r",
      c2 = ("%d crafts"):format(st.crafts), c3 = ns.Money(st.cost, true),
      hover = recipeHover(r, st.crafts, st.time, L, color),
    })
  end
  if #res.intermediates > 0 then
    table.insert(out, { kind = "section", text = "Craft along the way", right = T.Muted("cheaper than buying") })
    for _, cr in ipairs(res.intermediates) do
      local L = cr.mustLearn and ns.LearnInfo(cr.recipe, "Trainer", cr.recipe.cost) or nil
      table.insert(out, { kind = "row", item = cr.recipe.make and cr.recipe.make[1], title = cr.recipe.name,
        c2 = ("%d crafts"):format(cr.crafts), hover = recipeHover(cr.recipe, cr.crafts, cr.time, L) })
    end
  end
  return out
end

-- Shopping: this step first (what to buy right now), then the rest of the
-- route. Columns: item | have/need | buy.
function Lines.shop(res, prof, p)
  local out = {}
  local now = {}   -- item id -> amount the current step needs (raw buys)
  local function shopRow(id, need, have, unit, how)
    local missing = math.max(0, need - have)
    return {
      kind = "row", item = id, title = ns.ItemName(id),
      sub = unit and (ns.Money(unit) .. " each  ·  " .. (how == "vendor" and "Vendor" or how == "craft" and "Craft" or "AH")) or nil,
      tip = unit and { "Price: " .. ns.Prices:SourceText(id, how) } or nil,
      c2 = T.Color(missing > 0 and "bad" or "good", ("%d/%d"):format(math.min(have, need), need)),
      c3 = missing > 0 and ("buy %d"):format(missing) or T.Color("good", "ready"),
      c3sub = (missing > 0 and unit) and ns.Money(missing * unit, true) or nil,
    }
  end
  local unitOf = {}
  for _, e in ipairs(res.shopping) do unitOf[e.id] = e end

  if p then
    table.insert(out, { kind = "section", text = "This step: " .. p.recipe.name })
    table.insert(out, { kind = "header", icon = true, title = "Item", c2 = "Have", c3 = "Buy" })
    for _, m in ipairs(p.mats) do
      local all = (m.have or 0) + (m.bank or 0)
      if m.craft then
        local cr = m.craft.recipe
        local row = shopRow(m.id, m.need, all)
        row.c3 = m.missing > 0 and ("craft %d"):format(m.craft.n) or row.c3
        row.sub = "Craft yourself (cheaper)"
        if not ns.Known()[cr.id] and not (cr.src:find("s") and not next(ns.Known())) then
          row.sub = "Craft yourself (cheaper)  ·  learn it first"
          row.tip = learnTip(ns.LearnInfo(cr, "Trainer", cr.cost))
        end
        table.insert(out, row)
        if m.missing > 0 then
          for _, sub in ipairs(m.craft.sub) do
            local e = unitOf[sub.id]
            local r = shopRow(sub.id, sub.need, (sub.have or 0) + (sub.bank or 0), e and e.unit, e and e.how)
            r.indent = true
            table.insert(out, r)
            now[sub.id] = (now[sub.id] or 0) + sub.need
          end
        end
      else
        local e = unitOf[m.id]
        table.insert(out, shopRow(m.id, m.need, all, e and e.unit, e and e.how))
        now[m.id] = (now[m.id] or 0) + m.need
      end
    end
  end

  -- the rest of the route: what's left after this step
  local rows, missingCost = {}, 0
  for _, e in ipairs(res.shopping) do
    local qty = e.qty - (now[e.id] or 0)
    if qty > 0 then
      local _, all = ns.Count(e.id)
      local have = math.max(0, all - (now[e.id] or 0))
      missingCost = missingCost + math.max(0, qty - have) * (e.unit or 0)
      table.insert(rows, shopRow(e.id, qty, have, e.unit, e.how))
    end
  end
  if #rows > 0 then
    table.insert(out, { kind = "section", text = "Rest of the route", right = "to buy: " .. ns.Money(missingCost, true) })
    table.insert(out, { kind = "header", icon = true, title = "Item", c2 = "Have", c3 = "Buy" })
    for _, r in ipairs(rows) do table.insert(out, r) end
  end
  if res.reused and #res.reused > 0 then
    table.insert(out, { kind = "section", text = "Made earlier on this route", right = T.Muted("keep them, don't sell") })
    for _, u in ipairs(res.reused) do
      table.insert(out, { kind = "row", item = u.id, title = ns.ItemName(u.id), c3 = ("keep %d"):format(u.qty) })
    end
  end
  return out
end

-- Trainers: one question - who do I visit, and what do I learn there?
--   1. next rank: can you learn it yet
--   2. trainers: each listed once (one per zone), with the highest rank they teach
--   (where to get each recipe is in the Route tab's hover card)
local RANK_NAME = { [0] = "may teach", [1] = "Apprentice", [2] = "Journeyman", [3] = "Expert", [4] = "Artisan" }

function Lines.train(res, prof, p)
  local out = {}
  local rank, maxSkill = ns.ReadSkill()
  local nr = p and p.nextRank or ns.NextRank(rank or 1, maxSkill)
  local need = 1  -- lowest trainer rank that covers what you need next
  if nr then
    local rk = nr.rank
    local missing = {}
    if (rank or 0) < rk.skill then table.insert(missing, ("skill %d (you: %d)"):format(rk.skill, rank or 0)) end
    if rk.level and nr.level < rk.level then table.insert(missing, ("level %d (you: %d)"):format(rk.level, nr.level)) end
    table.insert(out, { kind = "section", text = "Next rank: " .. rk.next })
    table.insert(out, { kind = "callout", tone = nr.ready and "good" or "info",
      text = nr.ready and ("You can learn it now. It raises your cap from %d."):format(rk.cap)
        or ("Not yet: needs " .. table.concat(missing, ", ") .. ".") })
    if rk.how then
      table.insert(out, { kind = "row", icon = "Interface\\Icons\\INV_Misc_Book_09", title = "Not taught by trainers", sub = rk.how })
    else
      need = rk.tier or need
    end
  else
    table.insert(out, { kind = "callout", tone = "good", text = "No more ranks to train." })
  end

  -- recipes still to learn on the route
  local recipes = {}
  if res then
    for _, st in ipairs(res.steps) do
      local r = st.recipe
      if (st.learnCost > 0 or st.learnHow == "Quest") and not ns.Known()[r.id] then
        local L = ns.LearnInfo(r, st.learnHow, st.learnCost)
        table.insert(recipes, { st = st, L = L })
        if L.kind == "trainer" and not nr then need = math.max(need, L.tier) end
      end
    end
  end
  if nr and nr.rank.how then
    for _, x in ipairs(recipes) do if x.L.kind == "trainer" then need = math.max(need, x.L.tier) end end
  end

  -- trainers: once each, nearest first
  if not (nr and nr.rank.how) or #recipes > 0 then
    table.insert(out, { kind = "section", text = "Trainers", right = T.Muted("click the dot for a waypoint") })
    table.insert(out, { kind = "header", pin = true, title = "Trainer", c2 = "Zone", c3 = "Teaches up to" })
    local zones, n = {}, 0
    for _, t in ipairs(ns.TrainersFor(need)) do
      if not zones[t.zone] and n < 6 then
        zones[t.zone] = true
        n = n + 1
        table.insert(out, { kind = "row", pin = t, title = t.name, c2 = t.zone, c3 = T.Muted(RANK_NAME[t.tier or 0] or "") })
      end
    end
  end

  return out
end

------------------------------------------------------------------- public
local UI = { Lines = Lines }
ns.UI = UI

function UI:IsShown() return f and f:IsShown() end
function UI:Render() if f and f:IsShown() then f:Render() end end
function UI:RenderStatus() if f and f:IsShown() then f:RenderStatus() end end
function UI:Toggle()
  if not f then create() end
  if f:IsShown() then f:Hide() else f:Show() end
end
function UI:ContentText()
  if not f then return "" end
  if f.onboarding:IsShown() then
    return table.concat({ f.onboarding.title:GetText() or "", f.onboarding.body:GetText() or "",
      f.onboarding.button:GetText() or "" }, "\n")
  end
  return f.rows:Text()
end
function UI:CardText()
  if not f then return "" end
  local c = f.card
  local out = { c.skill:GetText() or "" }
  if c.empty:IsShown() then table.insert(out, c.empty:GetText() or "") end
  if c.name:IsShown() then
    table.insert(out, c.kicker:GetText() or "")
    table.insert(out, c.name:GetText() or "")
    table.insert(out, c.sub:GetText() or "")
  end
  for _, fs in ipairs(c.lines) do
    if fs:IsShown() then table.insert(out, fs:GetText() or "") end
  end
  if c.spotsTitle:IsShown() then table.insert(out, c.spotsTitle:GetText() or "") end
  for _, sp in ipairs(c.spots) do
    if sp:IsShown() then table.insert(out, (sp.pin:IsShown() and "(pin) " or "") .. (sp.text:GetText() or "")) end
  end
  if c.craft:IsShown() then
    table.insert(out, "[" .. (c.craft:GetText() or "") .. (c.craft:IsEnabled() and "" or " (disabled)") .. "]")
  end
  return table.concat(out, "\n")
end
function UI:FooterText()
  if not f then return "" end
  local parts = {}
  for _, l in ipairs(f.totalTip or {}) do table.insert(parts, type(l) == "table" and (l[1] .. " " .. l[2]) or l) end
  return (f.totalText:GetText() or "") .. " | " .. table.concat(parts, " / ")
end

-- A small button on the profession window.
function UI:AttachToTradeSkill()
  local parent = ProfessionsFrame or TradeSkillFrame
  if self.tsButton or not parent then return end
  local b = T.Button(parent, "CraftPath", "primary", 90, 22)
  b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -2)
  b:SetFrameLevel(parent:GetFrameLevel() + 10)
  b:SetScript("OnClick", function() UI:Toggle() end)
  self.tsButton = b
end
