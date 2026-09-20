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
    "IsInInstance",
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
    "AbbreviateNumbers",
    "IN_GAME_NAVIGATION_RANGE",

    -- Libs
    "LibStub"
}
