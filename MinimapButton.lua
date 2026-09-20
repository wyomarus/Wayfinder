-- MinimapButton adds a draggable minimap button for quick access to Wayfinder:
-- left-click toggles the compass banner, right-click opens the Settings panel.

local _, addon = ...
local _p = addon.private
local api = addon.API

local CreateFrame = CreateFrame
local Minimap = Minimap
local GetCursorPosition = GetCursorPosition
local GameTooltip = GameTooltip
local rad, deg, atan2, cos, sin = math.rad, math.deg, math.atan2, math.cos, math.sin

-- Known WoW: Forever beta bug affecting SavedVariables persistence in general - see
-- CardinalPoints.lua's compassDetail comment for details.
WayfinderSettings = WayfinderSettings or {}

-- Degrees around the minimap, matching where most addons' buttons start (upper-right).
local DEFAULT_ANGLE = 45

local minimapAngle = WayfinderSettings.minimapAngle
if minimapAngle == nil then
    minimapAngle = DEFAULT_ANGLE
end
WayfinderSettings.minimapAngle = minimapAngle

local button = CreateFrame("Button", "WayfinderMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 1, 1)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- crop the icon's edges, like most minimap buttons do
button.icon = icon

local border = button:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT")

--- Place the button at its saved angle around the minimap's edge.
local function updatePosition()
    local angle = rad(minimapAngle)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", cos(angle) * radius, sin(angle) * radius)
end

button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local minimapX, minimapY = Minimap:GetCenter()
        local cursorX, cursorY = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cursorX, cursorY = cursorX / scale, cursorY / scale

        minimapAngle = deg(atan2(cursorY - minimapY, cursorX - minimapX))
        WayfinderSettings.minimapAngle = minimapAngle
        updatePosition()
    end)
end)

button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "LeftButton" then
        if api.CompassBanner.IsShown() then
            _p.disableCompassBanner()
        else
            _p.enableCompassBanner()
        end
    elseif mouseButton == "RightButton" then
        api.Settings.Open()
    end
end)

button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Wayfinder")
    local toggleLabel = api.CompassBanner.IsShown() and "Hide" or "Show"
    GameTooltip:AddLine("Left-click: " .. toggleLabel .. " compass banner", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Open settings", 1, 1, 1)
    GameTooltip:Show()
end)

button:SetScript("OnLeave", GameTooltip_Hide)

updatePosition()
