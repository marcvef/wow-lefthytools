-- WhyPoor?: the price engine (Prices.lua) and friends' prices (Share.lua).
-- Needs: margins.lua
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

section("whypoor_prices")
check(ns.WhyPoor ~= nil and LT:GetModule("whypoor") ~= nil, "the module is there")
