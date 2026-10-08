-- Settings builds Wayfinder's options page in Blizzard's native addon Settings panel.
--
-- It's a single canvas category built only from our own frames, not a vertical-layout
-- category of Blizzard's Settings.Create* controls. Those controls are pooled frames the
-- panel reuses for every category, and it reads our initializers and calls our options
-- functions without securecallfunction, so they carried Wayfinder's taint onto frames it
-- later reused for Blizzard's own settings (e.g. Nameplates), where it can break Blizzard
-- code that runs there. Own frames keep our taint on our frames. The panel calls a canvas
-- frame's OnRefresh and OnDefault through securecallfunction, so those are safe to define.
--
-- The page copies the look of Blizzard's own settings pages (gold label on the left, its
-- control in a column on the right, a highlight and tooltip on hover, steppers for choices)
-- using plain frames and textures, so none of it depends on Blizzard's pooled templates.

local addonName, addon = ...
local _p = addon.private
local api = addon.API
local _C = addon.Constants

-- Cache global references
local CreateFrame = CreateFrame
local C_Texture = C_Texture
local C_Timer = C_Timer
local ScrollUtil = ScrollUtil
local GameTooltip = GameTooltip
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
local GetAddOnMetadata = C_AddOns.GetAddOnMetadata

local DetailLevel = _C.CompassDetail
local BannerOverlay = _C.BannerOverlay

local ICON = "Interface\\AddOns\\Wayfinder\\Media\\Icon.jpg"

-- Page layout. Every row is ROW_WIDTH wide: the label starts LABEL_X in (further for a
-- sub-setting), and the control sits in a column starting at CONTROL_X. Rows are spaced
-- ROW_GAP apart (35 pixels from one row to the next, as on Blizzard's own pages).
local ROW_HEIGHT = 26
local ROW_GAP = 9
local LABEL_X = 10
local SUBROW_INDENT = 18
local CONTROL_X = 250
local CONTROL_WIDTH = 260
local ROW_WIDTH = CONTROL_X + CONTROL_WIDTH
local SECTION_HEIGHT = 45
local SECTION_TITLE_X = 7
local ARROW_SIZE = 24

-- Blizzard's own checkbox art, where this client has it; classic checkbox art otherwise.
local CHECKBOX_ATLAS = "checkbox-minimal"
local CHECKMARK_ATLAS = "checkmark-minimal"
local CHECKBOX_FALLBACK = "Interface\\Buttons\\UI-CheckBox-Up"
local CHECKMARK_FALLBACK = "Interface\\Buttons\\UI-CheckBox-Check"
local checkboxAtlasAvailable = C_Texture and C_Texture.GetAtlasInfo
    and C_Texture.GetAtlasInfo(CHECKBOX_ATLAS) ~= nil
    and C_Texture.GetAtlasInfo(CHECKMARK_ATLAS) ~= nil

-- The background of Blizzard's dropdown buttons, behind a stepper's value.
local BAR_ATLAS = "common-dropdown-textholder"
local BAR_ART_PADDING = 8
local barAtlasAvailable = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BAR_ATLAS) ~= nil

-- The arrow of those dropdowns, which also serves as a stepper's buttons. It has a variant
-- for each button state.
local ARROW_ATLAS = "common-dropdown-a-button"
local arrowAtlasAvailable = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ARROW_ATLAS) ~= nil
    and C_Texture.GetAtlasInfo(ARROW_ATLAS .. "-hover") ~= nil
    and C_Texture.GetAtlasInfo(ARROW_ATLAS .. "-pressed") ~= nil
    and C_Texture.GetAtlasInfo(ARROW_ATLAS .. "-pressedhover") ~= nil
    and C_Texture.GetAtlasInfo(ARROW_ATLAS .. "-disabled") ~= nil

local TITLE_FONT =_G.GameFontHighlightHuge2 and "GameFontHighlightHuge2" or "GameFontHighlightLarge"

local panel = CreateFrame("Frame")
panel:Hide()

-- The page is taller than the panel at some window sizes and UI scales, so every control
-- lives on a frame inside a scroll frame rather than on the panel itself.
local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 4)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(1, 1)
scrollFrame:SetScrollChild(content)

local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -2)
scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 2)
ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar)

-- Sizes the scroll frame's content to fit the controls; assigned once they're all placed.
local updateContentHeight

scrollFrame:SetScript("OnSizeChanged", function(_, width)
    content:SetWidth(width)
    C_Timer.After(0, updateContentHeight)
end)

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
    C_Timer.After(0, updateContentHeight)
end

-- Called by the Settings panel's "Defaults" button. Banner position isn't a setting here,
-- just a button, so like before it isn't reset by this.
function panel.OnDefault()
    _p.enableCompassBanner()
    api.CompassBanner.Lock()
    api.CardinalPoints.SetDetail(DetailLevel.Pips)
    api.CompassBanner.SetOverlay(BannerOverlay.Off)
    api.CompassBanner.SetShowCenterLine(true)
    api.SuperTracking.Enable()
    api.SuperTracking.SetShowDistance(true)
    api.SuperTracking.SetShowETA(true)
end

_p.refreshSettingsPanel = function()
    if panel:IsVisible() then refreshPanel() end
end

-- Page layout: each row is anchored below the previous one, so the page reflows if a
-- row's height (e.g. the wrapped notes text) changes. Indents are relative to the page's
-- left margin.
local previous, previousIndent

--- @param region table
--- @param indent number
--- @param gap number Vertical space above region.
local function place(region, indent, gap)
    region:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", indent - previousIndent, -gap)
    previous, previousIndent = region, indent
end

local function createSectionHeader(text)
    local header = CreateFrame("Frame", nil, content)
    -- The gap above the first row below the header is part of the header's height.
    header:SetSize(ROW_WIDTH, SECTION_HEIGHT - ROW_GAP)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", SECTION_TITLE_X, -16)
    title:SetText(text)

    place(header, 0, 0)
    return header
end

--- A row of the page: a label on the left that, like Blizzard's own settings, highlights
--- and shows a tooltip while the mouse is over the row or anything on it.
--- @param label string
--- @param getTooltip function Returns the tooltip's title and text, read each time it shows.
--- @param isSubrow boolean|nil Whether this is a smaller, indented sub-setting of the row above.
--- @return table row
local function createRow(label, getTooltip, isSubrow)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:EnableMouse(true)

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints(row)
    highlight:SetColorTexture(1, 1, 1, 0.1)
    highlight:Hide()

    row.label = row:CreateFontString(nil, "OVERLAY", isSubrow and "GameFontNormalSmall" or "GameFontNormal")
    row.label:SetPoint("LEFT", LABEL_X + (isSubrow and SUBROW_INDENT or 0), 0)
    row.label:SetText(label)
    row.isSubrow = isSubrow

    local function setHovered(hovered)
        highlight:SetShown(hovered)
        if hovered then
            local title, text = getTooltip()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(text, nil, nil, nil, true)
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end
    row:SetScript("OnEnter", function() setHovered(true) end)
    row:SetScript("OnLeave", function() setHovered(false) end)

    --- A control on the row takes the mouse from the row itself, so it has to pass its
    --- hover state back.
    --- @param frame table
    function row.LinkHover(frame)
        frame:HookScript("OnEnter", function() setHovered(true) end)
        frame:HookScript("OnLeave", function() setHovered(false) end)
    end

    --- @param enabled boolean
    function row:SetLabelEnabled(enabled)
        local normal = self.isSubrow and "GameFontNormalSmall" or "GameFontNormal"
        local disabled = self.isSubrow and "GameFontDisableSmall" or "GameFontDisable"
        self.label:SetFontObject(enabled and normal or disabled)
    end

    place(row, 0, ROW_GAP)
    return row
end

--- @param label string
--- @param tooltip string
--- @param getValue function
--- @param setValue function Called with the new checked state.
--- @param isEnabled function|nil Whether the checkbox is clickable; always, if nil.
--- @param isSubrow boolean|nil
local function createCheckbox(label, tooltip, getValue, setValue, isEnabled, isSubrow)
    local row = createRow(label, function() return label, tooltip end, isSubrow)

    local checkbox = CreateFrame("CheckButton", nil, row)
    checkbox:SetSize(ROW_HEIGHT, ROW_HEIGHT)
    checkbox:SetPoint("LEFT", CONTROL_X, 0)
    row.LinkHover(checkbox)

    local box = checkbox:CreateTexture(nil, "ARTWORK")
    box:SetAllPoints(checkbox)
    local mark = checkbox:CreateTexture(nil, "OVERLAY")
    mark:SetAllPoints(checkbox)
    if checkboxAtlasAvailable then
        box:SetAtlas(CHECKBOX_ATLAS)
        mark:SetAtlas(CHECKMARK_ATLAS)
    else
        box:SetTexture(CHECKBOX_FALLBACK)
        mark:SetTexture(CHECKMARK_FALLBACK)
    end

    local function showCheckState()
        mark:SetShown(checkbox:GetChecked())
    end

    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        showCheckState()
        setValue(checked)
    end)

    function checkbox:Refresh()
        self:SetChecked(getValue())
        showCheckState()
        local enabled = not isEnabled or isEnabled()
        self:SetEnabled(enabled)
        box:SetDesaturated(not enabled)
        mark:SetDesaturated(not enabled)
        row:SetLabelEnabled(enabled)
    end

    table.insert(controls, checkbox)
    return checkbox
end

--- The arrow of a stepper's button for its current state, from the same button art as the
--- arrow of Blizzard's dropdowns, which matches the value's background.
--- @param button table
--- @return string atlas
local function getArrowAtlas(button)
    if not button:IsEnabled() then
        return ARROW_ATLAS .. "-disabled"
    elseif button.isDown and button.isOver then
        return ARROW_ATLAS .. "-pressedhover"
    elseif button.isOver then
        return ARROW_ATLAS .. "-hover"
    elseif button.isDown then
        return ARROW_ATLAS .. "-pressed"
    end
    return ARROW_ATLAS
end

--- A button that moves the stepper's selection one way. Blizzard's dropdown arrow art points
--- down, so it's turned to point the way the button steps. Without that art, the classic
--- page-arrow textures that every client has.
--- @param parent table
--- @param direction string "Prev" or "Next"
--- @param onClick function
local function createArrowButton(parent, direction, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ARROW_SIZE, ARROW_SIZE)
    button:SetScript("OnClick", onClick)

    if arrowAtlasAvailable then
        local arrow = button:CreateTexture(nil, "ARTWORK")
        arrow:SetPoint("CENTER", 0, -2)
        arrow:SetRotation(direction == "Prev" and -math.pi / 2 or math.pi / 2)

        local function showState()
            arrow:SetAtlas(getArrowAtlas(button), true)
        end
        button:SetScript("OnEnter", function() button.isOver = true; showState() end)
        button:SetScript("OnLeave", function() button.isOver, button.isDown = false, false; showState() end)
        button:SetScript("OnMouseDown", function() button.isDown = true; showState() end)
        button:SetScript("OnMouseUp", function() button.isDown = false; showState() end)
        button:SetScript("OnEnable", showState)
        button:SetScript("OnDisable", showState)
        showState()
    else
        local path = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
        button:SetNormalTexture(path .. "Up")
        button:SetPushedTexture(path .. "Down")
        button:SetDisabledTexture(path .. "Disabled")
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    end

    return button
end

--- A choice between a fixed list of options, shown as the current option between a pair of
--- arrows that step through the list, like Blizzard's own stepper settings.
--- @param label string
--- @param options table A list of { value = ..., label = string, tooltip = string }.
--- @param getValue function Returns the value of the current option.
--- @param setValue function Called with the value of the option stepped to.
--- @param isEnabled function|nil Whether the stepper is usable; always, if nil.
local function createStepper(label, options, getValue, setValue, isEnabled)
    local selected = 1
    local row = createRow(label, function()
        return label, options[selected].tooltip
    end)

    local stepper = CreateFrame("Frame", nil, row)
    stepper:SetSize(CONTROL_WIDTH, ARROW_SIZE)
    stepper:SetPoint("LEFT", CONTROL_X, 0)
    row.LinkHover(stepper)

    local function step(direction)
        local option = options[selected + direction]
        if not option then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        setValue(option.value)
    end

    local previousButton = createArrowButton(stepper, "Prev", function() step(-1) end)
    previousButton:SetPoint("LEFT")
    local nextButton = createArrowButton(stepper, "Next", function() step(1) end)
    nextButton:SetPoint("RIGHT")
    row.LinkHover(previousButton)
    row.LinkHover(nextButton)

    -- The value sits on the same button-style background Blizzard's dropdowns use. The art
    -- is padded past the button's edges, so it's inset from the arrows to end where they do.
    local bar = CreateFrame("Frame", nil, stepper)
    bar:SetPoint("TOPLEFT", previousButton, "TOPRIGHT", BAR_ART_PADDING, 0)
    bar:SetPoint("BOTTOMRIGHT", nextButton, "BOTTOMLEFT", -BAR_ART_PADDING, 0)

    local barBackground = bar:CreateTexture(nil, "BACKGROUND")
    if barAtlasAvailable then
        barBackground:SetAtlas(BAR_ATLAS)
        barBackground:SetPoint("TOPLEFT", bar, "TOPLEFT", -BAR_ART_PADDING, 7)
        barBackground:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", BAR_ART_PADDING, -9)
    else
        barBackground:SetColorTexture(0, 0, 0, 0.5)
        barBackground:SetAllPoints(bar)
    end

    stepper.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    stepper.text:SetPoint("CENTER", bar)

    function stepper:Refresh()
        local value = getValue()
        selected = 1
        for index, option in ipairs(options) do
            if option.value == value then selected = index end
        end
        self.text:SetText(options[selected].label)

        local enabled = not isEnabled or isEnabled()
        previousButton:SetEnabled(enabled and selected > 1)
        nextButton:SetEnabled(enabled and selected < #options)
        self.text:SetFontObject(enabled and "GameFontHighlight" or "GameFontDisable")
        row:SetLabelEnabled(enabled)
    end

    table.insert(controls, stepper)
    return stepper
end

--- A button row: a label on the left and a button in the control column.
--- @param label string
--- @param buttonText string
--- @param tooltip string
--- @param onClick function
--- @param isEnabled function|nil Whether the button is clickable; always, if nil.
local function createButtonRow(label, buttonText, tooltip, onClick, isEnabled)
    local row = createRow(label, function() return label, tooltip end)

    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetText(buttonText)
    button:SetSize(140, 22)
    button:SetPoint("LEFT", CONTROL_X, 0)
    button:SetScript("OnClick", onClick)
    row.LinkHover(button)

    function button:Refresh()
        local enabled = not isEnabled or isEnabled()
        self:SetEnabled(enabled)
        row:SetLabelEnabled(enabled)
    end

    table.insert(controls, button)
    return button
end

-- Page header: icon, name, version, author, and the .toc's notes, over a divider.

local icon = content:CreateTexture(nil, "ARTWORK")
icon:SetTexture(ICON)
icon:SetSize(48, 48)
icon:SetPoint("TOPLEFT", SECTION_TITLE_X, -12)

local title = content:CreateFontString(nil, "ARTWORK", TITLE_FONT)
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
title:SetText(GetAddOnMetadata(addonName, "Title") or addonName)

local byline = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
byline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
byline:SetText(
    "Version " .. (GetAddOnMetadata(addonName, "Version") or "unknown")
    .. "  -  By " .. (GetAddOnMetadata(addonName, "Author") or "unknown")
    .. "  -  MIT License"
)

local divider = content:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(1, 1, 1, 0.2)
divider:SetHeight(1)
divider:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -SECTION_TITLE_X, -8)
divider:SetWidth(ROW_WIDTH)

local notes = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
notes:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", SECTION_TITLE_X, -10)
notes:SetWidth(ROW_WIDTH - 2 * SECTION_TITLE_X)
notes:SetJustifyH("LEFT")
notes:SetJustifyV("TOP")
notes:SetText(GetAddOnMetadata(addonName, "Notes") or "")

previous, previousIndent = notes, SECTION_TITLE_X

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
    true
)

createButtonRow(
    "Banner position", "Reset position", "Reset the compass banner to its default position.",
    function() api.CompassBanner.ResetPosition() end,
    api.CompassBanner.IsShown
)

createStepper("Banner background", {
    { value = BannerOverlay.Off, label = "Off", tooltip = "No background behind the banner." },
    { value = BannerOverlay.Subtle, label = "Subtle", tooltip = "A faint dark fade behind the banner." },
    { value = BannerOverlay.Medium, label = "Medium", tooltip = "A dark fade behind the banner." },
    { value = BannerOverlay.Strong, label = "Strong", tooltip = "A strong dark fade behind the banner, for busy backgrounds." },
}, api.CompassBanner.GetOverlay, api.CompassBanner.SetOverlay, api.CompassBanner.IsShown)

createStepper("Compass detail", {
    { value = DetailLevel.None, label = "None", tooltip = "Hide compass detail entirely." },
    { value = DetailLevel.Cardinals, label = "Cardinals", tooltip = "Cardinal directions only (N, E, S, W)." },
    { value = DetailLevel.Intercardinals, label = "Intercardinals", tooltip = "Cardinal and intercardinal directions." },
    { value = DetailLevel.Pips, label = "Pips", tooltip = "Cardinal, intercardinal, and a tick every 15 degrees." },
}, api.CardinalPoints.GetDetail, api.CardinalPoints.SetDetail, api.CompassBanner.IsShown)

createCheckbox(
    "Show center line", "Show the line at the middle of the banner marking the direction you're facing. Not shown when compass detail is None.",
    api.CompassBanner.GetShowCenterLine, api.CompassBanner.SetShowCenterLine,
    function() return api.CompassBanner.IsShown() and api.CardinalPoints.GetDetail() ~= DetailLevel.None end
)

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
    api.SuperTracking.IsEnabled, true
)

createCheckbox(
    "Show ETA", "Show an estimated time of arrival to the super-tracked target.",
    api.SuperTracking.GetShowETA, api.SuperTracking.SetShowETA,
    api.SuperTracking.IsEnabled, true
)

-- Run after layout has settled (hence the C_Timer.After(0) at each call site), since a
-- frame's edges aren't known until then and the wrapped notes text changes its height.
updateContentHeight = function()
    local top, bottom = content:GetTop(), previous:GetBottom()
    if top and bottom then
        content:SetHeight(top - bottom + 16)
    end
end

local category = Settings.RegisterCanvasLayoutCategory(panel, "Wayfinder")
Settings.RegisterAddOnCategory(category)

api.Settings = {
    Open = function() Settings.OpenToCategory(category:GetID()) end,
}
