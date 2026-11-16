-- WhyPoor?: who I am (Context.lua) and the ideas, worked out and ranked (Methods.lua).
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

section("whypoor_methods")
check(ns.WhyPoor ~= nil and LT:GetModule("whypoor") ~= nil, "the module is there")
