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
--    local GetPlayerMapPosition = Map.GetPlayerMapPosition
--    local GetMapInfo = Map.GetMapInfo
--    local GetMapChildrenInfo = Map.GetMapChildrenInfo

local QuestLog = C_QuestLog
--    local GetLogIndexForQuestID = QuestLog.GetLogIndexForQuestID
--    local QuestLogGetInfo = QuestLog.GetInfo
--    local QuestLogIsOnMap = QuestLog.IsOnMap
local QuestLogGetNextWaypoint = QuestLog.GetNextWaypoint

--    local GetQuestPOIs = _G["GetQuestPOIs"]

--    local QuestOffer = C_QuestOffer
--    local QuestOfferGetMap = QuestOffer.GetMap

local SuperTrack = C_SuperTrack
local IsSuperTrackingAnything = SuperTrack.IsSuperTrackingAnything
local GetHighestPrioritySuperTrackingType = SuperTrack.GetHighestPrioritySuperTrackingType
local GetSuperTrackedQuestID = SuperTrack.GetSuperTrackedQuestID
local GetSuperTrackedMapPin = SuperTrack.GetSuperTrackedMapPin

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

--- Callback for the SuperTracking element on the compass banner.
local function superTrackingCallback()
    if not IsSuperTrackingAnything() then return end

    local playerX, playerY, instanceId = GetPlayerWorldPosition()
    if not (playerX and playerY and instanceId) then return end

    local trackingType = GetHighestPrioritySuperTrackingType()
    if not trackingType then return end

    local trackingFunction = trackingFunctions[trackingType]
    if not trackingFunction then return end

    local destX, destY = trackingFunction()
    if not (destX and destY) then return end

    local angle, _ = GetWorldVector(instanceId, playerX, playerY, destX, destY)
    if not angle then return end

    return 360 - deg(angle)
end

local function functionNotImplemented() end

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

    local mapID, x, y = QuestLogGetNextWaypoint(questID)
    if not mapID or not x or not y then return nil, nil end

    return GetWorldCoordinatesFromZone(x, y, mapID)
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

local SuperTrackedFrame = _G["SuperTrackedFrame"]
local superTrackingIconTexture = nil

local function getSuperTrackingIconTexture()
    if superTrackingIconTexture then return superTrackingIconTexture end
    local superTrackedIcon = SuperTrackedFrame and SuperTrackedFrame.Icon
    local texture = superTrackedIcon and superTrackedIcon:GetTexture()
    if texture then
        superTrackingIconTexture = texture
        return texture
    end
end

local superTrackingMarker = nil

--- Create the SuperTracking marker for the compass banner
local function createSuperTrackingMarker(frame)
    if superTrackingMarker then return superTrackingMarker end
    local superTrackedIconTexture = getSuperTrackingIconTexture()
    local marker = frame:CreateTexture(nil, "OVERLAY")
    marker:SetTexture(superTrackedIconTexture)
    marker:SetTexCoord(0.5, 1.0, 0.0, 0.5) -- should be the upper-right quadrant
    marker:SetSize(25, 25)
    superTrackingMarker = marker
    return marker
end

local isSticky = true

api.AddElementToBanner(
    "SuperTracking",
    superTrackingCallback,
    createSuperTrackingMarker,
    isSticky
)
