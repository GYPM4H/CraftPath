-- CraftPath main window.
--   header:   title, profession dropdown, options, close
--   controls: target skill, planning mode, tracker toggle
--   now card: current craft, chance, attempts, progress, alerts
--   tabs:     Route / Materials / Shopping / Trainers (table rows)
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
local SOURCE = { ah = "AH", auctionator = "Auctionator", vendor = "Vendor", craft = "Craft" }
local TIER_NAME = { [1] = "", [2] = "Journeyman", [3] = "Expert", [4] = "Artisan" }

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
  local title = T.Text(o, "Header", "accent")
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
  f.title:SetPoint("TOPLEFT", f.logo, "TOPRIGHT", 10, -1)
  f.title:SetText("CraftPath")
  f.subtitle = T.Text(f, "Small", "muted")
  f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
  f.subtitle:SetText("Profession leveling planner")

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

  f.trackerBtn = T.Button(f, "Tracker", "secondary", 110, 26)
  f.trackerBtn:SetPoint("TOPRIGHT", -PAD, -66)
  f.trackerBtn:SetScript("OnClick", function() ns.Tracker:Toggle(); f:Render() end)

  -- now card ----------------------------------------------------------------
  local card = T.Panel(f, T.C.panel, T.C.border)
  card:SetPoint("TOPLEFT", PAD, -106)
  card:SetPoint("TOPRIGHT", -PAD, -106)
  card:SetHeight(214)
  f.card = card

  card.icon = T.Icon(card, 46)
  card.icon:SetPoint("TOPLEFT", 14, -14)
  card.kicker = T.Text(card, "Tiny", "muted")
  card.kicker:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, 0)
  card.kicker:SetText("CRAFT NOW")
  card.name = T.Text(card, "Big", "text")
  card.name:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -3)
  card.name:SetPoint("RIGHT", -200, 0)
  card.sub = T.Text(card, "Small", "muted")
  card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
  card.sub:SetPoint("RIGHT", -200, 0)

  card.skill = T.Text(card, "Title", "text", "RIGHT")
  card.skill:SetPoint("TOPRIGHT", -14, -16)
  card.skillSub = T.Text(card, "Small", "muted", "RIGHT")
  card.skillSub:SetPoint("TOPRIGHT", card.skill, "BOTTOMRIGHT", 0, -4)

  card.total = T.Bar(card, T.C.info, 4)
  card.total:SetPoint("TOPLEFT", 14, -72)
  card.total:SetPoint("TOPRIGHT", -14, -72)
  card.total.label:Hide()

  -- stat tiles
  card.tiles = {}
  local tileNames = { "SKILL-UP CHANCE", "ATTEMPTS LEFT", "THIS STEP", "CRAFTED" }
  local tileW = (W - PAD * 2 - 28 - 3 * 10) / 4
  for i, name in ipairs(tileNames) do
    local t = T.Panel(card, T.C.panel2, { 0, 0, 0, 0 })
    t:SetSize(tileW, 56)
    t:SetPoint("TOPLEFT", 14 + (i - 1) * (tileW + 10), -86)
    t.label = T.Text(t, "Tiny", "muted")
    t.label:SetPoint("TOPLEFT", 10, -8)
    t.label:SetText(name)
    t.value = T.Text(t, "Title", "text")
    t.value:SetPoint("TOPLEFT", 10, -24)
    t.sub = T.Text(t, "Small", "muted")
    t.sub:SetPoint("LEFT", t.value, "RIGHT", 6, -1)
    card.tiles[i] = t
  end
  card.stepBar = T.Bar(card.tiles[3], T.C.good, 3)
  card.stepBar:SetPoint("BOTTOMLEFT", 10, 8)
  card.stepBar:SetPoint("BOTTOMRIGHT", -10, 8)
  card.stepBar.label:Hide()

  card.alerts = {}
  for i = 1, 3 do
    local a = CreateFrame("Frame", nil, card)
    a:SetHeight(18)
    a.dot = T.Fill(a, T.C.info, "ARTWORK")
    a.dot:SetSize(6, 6)
    a.dot:SetPoint("LEFT", 0, 0)
    a.text = T.Text(a, "Small", "text")
    a.text:SetPoint("LEFT", 12, 0)
    a.text:SetPoint("RIGHT")
    a:SetPoint("TOPLEFT", 16, -150 - (i - 1) * 20)
    a:SetPoint("RIGHT", -14, 0)
    card.alerts[i] = a
  end

  -- "where to learn": one trainer per line, the dot sets a waypoint
  local half = math.floor((W - PAD * 2) / 2)
  card.spots = {}
  for i = 1, 3 do
    local sp = CreateFrame("Frame", nil, card)
    sp:SetHeight(18)
    sp:SetPoint("TOPLEFT", half + 6, -150 - (i - 1) * 20)
    sp:SetPoint("RIGHT", -14, 0)
    sp.pin = T.Pin(sp, 14)
    sp.pin:SetPoint("LEFT", -4, 0)
    sp.dot = T.Fill(sp, T.C.accent, "ARTWORK")
    sp.dot:SetSize(6, 6)
    sp.dot:SetPoint("LEFT", 0, 0)
    sp.text = T.Text(sp, "Small", "text")
    sp.text:SetPoint("LEFT", 16, 0)
    sp.text:SetPoint("RIGHT")
    card.spots[i] = sp
  end
  card.half = half

  card.empty = T.Text(card, "Body", "muted", "CENTER")
  card.empty:SetPoint("CENTER")
  card.empty:SetWordWrap(true)
  card.empty:SetWidth(W - 120)

  -- tabs + content ------------------------------------------------------------
  f.tabs = T.Tabs(f, { { "plan", "Route" }, { "mats", "Materials" }, { "shop", "Shopping" }, { "train", "Trainers" } },
    function() return ns.settings.tab end,
    function(v) ns.settings.tab = v; f:Render() end)
  f.tabs:SetPoint("TOPLEFT", PAD, -330)
  f.tabs:SetPoint("TOPRIGHT", -PAD, -330)

  local area = CreateFrame("Frame", nil, f)
  area:SetPoint("TOPLEFT", PAD, -366)
  area:SetPoint("BOTTOMRIGHT", -PAD, 128)
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
  frule:SetPoint("BOTTOMLEFT", 1, 120)
  frule:SetPoint("BOTTOMRIGHT", -1, 120)
  frule:SetHeight(1)

  -- row 1: totals
  f.totalText = T.Text(f, "Header", "text")
  f.totalText:SetPoint("BOTTOMLEFT", PAD, 88)
  f.totalSub = T.Text(f, "Small", "muted")
  f.totalSub:SetPoint("BOTTOMLEFT", PAD, 66)

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
    c.skillSub:SetText(maxSkill and ("current cap " .. maxSkill) or "")
    c.total:SetValue(rank and rank / target or 0)
    local shown = p ~= nil
    for _, k in ipairs({ "icon", "kicker", "name", "sub" }) do c[k]:SetShown(shown) end
    for _, t in ipairs(c.tiles) do t:SetShown(shown) end
    c.empty:SetShown(not shown)
    if not shown then
      for _, a in ipairs(c.alerts) do a:Hide() end
      for _, sp in ipairs(c.spots) do sp:Hide() end
      if ns.needsScan then
        c.empty:SetText("Waiting for prices - see below.")
      else
        c.empty:SetText(ns.computeError or "No route yet.")
      end
      return
    end
    local m = ns.NowModel(p)
    local prof = ns.Prof()
    local L = m.learnFirst
    if L then
      c.kicker:SetText(T.Color("accent", "LEARN FIRST"))
      c.icon:SetIcon(L.kind == "trainer" and "Interface\\Icons\\INV_Misc_Book_09" or "Interface\\Icons\\INV_Scroll_03")
      c.name:SetText(T.Color("accent", m.name))
      c.sub:SetText(("%s  ·  %s  ·  then craft about %d (skill %d to %d)"):format(L.title, ns.Money(L.cost, true),
        m.left, m.stepFrom, m.stepTo))
    else
      c.kicker:SetText("CRAFT NOW")
      c.icon:SetIcon(m.recipe.make and m.recipe.make[1] or profIcon(prof))
      c.name:SetText("|cff" .. m.color .. m.name .. "|r")
      c.sub:SetText(("Skill %d to %d  ·  %s  ·  known"):format(m.stepFrom, m.stepTo, m.diff))
    end
    local t = c.tiles
    t[1].value:SetText(ns.Pct(m.chance))
    t[1].sub:SetText(("%.1f per point"):format(m.tries))
    t[2].value:SetText(tostring(m.left))
    t[2].sub:SetText(("90%%: %d"):format(m.safe))
    t[3].value:SetText(("%d%%"):format(math.floor(m.stepPct * 100 + 0.5)))
    t[3].sub:SetText("")
    c.stepBar:SetValue(m.stepPct)
    t[4].value:SetText(tostring(m.crafted))
    t[4].sub:SetText("this step")
    local alerts = {}
    -- learn first: the places go in their own column on the right
    local spots = L and L.where or {}
    for i, sp in ipairs(c.spots) do
      local w = spots[i]
      if w then
        local spot = L.spots and L.spots[i]
        sp.pin:SetSpot(spot)
        sp.dot:SetShown(not sp.pin:IsShown())
        sp.text:SetText(w)
        sp:Show()
      else
        sp:Hide()
      end
    end
    for _, a in ipairs(c.alerts) do
      a:SetPoint("RIGHT", c, "LEFT", #spots > 0 and (c.half - 10) or (W - PAD * 2 - 14), 0)
    end
    for _, A in ipairs(m.learnAlso) do
      table.insert(alerts, { "accent", ("Also learn %s: %s %s"):format(A.recipe.name, A.title, ns.Money(A.cost, true)) })
    end
    if m.missing then
      table.insert(alerts, { "bad", ("Missing for this step: %s"):format(m.missing) })
    else
      table.insert(alerts, { "good", "All materials for this step are in your bags or bank." })
    end
    if m.rank then table.insert(alerts, { m.rank.tone, m.rank.text }) end
    if #alerts < 3 and m.nextText then table.insert(alerts, { "muted", m.nextText }) end
    for i, a in ipairs(c.alerts) do
      local al = alerts[i]
      if al then
        a.dot:SetVertexColor(unpack(T.C[al[1]]))
        a.text:SetText(al[2])
        a.text:SetTextColor(unpack(al[1] == "muted" and T.C.muted or T.C.text))
        a:Show()
      else
        a:Hide()
      end
    end
  end

  function f:Render()
    local s = ns.settings
    local prof = ns.Prof()
    local rank, maxSkill = ns.ReadSkill()
    local owned = ns.Owned()[prof.key]
    self.prof:SetValue(ns.ProfName(prof), profIcon(prof), owned and (owned.rank .. " / " .. owned.max) or "not learned")
    if not self.target:HasFocus() then self.target:SetText(ns.Target()) end
    self.mode:Refresh()
    self.tabs:Refresh()
    self.trackerBtn:SetText(ns.Tracker:IsShown() and "Hide tracker" or "Show tracker")

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
      self.totalSub:SetText("")
      return
    end

    local entries
    if not (res and res.ok) then
      entries = { { kind = "callout", tone = "bad", text = ns.computeError or "Nothing to show." } }
      self.totalText:SetText("")
      self.totalSub:SetText("")
    else
      local build = ns.UI.Lines[s.tab] or ns.UI.Lines.plan
      entries = build(res, prof, p)
      local t = res.totals
      local totalLabel = t.total < 0 and ("Profit " .. T.Color("good", ns.Money(-t.total, true)))
        or ("Total " .. ns.Money(t.total, true))
      self.totalText:SetText(("%s     about %d crafts     %s"):format(totalLabel, t.crafts,
        T.Color("accent", "about " .. ns.Duration(t.time) .. " crafting")))
      self.totalSub:SetText(("Materials %s     Recipes %s%s     %s"):format(
        ns.Money(t.materials, true), ns.Money(t.learn, true),
        (s.sellBack and (t.sellBack or 0) > 0) and ("     Sell back -" .. ns.Money(t.sellBack, true)) or "",
        T.Muted(MODE_LABEL[s.mode])))
    end
    self.rows:Set(entries)
  end

  T.ApplyFontScale()
  return f
end

------------------------------------------------------------- row builders
local function haveText(have, bank)
  if bank and bank > 0 then return ("%d %s"):format(have, T.Muted(("+%d bank"):format(bank))) end
  return tostring(have)
end

-- one indented line per place to learn something, the dot sets a waypoint
local function placeRows(out, L)
  for i, w in ipairs(L.where) do
    local spot = L.spots and L.spots[i]
    table.insert(out, { kind = "row", indent = true, pin = spot,
      title = (spot and spot.map) and w or (T.Muted("-  ") .. w) })
  end
end

local function learnText(st)
  if st.learnHow == "known" then return T.Color("good", "known") end
  if st.learnHow == "starter" then return T.Color("good", "starter") end
  if st.learnHow == "Quest" then return T.Color("accent", "quest reward") end
  if st.learnCost > 0 then return st.learnHow .. " " .. ns.Money(st.learnCost, true) end
  return "learned earlier"
end

local function trainerTierFor(learn)
  if learn < 75 then return 1 end
  if learn < 150 then return 2 end
  if learn < 225 then return 3 end
  return 4
end

local function ageText(sec)
  if sec < 3600 then return math.floor(sec / 60) .. "m ago" end
  if sec < 86400 then return math.floor(sec / 3600) .. "h ago" end
  return math.floor(sec / 86400) .. "d ago"
end

local Lines = {}

-- Route: every step, current one highlighted, rank reminders inline.
function Lines.plan(res, prof, p)
  local out = {}
  local ranks, noted = prof.ranks or {}, {}
  table.insert(out, { kind = "note", text = ("%s route from %d to %d. \"90%%\" = attempts that cover 9 in 10 players."):format(
    MODE_LABEL[res.mode], res.from, res.to) })
  for i, st in ipairs(res.steps) do
    for k, rk in ipairs(ranks) do
      if not noted[k] and res.from < rk.cap and st.to > rk.skill then
        noted[k] = true
        table.insert(out, { kind = "callout", tone = "info", text = ("Learn %s before %d  -  needs skill %d%s. %s"):format(
          rk.next, rk.cap, rk.skill, rk.level and (" and level " .. rk.level) or "",
          rk.how and "From a book/quest: see Trainers." or "See Trainers.") })
      end
    end
    local r = st.recipe
    local _, color = ns.Difficulty(r, st.from)
    local learnHere = st.mustLearn and not ns.Known()[r.id]
    if learnHere then
      local L = ns.LearnInfo(r, st.learnHow, st.learnCost)
      table.insert(out, {
        kind = "row", active = i == 1, range = T.Color("accent", "learn"),
        icon = L.kind == "trainer" and "Interface\\Icons\\INV_Misc_Book_09" or "Interface\\Icons\\INV_Scroll_03",
        title = T.Color("accent", "Learn " .. r.name),
        c2 = L.title, c3 = ns.Money(L.cost, true),
      })
      placeRows(out, L)
    end
    local mats = {}
    for _, rg in ipairs(r.reag) do table.insert(mats, (rg[2] * st.crafts) .. " " .. ns.ItemName(rg[1])) end
    table.insert(out, {
      kind = "row", active = i == 1 and not learnHere, range = ("%d - %d"):format(st.from, st.to),
      item = r.make and r.make[1], icon = not r.make and profIcon(prof) or nil,
      title = r.name .. ((r.make and r.make[2] > 1) and T.Muted(("  makes %d"):format(r.make[2])) or ""),
      titleColor = color, sub = table.concat(mats, ", "),
      c2 = ("%d crafts"):format(st.crafts), c2sub = ("90%%: %d  ·  %s"):format(st.safe, ns.Duration(st.time)),
      c3 = ns.Money(st.cost, true), c3sub = learnHere and T.Color("accent", "learn first") or learnText(st),
    })
  end
  if #res.intermediates > 0 then
    table.insert(out, { kind = "section", text = "Craft along the way", right = T.Muted("cheaper than buying") })
    for _, cr in ipairs(res.intermediates) do
      table.insert(out, { kind = "row", item = cr.recipe.make and cr.recipe.make[1], title = cr.recipe.name,
        sub = cr.mustLearn and T.Color("accent", "learn first: " .. ns.LearnInfo(cr.recipe, "Trainer", cr.recipe.cost).text) or nil,
        c2 = ("%d crafts"):format(cr.crafts), c2sub = ("90%%: %d  ·  %s"):format(cr.safe, ns.Duration(cr.time)) })
    end
  end
  return out
end

local function matRows(out, mats, res, learn)
  for _, m in ipairs(mats) do
    table.insert(out, {
      kind = "row", item = m.id, title = ns.ItemName(m.id),
      sub = (function()
        local unit, how = res.itemCost(m.id, learn)
        if not unit then return ("%d per craft"):format(m.per) end
        return ("%d per craft  ·  %s each  ·  %s"):format(m.per, ns.Money(unit), ns.Prices:SourceText(m.id, how))
      end)(),
      c2 = "have " .. haveText(m.have, m.bank), c2sub = ("need %d  ·  90%%: %d"):format(m.need, m.needSafe),
      c3 = m.missing > 0 and T.Color("bad", ("missing %d"):format(m.missing)) or T.Color("good", "ready"),
    })
    if m.craft then
      local cr = m.craft.recipe
      local unknown = not ns.Known()[cr.id] and not (cr.src:find("s") and not next(ns.Known()))
      table.insert(out, { kind = "row", indent = true, item = cr.make and cr.make[1],
        title = T.Color("accent", ("Craft %d x %s"):format(m.craft.n, cr.name)),
        sub = unknown and ("learn it first: " .. ns.LearnInfo(cr, "Trainer", cr.cost).text) or "cheaper than buying it" })
      for _, sub in ipairs(m.craft.sub) do
        table.insert(out, { kind = "row", indent = true, item = sub.id, title = ns.ItemName(sub.id),
          c2 = "have " .. haveText(sub.have, sub.bank), c2sub = ("need %d"):format(sub.need),
          c3 = sub.missing > 0 and T.Color("bad", ("missing %d"):format(sub.missing)) or T.Color("good", "ready") })
      end
    end
  end
end

-- Materials: what this step (and the next) needs vs. your bags and bank.
function Lines.mats(res, prof, p)
  local out = {}
  if not p then return { { kind = "note", text = "No current step." } } end
  table.insert(out, { kind = "section", text = "Now: " .. p.recipe.name,
    right = T.Muted(("skill %d to %d  ·  about %d crafts"):format(p.stepFrom, p.stepTo, p.step.crafts)) })
  matRows(out, p.mats, res, p.recipe.learn)
  if p.next and p.nextMats then
    table.insert(out, { kind = "section", text = "Next: " .. p.next.recipe.name,
      right = T.Muted(("skill %d to %d  ·  about %d crafts"):format(p.next.from, p.next.to, p.next.crafts)) })
    matRows(out, p.nextMats, res, p.next.recipe.learn)
  end
  table.insert(out, { kind = "space" })
  table.insert(out, { kind = "note", text = "The Shopping tab adds up everything for the whole route." })
  return out
end

-- Shopping: the whole route, with what you have and where prices come from.
function Lines.shop(res)
  local out = {}
  local realm = ns.Prices:Realm().ah
  local missingCost = 0
  local rows = {}
  for _, e in ipairs(res.shopping) do
    local bags, all = ns.Count(e.id)
    local missing = math.max(0, e.qty - all)
    missingCost = missingCost + missing * (e.unit or 0)
    local src = ns.Prices:SourceText(e.id, e.how)
    table.insert(rows, {
      kind = "row", item = e.id, title = ns.ItemName(e.id),
      sub = ns.Money(e.unit) .. " each  ·  " .. src,
      c2 = ("need %d"):format(e.qty), c2sub = ("90%%: %d  ·  have %d"):format(e.safe, all),
      c3 = missing > 0 and T.Color("bad", ("buy %d"):format(missing)) or T.Color("good", "ready"),
      c3sub = missing > 0 and ns.Money(missing * (e.unit or 0), true) or nil,
    })
  end
  table.insert(out, { kind = "section", text = "Whole route", right = "still to buy: " .. ns.Money(missingCost, true) })
  for _, r in ipairs(rows) do table.insert(out, r) end
  if res.reused and #res.reused > 0 then
    table.insert(out, { kind = "section", text = "Made earlier on this route", right = T.Muted("keep them, don't sell") })
    for _, u in ipairs(res.reused) do
      table.insert(out, { kind = "row", item = u.id, title = ns.ItemName(u.id),
        sub = "You craft these in an earlier step and use them later - not bought, not sold.",
        c2 = ("keep %d"):format(u.qty) })
    end
  end
  return out
end

-- Trainers: next rank, who teaches it, and where to learn each recipe.
function Lines.train(res, prof, p)
  local out = {}
  local rank, maxSkill = ns.ReadSkill()
  local nr = p and p.nextRank or ns.NextRank(rank or 1, maxSkill)
  if nr then
    local rk = nr.rank
    table.insert(out, { kind = "section", text = "Next rank: " .. rk.next, right = T.Muted(("raises the cap from %d"):format(rk.cap)) })
    local need = { ("skill %d %s"):format(rk.skill, (rank or 0) >= rk.skill and T.Color("good", "ok") or T.Color("bad", ("(you: %d)"):format(rank or 0))) }
    if rk.level then
      table.insert(need, ("level %d %s"):format(rk.level, nr.level >= rk.level and T.Color("good", "ok") or T.Color("bad", ("(you: %d)"):format(nr.level))))
    end
    table.insert(out, { kind = "callout", tone = nr.ready and "good" or "info",
      text = (nr.ready and "You can learn it now.  " or "Not yet.  ") .. "Needs " .. table.concat(need, ", ") })
    if rk.how then
      table.insert(out, { kind = "row", icon = "Interface\\Icons\\INV_Misc_Book_09", title = "Not taught by trainers", sub = rk.how })
      table.insert(out, { kind = "note", text = "Forever may have changed this - check Wowhead if it isn't there." })
    else
      for _, t in ipairs(nr.trainers) do
        table.insert(out, { kind = "row", icon = profIcon(prof), title = t.name, sub = t.zone,
          pin = t, c3 = t.maybe and T.Muted("may teach it") or nil })
      end
    end
  else
    table.insert(out, { kind = "callout", tone = "good", text = "No more ranks to train." })
  end

  if not res then return out end
  table.insert(out, { kind = "section", text = "Recipes to learn on this route" })
  local any
  for _, st in ipairs(res.steps) do
    if st.learnCost > 0 or st.learnHow == "Quest" then
      any = true
      local r = st.recipe
      local L = ns.LearnInfo(r, st.learnHow, st.learnCost)
      local done = ns.Known()[r.id]
      table.insert(out, { kind = "row", item = r.make and r.make[1],
        title = done and (r.name .. "  " .. T.Color("good", "learned")) or r.name,
        sub = L.title,
        c2 = ("at %d"):format(st.from), c3 = ns.Money(st.learnCost, true) })
      if not done then placeRows(out, L) end
    end
  end
  if not any then table.insert(out, { kind = "note", text = "None - you know everything on the route." }) end
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
    for _, t in ipairs(c.tiles) do
      table.insert(out, (t.label:GetText() or "") .. " " .. (t.value:GetText() or "") .. " " .. (t.sub:GetText() or ""))
    end
  end
  for _, sp in ipairs(c.spots) do
    if sp:IsShown() then table.insert(out, (sp.pin:IsShown() and "(pin) " or "- ") .. (sp.text:GetText() or "")) end
  end
  for _, a in ipairs(c.alerts) do
    if a:IsShown() then table.insert(out, a.text:GetText() or "") end
  end
  return table.concat(out, "\n")
end
function UI:FooterText()
  return f and ((f.totalText:GetText() or "") .. " | " .. (f.totalSub:GetText() or "")) or ""
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
