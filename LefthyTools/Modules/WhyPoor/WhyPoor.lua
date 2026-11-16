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
--
-- This file: the module, its settings page, /whypoor and /lefthy whypoor, the minimap button (it joins
-- the combined LefthyTools button by itself, Core/Window.lua's Dock), and the few text helpers the
-- window, the bags and the goal share (W.Money, W.Age).

local M = LT:NewModule("whypoor", {
	title = "WhyPoor?",
	description = L["Ideas for making money with this character: what is worth doing at your level, class, professions and place, and roughly how much it brings, from your own kills, the auction house's prices and the classic world database. Informational only."],
	defaults = {
		minimapButton = true,
		minimapAngle = 120,   -- degrees, 0 = right, counter-clockwise
		sharePrices = true,   -- share auction house prices with friends (Beacon) and use theirs
		autoScan = true,      -- the whole auction house scanned when it opens (when the game allows one again)
		craftButton = true,   -- a "Margins" button on the profession window (Crafting.lua)
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

---------------------------------------------------------------------------
-- Shared text: money and ages, short
---------------------------------------------------------------------------

-- Copper in short: "1g 20s", "35s 2c", "8c" (German: k for copper), as Margins writes it; whole gold
-- from 100g on ("120g"), and without a zero part ("34g", "3s"). nil: nil.
function W.Money(copper)
	copper = tonumber(copper)
	if not copper then
		return nil
	end
	local c = math.floor(math.abs(copper) + 0.5)
	local text
	if c >= 1000000 or (c >= 10000 and math.floor(c / 100) % 100 == 0) then
		text = L["%dg"]:format(math.floor(c / 10000))
	elseif c >= 10000 then
		text = L["%dg %ds"]:format(math.floor(c / 10000), math.floor(c / 100) % 100)
	elseif c >= 100 and c % 100 == 0 then
		text = L["%ds"]:format(math.floor(c / 100))
	elseif c >= 100 then
		text = L["%ds %dc"]:format(math.floor(c / 100), c % 100)
	else
		text = L["%dc"]:format(c)
	end
	return copper <= -0.5 and ("-" .. text) or text
end

-- How long ago t was, short: "5 min", "2 h", "3 d" (under a minute: "1 min"). nil: nil.
function W.Age(t)
	t = tonumber(t)
	if not t then
		return nil
	end
	local s = math.max(0, time() - t)
	if s < 5400 then
		return L["%d min"]:format(math.max(1, math.floor(s / 60 + 0.5)))
	elseif s < 172800 then
		return L["%d h"]:format(math.floor(s / 3600 + 0.5))
	end
	return L["%d d"]:format(math.floor(s / 86400 + 0.5))
end

---------------------------------------------------------------------------
-- The minimap button
---------------------------------------------------------------------------

local MINIMAP_ICON = "Interface\\Icons\\INV_Misc_Coin_02"

function W.MinimapEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("WhyPoor?", 1, 0.82, 0)
	local line = W.Window and W.Window.GoalLine and W.Window.GoalLine()
	if line then
		GameTooltip:AddLine(line, 1, 1, 1, true)
	end
	GameTooltip:AddLine(L["Click: ideas for making money"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Right-click: your bags"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Drag: move it along the minimap"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

function W.MinimapClick(_, mouseButton)
	if not W.Window then
		return
	end
	if mouseButton == "RightButton" then
		W.Window.Open("bags")
	else
		W.Window.Toggle()
	end
end

-- After switching the module on or off and the setting (on the next frame).
function W.UpdateMinimapButton()
	local show = M.enabled and M.db and M.db.minimapButton and Minimap ~= nil
	if show and not W.minimapButton then
		W.minimapButton = LT.Window.MinimapButton("LefthyToolsWhyPoorMinimapButton", { icon = MINIMAP_ICON, db = M.db,
			angleKey = "minimapAngle", angle = 120, label = "WhyPoor?", onClick = W.MinimapClick, onEnter = W.MinimapEnter })
	end
	if W.minimapButton then
		W.minimapButton:SetShown(show and true or false)
		if show then
			W.minimapButton:Place()
		end
	end
end

---------------------------------------------------------------------------
-- The module's calls
---------------------------------------------------------------------------

-- The parts that care (Window.lua: closed when off; Crafting.lua: the profession window's button).
function W.Changed()
	if W.Window and W.Window.SettingsChanged then
		LT.Guard("WhyPoor.window", W.Window.SettingsChanged)
	end
	if W.Crafting and W.Crafting.SettingsChanged then
		LT.Guard("WhyPoor.crafting", W.Crafting.SettingsChanged)
	end
	W.UpdateMinimapButton()
end

function M:OnEnable()
	C_Timer.After(0, W.Changed)
end

function M:OnDisable()
	C_Timer.After(0, W.Changed)
end

function M:OnSettingChanged()
	C_Timer.After(0, W.Changed)
end

function M:BuildOptions(o)
	o:Header(L["Window"])
	o:Button(L["Open WhyPoor?"], L["Open"], function() W.Window.Open() end,
		L["Ideas for making money with this character, your bags' best sales and the auction house's deals, in one window. Also /whypoor."])
	o:Checkbox("minimapButton", L["Minimap button"],
		L["A button on the edge of the minimap: click opens the window, right-click your bags. Drag it to move it."])
	o:Header(L["Crafting"])
	o:Checkbox("craftButton", L["Margins button on the profession window"],
		L["A Margins button on your profession window: what the recipe shown costs and brings in the Crafting tab, and with the auction house open its prices are checked there."])
	o:Header(L["Auction house"])
	o:Checkbox("autoScan", L["Scan the whole auction house when it opens"],
		L["Opening the auction house reads all its listings at once, a little each frame, when the game allows that again (every 15 minutes). The prices give the Market tab's deals and the ideas' auction house prices. Off: only Margins' scan button scans."])
	o:Header(L["Friends"])
	o:Checkbox("sharePrices", L["Share auction house prices with friends"],
		L["Your auction house prices go to your Beacon friends with LefthyTools, and theirs come to you, marked as theirs. Needs Beacon."])
end

local function Help()
	M:Print("/whypoor - open or close the window: ideas for making money")
	M:Print("/whypoor ideas | crafting | bags | market | goal - the window on that page")
	M:Print("/whypoor minimap - show or hide the minimap button")
	M:Print("/whypoor settings - WhyPoor?'s settings")
end

local TABS = { ideas = "ideas", bags = "bags", market = "market", goal = "goal", crafting = "crafting", margins = "crafting" }

function M:OnSlashCommand(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "settings" or cmd == "options" then
		LT:OpenSettings(self)
	elseif cmd == "help" or cmd == "?" then
		Help()
	elseif cmd == "minimap" then
		LT:SetModuleSetting(self, "minimapButton", not self.db.minimapButton)
		self:Print("minimap button " .. (self.db.minimapButton and "on." or "off."))
	elseif not self.enabled then
		LT.Print("WhyPoor? is switched off (/lefthy enable whypoor).")
	elseif cmd == "" then
		W.Window.Toggle()
	elseif TABS[cmd] then
		W.Window.Open(TABS[cmd])
	else
		Help()
	end
end

SLASH_LEFTHYTOOLS_WHYPOOR1 = "/whypoor"
SlashCmdList.LEFTHYTOOLS_WHYPOOR = function(msg)
	M:OnSlashCommand(msg)
end
