-- CompassBanner manages the frame and elements of the compass banner.

local _, addon = ...
local _p = addon.private
local api = addon.API
local _C = addon.Constants

-- Cache global references
local deg, rad = math.deg, math.rad
local abs, exp, pi = math.abs, math.exp, math.pi
local GetPlayerFacing = GetPlayerFacing
local issecretvalue = issecretvalue or function() return false end
local CreateFrame = CreateFrame
local UIParent = UIParent

-- Constants
local BANNER_WIDTH = 600
local HALF_BANNER_WIDTH = BANNER_WIDTH / 2
local BANNER_HEIGHT = 25
local FOV = 135
local HALF_FOV = FOV / 2
local DEFAULT_BANNER_POINT = "TOP"
local DEFAULT_BANNER_X = 0
local DEFAULT_BANNER_Y = -10
local TWO_PI = 2 * pi

_C.BANNER_WIDTH = BANNER_WIDTH
_C.BANNER_HEIGHT = BANNER_HEIGHT
_C.FOV = FOV

--- The strengths of the optional dark backdrop behind the banner. Published on
--- addon.Constants since Settings.lua and Slash.lua need it too.
_C.BannerOverlay = {
    Off = 0,
    Subtle = 1,
    Medium = 2,
    Strong = 3,
}
local BannerOverlay = _C.BannerOverlay

local DEFAULT_OVERLAY = BannerOverlay.Off

--- How much the banner eases toward a new heading instead of jumping to it. Published on
--- addon.Constants since Settings.lua and Slash.lua need it too.
_C.TurnSmoothing = {
    Off = 0,
    Light = 1,
    Medium = 2,
    Heavy = 3,
}
local TurnSmoothing = _C.TurnSmoothing

local DEFAULT_TURN_SMOOTHING = TurnSmoothing.Off

-- Time constant, in seconds, of the exponential ease at each level: roughly how long the
-- banner takes to cover two thirds of a turn. Frame-rate independent.
local TURN_SMOOTHING_TIME = {
    [TurnSmoothing.Light] = 0.18,
    [TurnSmoothing.Medium] = 0.3,
    [TurnSmoothing.Heavy] = 0.5,
}

-- Below this gap (radians, ~0.06 degrees) the eased heading just snaps to the real one, so
-- it settles exactly instead of creeping forever.
local TURN_SNAP_EPSILON = 0.001

-- Opacity of the backdrop at each strength.
local OVERLAY_ALPHA = {
    [BannerOverlay.Subtle] = 0.4,
    [BannerOverlay.Medium] = 0.6,
    [BannerOverlay.Strong] = 0.85,
}

-- Media/BannerFade.tga is black fading smoothly to transparent toward every edge: 35% of
-- its width from each side, 30% of its height from top and bottom. The texture is drawn
-- taller than the banner so the vertical fade lands outside the text rather than on it.
local OVERLAY_TEXTURE = "Interface\\AddOns\\Wayfinder\\Media\\BannerFade"
local OVERLAY_VERTICAL_PADDING = 10

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
        rotateWhenSticky = true,
        enabled = true
    }

    table.insert(elements, element)

    return element
end

api.AddElementToBanner = addElementToBanner

--- Set whether a sticky element rotates to point sideways when pinned at the compass
--- edge (appropriate for a directional icon like an arrow, not for one without an
--- inherent direction like a tombstone). Only matters for elements marked sticky.
--- @param element table An element handle returned by api.AddElementToBanner.
--- @param rotateWhenSticky boolean
local function setElementRotateWhenSticky(element, rotateWhenSticky)
    assert(type(element) == "table", "Expected element to be a table")

    element.rotateWhenSticky = rotateWhenSticky
    if not rotateWhenSticky and element.uiElement then
        element.uiElement:SetRotation(0)
    end
end

api.SetElementRotateWhenSticky = setElementRotateWhenSticky

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

--- Create the frame for the compass banner, including the center "straight ahead" line
--- and a background shown only while unlocked, to make the draggable area visible.
--- @return table frame
local function buildCompassBannerFrame()
    local frame = CreateFrame("Frame", "WayfinderCompassBannerFrame", UIParent)
    frame:SetSize(BANNER_WIDTH, BANNER_HEIGHT)
    frame:SetPoint(DEFAULT_BANNER_POINT, DEFAULT_BANNER_X, DEFAULT_BANNER_Y)
    frame:RegisterForDrag("LeftButton")

    local line = frame:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(1, 1, 1, 1)
    line:SetSize(2, frame:GetHeight())
    line:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.centerLine = line

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0, 0, 0, 0.4)
    background:Hide()
    frame.dragBackground = background

    local overlay = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    overlay:SetTexture(OVERLAY_TEXTURE)
    overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, OVERLAY_VERTICAL_PADDING)
    overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -OVERLAY_VERTICAL_PADDING)
    overlay:Hide()
    frame.overlay = overlay

    return frame
end

addon.CompassBannerFrame = addon.CompassBannerFrame or buildCompassBannerFrame()

local bannerOverlay = _p.getOrSetDefault("bannerOverlay", DEFAULT_OVERLAY)

--- Render a backdrop strength without changing the remembered preference.
--- @param level number One of the BannerOverlay values.
local function applyOverlay(level)
    local overlay = addon.CompassBannerFrame.overlay
    local alpha = OVERLAY_ALPHA[level]
    overlay:SetShown(alpha ~= nil)
    if alpha then overlay:SetAlpha(alpha) end
end
applyOverlay(bannerOverlay)

--- Set the user's preferred backdrop strength: applies it now and remembers it.
--- Refreshing the Settings panel keeps its stepper in sync when this changes via a slash
--- command instead of the panel itself.
--- @param level number One of the BannerOverlay values.
local function setBannerOverlay(level)
    bannerOverlay = level
    WayfinderSettings.bannerOverlay = level
    applyOverlay(level)
    _p.refreshSettingsPanel()
end

-- Whether the center line is shown combines two things: the user's remembered preference
-- (showCenterLine), and whether the current compass detail level calls for a line at all
-- (centerLineAllowed, set by CardinalPoints.lua). Keeping them apart means changing the
-- detail level never overwrites the preference.
local showCenterLine = _p.getOrSetDefault("showCenterLine", true)
local centerLineAllowed = true

local function updateCenterLine()
    addon.CompassBannerFrame.centerLine:SetShown(showCenterLine and centerLineAllowed)
end

--- Allow or disallow the center "straight ahead" line independently of the banner itself.
--- It's still hidden while the user's preference is off.
--- @param shown boolean
local function setCenterLineShown(shown)
    centerLineAllowed = shown
    updateCenterLine()
end

api.SetCenterLineShown = setCenterLineShown

--- Set the user's preference for the center line: applies it now and remembers it.
--- Refreshing the Settings panel keeps its checkbox in sync when this changes via a slash
--- command instead of the panel itself.
--- @param shown boolean
local function setShowCenterLine(shown)
    showCenterLine = shown
    WayfinderSettings.showCenterLine = shown
    updateCenterLine()
    _p.refreshSettingsPanel()
end

-- A level the code doesn't know (a hand-edited file, or one from a newer version) falls
-- back to the default rather than being trusted.
local turnSmoothing = _p.getOrSetDefault("turnSmoothing", DEFAULT_TURN_SMOOTHING)
if turnSmoothing ~= TurnSmoothing.Off and not TURN_SMOOTHING_TIME[turnSmoothing] then
    turnSmoothing = DEFAULT_TURN_SMOOTHING
end

--- Set how much the banner eases when turning: applies it now and remembers it.
--- Refreshing the Settings panel keeps its stepper in sync when this changes via a slash
--- command instead of the panel itself.
--- @param level number One of the TurnSmoothing values.
local function setTurnSmoothing(level)
    turnSmoothing = level
    WayfinderSettings.turnSmoothing = level
    _p.refreshSettingsPanel()
end

--- Remember the banner's current position so it can be restored on the next load.
local function saveBannerPosition()
    local point, _, relativePoint, xOfs, yOfs = addon.CompassBannerFrame:GetPoint()
    WayfinderSettings.bannerPoint = point
    WayfinderSettings.bannerRelativePoint = relativePoint
    WayfinderSettings.bannerX = xOfs
    WayfinderSettings.bannerY = yOfs
end

--- Restore a previously saved banner position, if there is one.
local function applySavedBannerPosition()
    if not WayfinderSettings.bannerPoint then return end

    addon.CompassBannerFrame:ClearAllPoints()
    addon.CompassBannerFrame:SetPoint(
        WayfinderSettings.bannerPoint,
        UIParent,
        WayfinderSettings.bannerRelativePoint,
        WayfinderSettings.bannerX,
        WayfinderSettings.bannerY
    )
end

applySavedBannerPosition()

--- Reset the banner to its default position, clearing any previously saved position.
local function resetBannerPosition()
    WayfinderSettings.bannerPoint = nil
    WayfinderSettings.bannerRelativePoint = nil
    WayfinderSettings.bannerX = nil
    WayfinderSettings.bannerY = nil

    addon.CompassBannerFrame:ClearAllPoints()
    addon.CompassBannerFrame:SetPoint(DEFAULT_BANNER_POINT, DEFAULT_BANNER_X, DEFAULT_BANNER_Y)
end

local bannerLocked = true

--- Lock or unlock the banner for dragging. Locked (the default) behaves exactly as
--- before - mouse clicks pass through it. Unlocked shows a background so its bounds
--- are visible and lets it be dragged to a new position, which is then remembered.
--- @param locked boolean
local function setBannerLocked(locked)
    bannerLocked = locked

    local frame = addon.CompassBannerFrame
    frame:EnableMouse(not locked)
    frame:SetMovable(not locked)
    frame.dragBackground:SetShown(not locked)
    _p.refreshSettingsPanel()
end
setBannerLocked(true)

addon.CompassBannerFrame:SetScript("OnDragStart", function(frame)
    if bannerLocked then return end
    frame:StartMoving()
end)

addon.CompassBannerFrame:SetScript("OnDragStop", function(frame)
    frame:StopMovingOrSizing()
    saveBannerPosition()
end)

api.CompassBanner = {
    Lock = function() setBannerLocked(true) end,
    Unlock = function() setBannerLocked(false) end,
    IsLocked = function() return bannerLocked end,
    ResetPosition = resetBannerPosition,
    IsShown = function() return addon.CompassBannerFrame:IsShown() end,
    GetShowCenterLine = function() return showCenterLine end,
    SetShowCenterLine = setShowCenterLine,
    GetOverlay = function() return bannerOverlay end,
    SetOverlay = setBannerOverlay,
    GetTurnSmoothing = function() return turnSmoothing end,
    SetTurnSmoothing = setTurnSmoothing,
}

local function asDegrees(radians)
    local degrees = deg(radians)
    degrees = 360 - degrees            -- adjust for clockwise rotation
    return (degrees % 360 + 360) % 360 -- normalize to [0, 360)
end

--- Normalize an angle to [-180, 180).
--- @param angle number|nil
--- @return number|nil
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
        -- Rotate the marker 90 degrees when out of the field of view, unless it's been
        -- marked as not having an inherent direction (e.g. a tombstone, vs. an arrow).
        if element.uiElement and element.rotateWhenSticky then
            element.uiElement:SetRotation(rad(relativeAngle < 0 and 90 or -90))
        end
        return relativeAngle < 0 and -HALF_BANNER_WIDTH or HALF_BANNER_WIDTH
    else
        return nil
    end
end

local function updateElementPosition(element, position)
    if element.lastPosition ~= position then
        element.uiElement:SetPoint("CENTER", addon.CompassBannerFrame, "CENTER", position, 0)
        element.lastPosition = position
    end
    element.uiElement:Show()
end

local function processElement(element, facing)
    if not element then return end
    if not element.enabled then return end

    local angle = element.angleFunction() -- this is the big call to avoid when possible
    local relativeAngle = angle and getRelativeAngleTo(angle, facing)

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

-- Some places don't report which way the player is facing (the dungeons in Azj-Kahet were
-- the first to show it), and in combat the value can be a "secret" that arithmetic on
-- throws. Without a usable facing there's nothing to position the elements by, so rather
-- than leave them frozen where they were, the banner is made invisible until it's back. It
-- stays "shown" so this update keeps running to notice that.
local facingAvailable = true

-- The heading the banner is drawn at, in radians like GetPlayerFacing(). With turn
-- smoothing on it eases toward the real facing rather than jumping to it. nil until there's
-- a facing to start from, and reset whenever facing goes away, so the banner snaps straight
-- to the right heading when it reappears instead of swinging round to it.
local displayedFacing

--- Ease displayedFacing toward the real facing, the short way round.
--- @param facing number The real facing, in radians.
--- @param elapsed number Seconds since the last frame.
--- @return number displayedFacing
local function easeFacing(facing, elapsed)
    local smoothingTime = TURN_SMOOTHING_TIME[turnSmoothing]
    if not smoothingTime or not displayedFacing then
        displayedFacing = facing
        return facing
    end

    local delta = (facing - displayedFacing + pi) % TWO_PI - pi -- shortest arc, [-pi, pi)
    if abs(delta) < TURN_SNAP_EPSILON then
        displayedFacing = facing
    else
        displayedFacing = (displayedFacing + delta * (1 - exp(-elapsed / smoothingTime))) % TWO_PI
    end
    return displayedFacing
end

local function onUpdate(_, elapsed)
    local facing = GetPlayerFacing()
    local available = facing ~= nil and not issecretvalue(facing)
    if available ~= facingAvailable then
        facingAvailable = available
        addon.CompassBannerFrame:SetAlpha(available and 1 or 0)
        _p.refreshSettingsPanel()
    end
    if not available then
        displayedFacing = nil
        return
    end

    facing = easeFacing(facing, elapsed or 0)

    for _, element in ipairs(elements) do
        processElement(element, facing)
    end
end

-- The banner is shown when the user wants it (showBanner, remembered across sessions). Where
-- the game isn't reporting which way the player is facing, onUpdate also makes it invisible
-- without touching that choice, so it comes back by itself when facing does.
local showBanner = _p.getOrSetDefault("showBanner", true)

-- Refreshing the Settings panel keeps its controls in sync when the banner changes through
-- some other path - a slash command or the minimap button - rather than through the panel
-- itself.
local function updateBannerVisibility()
    addon.CompassBannerFrame:SetShown(showBanner)
    addon.CompassBannerFrame:SetScript("OnUpdate", showBanner and onUpdate or nil)
    _p.refreshSettingsPanel()
end

--- Show the banner at the user's request, and remember it.
local function enableCompassBanner()
    showBanner = true
    WayfinderSettings.showBanner = true
    updateBannerVisibility()
end
_p.enableCompassBanner = enableCompassBanner

--- Hide the banner at the user's request, and remember it.
local function disableCompassBanner()
    showBanner = false
    WayfinderSettings.showBanner = false
    updateBannerVisibility()
end
_p.disableCompassBanner = disableCompassBanner

api.CompassBanner.IsEnabled = function() return showBanner end
api.CompassBanner.IsFacingAvailable = function() return facingAvailable end

updateBannerVisibility()
