-- Settings builds Wayfinder's options page in Blizzard's native addon Settings panel.
--
-- It's a single canvas category built only from our own frames, not a vertical-layout
-- category of Blizzard's Settings.Create* controls. Those controls are pooled frames the
-- panel reuses for every category, and it reads our initializers and calls our options
-- functions without securecallfunction, so they carried Wayfinder's taint onto frames it
-- later reused for Blizzard's own settings (e.g. Nameplates), where it can break Blizzard
-- code that runs there. Own frames keep our taint on our frames. The panel calls a canvas
-- frame's OnRefresh and OnDefault through securecallfunction, so those are safe to define.

local addonName, addon = ...
local _p = addon.private
local api = addon.API
local _C = addon.Constants

-- Cache global references
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
local GetAddOnMetadata = C_AddOns.GetAddOnMetadata

local DetailLevel = _C.CompassDetail

local ICON = "Interface\\AddOns\\Wayfinder\\Media\\Icon.jpg"
local SUBCONTROL_INDENT = 24

local panel = CreateFrame("Frame")
panel:Hide()

-- Every control on the page, each with a Refresh method that reads its current value.
local controls = {}

local function refreshPanel()
    for _, control in ipairs(controls) do
        control:Refresh()
    end
end

-- Called by the Settings panel each time the page is shown.
function panel.OnRefresh()
    refreshPanel()
end

-- Called by the Settings panel's "Defaults" button. Banner position isn't a setting here,
-- just a button, so like before it isn't reset by this.
function panel.OnDefault()
    _p.enableCompassBanner()
    api.CompassBanner.Lock()
    api.CardinalPoints.SetDetail(DetailLevel.Pips)
    api.SuperTracking.Enable()
    api.SuperTracking.SetShowDistance(true)
    api.SuperTracking.SetShowETA(true)
end

_p.refreshSettingsPanel = function()
    if panel:IsVisible() then refreshPanel() end
end

--- Show a title-and-description tooltip for a control while the mouse is over it.
--- @param frame table
--- @param title string
--- @param description string
local function attachTooltip(frame, title, description)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(description, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

--- Stretch a check or radio button's clickable area across its label, as Blizzard's own
--- settings controls do, rather than just the small box.
--- @param button table
--- @param label table The button's FontString.
local function extendHitRectOverLabel(button, label)
    button:SetHitRectInsets(0, -(label:GetStringWidth() + 8), 0, 0)
end

-- Page layout: each control is anchored below the previous one, so the page reflows if a
-- control's height (e.g. the wrapped notes text) changes. Indents are relative to the
-- page's left margin.
local previous, previousIndent

--- @param region table
--- @param indent number
--- @param gap number Vertical space above region.
local function place(region, indent, gap)
    region:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", indent - previousIndent, -gap)
    previous, previousIndent = region, indent
end

local function createSectionHeader(text)
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    header:SetText(text)
    place(header, 0, 24)
    return header
end

--- @param label string
--- @param tooltip string
--- @param getValue function
--- @param setValue function Called with the new checked state.
--- @param isEnabled function|nil Whether the checkbox is clickable; always, if nil.
--- @param indent number|nil
local function createCheckbox(label, tooltip, getValue, setValue, isEnabled, indent)
    local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    checkbox.Text:SetFontObject("GameFontHighlight")
    checkbox.Text:SetText(label)
    extendHitRectOverLabel(checkbox, checkbox.Text)
    attachTooltip(checkbox, label, tooltip)

    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        setValue(checked)
    end)

    function checkbox:Refresh()
        self:SetChecked(getValue())
        local enabled = not isEnabled or isEnabled()
        self:SetEnabled(enabled)
        self.Text:SetFontObject(enabled and "GameFontHighlight" or "GameFontDisable")
    end

    place(checkbox, indent or 0, 4)
    table.insert(controls, checkbox)
    return checkbox
end

--- One of the compass detail radio buttons.
--- @param level number One of the DetailLevel values.
--- @param label string
--- @param tooltip string
local function createDetailRadio(level, label, tooltip)
    local radio = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
    radio.text:SetFontObject("GameFontHighlight")
    radio.text:SetText(label)
    extendHitRectOverLabel(radio, radio.text)
    attachTooltip(radio, label, tooltip)

    radio:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        api.CardinalPoints.SetDetail(level)
    end)

    function radio:Refresh()
        self:SetChecked(api.CardinalPoints.GetDetail() == level)
    end

    -- Radio buttons are smaller than checkboxes; nudge them in to line up with the boxes.
    place(radio, 8, 10)
    table.insert(controls, radio)
    return radio
end

-- About header: icon, name, version, author, and the .toc's notes.

local icon = panel:CreateTexture(nil, "ARTWORK")
icon:SetTexture(ICON)
icon:SetSize(64, 64)
icon:SetPoint("TOPLEFT", 16, -16)

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -4)
title:SetText(GetAddOnMetadata(addonName, "Title") or addonName)

local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
version:SetText("Version " .. (GetAddOnMetadata(addonName, "Version") or "unknown"))

local author = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
author:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -2)
author:SetText("By " .. (GetAddOnMetadata(addonName, "Author") or "unknown") .. " - MIT License")

local notes = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
notes:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12)
notes:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
notes:SetJustifyH("LEFT")
notes:SetJustifyV("TOP")
notes:SetText(GetAddOnMetadata(addonName, "Notes") or "")

previous, previousIndent = notes, 0

-- Compass banner

createSectionHeader("Compass banner")

createCheckbox(
    "Show compass banner", "Show or hide the compass banner.",
    api.CompassBanner.IsShown,
    function(shown)
        if shown then _p.enableCompassBanner() else _p.disableCompassBanner() end
    end
)

createCheckbox(
    "Lock position", "Lock the banner in place, or unlock it to drag to a new position.",
    api.CompassBanner.IsLocked,
    function(locked)
        if locked then api.CompassBanner.Lock() else api.CompassBanner.Unlock() end
    end,
    api.CompassBanner.IsShown,
    SUBCONTROL_INDENT
)

local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetButton:SetText("Reset position")
resetButton:SetSize(140, 22)
resetButton:SetScript("OnClick", function() api.CompassBanner.ResetPosition() end)
attachTooltip(resetButton, "Reset position", "Reset the compass banner to its default position.")
place(resetButton, 4, 8)

-- Compass detail

createSectionHeader("Compass detail")

createDetailRadio(DetailLevel.None, "None", "Hide compass detail entirely.")
createDetailRadio(DetailLevel.Cardinals, "Cardinals", "Cardinal directions only (N, E, S, W).")
createDetailRadio(DetailLevel.Intercardinals, "Intercardinals", "Cardinal and intercardinal directions.")
createDetailRadio(DetailLevel.Pips, "Pips", "Cardinal, intercardinal, and a tick every 15 degrees.")

-- SuperTracking

createSectionHeader("SuperTracking")

createCheckbox(
    "Enable tracking", "Show a marker on the compass banner for whatever you're currently super-tracking.",
    api.SuperTracking.IsEnabled,
    function(enabled)
        if enabled then api.SuperTracking.Enable() else api.SuperTracking.Disable() end
    end
)

createCheckbox(
    "Show distance", "Show the distance to the super-tracked target.",
    api.SuperTracking.GetShowDistance, api.SuperTracking.SetShowDistance,
    api.SuperTracking.IsEnabled, SUBCONTROL_INDENT
)

createCheckbox(
    "Show ETA", "Show an estimated time of arrival to the super-tracked target.",
    api.SuperTracking.GetShowETA, api.SuperTracking.SetShowETA,
    api.SuperTracking.IsEnabled, SUBCONTROL_INDENT
)

local category = Settings.RegisterCanvasLayoutCategory(panel, "Wayfinder")
Settings.RegisterAddOnCategory(category)

api.Settings = {
    Open = function() Settings.OpenToCategory(category:GetID()) end,
}
