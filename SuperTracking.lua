-- SuperTracking manages the SuperTracking icon on the compass banner.

local _, addon = ...
local _p = addon.private
local api = addon.API

local bind = _p.bind

-- Cache global references
local deg = math.deg
local print = print

local Enum = Enum

local Map = C_Map
local GetUserWaypoint = Map.GetUserWaypoint
local GetBestMapForUnit = Map.GetBestMapForUnit
local GetPlayerMapPosition = Map.GetPlayerMapPosition

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

local hbd = LibStub("HereBeDragons-2.0")
assert(hbd, "HereBeDragons-2.0 is required by the Wayfinder SuperTracking module")
addon.Dependencies["HereBeDragons-2.0"] = hbd

local GetPlayerWorldPosition = bind(hbd, hbd.GetPlayerWorldPosition)
local GetWorldVector = bind(hbd, hbd.GetWorldVector)
local GetWorldCoordinatesFromZone = bind(hbd, hbd.GetWorldCoordinatesFromZone)

-- forward declarations
local trackingFunctions
local updateSuperTrackingIcon
local setSuperTrackingDistanceText

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
        setSuperTrackingDistanceText(nil)
        return
    end

    updateSuperTrackingIcon()

    local playerX, playerY, instanceId = GetPlayerWorldPosition()
    if not (playerX and playerY and instanceId) then
        setSuperTrackingDistanceText(nil)
        return
    end

    local destX, destY = superTrackingDestination()
    if not (destX and destY) then
        setSuperTrackingDistanceText(nil)
        return
    end

    local angle, distance = GetWorldVector(instanceId, playerX, playerY, destX, destY)
    if not angle then
        setSuperTrackingDistanceText(nil)
        return
    end

    setSuperTrackingDistanceText(distance)

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
    return info.position:GetXY()
end

local function handleTaxiNode(map, typeId)
    local nodes = GetTaxiNodesForMap(map)
    for _, node in ipairs(nodes) do
        if node.nodeID == typeId then
            return GetWorldCoordinatesFromZone(node.position.x, node.position.y, map)
        end
    end
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
    [Enum.SuperTrackingType.Corpse] = functionNotImplemented,
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
local superTrackingIconApplied = false

-- Known WoW: Forever beta bug affecting SavedVariables persistence in general - see
-- CardinalPoints.lua's compassDetail comment for details.
WayfinderSettings = WayfinderSettings or {}
local showTrackingDistance = WayfinderSettings.showTrackingDistance
if showTrackingDistance == nil then
    showTrackingDistance = true
end
WayfinderSettings.showTrackingDistance = showTrackingDistance

--- Apply the live SuperTracking icon to our marker, retrying each update until
--- SuperTrackedFrame is available (starting SuperTracking is what creates it).
updateSuperTrackingIcon = function()
    if superTrackingIconApplied then return end

    local superTrackedIcon = SuperTrackedFrame and SuperTrackedFrame.Icon
    local atlas = superTrackedIcon and superTrackedIcon:GetAtlas()
    if not atlas then return end

    superTrackingMarker:SetAtlas(atlas, true)
    superTrackingIconApplied = true
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

--- Show the given distance below the marker, or hide the text if there's nothing to show
--- or the user has turned the distance readout off. Uses Blizzard's own localized
--- IN_GAME_NAVIGATION_RANGE string (the same one SuperTrackedFrame uses) rather than a
--- hardcoded unit suffix, since the distance unit label isn't the same in every locale.
--- @param distance number|nil Distance to the super-tracked target, in yards.
setSuperTrackingDistanceText = function(distance)
    if not showTrackingDistance or not distance then
        superTrackingDistanceText:Hide()
        return
    end

    superTrackingDistanceText:SetText(IN_GAME_NAVIGATION_RANGE:format(formatDistance(distance)))
    superTrackingDistanceText:Show()
end

local date = date

-- SavedVariable: a rolling log of debug snapshots, written to disk on logout/reload,
-- so output can be read from the SavedVariables file instead of copy-pasting chat.
WayfinderDebug = WayfinderDebug or {}
local MAX_DEBUG_ENTRIES = 20

--- Join args into one line the same way multi-arg print() displays them, tolerating nils.
local function toLine(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end

--- Print diagnostic info about the SuperTracking chain, to help debug why no marker is showing.
--- Also records the same output as one entry in the WayfinderDebug SavedVariable.
local function debugSuperTracking()
    local lines = {}
    local function out(...)
        print(...)
        table.insert(lines, toLine(...))
    end

    out("Wayfinder SuperTracking debug:")
    out(" IsSuperTrackingAnything:", IsSuperTrackingAnything())

    local playerX, playerY, instanceId = GetPlayerWorldPosition()
    out(" GetPlayerWorldPosition:", playerX, playerY, instanceId)

    local map = GetBestMapForUnit("player")
    out(" GetBestMapForUnit:", map)
    if map then
        local x, y, waypointDescription = GetNextWaypointForMap(map)
        out(" GetNextWaypointForMap (x, y, description):", x, y, waypointDescription)
    end

    local trackingType = GetHighestPrioritySuperTrackingType()
    out(" GetHighestPrioritySuperTrackingType:", trackingType)

    if trackingType == Enum.SuperTrackingType.Quest then
        local questID = GetSuperTrackedQuestID()
        out(" GetSuperTrackedQuestID:", questID)
        if questID then
            RequestLoadQuestByID(questID)
            if map then SetMapForQuestPOIs(map) end
            local qMapID, qx, qy = QuestLogGetNextWaypoint(questID)
            out(" raw QuestLogGetNextWaypoint (mapID, x, y):", qMapID, qx, qy)

            if map then
                local quests = GetQuestsOnMap(map)
                out(" GetQuestsOnMap count:", quests and #quests)
                local found = false
                if quests then
                    for _, poi in ipairs(quests) do
                        if poi.questID == questID then
                            out(" GetQuestsOnMap match (mapID, x, y):", poi.mapID, poi.x, poi.y)
                            found = true
                        end
                    end
                end
                if not found then
                    out(" GetQuestsOnMap: no entry for this questID")
                end
            end
        end
    end

    local trackingFunction = trackingType and trackingFunctions[trackingType]
    out(" fallback trackingFunction found:", trackingFunction ~= nil)

    local ok, destX, destY = pcall(superTrackingDestination)
    out(" superTrackingDestination result (ok, destX, destY):", ok, destX, destY)

    if ok and destX and destY and playerX and playerY and instanceId then
        local angle = GetWorldVector(instanceId, playerX, playerY, destX, destY)
        out(" GetWorldVector angle:", angle)
    end

    out(" SuperTrackedFrame exists:", SuperTrackedFrame ~= nil)
    local icon = SuperTrackedFrame and SuperTrackedFrame.Icon
    out(" SuperTrackedFrame.Icon atlas:", icon and icon:GetAtlas())
    out(" superTrackingIconApplied:", superTrackingIconApplied)

    -- Sanity check: round-trip the player's own position through HereBeDragons'
    -- zone conversion. If this doesn't roughly match GetPlayerWorldPosition, HBD
    -- doesn't know how to convert coordinates for this map at all, regardless of
    -- which Blizzard API supplies a destination.
    if map then
        local selfPos = GetPlayerMapPosition(map, "player")
        out(" GetPlayerMapPosition on current map:", selfPos and selfPos.x, selfPos and selfPos.y)
        if selfPos then
            local wx, wy, wi = GetWorldCoordinatesFromZone(selfPos.x, selfPos.y, map)
            out(" GetWorldCoordinatesFromZone round-trip (wx, wy, wi):", wx, wy, wi)
        end
    end

    -- Also try resolving a plain user waypoint directly, if one is set, since it
    -- doesn't depend on quest data at all.
    local ok2, wpX, wpY = pcall(superTrackingUserWaypoint)
    out(" superTrackingUserWaypoint result (ok, x, y):", ok2, wpX, wpY)

    table.insert(WayfinderDebug, { time = date("%Y-%m-%d %H:%M:%S"), lines = lines })
    while #WayfinderDebug > MAX_DEBUG_ENTRIES do
        table.remove(WayfinderDebug, 1)
    end

    print("Wayfinder: debug entry saved (" .. #WayfinderDebug .. " total). /reload or log out to flush to disk.")
end
api.DebugSuperTracking = debugSuperTracking

local isSticky = true

local superTrackingElement = api.AddElementToBanner(
    "SuperTracking",
    superTrackingCallback,
    createSuperTrackingMarker,
    isSticky
)

api.SuperTracking = {
    Enable = function() api.SetElementEnabled(superTrackingElement, true) end,
    Disable = function()
        api.SetElementEnabled(superTrackingElement, false)
        setSuperTrackingDistanceText(nil)
    end,
    SetShowDistance = function(shown)
        showTrackingDistance = shown
        WayfinderSettings.showTrackingDistance = shown
        if not shown then
            superTrackingDistanceText:Hide()
        end
    end,
    GetShowDistance = function() return showTrackingDistance end,
}
