-- CompassBanner manages the frame and elements of the compass banner.

local _, addon = ...
local _p = addon.private
local api = addon.API
local _C = addon.Constants

-- Cache global references
local deg, rad = math.deg, math.rad
local abs = math.abs
local GetPlayerFacing = GetPlayerFacing
local CreateFrame = CreateFrame
local UIParent = UIParent

-- Constants
local BANNER_WIDTH = 600
local HALF_BANNER_WIDTH = BANNER_WIDTH / 2
local BANNER_HEIGHT = 25
local FOV = 135
local HALF_FOV = FOV / 2

_C.BANNER_WIDTH = BANNER_WIDTH
_C.BANNER_HEIGHT = BANNER_HEIGHT
_C.FOV = FOV

local playerFacing

local elements = {}

--- Add an element to the compass banner.
--- @param name string The name of the element to be displayed on the compass banner.
--- @param angleFunction function A function that returns the angle of the element relative to the player.
--- @param createBannerMarker function A function that creates the UI element for the element on the compass banner.
--- @param isMarkerSticky boolean Whether the marker should be sticky or not.
--- @return table element A handle for the added element, usable with api.SetElementEnabled.
local function addElementToBanner(name, angleFunction, createBannerMarker, isMarkerSticky)
    assert(type(name) == "string", "Expected name to be a string")
    assert(type(angleFunction) == "function", "Expected angleFunction to be a function")
    assert(type(createBannerMarker) == "function", "Expected createBannerMarker to be a function")

    local uiElement = createBannerMarker(addon.CompassBannerFrame)
    local element = {
        name = name,
        angleFunction = angleFunction,
        uiElement = uiElement,
        isSticky = isMarkerSticky or false,
        enabled = true
    }

    table.insert(elements, element)

    return element
end

api.AddElementToBanner = addElementToBanner

--- Enable or disable a previously added element, hiding it immediately when disabled.
--- @param element table An element handle returned by api.AddElementToBanner.
--- @param enabled boolean Whether the element should be processed and shown.
local function setElementEnabled(element, enabled)
    assert(type(element) == "table", "Expected element to be a table")

    element.enabled = enabled
    if not enabled then
        element.uiElement:Hide()
    end
end

api.SetElementEnabled = setElementEnabled

-- Create the frame for the compass banner
local function buildCompassBannerFrame()
    local frame = CreateFrame("Frame", "WayfinderCompassBannerFrame", UIParent)
    frame:SetSize(BANNER_WIDTH, BANNER_HEIGHT)
    frame:SetPoint("TOP", 0, -10)

    -- Create a texture for the vertical line marking straight ahead
    local line = frame:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(1, 1, 1, 1)               -- White color, fully opaque
    line:SetSize(2, frame:GetHeight())             -- Width of 2 pixels, height same as the frame
    line:SetPoint("CENTER", frame, "CENTER", 0, 0) -- Centered vertically in the frame
    frame.centerLine = line

    return frame
end

addon.CompassBannerFrame = addon.CompassBannerFrame or buildCompassBannerFrame()

--- Show or hide the center "straight ahead" line independently of the banner itself.
--- @param shown boolean
local function setCenterLineShown(shown)
    if shown then
        addon.CompassBannerFrame.centerLine:Show()
    else
        addon.CompassBannerFrame.centerLine:Hide()
    end
end

api.SetCenterLineShown = setCenterLineShown

local function asDegrees(radians)
    local degrees = deg(radians)
    degrees = 360 - degrees            -- adjust for clockwise rotation
    return (degrees % 360 + 360) % 360 -- normalize to [0, 360)
end

--    local function asRadians(degrees)
--        degrees = 360 - degrees -- adjust for counterclockwise rotation
--        return rad(degrees)
--    end

--    local function getRelativeAngle(angle1, angle2)
--        local relativeAngle = angle1 - angle2
--        return (relativeAngle % 360 + 360) % 360
--    end

-- Normalize angle to [-180, 180)
local function normalizeAngle180(angle)
    if not angle then return end

    angle = (angle % 360 + 360) % 360
    if angle > 180 then
        angle = angle - 360
    end

    return angle
end

--- Get the relative angle to a target angle from the player's facing direction.
--- @param angle number The target angle.
--- @param facing number|nil The player's facing direction.
--- @return number|nil The relative angle to the target angle.
local function getRelativeAngleTo(angle, facing)
    facing = facing or GetPlayerFacing()
    if not facing then return end
    facing = asDegrees(facing)
    local relativeAngle = facing - angle
    return normalizeAngle180(relativeAngle)
end

local function calculateBannerPosition(relativeAngle, isSticky, element)
    isSticky = isSticky or false
    relativeAngle = -relativeAngle -- reverse direction for UI
    if abs(relativeAngle) < HALF_FOV then
        if element.uiElement then
            element.uiElement:SetRotation(0)
        end
        return (relativeAngle / HALF_FOV) * HALF_BANNER_WIDTH
    elseif isSticky then
        -- Rotate the marker 90 degrees when out of the field of view
        if element.uiElement then
            element.uiElement:SetRotation(rad(relativeAngle < 0 and 90 or -90))
        end
        return relativeAngle < 0 and -HALF_BANNER_WIDTH or HALF_BANNER_WIDTH
    else
        return nil
    end
end

local function updateElementPosition(element, position)
    if element.uiElement:GetPoint() ~= position then
        element.uiElement:SetPoint("CENTER", addon.CompassBannerFrame, "CENTER", position, 0)
    end
    element.uiElement:Show()
end

local function processElement(element)
    if not element then return end
    if not element.enabled then return end

    playerFacing = GetPlayerFacing() -- could also check if player is in an instance
    if not playerFacing then return end

    local angle = element.angleFunction() -- this is the big call to avoid when possible
    local relativeAngle = angle and getRelativeAngleTo(angle, playerFacing)

    if not relativeAngle then
        element.uiElement:Hide()
        return
    end

    local position = calculateBannerPosition(relativeAngle, element.isSticky, element)
    if position then
        updateElementPosition(element, position)
    else
        element.uiElement:Hide()
    end
end

local function onUpdate()
    for _, element in ipairs(elements) do
        processElement(element)
    end
end

local function enableCompassBanner()
    addon.CompassBannerFrame:Show()
    addon.CompassBannerFrame:SetScript("OnUpdate", onUpdate)
end
_p.enableCompassBanner = enableCompassBanner

local function disableCompassBanner()
    addon.CompassBannerFrame:Hide()
    addon.CompassBannerFrame:SetScript("OnUpdate", nil)
end
_p.disableCompassBanner = disableCompassBanner

enableCompassBanner()
