std = "lua51"
max_line_length = false
exclude_files = {
    "**/Libs/**/*.lua",
    ".luacheckrc"
}
ignore = {
}

globals = {
    -- Saved Variables
    "WayfinderDebug",
    "WayfinderSettings",

    -- Lua
    "date",

    -- WoW
    "CreateFrame",
    "GetPlayerFacing",
    "GetTime",
    "GetUnitSpeed",
    "issecretvalue",
    "Settings",
    "PlaySound",
    "SOUNDKIT",
    "GameTooltip",
    "GameTooltip_Hide",
    "UIParent",
    "Enum",
    "SlashCmdList",
    "SuperTrackedFrame",
    "C_Map",
    "C_QuestLog",
    "C_SuperTrack",
    "C_AreaPoiInfo",
    "C_TaxiMap",
    "C_Navigation",
    "C_DeathInfo",
    "C_AddOns",
    "C_Texture",
    "C_Timer",
    "ScrollUtil",
    "AbbreviateNumbers",
    "IN_GAME_NAVIGATION_RANGE",

    -- Addon Compartment entry points - dispatched to by name from Wayfinder.toc, must be
    -- plain globals
    "Wayfinder_OnAddonCompartmentClick",
    "Wayfinder_OnAddonCompartmentEnter",
    "Wayfinder_OnAddonCompartmentLeave",

    -- Libs
    "LibStub"
}
