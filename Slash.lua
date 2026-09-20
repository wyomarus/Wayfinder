-- Slash commands

local _, addon = ...
local _p = addon.private
local api = addon.API

local print = print

local function ShowCompassBanner()
    _p.enableCompassBanner()
    print("Compass banner shown.")
end

local function HideCompassBanner()
    _p.disableCompassBanner()
    print("Compass banner hidden.")
end

local function EnableCardinalPoints()
    api.CardinalPoints:Show()
    print("CardinalPoints enabled.")
end

local function DisableCardinalPoints()
    api.CardinalPoints:Hide()
    print("CardinalPoints disabled.")
end

local function EnableSuperTracking()
    api.SuperTracking:Enable()
    print("SuperTracking enabled.")
end

local function DisableSuperTracking()
    api.SuperTracking:Disable()
    print("SuperTracking disabled.")
end

local function DebugSuperTracking()
    api.DebugSuperTracking()
end

local function EnableTrackingDistance()
    api.SuperTracking.SetShowDistance(true)
    print("SuperTracking distance readout enabled.")
end

local function DisableTrackingDistance()
    api.SuperTracking.SetShowDistance(false)
    print("SuperTracking distance readout disabled.")
end

local function SetCompassDetail(arg)
    local level = tonumber(arg)
    if not level or level < 0 or level > 3 or level % 1 ~= 0 then
        print("Usage: /wayfinder detail <0-3>")
        print(" 0 - hide compass detail entirely")
        print(" 1 - cardinal directions only (N, E, S, W)")
        print(" 2 - cardinal and intercardinal directions (default)")
        print(" 3 - cardinal, intercardinal, and a tick every 15 degrees")
        return
    end

    api.CardinalPoints.SetDetail(level)
    print("Compass detail set to " .. level .. ".")
end

local function PrintUsage()
    print("Usage:")
    print("/wayfinder show - Show the compass banner")
    print("/wayfinder hide - Hide the compass banner")
    print("/wayfinder compass enable|disable - Enable or disable the CardinalPoints")
    print("/wayfinder detail <0-3> - Set how much compass detail is shown")
    print("/wayfinder tracking enable|disable - Enable or disable SuperTracking")
    print("/wayfinder distance enable|disable - Show or hide the SuperTracking distance readout")
    print("/wayfinder debug tracking - Print SuperTracking diagnostic info")
end

local commandHandlers = {
    show = ShowCompassBanner,
    hide = HideCompassBanner,
    compass = {
        enable = EnableCardinalPoints,
        disable = DisableCardinalPoints,
    },
    detail = SetCompassDetail,
    tracking = {
        enable = EnableSuperTracking,
        disable = DisableSuperTracking,
    },
    distance = {
        enable = EnableTrackingDistance,
        disable = DisableTrackingDistance,
    },
    debug = {
        tracking = DebugSuperTracking,
    },
}

local function HandleSlashCommands(msg)
    local command, subcommand = msg:match("^(%S*)%s*(.-)$")
    local handler = commandHandlers[command]

    if type(handler) == "function" then
        handler(subcommand)
    elseif type(handler) == "table" then
        local subHandler = handler[subcommand]
        if type(subHandler) == "function" then
            subHandler()
        else
            PrintUsage()
        end
    else
        PrintUsage()
    end
end

local SlashCmdList = SlashCmdList
SlashCmdList["WAYFINDER"] = HandleSlashCommands
_G.SLASH_WAYFINDER1 = "/wayfinder"
_G.SLASH_WAYFINDER2 = "/wf"
