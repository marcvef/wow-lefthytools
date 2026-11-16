-- WhyPoor?: the module, its settings, the window, the bags, the tooltip line, the goal (WhyPoor.lua, Window.lua, Bags.lua, Goal.lua).
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

section("whypoor_window")
check(ns.WhyPoor ~= nil and LT:GetModule("whypoor") ~= nil, "the module is there")
