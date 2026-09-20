-- Author      : Wyomarus
-- Create Date : 9/7/2024 5:11:21 PM

local addonName, addon = ...
_G[addonName] = addon -- expose the addon table globally by name, for in-game inspection/debugging

-- Addon namespaces. Each carries a "$Info" key as a self-documenting description,
-- readable via /dump or /script in-game without needing to open the source.
addon.API = addon.API or {
    ["$Info"] = "API functions for the Wayfinder addon."
}

addon.Dependencies = addon.Dependencies or {
    ["$Info"] = "Libraries and other dependencies used by the Wayfinder addon."
}

addon.private = addon.private or {
    ["$Info"] = "Private functions and data for the Wayfinder addon."
}

addon.Constants = addon.Constants or {
    ["$Info"] = "Constants used by the Wayfinder addon."
}

local _p = addon.private

assert(LibStub, addonName .. " requires LibStub")

-- Cache global references
local print = print
local format = string.format

-- Global helper functions

--- Bind a method to an object, returning a closure that captures the object as the
--- first argument so it can be called without it (i.e. obj:method() instead of
--- obj.method(obj)).
--- @param obj table
--- @param method function
--- @return function
local function bind(obj, method)
    assert(type(obj) == "table", "Expected obj to be a table")
    assert(type(method) == "function", "Expected method to be a function")

    return function(...)
        return method(obj, ...)
    end
end
_p.bind = bind

--- Print a table's key/value pairs to the default chat frame.
--- @param tbl table
local function printTable(tbl)
    assert(type(tbl) == "table", "Expected tbl to be a table")

    for key, value in pairs(tbl) do
        print(format("%s:", key), value)
    end
end
_p.printTable = printTable
