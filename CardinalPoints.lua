-- CardinalPoints manages the cardinal points on the compass banner.

local _, addon = ...
local api = addon.API

local cardinalDirections = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function calculateAngle(index, totalDirections)
    return (index - 1) * (360 / totalDirections)
end

local function createMarker(frame, direction)
    local fontString = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fontString:SetText(direction)
    return fontString
end

for i = 1, #cardinalDirections do
    local direction = cardinalDirections[i]
    api.AddElementToBanner(
        direction,
        function()
            return calculateAngle(i, #cardinalDirections)
        end,
        function(frame)
            return createMarker(frame, direction)
        end,
        false
    )
end
