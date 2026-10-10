-- SuperTracking manages the SuperTracking icon on the compass banner.

local _, addon = ...
local _p = addon.private
local api = addon.API

-- SuperTracking needs APIs that only some clients have: Classic Era has no C_SuperTrack,
-- C_Navigation or Enum.SuperTrackingType, for example. Where they're missing, leave the
-- rest of the addon working and stand in a version of the module that does nothing, which
-- the settings page and slash commands check with IsSupported before offering the feature.
if not (C_SuperTrack and C_Navigation and Enum and Enum.SuperTrackingType and Enum.SuperTrackingMapPinType) then
    local function doNothing() end

    api.SuperTracking = {
        IsSupported = function() return false end,
        Enable = doNothing,
        Disable = doNothing,
        IsEnabled = function() return false end,
        SetShowDistance = doNothing,
        GetShowDistance = function() return false end,
        SetShowETA = doNothing,
        GetShowETA = function() return false end,
    }
    return
end

local bind = _p.bind

-- Cache global references
local deg = math.deg
local GetTime = GetTime

local Enum = Enum

local Map = C_Map
local GetUserWaypoint = Map.GetUserWaypoint
local GetBestMapForUnit = Map.GetBestMapForUnit

local QuestLog = C_QuestLog
local QuestLogGetNextWaypoint = QuestLog.GetNextWaypoint
local RequestLoadQuestByID = QuestLog.RequestLoadQuestByID
local SetMapForQuestPOIs = QuestLog.SetMapForQuestPOIs
local GetQuestsOnMap = QuestLog.GetQuestsOnMap

local SuperTrack = C_SuperTrack
local IsSuperTrackingAnything = SuperTrack.IsSuperTrackingAnything
local GetHighestPrioritySuperTrackingType = SuperTrack.GetHighestPrioritySuperTrackingType
local GetSuperTrackedQuestID = SuperTrack.GetSuperTrackedQuestID
local GetSuperTrackedMapPin = SuperTrack.GetSuperTrackedMapPin

local Navigation = C_Navigation
local GetNextWaypointForMap = Navigation.GetNextWaypointForMap

local AreaPoiInfo = C_AreaPoiInfo
local GetAreaPOIInfo = AreaPoiInfo.GetAreaPOIInfo

local TaxiMap = C_TaxiMap
local GetTaxiNodesForMap = TaxiMap.GetTaxiNodesForMap

local DeathInfo = C_DeathInfo
local GetCorpseMapPosition = DeathInfo.GetCorpseMapPosition

local hbd = LibStub("HereBeDragons-2.0")
assert(hbd, "HereBeDragons-2.0 is required by the Wayfinder SuperTracking module")
addon.Dependencies["HereBeDragons-2.0"] = hbd

local GetPlayerWorldPosition = bind(hbd, hbd.GetPlayerWorldPosition)
local GetWorldVector = bind(hbd, hbd.GetWorldVector)
local GetWorldCoordinatesFromZone = bind(hbd, hbd.GetWorldCoordinatesFromZone)

-- forward declarations
local trackingFunctions
local updateSuperTrackingIcon
local superTrackingElement
local updateSuperTrackingReadout

--- Resolve the world-map coordinates of whatever is currently super-tracked.
--- Tries C_Navigation.GetNextWaypointForMap first, since that's the unified API
--- Blizzard's own navigation UI (Blizzard_QuestNavigation) uses for the current
--- super-tracked target regardless of type. Falls back to the per-type handlers
--- in trackingFunctions for anything that API doesn't cover.
local function superTrackingDestination()
    local map = GetBestMapForUnit("player")
    if map then
        local x, y = GetNextWaypointForMap(map)
        if x and y then
            return GetWorldCoordinatesFromZone(x, y, map)
        end
    end

    local trackingType = GetHighestPrioritySuperTrackingType()
    if not trackingType then return end

    local trackingFunction = trackingFunctions[trackingType]
    if not trackingFunction then return end

    return trackingFunction()
end

--- Callback for the SuperTracking element on the compass banner.
local function superTrackingCallback()
    if not IsSuperTrackingAnything() then
        updateSuperTrackingReadout(nil)
        return
    end

    updateSuperTrackingIcon()

    local playerX, playerY, instanceId = GetPlayerWorldPosition()
    if not (playerX and playerY and instanceId) then
        updateSuperTrackingReadout(nil)
        return
    end

    local destX, destY = superTrackingDestination()
    if not (destX and destY) then
        updateSuperTrackingReadout(nil)
        return
    end

    local angle, distance = GetWorldVector(instanceId, playerX, playerY, destX, destY)
    if not angle then
        updateSuperTrackingReadout(nil)
        return
    end

    updateSuperTrackingReadout(distance)

    return 360 - deg(angle)
end

local function functionNotImplemented() end

-- GetNextWaypoint can legitimately return nothing until the quest's full data has
-- been requested and the active map for quest POIs has been set - normally done by
-- the quest log/map UI, which this addon never opens. RequestLoadQuestByID is async,
-- so only fire it once per quest and let the next update pick up the result.
local lastRequestedQuestID = nil

local function superTrackingQuest()
    local questID = GetSuperTrackedQuestID()
    if not questID then return nil, nil end

    if lastRequestedQuestID ~= questID then
        RequestLoadQuestByID(questID)
        lastRequestedQuestID = questID
    end

    local map = GetBestMapForUnit("player")
    if map then
        SetMapForQuestPOIs(map)
    end

    local mapID, x, y = QuestLogGetNextWaypoint(questID)
    if mapID and x and y then
        return GetWorldCoordinatesFromZone(x, y, mapID)
    end

    -- Fall back to the quest's map pin (the older POI system, used to place a single
    -- marker on the map/minimap) since GetNextWaypoint's pathing data may not exist
    -- for older quest content.
    if map then
        local quests = GetQuestsOnMap(map)
        if quests then
            for _, poi in ipairs(quests) do
                if poi.questID == questID then
                    return GetWorldCoordinatesFromZone(poi.x, poi.y, poi.mapID)
                end
            end
        end
    end

    return nil, nil
end

local function superTrackingUserWaypoint()
    local point = GetUserWaypoint()
    return GetWorldCoordinatesFromZone(point.position.x, point.position.y, point.uiMapID)
end

local function handleAreaPOI(map, typeId)
    local info = GetAreaPOIInfo(map, typeId)
    if not info then return end
    local x, y = info.position:GetXY()
    return GetWorldCoordinatesFromZone(x, y, map)
end

local function handleTaxiNode(map, typeId)
    local nodes = GetTaxiNodesForMap(map)
    for _, node in ipairs(nodes) do
        if node.nodeID == typeId then
            return GetWorldCoordinatesFromZone(node.position.x, node.position.y, map)
        end
    end
end

--- Get the world coordinates of the player's own corpse, if it's on their current map.
local function superTrackingCorpse()
    local map = GetBestMapForUnit("player")
    if not map then return end

    local position = GetCorpseMapPosition(map)
    if not position then return end

    local x, y = position:GetXY()
    return GetWorldCoordinatesFromZone(x, y, map)
end

local mapPinTrackingFunctions = {
    [Enum.SuperTrackingMapPinType.AreaPOI] = handleAreaPOI,
    [Enum.SuperTrackingMapPinType.QuestOffer] = functionNotImplemented,
    [Enum.SuperTrackingMapPinType.TaxiNode] = handleTaxiNode,
    [Enum.SuperTrackingMapPinType.DigSite] = functionNotImplemented,
}

--- Get the world coordinates for the SuperTracking map pin.
--- @return number|nil, number|nil The x and y coordinates of the map pin.
local function superTrackingMapPin()
    local pinType, typeId = GetSuperTrackedMapPin()
    if not (pinType and typeId) then return end

    local map = GetBestMapForUnit("player")
    if not map then return end

    local mapPinTrackingFunction = mapPinTrackingFunctions[pinType]
    if not mapPinTrackingFunction then return end

    return mapPinTrackingFunction(map, typeId)
end

trackingFunctions = {
    [Enum.SuperTrackingType.Quest] = superTrackingQuest,
    [Enum.SuperTrackingType.UserWaypoint] = superTrackingUserWaypoint,
    [Enum.SuperTrackingType.Corpse] = superTrackingCorpse,
    [Enum.SuperTrackingType.Scenario] = functionNotImplemented,
    [Enum.SuperTrackingType.Content] = functionNotImplemented,
    [Enum.SuperTrackingType.PartyMember] = functionNotImplemented,
    [Enum.SuperTrackingType.MapPin] = superTrackingMapPin,
    [Enum.SuperTrackingType.Vignette] = functionNotImplemented,
}

-- SuperTrackedFrame belongs to the on-demand Blizzard_QuestNavigation module, so it may not
-- exist yet at addon load time. Its icon is also an atlas texture (Navigation-Tracked-Icon),
-- not a plain image file, so it has to be copied with GetAtlas/SetAtlas rather than
-- GetTexture/SetTexCoord.
local SuperTrackedFrame = SuperTrackedFrame
local superTrackingMarker = nil
local superTrackingDistanceText = nil
local superTrackingETAText = nil
local superTrackingIconAtlas = nil

local showTrackingDistance = _p.getOrSetDefault("showTrackingDistance", true)
local showTrackingETA = _p.getOrSetDefault("showTrackingETA", true)
local trackingEnabled = _p.getOrSetDefault("trackingEnabled", true)

--- Apply the live SuperTracking icon to our marker. Retries each update until
--- SuperTrackedFrame is available (starting SuperTracking is what creates it), and
--- re-applies whenever the atlas itself changes, since Blizzard uses a different icon
--- per tracking type (e.g. a tombstone for a corpse vs. a waypoint flag for a quest).
updateSuperTrackingIcon = function()
    local superTrackedIcon = SuperTrackedFrame and SuperTrackedFrame.Icon
    local atlas = superTrackedIcon and superTrackedIcon:GetAtlas()
    if not atlas or atlas == superTrackingIconAtlas then return end

    superTrackingMarker:SetAtlas(atlas, true)
    superTrackingIconAtlas = atlas

    -- A tombstone (corpse tracking) has no inherent direction, unlike the arrow/flag
    -- icons used for everything else, so don't rotate it when pinned at the FOV edge.
    local trackingType = GetHighestPrioritySuperTrackingType()
    api.SetElementRotateWhenSticky(superTrackingElement, trackingType ~= Enum.SuperTrackingType.Corpse)
end

--- Anchor the ETA text below the distance text when distance is shown, or directly
--- below the marker when it isn't, so disabling the distance readout doesn't leave a
--- blank gap above an otherwise still-enabled ETA line.
local function updateSuperTrackingETAAnchor()
    superTrackingETAText:ClearAllPoints()
    if showTrackingDistance then
        superTrackingETAText:SetPoint("TOP", superTrackingDistanceText, "BOTTOM", 0, -2)
    else
        superTrackingETAText:SetPoint("TOP", superTrackingMarker, "BOTTOM", 0, -2)
    end
end

--- Create the SuperTracking marker for the compass banner
local function createSuperTrackingMarker(frame)
    if superTrackingMarker then return superTrackingMarker end
    local marker = frame:CreateTexture(nil, "OVERLAY")
    marker:SetSize(25, 25)
    superTrackingMarker = marker

    local distanceText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    distanceText:SetPoint("TOP", marker, "BOTTOM", 0, -2)
    distanceText:Hide()
    superTrackingDistanceText = distanceText

    local etaText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    etaText:Hide()
    superTrackingETAText = etaText
    updateSuperTrackingETAAnchor()

    return marker
end

--- Format a distance the same way Blizzard's own SuperTrackedFrame does: round to a
--- whole number, then abbreviate it (e.g. "1.2k") once it's four digits or more.
--- @param distance number
--- @return string
local function formatDistance(distance)
    local rounded = math.floor(distance + 0.5)
    if rounded < 1000 then
        return tostring(rounded)
    else
        return AbbreviateNumbers(rounded)
    end
end

--- Format a countdown of seconds as e.g. "45s" or "2m 10s".
--- @param seconds number
--- @return string
local function formatETA(seconds)
    seconds = math.floor(seconds + 0.5)
    if seconds < 60 then
        return seconds .. "s"
    end
    return math.floor(seconds / 60) .. "m " .. (seconds % 60) .. "s"
end

-- The ETA comes from how quickly the distance to the target is shrinking, not from the
-- player's movement speed. GetUnitSpeed reports 0 as the current speed while flying, can't
-- tell moving toward the target from moving away, and can be a "secret" value in combat
-- (WoW 12.0+'s addon disarmament system), which arithmetic on throws. Distance can be read in
-- every situation, so this works the same on foot, on a mount, while flying or Skyriding, and
-- on a taxi.
--
-- Distance is noisy, though: recorded on a real walk, a speed worked out from a quarter of a
-- second of it is about 1% off, and at an ETA of three minutes that's two seconds - enough to
-- make the seconds flip up and down. So what's shown is a countdown that ticks down by itself
-- and only jumps when a fresh estimate disagrees with it by more than a few percent. The
-- estimates come from the most recent stretch of the distance history - the last half of it:
-- at first only half a second or so, which is nearly instantaneous and shows a number after a
-- second, then up to a second as the history fills in, which is steadier. A longer average
-- would still be counting the time the player spent getting up to speed. Stopping, or moving
-- away, is judged on the last third of a second alone, so that "--" shows up promptly, and
-- while the player is still slowing down the countdown is never moved to a longer ETA - that
-- would only be the start of a stop, showing a number that counts up for an instant.
local ETA_WINDOW = 2 -- seconds of distance history kept
local ETA_WARMUP = 1 -- seconds of history needed before an ETA is shown
local ETA_LOOKBACK_MIN = 0.5 -- the speed is measured over the last half of the history, but over at least this...
local ETA_LOOKBACK_MAX = 1 -- ...and at most this many seconds
local ETA_STOP_WINDOW = 0.3 -- seconds the player must have been approaching over, or there's no ETA
local ETA_SLOWING_FRACTION = 0.97 -- below this fraction of the speed, the player is still slowing down
local ETA_MIN_CLOSING_SPEED = 0.5 -- yards per second below which the player counts as not approaching
local ETA_RECORD_INTERVAL = 0.05 -- seconds between records of the distance
local ETA_RESTART_AFTER = 1.5 -- seconds without an update before starting over
local ETA_TOLERANCE_SECONDS = 1.5 -- how far an estimate can differ from the countdown before the countdown jumps to it...
local ETA_TOLERANCE_FRACTION = 0.04 -- ...or this fraction of the estimate, whichever is more

local historyTimes, historyDistances = {}, {}
local closingSpeed, anchorETA, anchorTime

local function clearList(list)
    for i = #list, 1, -1 do
        list[i] = nil
    end
end

--- Forget the distance history and the countdown, so the next ETA starts afresh.
local function forgetETA()
    clearList(historyTimes)
    clearList(historyDistances)
    closingSpeed, anchorETA, anchorTime = nil, nil, nil
end

--- Take in the latest distance to the target and work out the ETA, in seconds.
--- @param distance number|nil Distance to the super-tracked target, in yards. Nil forgets everything.
--- @return number|nil eta Seconds to arrive, or nil if the player isn't clearly approaching (yet).
local function updateETA(distance)
    if not distance then
        forgetETA()
        return nil
    end

    local now = GetTime()
    local count = #historyTimes
    if count > 0 and now - historyTimes[count] > ETA_RESTART_AFTER then
        forgetETA()
        count = 0
    end

    if count == 0 or now - historyTimes[count] >= ETA_RECORD_INTERVAL then
        count = count + 1
        historyTimes[count], historyDistances[count] = now, distance
    end

    -- Keep one record at least a window old, as the far end of the average, and nothing older.
    while count > 1 and now - historyTimes[2] >= ETA_WINDOW do
        table.remove(historyTimes, 1)
        table.remove(historyDistances, 1)
        count = count - 1
    end

    -- Not approaching: shown at once, and the history starts over once the player moves again.
    local recent
    for i = count, 1, -1 do
        if now - historyTimes[i] >= ETA_STOP_WINDOW then
            recent = i
            break
        end
    end
    if not recent then
        closingSpeed = nil
        return nil
    end
    local recentSpeed = (historyDistances[recent] - distance) / (now - historyTimes[recent])
    if recentSpeed <= ETA_MIN_CLOSING_SPEED then
        forgetETA()
        return nil
    end

    local span = now - historyTimes[1]
    if span < ETA_WARMUP then
        closingSpeed = nil
        return nil
    end

    -- The speed over the most recent stretch: half the history, within the limits above.
    local lookback = math.min(ETA_LOOKBACK_MAX, math.max(ETA_LOOKBACK_MIN, span / 2))
    local base = 1
    for i = count, 1, -1 do
        if now - historyTimes[i] >= lookback then
            base = i
            break
        end
    end
    closingSpeed = (historyDistances[base] - distance) / math.max(now - historyTimes[base], 0.001)
    if closingSpeed <= ETA_MIN_CLOSING_SPEED then
        closingSpeed, anchorETA, anchorTime = nil, nil, nil
        return nil
    end

    local estimate = distance / closingSpeed
    if not anchorETA then
        anchorETA, anchorTime = estimate, now
    else
        local counted = anchorETA - (now - anchorTime)
        local slowing = recentSpeed < ETA_SLOWING_FRACTION * closingSpeed
        if math.abs(estimate - counted) > math.max(ETA_TOLERANCE_SECONDS, ETA_TOLERANCE_FRACTION * estimate)
            and not (slowing and estimate > counted) then
            anchorETA, anchorTime = estimate, now
        end
    end

    return math.max(anchorETA - (now - anchorTime), 0)
end

--- Show the distance and/or ETA to the super-tracked target below the marker (ETA below
--- distance), or hide each independently when there's nothing to show or its readout is
--- turned off. Distance uses Blizzard's own localized IN_GAME_NAVIGATION_RANGE string
--- (the same one SuperTrackedFrame uses) rather than a hardcoded unit suffix, since the
--- label isn't the same in every locale. ETA is a straight-line estimate from how fast the
--- player is closing in on the target (see updateETA), so it's jumpy while turning and
--- shows "--" as soon as the player stops or moves away. Whenever ETA is enabled and there's
--- a target, the line always shows something ("--" when there's no usable speed yet) rather
--- than appearing/disappearing, so toggling the setting or standing still both read clearly
--- instead of looking like nothing happened.
--- @param distance number|nil Distance to the super-tracked target, in yards.
updateSuperTrackingReadout = function(distance)
    local eta = updateETA(distance)
    if _p.traceETA then _p.traceETA(distance, eta, closingSpeed) end

    if distance and showTrackingDistance then
        superTrackingDistanceText:SetText(IN_GAME_NAVIGATION_RANGE:format(formatDistance(distance)))
        superTrackingDistanceText:Show()
    else
        superTrackingDistanceText:Hide()
    end

    if distance and showTrackingETA then
        if eta then
            superTrackingETAText:SetText(formatETA(eta))
        else
            superTrackingETAText:SetText("--")
        end
        superTrackingETAText:Show()
    else
        superTrackingETAText:Hide()
    end
end

--- A view of this module's internals for the diagnostics in Debug.lua, which keeps them out
--- of this file. It's a function, not a table built once, so it reports the values as they
--- are when it's called.
--- @return table state closingSpeed, trackingFunctions, destination, userWaypoint, iconAtlas
local function getSuperTrackingState()
    return {
        closingSpeed = closingSpeed,
        trackingFunctions = trackingFunctions,
        destination = superTrackingDestination,
        userWaypoint = superTrackingUserWaypoint,
        iconAtlas = superTrackingIconAtlas,
    }
end
_p.getSuperTrackingState = getSuperTrackingState

local isSticky = true

superTrackingElement = api.AddElementToBanner(
    "SuperTracking",
    superTrackingCallback,
    createSuperTrackingMarker,
    isSticky
)
api.SetElementEnabled(superTrackingElement, trackingEnabled)

-- Refreshing the Settings panel below keeps its checkboxes in sync when these are changed
-- via a slash command instead of the panel itself.
api.SuperTracking = {
    IsSupported = function() return true end,
    Enable = function()
        api.SetElementEnabled(superTrackingElement, true)
        trackingEnabled = true
        WayfinderSettings.trackingEnabled = true
        _p.refreshSettingsPanel()
    end,
    Disable = function()
        api.SetElementEnabled(superTrackingElement, false)
        updateSuperTrackingReadout(nil)
        trackingEnabled = false
        WayfinderSettings.trackingEnabled = false
        _p.refreshSettingsPanel()
    end,
    IsEnabled = function() return trackingEnabled end,
    SetShowDistance = function(shown)
        showTrackingDistance = shown
        WayfinderSettings.showTrackingDistance = shown
        updateSuperTrackingETAAnchor()
        _p.refreshSettingsPanel()
    end,
    GetShowDistance = function() return showTrackingDistance end,
    SetShowETA = function(shown)
        showTrackingETA = shown
        WayfinderSettings.showTrackingETA = shown
        _p.refreshSettingsPanel()
    end,
    GetShowETA = function() return showTrackingETA end,
}
