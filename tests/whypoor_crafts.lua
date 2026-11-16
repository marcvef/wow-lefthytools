-- WhyPoor?: the cheapest way to get an item and what a recipe brings, crafting the reagents yourself (Crafts.lua), and Margins using it.
-- Needs: margins.lua
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

section("whypoor_crafts")
check(ns.WhyPoor ~= nil and LT:GetModule("whypoor") ~= nil, "the module is there")
