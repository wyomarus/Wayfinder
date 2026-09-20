-- Author      : Wyomarus
-- Create Date : 9/7/2024 5:11:21 PM

local addonName, addon = ...
_G[addonName] = addon

-- Addon namespaces
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

-- Global helper functions --

-- Binds a method to an object, creating a closure
-- to capture the object as the first argument
-- so it can be called as a function without the object reference as the first argument
-- (i.e. obj:method() instead of obj.method(obj)).
local function bind(obj, method)
    assert(type(obj) == "table", "Expected obj to be a table")
    assert(type(method) == "function", "Expected method to be a function")

    return function(...)
        return method(obj, ...)
    end
end
_p.bind = bind

-- Print a table to the default chat frame
local function printTable(table)
    assert(type(table) == "table", "Expected table to be a table")

    for key, value in pairs(table) do
        print(format("%s:", key), value)
    end
end
_p.printTable = printTable
