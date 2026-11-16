local _, ns = ...
local LT = ns.LT
local L = ns.L

-- WhyPoor?: ideas for making money, for this character, now: what's worth doing at its level, class,
-- professions and place, and how much it brings, from your own kills and sales, the auction house's
-- prices and the classic world database. Informational only: it never buys, sells or posts.
-- docs/whypoor.md has the parts and how they fit together.
--
-- Its own saved table (LefthyToolsWhyPoorDB, account-wide; Core/Core.lua stamps its world):
--   prices = { ... }   Prices.lua: auction house prices, per realm and faction, with their history
--   goal = { ... }     Goal.lua: the money goal (the mount), per character
--   ui = { ... }       Window.lua: the window's place, tab and list state

local M = LT:NewModule("whypoor", {
	title = "WhyPoor?",
	description = L["Ideas for making money with this character: what is worth doing at your level, class, professions and place, and roughly how much it brings, from your own kills, the auction house's prices and the classic world database. Informational only."],
	defaults = {
		minimapButton = true,
		minimapAngle = 120,   -- degrees, 0 = right, counter-clockwise
		tooltip = true,       -- one line in item tooltips (bags, auction house): vendor or auction house
		bagCoins = true,      -- a tiny coin on items in the sorted bags worth more at the auction house
		sharePrices = true,   -- share auction house prices with friends (Beacon) and use theirs
		window = {},          -- shown, left, top, tab (Window.lua)
	},
})

local W = ns.WhyPoor or {}
ns.WhyPoor = W
W.module = M

-- The saved table (nil before the saved variables are loaded).
function W.DB()
	return W.db
end

LT.onLoad[#LT.onLoad + 1] = function()
	LefthyToolsWhyPoorDB = type(LefthyToolsWhyPoorDB) == "table" and LefthyToolsWhyPoorDB or {}
	W.db = LefthyToolsWhyPoorDB
	for _, key in ipairs({ "prices", "goal", "ui" }) do
		W.db[key] = type(W.db[key]) == "table" and W.db[key] or {}
	end
end
