-- Settings integrates Wayfinder's options into Blizzard's native addon Settings panel.

local _, addon = ...
local _p = addon.private
local api = addon.API
local _C = addon.Constants

local DetailLevel = _C.CompassDetail

local category, layout = Settings.RegisterVerticalLayoutCategory("Wayfinder")
Settings.RegisterAddOnCategory(category)

api.Settings = {
    Open = function() Settings.OpenToCategory(category:GetID()) end,
}

--- Register a setting backed by custom get/set callbacks rather than a direct
--- WayfinderSettings binding, so changing it in the panel goes through the same api.*
--- functions the slash commands use, keeping each module's own cached state in sync.
--- @param variable string A globally-unique setting name.
--- @param name string The label shown in the panel.
--- @param default boolean|number
--- @param getValue function
--- @param setValue function
--- @return table setting
local function registerSetting(variable, name, default, getValue, setValue)
    return Settings.RegisterProxySetting(category, variable, type(default), name, default, getValue, setValue)
end

layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Compass banner"))

local showBannerSetting = registerSetting(
    "WayfinderShowBanner", "Show compass banner", true,
    api.CompassBanner.IsShown,
    function(shown)
        if shown then _p.enableCompassBanner() else _p.disableCompassBanner() end
    end
)
local showBannerCheckbox = Settings.CreateCheckbox(category, showBannerSetting, "Show or hide the compass banner.")

local lockBannerSetting = registerSetting(
    "WayfinderLockBanner", "Lock position", true,
    api.CompassBanner.IsLocked,
    function(locked)
        if locked then api.CompassBanner.Lock() else api.CompassBanner.Unlock() end
    end
)
local lockBannerCheckbox = Settings.CreateCheckbox(
    category, lockBannerSetting, "Lock the banner in place, or unlock it to drag to a new position."
)
lockBannerCheckbox:SetParentInitializer(showBannerCheckbox, function() return showBannerSetting:GetValue() end)

layout:AddInitializer(CreateSettingsButtonInitializer(
    "Banner position", "Reset position",
    function() api.CompassBanner.ResetPosition() end,
    "Reset the compass banner to its default position.",
    true
))

local detailSetting = Settings.RegisterProxySetting(
    category, "WayfinderCompassDetail", type(DetailLevel.Pips), "Compass detail", DetailLevel.Pips,
    api.CardinalPoints.GetDetail, api.CardinalPoints.SetDetail
)
local function GetCompassDetailOptions()
    local container = Settings.CreateControlTextContainer()
    container:Add(DetailLevel.None, "None", "Hide compass detail entirely.")
    container:Add(DetailLevel.Cardinals, "Cardinals", "Cardinal directions only (N, E, S, W).")
    container:Add(DetailLevel.Intercardinals, "Intercardinals", "Cardinal and intercardinal directions.")
    container:Add(DetailLevel.Pips, "Pips", "Cardinal, intercardinal, and a tick every 15 degrees.")
    return container:GetData()
end
Settings.CreateDropdown(category, detailSetting, GetCompassDetailOptions, "How much compass detail to show.")

layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("SuperTracking"))

local trackingSetting = registerSetting(
    "WayfinderTrackingEnabled", "Enable tracking", true,
    api.SuperTracking.IsEnabled,
    function(enabled)
        if enabled then api.SuperTracking.Enable() else api.SuperTracking.Disable() end
    end
)
local trackingCheckbox = Settings.CreateCheckbox(
    category, trackingSetting, "Show a marker on the compass banner for whatever you're currently super-tracking."
)

local distanceSetting = registerSetting(
    "WayfinderShowDistance", "Show distance", true,
    api.SuperTracking.GetShowDistance, api.SuperTracking.SetShowDistance
)
local distanceCheckbox = Settings.CreateCheckbox(
    category, distanceSetting, "Show the distance to the super-tracked target."
)
distanceCheckbox:SetParentInitializer(trackingCheckbox, function() return trackingSetting:GetValue() end)

local etaSetting = registerSetting(
    "WayfinderShowETA", "Show ETA", true,
    api.SuperTracking.GetShowETA, api.SuperTracking.SetShowETA
)
local etaCheckbox = Settings.CreateCheckbox(
    category, etaSetting, "Show an estimated time of arrival to the super-tracked target."
)
etaCheckbox:SetParentInitializer(trackingCheckbox, function() return trackingSetting:GetValue() end)
