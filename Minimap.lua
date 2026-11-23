-- CraftPath minimap button.
-- Uses LibDataBroker + LibDBIcon when another addon has loaded them (the
-- standard way minimap collectors such as MinimapButtonButton gather
-- buttons). Otherwise it creates a normal named button parented to the
-- Minimap, the same shape as LibDBIcon buttons, which collectors also pick up.
local ADDON, ns = ...

local ICON = "Interface\\AddOns\\CraftPath\\Media\\Icon"
local Mini = {}
ns.Minimap = Mini

local function onClick(button)
  if button == "RightButton" then ns.Tracker:Toggle() else ns.UI:Toggle() end
end

local function tooltip(tt)
  tt:AddLine("CraftPath")
  local prof = ns.Prof()
  local rank = ns.ReadSkill()
  tt:AddLine(("%s  %s / %d"):format(ns.ProfName(prof), rank or "?", ns.Target()), 1, 1, 1)
  tt:AddLine("Left-click: planner   Right-click: tracker", 0.7, 0.7, 0.7)
end

---------------------------------------------------------------- LibDBIcon
local function libs()
  if not LibStub then return end
  local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
  local icon = LibStub:GetLibrary("LibDBIcon-1.0", true)
  if ldb and icon then return ldb, icon end
end

---------------------------------------------------------------- own button
local button
local function updatePosition()
  local angle = math.rad(ns.db.minimap.minimapPos or 210)
  local radius = ((Minimap:GetWidth() or 140) / 2) + 5
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function createButton()
  local b = CreateFrame("Button", "CraftPathMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(21, 21)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0, 1, 0, 1)
  icon:SetPoint("TOPLEFT", 6, -5)
  b.icon = icon
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function(_, mouse) onClick(mouse) end)
  b:SetScript("OnEnter", function(self)
    local rank = ns.ReadSkill()
    ns.T.ShowHover(self, "CraftPath", { ("%s  %s / %d"):format(ns.ProfName(ns.Prof()), rank or "?", ns.Target()),
      ns.T.Muted("Left-click: planner   Right-click: tracker") })
  end)
  b:SetScript("OnLeave", function() ns.T.HideHover() end)
  -- drag around the minimap edge
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local scale = Minimap:GetEffectiveScale() or 1
      local cx, cy = GetCursorPosition()
      cx, cy = cx / scale, cy / scale
      ns.db.minimap.minimapPos = math.deg(math.atan2(cy - my, cx - mx)) % 360
      updatePosition()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  return b
end

---------------------------------------------------------------- public
function Mini:Init()
  ns.db.minimap = ns.db.minimap or { hide = false, minimapPos = 210 }
  local ldb, dbicon = libs()
  if ldb and dbicon then
    local obj = ldb:NewDataObject("CraftPath", {
      type = "launcher", text = "CraftPath", icon = ICON,
      OnClick = function(_, mouse) onClick(mouse) end,
      OnTooltipShow = tooltip,
    })
    dbicon:Register("CraftPath", obj, ns.db.minimap)
    self.lib = dbicon
    return
  end
  if not Minimap then return end
  button = createButton()
  self.button = button
  updatePosition()
  button:SetShown(not ns.db.minimap.hide)
end

function Mini:SetShown(show)
  ns.db.minimap.hide = not show
  if self.lib then
    if show then self.lib:Show("CraftPath") else self.lib:Hide("CraftPath") end
  elseif button then
    button:SetShown(show)
  end
end
