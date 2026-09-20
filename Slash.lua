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
    addon.CardinalPoints:Show()
    print("CardinalPoints enabled.")
end

local function DisableCardinalPoints()
    addon.CardinalPoints:Hide()
    print("CardinalPoints disabled.")
end

local function EnableSuperTracking()
    addon.SuperTracking:Enable()
    print("SuperTracking enabled.")
end

local function DisableSuperTracking()
    addon.SuperTracking:Disable()
    print("SuperTracking disabled.")
end

local function DebugSuperTracking()
    api.DebugSuperTracking()
end

local function PrintUsage()
    print("Usage:")
    print("/wayfinder show - Show the compass banner")
    print("/wayfinder hide - Hide the compass banner")
    print("/wayfinder compass enable|disable - Enable or disable the CardinalPoints")
    print("/wayfinder tracking enable|disable - Enable or disable SuperTracking")
    print("/wayfinder debug tracking - Print SuperTracking diagnostic info")
end

local commandHandlers = {
    show = ShowCompassBanner,
    hide = HideCompassBanner,
    compass = {
        enable = EnableCardinalPoints,
        disable = DisableCardinalPoints,
    },
    tracking = {
        enable = EnableSuperTracking,
        disable = DisableSuperTracking,
    },
    debug = {
        tracking = DebugSuperTracking,
    },
}

local function HandleSlashCommands(msg)
    local command, subcommand = msg:match("^(%S*)%s*(.-)$")
    local handler = commandHandlers[command]

    if type(handler) == "function" then
        handler()
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

local SlashCmdList = _G["SlashCmdList"]
SlashCmdList["WAYFINDER"] = HandleSlashCommands
_G.SLASH_WAYFINDER1 = "/wayfinder"
_G.SLASH_WAYFINDER2 = "/wf"
