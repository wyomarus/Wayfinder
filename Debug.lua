-- Debug holds Wayfinder's diagnostics: the /wayfinder debug commands and the WayfinderDebug
-- SavedVariable they record into. Nothing else needs it - SuperTracking.lua only offers a
-- read-only view of its state (_p.getSuperTrackingState) and an optional hook (_p.traceETA),
-- and Slash.lua only lists the commands when they exist - so a build can leave this file out.

local _, addon = ...
local _p = addon.private
local api = addon.API

-- Like SuperTracking, the diagnostics need APIs that only some clients have. Where they're
-- missing, stand in versions that do nothing (Slash.lua says so before calling them).
if not api.SuperTracking.IsSupported() then
    local function doNothing() end

    api.DebugSuperTracking = doNothing
    api.DebugETATrace = doNothing
    return
end

local bind = _p.bind

-- Cache global references
local print = print
local format = string.format
local date = date
local GetTime = GetTime
local GetUnitSpeed = GetUnitSpeed
local issecretvalue = issecretvalue

local Enum = Enum

local Map = C_Map
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

local GetNextWaypointForMap = C_Navigation.GetNextWaypointForMap

local hbd = addon.Dependencies["HereBeDragons-2.0"]
local GetPlayerWorldPosition = bind(hbd, hbd.GetPlayerWorldPosition)
local GetWorldVector = bind(hbd, hbd.GetWorldVector)
local GetWorldCoordinatesFromZone = bind(hbd, hbd.GetWorldCoordinatesFromZone)

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
    local state = _p.getSuperTrackingState()
    local lines = {}
    local function out(...)
        print(...)
        table.insert(lines, toLine(...))
    end

    out("Wayfinder SuperTracking debug:")
    out(" IsSuperTrackingAnything:", IsSuperTrackingAnything())

    local playerX, playerY, instanceId = GetPlayerWorldPosition()
    out(" GetPlayerWorldPosition:", playerX, playerY, instanceId)

    -- tostring() on a secret value throws just like arithmetic does, so it has to be
    -- checked before printing rather than passed straight to out()/print().
    local speed = GetUnitSpeed("player")
    out(" GetUnitSpeed(player):", issecretvalue(speed) and "<secret>" or speed)
    out(" closing speed on the target (yards/second):", state.closingSpeed)

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

    local trackingFunction = trackingType and state.trackingFunctions[trackingType]
    out(" fallback trackingFunction found:", trackingFunction ~= nil)

    local ok, destX, destY = pcall(state.destination)
    out(" superTrackingDestination result (ok, destX, destY):", ok, destX, destY)

    if ok and destX and destY and playerX and playerY and instanceId then
        local angle = GetWorldVector(instanceId, playerX, playerY, destX, destY)
        out(" GetWorldVector angle:", angle)
    end

    out(" SuperTrackedFrame exists:", SuperTrackedFrame ~= nil)
    local icon = SuperTrackedFrame and SuperTrackedFrame.Icon
    out(" SuperTrackedFrame.Icon atlas:", icon and icon:GetAtlas())
    out(" superTrackingIconAtlas (last applied):", state.iconAtlas)

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
    local ok2, wpX, wpY = pcall(state.userWaypoint)
    out(" superTrackingUserWaypoint result (ok, x, y):", ok2, wpX, wpY)

    table.insert(WayfinderDebug, { time = date("%Y-%m-%d %H:%M:%S"), lines = lines })
    while #WayfinderDebug > MAX_DEBUG_ENTRIES do
        table.remove(WayfinderDebug, 1)
    end

    print("Wayfinder: debug entry saved (" .. #WayfinderDebug .. " total). /reload or log out to flush to disk.")
end
api.DebugSuperTracking = debugSuperTracking

-- While recording (see debugETATrace), every readout update is logged - the time, the
-- distance to the target, the closing speed and the ETA that gives - so a jumpy ETA can be
-- studied from the SavedVariables file afterwards instead of guessed at.
local ETA_TRACE_SECONDS = 10
local etaTrace = nil

--- Log one ETA sample while a trace is recording. SuperTracking.lua calls this on every
--- readout update, if it's set.
--- @param distance number|nil
--- @param eta number|nil
--- @param closingSpeed number|nil
_p.traceETA = function(distance, eta, closingSpeed)
    if not (etaTrace and distance) then return end

    local elapsed = GetTime() - etaTrace.start
    table.insert(etaTrace.lines, format(
        "%.3f d=%.3f c=%s eta=%s",
        elapsed,
        distance,
        closingSpeed and format("%.3f", closingSpeed) or "-",
        eta and format("%.3f", eta) or "-"
    ))

    if elapsed >= ETA_TRACE_SECONDS then
        table.insert(WayfinderDebug, { time = date("%Y-%m-%d %H:%M:%S"), source = "etaTrace", lines = etaTrace.lines })
        while #WayfinderDebug > MAX_DEBUG_ENTRIES do
            table.remove(WayfinderDebug, 1)
        end
        print(format(
            "Wayfinder: ETA trace saved (%d samples). /reload or log out to write it to disk.",
            #etaTrace.lines
        ))
        etaTrace = nil
    end
end

--- Start recording the ETA for a few seconds, to study how it behaves while moving.
local function debugETATrace()
    etaTrace = { start = GetTime(), lines = {} }
    print(format("Wayfinder: recording the ETA for %d seconds - walk straight toward your tracked target.", ETA_TRACE_SECONDS))
end
api.DebugETATrace = debugETATrace
