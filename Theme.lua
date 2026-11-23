-- CraftPath theme: flat dark look, one amber accent, readable fonts.
-- Small widget kit used by the main window and the tracker.
local ADDON, ns = ...

local T = {}
ns.T = T

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

---------------------------------------------------------------- palette
T.C = {
  bg      = { 0.071, 0.078, 0.094, 0.97 }, -- window
  panel   = { 0.106, 0.118, 0.141, 1 },    -- cards
  panel2  = { 0.141, 0.157, 0.188, 1 },    -- raised / hover
  stripe  = { 1, 1, 1, 0.025 },
  border  = { 0.204, 0.224, 0.267, 1 },
  text    = { 0.906, 0.918, 0.937, 1 },
  muted   = { 0.553, 0.584, 0.643, 1 },
  accent  = { 0.949, 0.647, 0.255, 1 },    -- amber
  good    = { 0.298, 0.765, 0.541, 1 },
  bad     = { 0.941, 0.416, 0.416, 1 },
  info    = { 0.353, 0.690, 0.965, 1 },
}
T.HEX = {
  text = "e7eaef", muted = "8d95a4", accent = "f2a541", good = "4cc38a", bad = "f06a6a", info = "5ab0f6",
}
function T.Color(hex, s) return "|cff" .. (T.HEX[hex] or hex) .. s .. "|r" end
function T.Muted(s) return T.Color("muted", s) end

---------------------------------------------------------------- fonts
-- name -> base size; live-resized with ns.settings.fontScale
local SIZES = { Big = 21, Title = 17, Header = 14.5, Body = 13, Small = 11.5, Tiny = 10.5 }
T.Font = {}
for name, size in pairs(SIZES) do
  local fo = CreateFont("CraftPathFont" .. name)
  fo:SetFont(FONT, size, "")
  fo:SetShadowOffset(1, -1)
  fo:SetShadowColor(0, 0, 0, 0.85)
  fo:SetTextColor(unpack(T.C.text))
  T.Font[name] = fo
end

function T.ApplyFontScale()
  local scale = (ns.settings and ns.settings.fontScale) or 1
  for name, size in pairs(SIZES) do
    T.Font[name]:SetFont(FONT, math.floor(size * scale + 0.5), "")
  end
end

---------------------------------------------------------------- basics
function T.Backdrop(frame, bg, border)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  frame:SetBackdropColor(unpack(bg or T.C.panel))
  frame:SetBackdropBorderColor(unpack(border or T.C.border))
end

function T.Panel(parent, bg, border, kind)
  local f = CreateFrame(kind or "Frame", nil, parent, BACKDROP)
  T.Backdrop(f, bg, border)
  return f
end

function T.Text(parent, font, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(T.Font[font or "Body"])
  if color then fs:SetTextColor(unpack(T.C[color] or color)) end
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

function T.Fill(parent, color, layer)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(WHITE)
  t:SetVertexColor(unpack(color))
  return t
end

function T.Tooltip(widget, title, body)
  widget:HookScript("OnEnter", function(self)
    local t = type(title) == "function" and title() or title
    local b = type(body) == "function" and body() or body
    if not t or t == "" then return end
    local lines = {}
    for line in ((b or "") .. "\n"):gmatch("(.-)\n") do table.insert(lines, line) end
    while lines[#lines] == "" do table.remove(lines) end
    T.ShowHover(self, t, lines)
  end)
  widget:HookScript("OnLeave", function() T.HideHover() end)
end

local function iconTexture(id)
  if not id then return nil end
  if type(id) == "string" then return id end
  local tex = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
  return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end
T.ItemIcon = iconTexture

function T.Icon(parent, size)
  local holder = T.Panel(parent, { 0, 0, 0, 1 }, T.C.border)
  holder:SetSize(size, size)
  holder.tex = holder:CreateTexture(nil, "ARTWORK")
  holder.tex:SetPoint("TOPLEFT", 1, -1)
  holder.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  holder.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  function holder:SetIcon(id) self.tex:SetTexture(iconTexture(id)) end
  return holder
end

---------------------------------------------------------------- buttons
-- kind: "primary" (amber), "secondary" (outlined), "ghost" (text only)
function T.Button(parent, label, kind, w, h)
  kind = kind or "secondary"
  local b = CreateFrame("Button", nil, parent, BACKDROP)
  b:SetSize(w or 100, h or 26)
  local fs = T.Text(b, "Body", nil, "CENTER")
  fs:SetPoint("CENTER")
  b:SetFontString(fs)
  b:SetText(label or "")
  b.kind = kind
  -- keep tooltips working on disabled buttons (e.g. scans away from the AH)
  if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end

  local function paint(self, hover)
    local enabled = self:IsEnabled()
    if self.kind == "primary" then
      local c = T.C.accent
      local k = not enabled and 0.35 or hover and 1.12 or 1
      T.Backdrop(self, { c[1] * k, c[2] * k, c[3] * k, 1 }, { c[1] * k, c[2] * k, c[3] * k, 1 })
      fs:SetTextColor(0.08, 0.06, 0.03, enabled and 1 or 0.7)
      -- dark text on amber: a drop shadow would only smear it
      fs:SetShadowOffset(0, 0)
      fs:SetShadowColor(0, 0, 0, 0)
    elseif self.kind == "ghost" then
      T.Backdrop(self, hover and enabled and T.C.panel2 or { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
      fs:SetTextColor(unpack(enabled and (hover and T.C.text or T.C.muted) or { 0.4, 0.4, 0.4, 1 }))
    else
      local sel = self.selected
      T.Backdrop(self, (sel or (hover and enabled)) and T.C.panel2 or T.C.panel,
        sel and T.C.text or T.C.border)
      fs:SetTextColor(unpack(not enabled and { 0.4, 0.42, 0.46, 1 } or T.C.text))
    end
  end
  b.Paint = paint
  b:SetScript("OnEnter", function(self) paint(self, true) end)
  b:SetScript("OnLeave", function(self) paint(self, false) end)
  b:SetScript("OnEnable", function(self) paint(self, false) end)
  b:SetScript("OnDisable", function(self) paint(self, false) end)
  function b:SetSelected(v) self.selected = v; paint(self, false) end
  paint(b, false)
  return b
end

-- square icon button (close, gear...)
function T.IconButton(parent, texture, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 22, size or 22)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexture(texture)
  b.icon:SetVertexColor(unpack(T.C.muted))
  b:SetScript("OnEnter", function(self) self.icon:SetVertexColor(unpack(T.C.text)) end)
  b:SetScript("OnLeave", function(self) self.icon:SetVertexColor(unpack(T.C.muted)) end)
  return b
end

function T.CloseButton(parent)
  local b = T.IconButton(parent, "Interface\\Buttons\\UI-StopButton", 16)
  return b
end

-- Segmented control: options = { {value, label, tip}, ... }
function T.Segmented(parent, options, get, set, w)
  local holder = CreateFrame("Frame", nil, parent)
  local bw = w or 96
  holder:SetSize(bw * #options, 26)
  holder.buttons = {}
  for i, o in ipairs(options) do
    local b = T.Button(holder, o[2], "secondary", bw + (i < #options and 1 or 0), 26)
    b:SetPoint("LEFT", (i - 1) * bw, 0)
    b:SetScript("OnClick", function() set(o[1]); holder:Refresh() end)
    if o[3] then T.Tooltip(b, o[2], o[3]) end
    holder.buttons[i] = b
  end
  function holder:Refresh()
    for i, o in ipairs(options) do self.buttons[i]:SetSelected(get() == o[1]) end
  end
  return holder
end

-- Toggle: flat checkbox + label
function T.Toggle(parent, label, get, set, tip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(260, 24)
  local box = T.Panel(b, T.C.panel, T.C.border)
  box:SetSize(18, 18)
  box:SetPoint("LEFT")
  local check = T.Fill(box, T.C.text, "ARTWORK")
  check:SetPoint("TOPLEFT", 4, -4)
  check:SetPoint("BOTTOMRIGHT", -4, 4)
  local fs = T.Text(b, "Body", "text")
  fs:SetPoint("LEFT", box, "RIGHT", 8, 0)
  fs:SetText(label)
  function b:Refresh() check:SetShown(get() and true or false) end
  b:SetScript("OnClick", function(self) set(not get()); self:Refresh() end)
  b:SetScript("OnEnter", function() box:SetBackdropBorderColor(unpack(T.C.accent)) end)
  b:SetScript("OnLeave", function() box:SetBackdropBorderColor(unpack(T.C.border)) end)
  if tip then T.Tooltip(b, label, tip) end
  b:Refresh()
  return b
end

function T.Input(parent, w, numeric)
  local e = CreateFrame("EditBox", nil, parent, BACKDROP)
  e:SetSize(w or 60, 26)
  T.Backdrop(e, T.C.panel, T.C.border)
  e:SetFontObject(T.Font.Body)
  e:SetTextInsets(8, 8, 0, 0)
  e:SetAutoFocus(false)
  e:SetJustifyH("CENTER")
  if numeric then e:SetNumeric(true) end
  e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(T.C.accent)) end)
  e:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(T.C.border)) end)
  return e
end

---------------------------------------------------------------- bars
function T.Bar(parent, color, h)
  local sb = CreateFrame("StatusBar", nil, parent)
  sb:SetStatusBarTexture(WHITE)
  sb:SetStatusBarColor(unpack(color or T.C.accent))
  sb:SetMinMaxValues(0, 1)
  sb:SetHeight(h or 8)
  local bg = T.Fill(sb, { 1, 1, 1, 0.07 }, "BACKGROUND")
  bg:SetAllPoints()
  sb.label = T.Text(sb, "Tiny", "text", "CENTER")
  sb.label:SetPoint("CENTER")
  return sb
end

---------------------------------------------------------------- tabs
function T.Tabs(parent, tabs, get, set)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(30)
  holder.items = {}
  local x = 0
  for i, t in ipairs(tabs) do
    local b = CreateFrame("Button", nil, holder)
    local fs = T.Text(b, "Header", nil, "CENTER")
    fs:SetPoint("CENTER", 0, 2)
    b:SetFontString(fs)
    b:SetText(t[2])
    b.fs = fs
    local w = math.max(80, (fs:GetStringWidth() or 60) + 28)
    b:SetSize(w, 30)
    b:SetPoint("LEFT", x, 0)
    x = x + w
    b.line = T.Fill(b, T.C.text, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT", 8, 0)
    b.line:SetPoint("BOTTOMRIGHT", -8, 0)
    b.line:SetHeight(2)
    b:SetScript("OnClick", function() set(t[1]) end)
    b:SetScript("OnEnter", function(self) if get() ~= t[1] then fs:SetTextColor(unpack(T.C.text)) end end)
    b:SetScript("OnLeave", function() holder:Refresh() end)
    b.key = t[1]
    holder.items[i] = b
  end
  local rule = T.Fill(holder, T.C.border, "BACKGROUND")
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")
  rule:SetHeight(1)
  function holder:Refresh()
    for _, b in ipairs(self.items) do
      local on = get() == b.key
      b.line:SetShown(on)
      b.fs:SetTextColor(unpack(on and T.C.text or T.C.muted))
    end
  end
  return holder
end

---------------------------------------------------------------- dropdown
-- items(): { {value, label, right, dim}, ... }
function T.Dropdown(parent, w, items, get, set)
  local b = CreateFrame("Button", nil, parent, BACKDROP)
  b:SetSize(w, 28)
  T.Backdrop(b, T.C.panel, T.C.border)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(18, 18)
  b.icon:SetPoint("LEFT", 6, 0)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.label = T.Text(b, "Body", "text")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
  b.right = T.Text(b, "Small", "muted", "RIGHT")
  b.right:SetPoint("RIGHT", -24, 0)
  local arrow = b:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", -8, 0)
  arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  arrow:SetVertexColor(unpack(T.C.muted))

  local list = T.Panel(UIParent, T.C.panel, T.C.border)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetClampedToScreen(true)
  list:Hide()
  list.rows = {}
  -- click anywhere else closes the list
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:Hide()
  catcher:SetScript("OnClick", function() list:Hide() end)
  list:SetScript("OnHide", function() catcher:Hide() end)
  b.list = list

  local function open()
    local data = items()
    for i, it in ipairs(data) do
      local r = list.rows[i]
      if not r then
        r = CreateFrame("Button", nil, list)
        r:SetHeight(26)
        r.hl = T.Fill(r, T.C.panel2, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 8, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = T.Text(r, "Body", "text")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.right = T.Text(r, "Small", "muted", "RIGHT")
        r.right:SetPoint("RIGHT", -10, 0)
        r.mark = T.Fill(r, T.C.accent, "ARTWORK")
        r.mark:SetPoint("TOPLEFT")
        r.mark:SetPoint("BOTTOMLEFT")
        r.mark:SetWidth(2)
        r:SetScript("OnEnter", function(self) self.hl:Show() end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        list.rows[i] = r
      end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 26)
      r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 26)
      r.icon:SetTexture(it.icon)
      r.text:SetText(it.label)
      r.text:SetTextColor(unpack(it.dim and T.C.muted or T.C.text))
      r.right:SetText(it.right or "")
      r.mark:SetShown(get() == it.value)
      r:SetScript("OnClick", function() list:Hide(); set(it.value) end)
      r:Show()
    end
    for i = #data + 1, #list.rows do list.rows[i]:Hide() end
    list:SetSize(w, #data * 26 + 2)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    catcher:Show()
    list:Show()
  end
  b:SetScript("OnClick", function() if list:IsShown() then list:Hide() else open() end end)
  b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(T.C.accent)) end)
  b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(T.C.border)) end)
  function b:SetValue(label, icon, right)
    self.label:SetText(label)
    self.icon:SetTexture(icon)
    self.right:SetText(right or "")
  end
  return b
end

---------------------------------------------------------------- rows
-- A pooled list of table rows inside a scroll child.
-- entry kinds:
--   { kind = "section", text, right }
--   { kind = "row", icon, item, range, title, titleColor, sub, c2, c2sub, c3, c3sub, active, indent, pin,
--     tip = { lines for the hover card, titled with the item's name },
--     hover = { title, lines } (themed hover card instead of the item tooltip) }
--   { kind = "callout", text, tone = "info"|"bad"|"good" }
--   { kind = "note", text }
--   { kind = "space" }
-- Small clickable dot that sets a map waypoint to `self.spot`
-- ({ name, zone, map, x, y }, see ns.Waypoint).
function T.Pin(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 16, size or 16)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  b.tex:SetTexture("Interface\\COMMON\\Indicator-Yellow")
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetTexture("Interface\\COMMON\\Indicator-Yellow")
  b.hl:SetBlendMode("ADD")
  b:SetScript("OnClick", function(self) if self.spot then ns.Waypoint(self.spot) end end)
  b:SetScript("OnEnter", function(self)
    local s = self.spot
    if not s then return end
    T.ShowHover(self, "Set waypoint", { ("%s, %s (%.1f, %.1f)"):format(s.name, s.zone, s.x, s.y),
      T.Muted("Marks it on your map and minimap" .. (TomTom and " (TomTom)." or ".")) }, "right")
  end)
  b:SetScript("OnLeave", function() T.HideHover() end)
  -- only spots with coordinates are clickable
  function b:SetSpot(s)
    self.spot = (s and s.map and s.x) and s or false
    self:SetShown(self.spot ~= false)
  end
  return b
end

-- Hover card in the addon's own style; every tooltip in CraftPath uses it.
-- T.ShowHover(owner, title, lines, where): lines are strings ("" = small gap),
-- where = "right" (beside the owner) or nil (above/below, whichever fits).
local hover
local MAXW = 340
function T.ShowHover(owner, title, lines, where)
  if type(lines) == "string" then lines = { lines } end
  lines = lines or {}
  if not hover then
    hover = T.Panel(UIParent, T.C.panel, T.C.border)
    hover:SetFrameStrata("TOOLTIP")
    hover:SetClampedToScreen(true)
    hover.title = T.Text(hover, "Header", "text")
    hover.title:SetPoint("TOPLEFT", 12, -10)
    hover.lines, hover.values, hover.rules = {}, {}, {}
  end
  hover.title:SetText(title or "")
  local function natural(fs)
    return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
  end
  -- a line is text, "" (small gap), "---" (divider) or { label, value }
  -- (value right-aligned, so amounts line up)
  local w = math.min(MAXW, math.max(160, natural(hover.title)))
  for i, line in ipairs(lines) do
    local fs = hover.lines[i]
    if not fs then
      fs = T.Text(hover, "Body", "text")
      fs:SetWordWrap(true)
      fs:SetJustifyV("TOP")
      hover.lines[i] = fs
      hover.values[i] = T.Text(hover, "Body", "text", "RIGHT")
      hover.rules[i] = T.Fill(hover, T.C.border, "ARTWORK")
      hover.rules[i]:SetHeight(1)
    end
    fs:SetWidth(0)
    if type(line) == "table" then
      fs:SetText(line[1])
      hover.values[i]:SetText(line[2])
      w = math.min(MAXW, math.max(w, natural(fs) + natural(hover.values[i]) + 28))
    else
      fs:SetText(line == "---" and "" or line)
      w = math.min(MAXW, math.max(w, natural(fs)))
    end
  end
  local y = -10 - (hover.title:GetStringHeight() or 16) - (#lines > 0 and 8 or 0)
  for i, line in ipairs(lines) do
    local fs, val, rule = hover.lines[i], hover.values[i], hover.rules[i]
    fs:ClearAllPoints(); val:ClearAllPoints(); rule:ClearAllPoints()
    val:Hide(); rule:Hide()
    if line == "---" then
      fs:Hide()
      rule:SetPoint("TOPLEFT", 12, y - 3)
      rule:SetPoint("TOPRIGHT", -12, y - 3)
      rule:Show()
      y = y - 8
    else
      fs:SetPoint("TOPLEFT", 12, y)
      fs:Show()
      if type(line) == "table" then
        fs:SetWidth(w - 80)
        val:SetPoint("TOPRIGHT", -12, y)
        val:SetWidth(80)
        val:Show()
      else
        fs:SetWidth(w)
      end
      y = y - (line == "" and 6 or ((fs:GetStringHeight() or 14) + 4))
    end
  end
  for i = #lines + 1, #hover.lines do hover.lines[i]:Hide(); hover.values[i]:Hide(); hover.rules[i]:Hide() end
  hover:SetSize(w + 24, -y + 6)
  hover:ClearAllPoints()
  if where == "right" then
    hover:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
  else
    local bottom = owner.GetBottom and owner:GetBottom()
    local mid = UIParent.GetHeight and UIParent:GetHeight()
    if type(bottom) == "number" and type(mid) == "number" and bottom < mid / 2 then
      hover:SetPoint("BOTTOM", owner, "TOP", 0, 6)
    else
      hover:SetPoint("TOP", owner, "BOTTOM", 0, -6)
    end
  end
  hover:Show()
end
function T.HideHover() if hover then hover:Hide() end end
T.HoverText = function() -- for tests
  if not hover or not hover:IsShown() then return "" end
  local out = { hover.title:GetText() or "" }
  for i, fs in ipairs(hover.lines) do
    if fs:IsShown() then
      local v = hover.values[i]
      table.insert(out, (fs:GetText() or "") .. (v:IsShown() and (" | " .. (v:GetText() or "")) or ""))
    end
  end
  return table.concat(out, "\n")
end

function T.Rows(child, width)
  local R = { pool = {}, used = 0, child = child, width = width }

  local function newRow()
    local r = CreateFrame("Button", nil, child)
    r.bg = T.Fill(r, T.C.stripe, "BACKGROUND")
    r.bg:SetAllPoints()
    r.accent = T.Fill(r, T.C.accent, "ARTWORK")
    r.accent:SetPoint("TOPLEFT")
    r.accent:SetPoint("BOTTOMLEFT")
    r.accent:SetWidth(3)
    r.range = T.Text(r, "Small", "muted")
    r.icon = T.Icon(r, 28)
    r.title = T.Text(r, "Body", "text")
    r.sub = T.Text(r, "Small", "muted")
    r.c2 = T.Text(r, "Body", "text", "RIGHT")
    r.c2sub = T.Text(r, "Small", "muted", "RIGHT")
    r.c3 = T.Text(r, "Body", "text", "RIGHT")
    r.c3sub = T.Text(r, "Small", "muted", "RIGHT")
    r.wide = T.Text(r, "Body", "text")
    r.wide:SetWordWrap(true)
    r.pin = T.Pin(r, 16)
    r:SetScript("OnEnter", function(self)
      if self.hover then return T.ShowHover(self, self.hover.title, self.hover.lines, "right") end
      if self.tip then
        T.ShowHover(self, self.item and ns.ItemName(self.item) or "", self.tip, "right")
      end
    end)
    r:SetScript("OnLeave", function() T.HideHover() end)
    return r
  end

  local function reset(r)
    for _, k in ipairs({ "range", "title", "sub", "c2", "c2sub", "c3", "c3sub", "wide" }) do
      r[k]:SetText(""); r[k]:Hide(); r[k]:ClearAllPoints()
    end
    r.icon:Hide()
    r.icon:ClearAllPoints()
    r.pin:SetSpot(nil)
    r.pin:ClearAllPoints()
    r.accent:Hide()
    r.bg:Show()
    r.item, r.tip, r.hover = nil, nil, nil
  end

  function R:Set(entries)
    self.text = {}
    local y, stripe = 0, false
    local W = self.width
    for i, e in ipairs(entries) do
      local r = self.pool[i] or newRow()
      self.pool[i] = r
      reset(r)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -y)
      r:SetWidth(W)
      local h
      if e.kind == "section" then
        h = 34
        r.bg:SetVertexColor(0, 0, 0, 0)
        r.title:SetFontObject(T.Font.Header)
        r.title:SetTextColor(unpack(T.C.text))
        r.title:SetPoint("BOTTOMLEFT", 6, 7)
        r.title:SetText(e.text); r.title:Show()
        if e.right then
          r.c3:SetPoint("BOTTOMRIGHT", -8, 8); r.c3:SetText(e.right); r.c3:Show()
        end
        stripe = false
        table.insert(self.text, e.text .. (e.right and ("  " .. e.right) or ""))
      elseif e.kind == "callout" then
        local c = T.C[e.tone or "info"]
        r.bg:SetVertexColor(c[1], c[2], c[3], 0.12)
        r.accent:SetVertexColor(unpack(c)); r.accent:Show()
        r.wide:SetPoint("TOPLEFT", 12, -7); r.wide:SetWidth(W - 24)
        r.wide:SetText(e.text); r.wide:Show()
        h = math.max(30, (r.wide:GetStringHeight() or 14) + 14)
        table.insert(self.text, e.text)
      elseif e.kind == "note" then
        r.bg:SetVertexColor(0, 0, 0, 0)
        r.wide:SetPoint("TOPLEFT", 6, -4); r.wide:SetWidth(W - 12)
        r.wide:SetText(T.Muted(e.text)); r.wide:Show()
        h = math.max(22, (r.wide:GetStringHeight() or 14) + 8)
        table.insert(self.text, e.text)
      elseif e.kind == "space" then
        r.bg:SetVertexColor(0, 0, 0, 0)
        h = 10
      elseif e.kind == "header" then
        -- column labels, laid out exactly like the rows below:
        -- { kind = "header", range, title, c2, c3, icon = true, pin = true }
        h = 24
        r.bg:SetVertexColor(0, 0, 0, 0)
        local x = 10
        if e.range then
          r.range:SetPoint("LEFT", x, 0); r.range:SetText(e.range); r.range:Show()
          x = x + 66
        end
        if e.pin then x = x + 24 end
        if e.icon then x = x + 36 end
        r.title:SetFontObject(T.Font.Small)
        r.title:SetTextColor(unpack(T.C.muted))
        r.title:SetPoint("LEFT", x, 0); r.title:SetWidth(W - x - 260)
        r.title:SetText(e.title or ""); r.title:Show()
        for _, c in ipairs({ { r.c2, e.c2, 136 }, { r.c3, e.c3, 10 } }) do
          if c[2] then
            c[1]:SetWidth(120); c[1]:SetPoint("RIGHT", -c[3], 0)
            c[1]:SetText(T.Muted(c[2])); c[1]:Show()
          end
        end
        stripe = false
        table.insert(self.text, table.concat({ e.range or "", e.title or "", e.c2 or "", e.c3 or "" }, " | "))
      else -- row
        local two = e.sub or e.c2sub or e.c3sub
        h = two and 44 or 30
        stripe = not stripe
        r.bg:SetVertexColor(1, 1, 1, stripe and 0.03 or 0)
        if e.active then
          r.bg:SetVertexColor(1, 1, 1, 0.07)
          r.accent:SetVertexColor(unpack(T.C.text)); r.accent:Show()
        end
        local x = 10 + (e.indent and 28 or 0)
        if e.range then
          r.range:SetPoint("LEFT", x, 0); r.range:SetText(e.range); r.range:Show()
          x = x + 66
        end
        if e.pin then -- keep the column even when there's no dot
          if e.pin.map then r.pin:SetPoint("LEFT", x, 0); r.pin:SetSpot(e.pin) end
          x = x + 24
        end
        if e.icon or e.item then
          r.icon:SetPoint("LEFT", x, 0); r.icon:SetIcon(e.icon or e.item); r.icon:Show()
          x = x + 36
        end
        r.item, r.tip, r.hover = e.item, e.tip, e.hover
        local right = 260
        r.title:SetFontObject(T.Font.Body)
        r.title:SetTextColor(unpack(T.C.text))
        if two then
          r.title:SetPoint("TOPLEFT", x, -7)
          r.sub:SetPoint("TOPLEFT", x, -25); r.sub:SetWidth(W - x - right); r.sub:SetText(e.sub or ""); r.sub:Show()
        else
          r.title:SetPoint("LEFT", x, 0)
        end
        r.title:SetWidth(W - x - right)
        r.title:SetText(e.titleColor and ("|cff" .. e.titleColor .. e.title .. "|r") or e.title)
        r.title:Show()
        local function col(fs, fsub, text, sub, rightX, width)
          if not text then return end
          fs:SetWidth(width); fsub:SetWidth(width)
          if two then
            fs:SetPoint("TOPRIGHT", -rightX, -7)
            fsub:SetPoint("TOPRIGHT", -rightX, -25); fsub:SetText(sub or ""); fsub:Show()
          else
            fs:SetPoint("RIGHT", -rightX, 0)
          end
          fs:SetText(text); fs:Show()
        end
        col(r.c3, r.c3sub, e.c3, e.c3sub, 10, 120)
        col(r.c2, r.c2sub, e.c2, e.c2sub, 136, 120)
        table.insert(self.text, table.concat({ e.range or "", e.title or "", e.sub or "", e.c2 or "", e.c2sub or "",
          e.c3 or "", e.c3sub or "" }, "  "))
      end
      r:SetHeight(h)
      r:Show()
      y = y + h
    end
    for i = #entries + 1, #self.pool do self.pool[i]:Hide() end
    self.child:SetHeight(math.max(y, 10))
  end

  -- plain text of what's shown (for tests / debugging)
  function R:Text() return table.concat(self.text or {}, "\n") end
  return R
end
