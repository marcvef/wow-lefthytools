-- WhyPoor?: the money data add-on and its reader (Data.lua).
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

section("whypoor_data")
check(ns.WhyPoor ~= nil and LT:GetModule("whypoor") ~= nil, "the module is there")
