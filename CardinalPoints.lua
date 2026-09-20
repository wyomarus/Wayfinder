-- CardinalPoints manages the cardinal, intercardinal, and fine-detail tick marks
-- on the compass banner, and the user's chosen level of detail for them.

local _, addon = ...
local api = addon.API

-- Known WoW: Forever beta bug: SavedVariables are written to disk correctly but not
-- reliably read back on /reload or client restart (confirmed independently of this
-- addon: https://github.com/ClassicWoWCommunity/forever-bugs/issues/34). Wayfinder.toc's
-- LoadSavedVariablesFirst is the objectively correct setting for this and the code below
-- is otherwise standard, but neither can work around the underlying client bug - until
-- Blizzard fixes it, compassDetail may silently revert to DEFAULT_DETAIL every reload.
-- Defaulting to the highest level in the meantime so a reset is the most useful outcome.
WayfinderSettings = WayfinderSettings or {}

local DEFAULT_DETAIL = 3

local cardinalDirections = {
    { name = "N", angle = 0 },
    { name = "E", angle = 90 },
    { name = "S", angle = 180 },
    { name = "W", angle = 270 },
}

local intercardinalDirections = {
    { name = "NE", angle = 45 },
    { name = "SE", angle = 135 },
    { name = "SW", angle = 225 },
    { name = "NW", angle = 315 },
}

local function createLabel(frame, text, fontTemplate, alpha)
    local fontString = frame:CreateFontString(nil, "OVERLAY", fontTemplate)
    fontString:SetText(text)
    if alpha then
        fontString:SetAlpha(alpha)
    end
    return fontString
end

local CARDINAL_PIP_HEIGHT = 10
local INTERCARDINAL_PIP_HEIGHT = 6

local function createPip(frame, height)
    local pip = frame:CreateTexture(nil, "ARTWORK")
    pip:SetColorTexture(1, 1, 1, 0.5)
    pip:SetSize(2, height)
    return pip
end

--- Whether a tick at the given angle sits closer to a cardinal direction (N/E/S/W)
--- than to an intercardinal one (NE/SE/SW/NW), to grade its height accordingly.
local function isPipNearCardinal(angle)
    local offset = angle % 90
    local distToCardinal = math.min(offset, 90 - offset)
    local distToIntercardinal = math.abs(45 - offset)
    return distToCardinal < distToIntercardinal
end

--- Register a compass-banner element at a fixed absolute angle (it doesn't move with the player).
local function addFixedAngleElement(name, angle, createBannerMarker)
    return api.AddElementToBanner(
        name,
        function() return angle end,
        createBannerMarker,
        false
    )
end

local function setElementsEnabled(elementList, enabled)
    for _, element in ipairs(elementList) do
        api.SetElementEnabled(element, enabled)
    end
end

local cardinalElements = {}
for _, direction in ipairs(cardinalDirections) do
    local element = addFixedAngleElement(direction.name, direction.angle, function(frame)
        return createLabel(frame, direction.name, "GameFontNormalLarge")
    end)
    table.insert(cardinalElements, element)
end

local intercardinalElements = {}
for _, direction in ipairs(intercardinalDirections) do
    local element = addFixedAngleElement(direction.name, direction.angle, function(frame)
        return createLabel(frame, direction.name, "GameFontNormal", 0.8)
    end)
    table.insert(intercardinalElements, element)
end

-- One tick every 15 degrees, skipping the 8 positions already covered by a
-- cardinal or intercardinal label (the multiples of 45). Ticks nearer a cardinal
-- are taller, extending the same cardinal > intercardinal visual weighting down
-- to this level of detail.
local pipElements = {}
for angle = 0, 345, 15 do
    if angle % 45 ~= 0 then
        local height = isPipNearCardinal(angle) and CARDINAL_PIP_HEIGHT or INTERCARDINAL_PIP_HEIGHT
        local element = addFixedAngleElement("Pip" .. angle, angle, function(frame)
            return createPip(frame, height)
        end)
        table.insert(pipElements, element)
    end
end

--- Set how much compass detail is shown: 0 hides everything, 1 shows only N/E/S/W,
--- 2 (the default) adds the intercardinal directions, 3 adds a tick every 15 degrees.
--- @param level number
local function applyDetail(level)
    setElementsEnabled(cardinalElements, level >= 1)
    setElementsEnabled(intercardinalElements, level >= 2)
    setElementsEnabled(pipElements, level >= 3)
    api.SetCenterLineShown(level >= 1)
    WayfinderSettings.compassDetail = level
end

api.CardinalPoints = {
    Show = function() applyDetail(2) end,
    Hide = function() applyDetail(0) end,
    SetDetail = applyDetail,
    GetDetail = function() return WayfinderSettings.compassDetail end,
}

applyDetail(WayfinderSettings.compassDetail or DEFAULT_DETAIL)
