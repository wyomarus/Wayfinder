-- SuperTracking manages the SuperTracking icon on the compass banner.

local _, addon = ...
local _p = addon.private
local api = addon.API

local bind = _p.bind

local deg = math.deg
--    local print = print
--    local format = string.format

local Enum = _G.Enum

local Map = C_Map
local GetUserWaypoint = Map.GetUserWaypoint
local GetBestMapForUnit = Map.GetBestMapForUnit
--    local GetWorldPosFromMapPos = Map.GetWorldPosFromMapPos
local GetPlayerMapPosition = Map.GetPlayerMapPosition
--    local GetMapInfo = Map.GetMapInfo
--    local GetMapChildrenInfo = Map.GetMapChildrenInfo

local QuestLog = C_QuestLog
--    local GetLogIndexForQuestID = QuestLog.GetLogIndexForQuestID
--    local QuestLogGetInfo = QuestLog.GetInfo
--    local QuestLogIsOnMap = QuestLog.IsOnMap
local QuestLogGetNextWaypoint = QuestLog.GetNextWaypoint
local RequestLoadQuestByID = QuestLog.RequestLoadQuestByID
local SetMapForQuestPOIs = QuestLog.SetMapForQuestPOIs
local GetQuestsOnMap = QuestLog.GetQuestsOnMap

--    local GetQuestPOIs = _G["GetQuestPOIs"]

--    local QuestOffer = C_QuestOffer
--    local QuestOfferGetMap = QuestOffer.GetMap

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
--    local GetPlayerZone = bind(hbd, hbd.GetPlayerZone)
--    local GetPlayerZonePosition = bind(hbd, hbd.GetPlayerZonePosition)
--    local GetUnitWorldPosition = bind(hbd, hbd.GetUnitWorldPosition)

local GetWorldVector = bind(hbd, hbd.GetWorldVector)
local GetWorldCoordinatesFromZone = bind(hbd, hbd.GetWorldCoordinatesFromZone)

-- helper functions
--[[
    local function GetContinentIdFromMapId(uiMapId)
        local mapInfo = C_Map.GetMapInfo(uiMapId)
        if not mapInfo then return end
        local uiMapType = mapInfo.mapType
        if uiMapType == Enum.UIMapType.Continent then
            return uiMapId
        end
        local parent = mapInfo.parentMapID
        if parent then
            return GetContinentIdFromMapId(parent)
        end
    end
]]

-- Get all the maps in the game recursively as a tree structure
--    local function getAllTheMaps(parentMapID)
--        local function addMaps(mapID, maps)
--            local mapInfo = GetMapInfo(mapID)
--            if not mapInfo then return end
--            local map = {}
--            for key, value in pairs(mapInfo) do
--                map[key] = value
--            end
--            maps[map.name] = map
--            for _, childMap in ipairs(GetMapChildrenInfo(mapID)) do
--                local childMapInfo = GetMapInfo(childMap.mapID)
--                if childMapInfo then
--                    addMaps(childMap.mapID, map)
--                end
--            end
--        end
--
--        local allMaps = {}
--        local rootMapID = parentMapID or 946 -- map ID of Cosmic map
--        addMaps(rootMapID, allMaps)
--        return allMaps
--    end
--
--    local mapTree = getAllTheMaps()
--    _p.MapTree = mapTree
--
--    local function foo()
--        local map = GetBestMapForUnit("player")
--        if not map then return end
--        local pos = GetPlayerMapPosition(map, "player")
--        if not pos then return end
--        local cid, wpos = GetWorldPosFromMapPos(map, pos)
--        if not cid or not wpos then return end
--        local x, y, i = GetPlayerWorldPosition()
--        if not x or not y or not i then return end
--        print("--------------------------------------------\n",
--            "Map:", map,
--            format("Pos: (%.4f, %.4f)\n", pos.x, pos.y),
--            format("   World: (%.2f, %.2f)\n", wpos.x, wpos.y),
--            format("  Player: (%.2f, %.2f) in %d", x, y, i))
--
--        local function printMapInfo(map)
--            local mapInfo = GetMapInfo(map)
--            if not mapInfo then return end
--            print(">>> Map info for map:", map)
--            printTable(mapInfo)
--            printMapInfo(mapInfo.parentMapID)
--        end
--
--        printMapInfo(map)
--    end
--    _p.Foo = foo

-- local functions
-- forward declarations
local trackingFunctions
local updateSuperTrackingIcon

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
    if not IsSuperTrackingAnything() then return end

    updateSuperTrackingIcon()

    local playerX, playerY, instanceId = GetPlayerWorldPosition()
    if not (playerX and playerY and instanceId) then return end

    local destX, destY = superTrackingDestination()
    if not (destX and destY) then return end

    local angle, _ = GetWorldVector(instanceId, playerX, playerY, destX, destY)
    if not angle then return end

    return 360 - deg(angle)
end

local function functionNotImplemented() end

-- GetNextWaypoint can legitimately return nothing until the quest's full data has
-- been requested and the active map for quest POIs has been set - normally done by
-- the quest log/map UI, which this addon never opens. RequestLoadQuestByID is async,
-- so only fire it once per quest and let the next update pick up the result.
local lastRequestedQuestID = nil

--    local lastQuestInfo = nil
local function superTrackingQuest()
    local questID = GetSuperTrackedQuestID()
    assert(questID, "Expected questID to be a number")

    --local logIndex = GetLogIndexForQuestID(questID);
    --if logIndex then
    --    local questInfo = QuestLogGetInfo(logIndex)
    --    if questInfo and questInfo ~= lastQuestInfo then
    --        print("--------------------------------------------")
    --        print("Quest info for questID:", questID)
    --        printTable(questInfo)
    --        lastQuestInfo = questInfo
    --    end
    --end

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

--- Get the world coordinates for the SuperTracking map pin.
--- @return number|nil, number|nil The x and y coordinates of the map pin.
local function superTrackingMapPin()
    local pinType, typeId = GetSuperTrackedMapPin()
    assert(pinType and typeId, "Expected pinType and typeId to be non-nil")

    local map = GetBestMapForUnit("player")
    if not map then return end

    local function handleAreaPOI()
        local info = GetAreaPOIInfo(map, typeId)
        assert(info, "Expected GetAreaPOIInfo to be non-nil")
        return info.position:GetXY()
    end

    local function handleQuestOffer()
    end

    local function handleTaxiNode()
        local nodes = GetTaxiNodesForMap(map)
        for _, node in ipairs(nodes) do
            if node.nodeID == typeId then
                return GetWorldCoordinatesFromZone(node.position.x, node.position.y, map)
            end
        end
    end

    local function handleDigSite()
    end

    local mapPinTrackingFunctions = {
        [Enum.SuperTrackingMapPinType.AreaPOI] = handleAreaPOI,
        [Enum.SuperTrackingMapPinType.QuestOffer] = handleQuestOffer,
        [Enum.SuperTrackingMapPinType.TaxiNode] = handleTaxiNode,
        [Enum.SuperTrackingMapPinType.DigSite] = handleDigSite,
    }

    local mapPinTrackingFunction = mapPinTrackingFunctions[pinType]

    return mapPinTrackingFunction()
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
local SuperTrackedFrame = _G["SuperTrackedFrame"]
local superTrackingMarker = nil
local superTrackingIconApplied = false

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
    return marker
end

local print = print
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

addon.SuperTracking = {
    Enable = function() api.SetElementEnabled(superTrackingElement, true) end,
    Disable = function() api.SetElementEnabled(superTrackingElement, false) end,
}
