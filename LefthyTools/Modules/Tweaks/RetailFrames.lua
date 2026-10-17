local _, ns = ...

-- Misc Tweaks: retail unit frames (retailFrames, off by default).
--
-- Since build 1.60.1.70425 Forever draws the player, target, focus, party and pet frames in a
-- classic style: its own art set ("c60", Data/RetailUnitFrames.lua explains the atlas sets)
-- overrides the retail atlases by name, and its Camelot code moves the bars, names and levels to fit
-- (PlayerFrame_Update*Visuals, TargetFrameMixin:OnLoad / UpdateHealthBarVisuals, the party frames'
-- ArtLayoutInfo, the target of target and pet frames' OnLoad). Switched on, this puts retail back:
--
--   * Art: every texture of those frames showing one of the overridden atlases gets retail's file,
--     texture coordinates and (where Blizzard sizes it by the atlas) size; mask textures retail's
--     mask file. A status bar's fill crops its texture itself, so it gets another atlas with
--     retail's bar art instead (RETAIL_FRAME_BARS). Each texture's SetAtlas and each bar's
--     SetStatusBarTexture is post-hooked, so later changes (target classification, power types,
--     vehicles) come out retail too.
--   * Layout: retail's positions (Blizzard's own retail code and XML), after Blizzard's code places
--     them (post-hooks). Bars and their containers are protected frames: moved only out of combat;
--     if Forever's code moves them in combat (a new target), they follow when it ends. Textures and
--     font strings any time.
--
-- Nothing of Blizzard's is replaced; only hooksecurefunc post-hooks. Switching it off takes a /reload
-- (Forever's layout isn't put back piece by piece).

local LT = ns.LT
local ART = ns.RETAIL_FRAME_ART or {}
local BARS = ns.RETAIL_FRAME_BARS or {}
local issecret = LT.IsSecret

local on = false
local applied = false        -- switched on this session (switching off then needs a /reload)
local layoutPending = false  -- protected frames to move once combat ends
local hooked = setmetatable({}, { __mode = "k" })    -- texture or bar -> true (post-hooked)
local barTexture = setmetatable({}, { __mode = "k" }) -- a status bar's fill texture -> true
local events = CreateFrame("Frame")

-- t[k1][k2]... or nil (Blizzard's frames, if this client has them as expected).
local function Path(t, ...)
	for i = 1, select("#", ...) do
		if type(t) ~= "table" then
			return nil
		end
		t = t[select(i, ...)]
	end
	return t
end

local function Key(atlas)
	return type(atlas) == "string" and not issecret(atlas) and atlas:lower() or nil
end

local function Point(region, ...)
	if region then
		region:ClearAllPoints()
		region:SetPoint(...)
	end
end

---------------------------------------------------------------------------
-- Art
---------------------------------------------------------------------------

-- A texture just set to one of Forever's overridden atlases: retail's instead.
local function Restyle(texture, atlas, useAtlasSize)
	local key = on and Key(atlas)
	if not key then
		return
	end
	if barTexture[texture] then
		local alias = BARS[key]
		if alias then
			texture:SetAtlas(alias) -- (this hook runs again: the alias isn't one of Forever's)
		end
		return
	end
	local art = ART[key]
	if not art then
		return
	end
	if texture:GetObjectType() == "MaskTexture" then
		texture:SetTexture(art[1], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	else
		texture:SetTexture(art[1])
		texture:SetTexCoord(art[2], art[3], art[4], art[5])
	end
	if useAtlasSize then
		texture:SetSize(art[6], art[7])
	end
end

local function OnSetAtlas(texture, atlas, useAtlasSize)
	Restyle(texture, atlas, useAtlasSize)
end

local function OnSetStatusBarTexture(bar, asset)
	local texture = bar:GetStatusBarTexture()
	if texture then
		barTexture[texture] = true
	end
	local alias = on and BARS[Key(asset) or ""]
	if alias then
		bar:SetStatusBarTexture(alias) -- (this hook runs again: the alias isn't one of Forever's)
	end
end

-- Did Blizzard size it by its atlas (XML useAtlasSize)? Then it has the atlas's size now. A size the
-- game keeps secret (a bar's fill: its width is the health) is a bar's, not the atlas's.
local function SizedByAtlas(texture, atlas)
	if barTexture[texture] then
		return false
	end
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	local w, h = texture:GetSize()
	if not info or issecret(w) or issecret(h) or type(w) ~= "number" or type(h) ~= "number" then
		return false
	end
	return math.abs(w - info.width) < 0.5 and math.abs(h - info.height) < 0.5
end

local function Texture(texture)
	if not hooked[texture] then
		hooked[texture] = true
		hooksecurefunc(texture, "SetAtlas", OnSetAtlas)
	end
	local atlas = texture.GetAtlas and texture:GetAtlas()
	if atlas then
		Restyle(texture, atlas, SizedByAtlas(texture, atlas))
	end
end

-- Every texture of a frame and its children (status bars first: their fill is marked as such).
local function Walk(frame, depth)
	if type(frame) ~= "table" or depth > 10 or (frame.IsForbidden and frame:IsForbidden()) then
		return
	end
	if frame.GetStatusBarTexture then
		local fill = frame:GetStatusBarTexture()
		if fill then
			barTexture[fill] = true
		end
		if not hooked[frame] then
			hooked[frame] = true
			hooksecurefunc(frame, "SetStatusBarTexture", OnSetStatusBarTexture)
		end
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region.GetObjectType and region:GetObjectType()
		if kind == "Texture" or kind == "MaskTexture" then
			Texture(region)
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		Walk(child, depth + 1)
	end
end

local function PartyMembers()
	local list, pool = {}, Path(PartyFrame, "PartyMemberFramePool")
	if pool and pool.EnumerateActive then
		for member in pool:EnumerateActive() do
			list[#list + 1] = member
		end
	end
	return list
end

local function WalkAll()
	for _, name in ipairs({ "PlayerFrame", "PetFrame", "TargetFrame", "FocusFrame", "TargetFrameToT", "FocusFrameToT",
			"PartyFrame", "Boss1TargetFrame", "Boss2TargetFrame", "Boss3TargetFrame", "Boss4TargetFrame", "Boss5TargetFrame" }) do
		Walk(_G[name], 0)
	end
end

---------------------------------------------------------------------------
-- Layout: retail's (Blizzard's retail Lua and XML). Regions any time, protected frames out of combat.
---------------------------------------------------------------------------

local function CanMove()
	if InCombatLockdown() then
		layoutPending = true
		return false
	end
	return true
end

-- The player frame: level (gold, at the top right), name, flash, status, bars.
local function PlayerMain()
	return Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain")
end

local function PlayerName_()
	local main = PlayerMain()
	if main and PlayerName then
		Point(PlayerName, "TOPLEFT", main, "TOPLEFT", PlayerFrame.unit == "vehicle" and 96 or 88, -27)
	end
end

local function PlayerLevelColour()
	local unit = PlayerFrame and PlayerFrame.unit or "player"
	local level, effective = UnitLevel(unit), UnitEffectiveLevel and UnitEffectiveLevel(unit) or UnitLevel(unit)
	if PlayerLevelText and not issecret(level) and not issecret(effective) and level == effective then
		PlayerLevelText:SetVertexColor(1, 0.82, 0, 1)
	end
end

local function PlayerFlash()
	local flash = Path(PlayerFrame, "PlayerFrameContainer", "FrameFlash")
	if not flash then
		return
	end
	if PlayerFrame.unit == "vehicle" then
		flash:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Vehicle-InCombat", true)
		flash:SetPoint("CENTER", flash:GetParent(), "CENTER", -3.5, 1)
	elseif PlayerFrame_GetAlternatePowerBar and PlayerFrame_GetAlternatePowerBar() then
		flash:SetPoint("CENTER", flash:GetParent(), "CENTER", -2, 0.5)
	else
		flash:SetPoint("CENTER", flash:GetParent(), "CENTER", -1.5, 1)
	end
end

local function PlayerStatus()
	local status = Path(PlayerMain(), "StatusTexture")
	local flash = Path(PlayerFrame, "PlayerFrameContainer", "FrameFlash")
	if not (status and flash) then
		return
	end
	if PlayerFrame.unit == "vehicle" then
		status:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Vehicle-Status", true)
		status:SetPoint("TOPLEFT", flash:GetParent(), "TOPLEFT", 11, -8)
	else
		status:SetPoint("TOPLEFT", flash:GetParent(), "TOPLEFT", 18, -14)
	end
end

local function PlayerHealth()
	local main = PlayerMain()
	local container = Path(main, "HealthBarsContainer")
	local bar = Path(container, "HealthBar")
	if not bar then
		return
	end
	local vehicle = PlayerFrame.unit == "vehicle"
	local mask = container.HealthBarMask
	if mask then
		if vehicle then
			mask:SetPoint("TOPLEFT", container, "TOPLEFT", -8, 6)
		else
			mask:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 6)
			mask:SetHeight(31)
		end
	end
	if CanMove() then
		local height = vehicle and 20 or 19
		container:SetWidth(vehicle and 118 or 124)
		container:SetHeight(height)
		container:SetPoint("TOPLEFT", vehicle and 91 or 85, vehicle and -40 or -41)
		bar:SetHeight(height)
		Point(bar, "TOPLEFT", container, "TOPLEFT", 0, 0)
	end
end

local function PlayerMana()
	local bar = Path(PlayerMain(), "ManaBar")
	if not bar then
		return
	end
	local vehicle = PlayerFrame.unit == "vehicle"
	if bar.ManaBarMask then
		bar.ManaBarMask:SetWidth(vehicle and 121 or 128)
	end
	if CanMove() then
		bar:SetWidth(vehicle and 118 or 124)
		bar:SetHeight(10)
		bar:SetPoint("TOPLEFT", vehicle and 91 or 85, -61)
	end
end

local function Player()
	local main = PlayerMain()
	if not main then
		return
	end
	if PlayerLevelText then
		if GameNormalNumberFont then
			PlayerLevelText:SetFontObject(GameNormalNumberFont)
		end
		PlayerLevelText:SetJustifyH("RIGHT")
		Point(PlayerLevelText, "TOPRIGHT", main, "TOPRIGHT", -24.5, -28)
	end
	if main.LevelBackgroundCircle then
		main.LevelBackgroundCircle:Hide() -- (Forever's; retail shows the level on the frame)
	end
	if PlayerName then
		PlayerName:SetJustifyH("LEFT")
		PlayerName:SetWidth(96)
	end
	PlayerName_()
	PlayerLevelColour()
	PlayerFlash()
	PlayerStatus()
	PlayerHealth()
	PlayerMana()
end

-- Target and focus: name and level left of the reputation colour, the level's skull, flash, bars.
local function TargetHealth(frame, classification)
	local main = Path(frame, "TargetFrameContent", "TargetFrameContentMain")
	local container = Path(main, "HealthBarsContainer")
	local bar = Path(container, "HealthBar")
	if not bar then
		return
	end
	local minus = classification == "minus"
	if container.HealthBarMask then
		container.HealthBarMask:SetAtlas(minus and "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn-Bar-Health-Mask"
			or "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask", true)
		container.HealthBarMask:SetPoint("TOPLEFT", -1, minus and 2 or 6)
	end
	if CanMove() then
		container:SetHeight(minus and 12 or 20)
		container:SetWidth(minus and 125 or 126)
		container:SetPoint("BOTTOMRIGHT", frame.TargetFrameContainer, "LEFT", minus and 148 or 149, minus and -1 or -10)
		Point(bar, "TOPLEFT", container, "TOPLEFT", 0, 0)
	end
end

local function Target(frame)
	local main = Path(frame, "TargetFrameContent", "TargetFrameContentMain")
	local rep = Path(main, "ReputationColor")
	if not rep then
		return
	end
	Point(rep, "TOPRIGHT", main, "TOPRIGHT", -75, -25)
	if main.Name then
		main.Name:SetJustifyH("LEFT")
		main.Name:SetWidth(90)
		Point(main.Name, "TOPLEFT", rep, "TOPRIGHT", -106, -1)
	end
	if main.LevelText then
		if GameNormalNumberFont then
			main.LevelText:SetFontObject(GameNormalNumberFont)
		end
		main.LevelText:SetJustifyH("CENTER")
		Point(main.LevelText, "TOPLEFT", rep, "TOPRIGHT", -133, -2)
		Point(Path(frame, "TargetFrameContent", "TargetFrameContentContextual", "HighLevelTexture"), "TOPLEFT", main.LevelText, "TOPLEFT", 4, 2)
	end
	if main.LevelBackgroundCircle then
		main.LevelBackgroundCircle:Hide()
	end
	Point(Path(frame, "TargetFrameContainer", "Flash"), "CENTER", frame.TargetFrameContainer, "CENTER", 0, 2)
	local mana = main.ManaBar
	if mana then
		Point(mana.RightText, "RIGHT", mana, "RIGHT", -13, 0)
		if CanMove() and main.HealthBarsContainer then
			mana:SetWidth(134)
			Point(mana, "TOPRIGHT", main.HealthBarsContainer, "BOTTOMRIGHT", 8, -1)
		end
	end
	local unit = frame.unit
	local exists = unit and UnitExists(unit)
	local classification = exists and not issecret(exists) and UnitClassification(unit) or nil
	TargetHealth(frame, not issecret(classification) and classification or nil)
end

-- Target of target (the target's and the focus's) and the pet: name, bars, masks.
local function TargetOfTarget(frame)
	if not (frame and frame.HealthBar and frame.ManaBar) then
		return
	end
	if frame.Name and frame.Portrait then
		frame.Name:SetJustifyH("LEFT")
		Point(frame.Name, "TOPLEFT", frame.Portrait, "TOPRIGHT", 2, 0)
	end
	Point(frame.HealthBar.HealthBarMask, "TOPLEFT", frame.HealthBar, "TOPLEFT", -29, 3)
	if CanMove() then
		Point(frame.HealthBar, "BOTTOMRIGHT", frame, "RIGHT", -6, -2.5)
		Point(frame.ManaBar, "TOPLEFT", frame.HealthBar, "BOTTOMLEFT", -4, -1)
	end
end

local function Pet()
	if not (PetFrame and PetPortrait and PetFrameHealthBar and PetFrameManaBar) then
		return
	end
	if PetName then
		PetName:SetJustifyH("LEFT")
		Point(PetName, "TOPLEFT", PetPortrait, "TOPRIGHT", 2, 0)
	end
	Point(PetAttackModeTexture, "TOPLEFT", PetFrame, "TOPLEFT", 0, 1)
	Point(PetFrameFlash, "TOPLEFT", PetFrame, "TOPLEFT", 1, 0)
	Point(PetFrameHealthBarMask, "TOPLEFT", PetFrameHealthBar, "TOPLEFT", -29, 3)
	if CanMove() then
		Point(PetFrameHealthBar, "BOTTOMLEFT", PetPortrait, "RIGHT", 2, -3.5)
		Point(PetFrameManaBar, "TOPLEFT", PetFrameHealthBar, "BOTTOMLEFT", -4, -1)
	end
end

-- Party members: retail's ArtLayoutInfo (Forever replaced its Player and Character entries).
local PARTY = {
	Player = { name = 57, role = { -5, -5 }, health = { 70, 10, 45, -19, -29, 3 }, mana = { 74, 41, -30, 14, -26 },
		flash = { 1, -2 }, status = { 1, -2 } },
	Character = { name = 57, role = { -5, -5 }, health = { 70, 10, 45, -19, -29, 3 }, mana = { 69, 46, -30, 17, -28, 128, 9 },
		flash = { 1, -2 }, status = { 1, -2 } },
}

local function PartyName(member)
	if member.Name and member.state ~= "vehicle" then
		member.Name:SetPoint("TOPLEFT", member, "TOPLEFT", 46, (LOCALE_zhCN or LOCALE_zhTW) and -4 or -6)
	end
end

local function PartyMember(member, style)
	local layout = PARTY[style]
	local container, mana = member.HealthBarContainer, member.ManaBar
	if not (layout and container and container.HealthBar and mana) then
		return
	end
	if member.Flash then
		member.Flash:SetPoint("TOPLEFT", member, "TOPLEFT", layout.flash[1], layout.flash[2])
	end
	local overlay = member.PartyMemberOverlay
	if overlay and overlay.Status then
		overlay.Status:SetPoint("TOPLEFT", member, "TOPLEFT", layout.status[1], layout.status[2])
	end
	if overlay and overlay.RoleIcon then
		overlay.RoleIcon:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", layout.role[1], layout.role[2])
	end
	local h, m = layout.health, layout.mana
	if container.HealthBarMask then
		container.HealthBarMask:SetPoint("TOPLEFT", h[5], h[6])
	end
	if mana.ManaBarMask then
		mana.ManaBarMask:SetPoint("TOPLEFT", member, "TOPLEFT", m[4], m[5])
		if m[6] then
			mana.ManaBarMask:SetSize(m[6], m[7])
		end
	end
	if member.Name then
		member.Name:SetWidth(layout.name)
	end
	PartyName(member)
	if CanMove() then
		container.HealthBar:SetHeight(h[2])
		container:SetWidth(h[1])
		container:SetPoint("TOPLEFT", member, "TOPLEFT", h[3], h[4])
		mana:SetWidth(m[1])
		mana:SetPoint("TOPLEFT", member, "TOPLEFT", m[2], m[3])
	end
end

local function PartyStyle(member)
	if member.state == "vehicle" then
		return nil -- (Forever kept retail's vehicle layout)
	end
	return member.frameType == "CharacterFrameOn" and "Character" or "Player"
end

local function HookParty()
	for _, member in ipairs(PartyMembers()) do
		if not hooked[member] then
			hooked[member] = true
			if member.ToPlayerArt then
				hooksecurefunc(member, "ToPlayerArt", function(self) if on then PartyMember(self, "Player") end end)
			end
			if member.ToCharacterStyleArt then
				hooksecurefunc(member, "ToCharacterStyleArt", function(self) if on then PartyMember(self, "Character") end end)
			end
			if member.UpdateNameTextAnchors then
				hooksecurefunc(member, "UpdateNameTextAnchors", function(self) if on then PartyName(self) end end)
			end
		end
	end
end

local function Party()
	HookParty()
	for _, member in ipairs(PartyMembers()) do
		local style = PartyStyle(member)
		if style then
			PartyMember(member, style)
		end
	end
end

local function Layout()
	layoutPending = false
	Player()
	for _, frame in ipairs({ TargetFrame, FocusFrame }) do
		Target(frame)
	end
	TargetOfTarget(TargetFrameToT)
	TargetOfTarget(FocusFrameToT)
	Pet()
	Party()
end

---------------------------------------------------------------------------
-- Hooks (once) and switching
---------------------------------------------------------------------------

local function Hook(name, fn)
	if type(_G[name]) == "function" then
		hooksecurefunc(name, function(...) if on then fn(...) end end)
	end
end

local hooksSet = false
local function SetHooks()
	if hooksSet then
		return
	end
	hooksSet = true
	Hook("PlayerFrame_UpdatePlayerNameTextAnchor", PlayerName_)
	Hook("PlayerFrame_UpdateLevel", PlayerLevelColour)
	Hook("PlayerFrame_UpdateFlashTextureVisuals", PlayerFlash)
	Hook("PlayerFrame_UpdateStatusTextureVisuals", PlayerStatus)
	Hook("PlayerFrame_UpdateHealthBarVisuals", PlayerHealth)
	Hook("PlayerFrame_UpdateManaBarVisuals", PlayerMana)
	for _, frame in ipairs({ TargetFrame, FocusFrame }) do
		if type(frame) == "table" and type(frame.UpdateHealthBarVisuals) == "function" then
			hooksecurefunc(frame, "UpdateHealthBarVisuals", function(self, classification)
				if on then
					TargetHealth(self, classification)
				end
			end)
		end
	end
end

-- The events only note what to do; it's done on the next frame, once for a burst (a raid forming
-- sends GROUP_ROSTER_UPDATE many times a second).
local partyChanged = false
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
	self:Hide()
	if not on then
		return
	end
	if partyChanged then
		partyChanged = false
		Walk(PartyFrame, 0) -- new party member frames get their hooks and art
		Party()
	end
	if layoutPending and not InCombatLockdown() then
		Layout() -- (combat is over: the protected frames' turn)
	end
end)

events:SetScript("OnEvent", function(_, event)
	if not on then
		return
	end
	if event == "GROUP_ROSTER_UPDATE" then
		partyChanged = true
	elseif not layoutPending then
		return -- PLAYER_REGEN_ENABLED with nothing left over from the fight
	end
	driver:Show()
end)

-- Called by Tweaks.lua when the switch changes (on the next frame, never in a callback).
function ns.ApplyRetailFrames(enable)
	if enable then
		on, applied = true, true
		SetHooks()
		WalkAll()
		Layout()
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		events:RegisterEvent("GROUP_ROSTER_UPDATE")
	else
		on = false
		events:UnregisterAllEvents()
		if applied then
			LT:GetModule("tweaks"):Print("Retail unit frames: off. Type /reload to get Forever's frames back.")
		end
	end
end

-- For tests.
function ns.RetailFramesPending()
	return layoutPending
end
