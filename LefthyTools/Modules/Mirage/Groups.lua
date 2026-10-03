local _, ns = ...
local L = ns.L

local data = {}
ns.MirageData = data

-- HUD element groups Mirage fades. Each group fades as one unit and is revealed
-- as one unit when you mouse over any of its frames.
--
-- Frame names come from the Forever UI source (build 1.60.1.70009, "Camelot"
-- game type, which inherits the Mainline family). Names that don't exist in the
-- running client are skipped, so fallbacks for other clients are harmless.
--
-- Only list top-level containers. Blizzard alpha-manages many child frames
-- itself (party range fade, aura blinking, chat tab fading), and alpha is
-- inherited, so fading the container is enough. If a listed frame turns out to
-- be a child of another listed frame, Mirage.lua skips it to avoid double-fading.
-- Never list a frame whose own alpha Blizzard animates or reads back
-- (self:GetAlpha() checks); fade its parent and list it under `hover` instead.

local function ChatFrames()
	local names = {
		"GeneralDockManager",
		"ChatFrameMenuButton",
		"ChatFrameChannelButton",
		"ChatFrameToggleVoiceDeafenButton",
		"ChatFrameToggleVoiceMuteButton",
		"QuickJoinToastButton",
	}
	-- CHAT_FRAMES also holds temporary whisper windows (ChatFrame11+).
	local frames = CHAT_FRAMES
	if type(frames) ~= "table" or #frames == 0 then
		frames = {}
		for i = 1, (NUM_CHAT_WINDOWS or 10) do
			frames[i] = "ChatFrame" .. i
		end
	end
	for _, name in ipairs(frames) do
		names[#names + 1] = name
		names[#names + 1] = name .. "Tab"
		names[#names + 1] = name .. "EditBox"
		names[#names + 1] = name .. "ButtonFrame"
	end
	return names
end

data.GROUPS = {
	{
		key = "actionbars",
		label = L["Action bars"],
		frames = {
			"MainActionBar", "MainMenuBar",
			"MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
			"MultiBar5", "MultiBar6", "MultiBar7",
			"StanceBar", "PetActionBar", "PossessActionBar", "MultiCastActionBarFrame",
		},
	},
	{
		-- Forever's controller UI (Blizzard_GamepadActionBars / Blizzard_Gamepad, camelot only).
		-- Not an Edit Mode system, but a plain UIParent child, so alpha works the same way.
		-- Blizzard alpha-manages the children (inactive bars, flyouts), never these roots.
		key = "controller",
		label = L["Controller action bars & button legend"],
		frames = { "GamepadMainActionBarFrame", "GamepadPersistentInputLegend" },
	},
	{
		key = "reticle",
		label = L["Controller aiming reticle"],
		frames = { "GamepadReticle" },
		default = false, -- used to aim interactions, so it stays visible unless asked
	},
	{
		key = "unitframes",
		label = L["Player, pet, target & focus frames"],
		frames = { "PlayerFrame", "PetFrame", "TargetFrame", "FocusFrame", "PersonalResourceDisplayFrame" },
	},
	{
		key = "party",
		label = L["Party & raid frames"],
		frames = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer" },
	},
	{
		key = "cooldowns",
		label = L["Cooldown Manager & swing timer"],
		frames = {
			"EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer",
			"SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame",
		},
	},
	{
		key = "buffs",
		label = L["Buffs & debuffs"],
		frames = { "BuffFrame", "DebuffFrame" },
	},
	{
		key = "minimap",
		label = L["Minimap"],
		frames = { "MinimapCluster" },
	},
	{
		key = "objectives",
		label = L["Quest & objective tracker"],
		frames = { "ObjectiveTrackerFrame" },
	},
	{
		key = "menu",
		label = L["Micro menu & bag bar"],
		frames = { "MicroMenuContainer", "BagsBar" },
	},
	{
		key = "xpbars",
		label = L["Experience & reputation bars"],
		-- The bar containers are alpha-managed by Blizzard: they start at alpha 0, fade
		-- with their own animations, and branch on self:GetAlpha(). Fading them directly
		-- confuses that logic (bars stuck hidden), so fade their parent instead. The
		-- containers can be moved in Edit Mode, away from the parent's rect, so hover is
		-- detected on them.
		frames = { "StatusTrackingBarManager" },
		hover = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" },
	},
	{
		key = "meter",
		label = L["Damage meter"],
		frames = { "DamageMeter" },
	},
	{
		key = "chat",
		label = L["Chat"],
		frames = ChatFrames,
	},
	{
		key = "misc",
		label = L["Durability & vehicle indicators"],
		frames = { "DurabilityFrame", "VehicleSeatIndicator" },
	},
}

-- Windows that count as "using the UI". Most Blizzard windows register with the
-- UIParent panel manager and are caught via GetUIPanel(); these are extras that
-- don't, or might not, in this client.
data.WINDOWS = {
	"WorldMapFrame", "GameMenuFrame", "SettingsPanel", "KeyBindingFrame", "AddonList",
	"LootFrame", "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame",
	"QuestLogFrame", "MerchantFrame", "GossipFrame", "QuestFrame", "TaxiFrame", "BankFrame",
	"MailFrame", "TradeFrame", "AuctionHouseFrame", "ProfessionsFrame", "ClassTrainerFrame",
	"FriendsFrame", "MacroFrame", "ItemTextFrame", "DressUpFrame", "InspectFrame",
}

data.PANEL_AREAS = { "left", "center", "right", "doublewide", "fullscreen" }

-- Controller UI that means "actively using the interface" while shown: HUD
-- navigation mode, the radial menu, the action bar editor and bar flyouts.
data.CONTROLLER_WINDOWS = {
	"GamepadHudMode", "GamepadRadial", "GamepadActionBarEditFrame",
	"GamepadSpellFlyout", "GamepadPetActionFlyout", "GamepadPetSpellFlyout",
}

-- Chat events that briefly reveal the chat group. Say/yell/channels are left out
-- on purpose: in a city they would keep chat visible permanently.
data.CHAT_EVENTS = {
	"CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
}
