local _, ns = ...
local L = ns.L

-- Misc Tweaks: who has aggro, on enemy nameplates (aggroNameplate).
--
-- In a group, the left end of each enemy's health bar says whom it's on: ">YOU<" when it's you,
-- else the first three letters of their name, in the colour of their role (tank blue, healer
-- green, damage red; white when it isn't known; a pet tan; someone outside the group grey). Small,
-- outlined with a shadow so the colour reads on the red bar (no backing: the user) (the user: "people will mostly look for the
-- color first"). Like the combo dots in the middle of the bar it takes no room: nothing on the
-- nameplate moves.
--
-- Who has it: the mob's target, when that's someone in the group whose threat says they're tanking
-- it (or whose threat can't be read). When the target isn't tanking it (a spell at someone else, a
-- fear), whoever is: UnitThreatSituation 3 (else 2) over the group. Someone outside the group
-- (another player, an escort): grey. A value the game keeps secret: that source is skipped;
-- nothing known, no tag. Only enemies in combat, not players.
--
-- Roles: UnitGroupRolesAssigned (the dungeon finder or a role check sets them), else the raid's
-- main tank, else a guess: Bear Form, Dire Bear Form and Righteous Fury are a tank, and so is your
-- own Defensive Stance. A group made by hand has no roles: its leader can start Blizzard's role
-- check (InitiateRolePoll: a button in the settings, /lefthy tweaks rolecheck), and everyone picks
-- one in Blizzard's window, LefthyTools or not.
--
-- Cost: events only mark a nameplate to look at again (its threat list, its target, its combat
-- flag); one OnUpdate looks at the marked ones on the next frame. While you're in combat in a
-- group it also looks at every enemy nameplate twice a second (once a second in a raid), in case
-- an event was missed; otherwise it stops.
--
-- The fight stream's battle row shows the same tag on the mobs fought (Beacon, StreamSense.lua and
-- StreamBattle.lua): ns.AggroHolder reads whom a mob is on, ns.AggroTag its text and colour. Its
-- sensor reads them also with this tweak off (or Misc Tweaks off); while it runs, ns.AggroWatch
-- keeps the group's roster fresh.

local SIZE = 8                   -- the letters (px, outlined)
local SWEEP, SWEEP_RAID = 0.5, 1 -- seconds between looks at every enemy while in combat
local PREVIEW_FOR = 10           -- seconds the examples show (/lefthy tweaks aggrotest)
local COLORS = {
	TANK = { 0.35, 0.62, 1 },
	HEALER = { 0.3, 0.95, 0.4 },
	DAMAGER = { 1, 0.32, 0.26 },
	NONE = { 0.92, 0.92, 0.92 },
	PET = { 0.85, 0.72, 0.45 },
	OUTSIDER = { 0.6, 0.6, 0.6 },
}
local TANK_AURAS = { 5487, 9634, 25780 } -- Bear Form, Dire Bear Form, Righteous Fury
local DEFENSIVE_STANCE = 71
local issecret = issecretvalue or function() return false end

local on = false                 -- switched by Tweaks.lua (ns.ApplyAggro)
local plates = {}                -- nameplate unit -> true: its nameplate is up
local dirty = {}                 -- nameplate unit -> true: look at it again
local tags = setmetatable({}, { __mode = "k" }) -- a nameplate's unit frame -> our tag on it
local shownOn = {}               -- nameplate unit -> the tag showing on it
local roster, rosterList = {}, {} -- GUID -> { unit, guid, name, role, you, pet }; and in group order
local rosterDirty = true
local sweeping, sinceSweep = false, 0
local previewUntil = 0
local auraNames                  -- TANK_AURAS' names, read once
local driver = CreateFrame("Frame")
local events = CreateFrame("Frame")

local function Value(f, ...)
	if not f then
		return nil
	end
	local ok, v = pcall(f, ...)
	if ok and not issecret(v) then
		return v
	end
end

-- The first three letters of a name (whole letters: "Ä" is two bytes).
local function Short(name)
	local out = {}
	for char in name:gmatch("[\1-\127\194-\244][\128-\191]*") do
		out[#out + 1] = char
		if #out == 3 then
			break
		end
	end
	return table.concat(out)
end

---------------------------------------------------------------------------
-- The group and its roles
---------------------------------------------------------------------------

local function HasTankAura(unit)
	if not auraNames then
		auraNames = {}
		for _, id in ipairs(TANK_AURAS) do
			local info = C_Spell and not C_Spell.GetSpellName and Value(C_Spell.GetSpellInfo, id)
			local name = C_Spell and (Value(C_Spell.GetSpellName, id) or type(info) == "table" and info.name)
			if name then
				auraNames[#auraNames + 1] = name
			end
		end
	end
	local bySpellName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
	local byName = AuraUtil and AuraUtil.FindAuraByName
	for _, name in ipairs(auraNames) do
		if (bySpellName and Value(bySpellName, unit, name, "HELPFUL")) or (byName and Value(byName, name, unit, "HELPFUL")) then
			return true
		end
	end
	return false
end

local function InDefensiveStance()
	local form = Value(GetShapeshiftForm)
	if not form or form == 0 or not GetShapeshiftFormInfo then
		return false
	end
	local ok, _, _, _, spellID = pcall(GetShapeshiftFormInfo, form)
	return ok and not issecret(spellID) and spellID == DEFENSIVE_STANCE
end

local function Role(unit, you)
	local role = Value(UnitGroupRolesAssigned, unit)
	if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
		return role
	elseif Value(GetPartyAssignment, "MAINTANK", unit) then
		return "TANK"
	elseif HasTankAura(unit) or (you and InDefensiveStance()) then
		return "TANK"
	end
	return "NONE"
end

local function AddMember(unit, you, pet)
	local guid = Value(UnitGUID, unit)
	if not guid or roster[guid] or (not you and not Value(UnitExists, unit)) then
		return -- (a raid lists you once more, and your pet)
	end
	local member = { unit = unit, guid = guid, name = Value(UnitName, unit), you = you, pet = pet }
	member.role = not pet and Role(unit, you) or nil
	roster[guid] = member
	rosterList[#rosterList + 1] = member
end

local function BuildRoster()
	rosterDirty = false
	wipe(roster)
	wipe(rosterList)
	AddMember("player", true, false)
	AddMember("pet", false, true)
	local raid = IsInRaid and IsInRaid()
	local prefix = raid and "raid" or "party"
	for i = 1, raid and 40 or 4 do
		AddMember(prefix .. i, false, false)
		AddMember(prefix .. "pet" .. i, false, true)
	end
end

---------------------------------------------------------------------------
-- Who has it
---------------------------------------------------------------------------

-- A unit's threat on the mob: 0-3, nil (not on its list), or false (it can't be read).
local function Threat(unit, mob)
	local ok, status = pcall(UnitThreatSituation, unit, mob)
	if not ok or issecret(status) then
		return false
	end
	return status
end

-- Whom the mob is on: a member of the group, or { name, outsider = true }; nil: nobody known.
local function Holder(mob)
	local target = mob .. "target"
	local guid = Value(UnitGUID, target)
	local member = guid and roster[guid]
	if member then
		local status = Threat(member.unit, mob)
		if status ~= 0 and status ~= 1 then
			return member -- (tanking it, or its threat can't be read: its target it is)
		end
	end
	-- Its target isn't tanking it (a spell at someone else, a fear), or isn't known: whoever is.
	local best, bestStatus
	for _, other in ipairs(rosterList) do
		local status = Threat(other.unit, mob)
		if status and status >= 2 and (not bestStatus or status > bestStatus) then
			best, bestStatus = other, status
		end
	end
	if best or member then
		return best or member
	end
	if guid and Value(UnitExists, target) then
		local name = Value(UnitName, target)
		if type(name) == "string" and name ~= "" then
			return { name = name, outsider = true }
		end
	end
end

-- What colours its tag: a member's role ("TANK", "HEALER", "DAMAGER", "NONE"), "PET" or "OUTSIDER".
local function RoleOf(holder)
	if holder.outsider then
		return "OUTSIDER"
	elseif holder.pet then
		return "PET"
	end
	return holder.role or "NONE"
end

-- A tag's text and colour: ">YOU<" in your role's colour, else the first three letters of the name.
local function Tag(role, name, you)
	return you and L[">YOU<"] or Short(name or "?"), COLORS[role] or COLORS.NONE
end

---------------------------------------------------------------------------
-- The tag on a nameplate
---------------------------------------------------------------------------

-- A nameplate's unit frame, if it has one addons may touch.
local function PlateFrame(unit)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return nil
	end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate or issecret(plate) or (plate.IsForbidden and plate:IsForbidden()) then
		return nil
	end
	return plate.UnitFrame
end

local function TagFor(frame)
	local tag = tags[frame]
	if not tag then
		tag = CreateFrame("Frame", nil, frame)
		tag.Text = tag:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tag.Text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", SIZE, "OUTLINE")
		tag.Text:SetShadowColor(0, 0, 0, 1) -- (no backing: a thin outline and a shadow keep it readable)
		tag.Text:SetShadowOffset(1, -1)
		tag.Text:SetPoint("CENTER", tag, "CENTER", 0, 0)
		tag:Hide()
		tags[frame] = tag
	end
	return tag
end

local function Hide(unit)
	local tag = shownOn[unit]
	if tag then
		tag:Hide()
		shownOn[unit] = nil
	end
end

local function Show(unit, text, color)
	local frame = PlateFrame(unit)
	if not frame then
		return Hide(unit)
	end
	local tag = TagFor(frame)
	-- On the health bar itself, at its left end (its container can be taller than the bar).
	local container = frame.HealthBarsContainer
	local bar = frame.healthBar or (type(container) == "table" and container.healthBar) or container or frame
	local ok = pcall(function()
		tag:ClearAllPoints()
		tag:SetPoint("LEFT", bar, "LEFT", 1, 0)
		tag:SetFrameLevel(bar:GetFrameLevel() + 10)
	end)
	if not ok then
		tag:Hide()
		return
	end
	tag.Text:SetText(text)
	tag.Text:SetTextColor(color[1], color[2], color[3])
	tag:SetSize(math.ceil(tag.Text:GetStringWidth()) + 4, SIZE + 3)
	tag:Show()
	shownOn[unit] = tag
end

-- The examples (/lefthy tweaks aggrotest): each enemy nameplate another one.
local SAMPLES = {
	{ nil, "TANK" }, -- (>YOU<)
	{ "Annabelle", "HEALER" },
	{ "Borgar", "DAMAGER" },
	{ "Cilla", "NONE" },
}

local function Sample(unit)
	if not (plates[unit] and Value(UnitCanAttack, "player", unit)) then
		return Hide(unit)
	end
	local sample = SAMPLES[((tonumber(unit:match("(%d+)$")) or 1) - 1) % #SAMPLES + 1]
	Show(unit, Tag(sample[2], sample[1], not sample[1]))
end

local function Update(unit)
	if GetTime() < previewUntil then
		return Sample(unit)
	end
	if not (on and plates[unit] and IsInGroup and IsInGroup()) then
		return Hide(unit)
	end
	if not Value(UnitCanAttack, "player", unit) or Value(UnitIsPlayer, unit) or Value(UnitIsDead, unit)
		or not Value(UnitAffectingCombat, unit) then
		return Hide(unit)
	end
	if rosterDirty then
		BuildRoster()
	end
	local holder = Holder(unit)
	if not holder then
		return Hide(unit)
	end
	Show(unit, Tag(RoleOf(holder), holder.name, holder.you))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function MarkAll()
	for unit in pairs(plates) do
		dirty[unit] = true
	end
	driver:Show()
end

local function Mark(unit)
	if unit and plates[unit] then
		dirty[unit] = true
		driver:Show()
	end
end

-- In combat in a group: every enemy is looked at again now and then. inCombat: what the event
-- says (the combat lockdown begins only after PLAYER_REGEN_DISABLED, so InCombatLockdown is still
-- false inside it); nil: asked.
local function CheckSweep(inCombat)
	if inCombat == nil then
		inCombat = (InCombatLockdown and InCombatLockdown()) or Value(UnitAffectingCombat, "player") == true
	end
	sweeping = on and IsInGroup and IsInGroup() and inCombat or false
	sinceSweep = 0
	if sweeping then
		driver:Show()
	end
end

driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
	for unit in pairs(dirty) do
		dirty[unit] = nil
		local ok, err = pcall(Update, unit)
		if not ok then
			geterrorhandler()(err)
		end
	end
	if sweeping then
		sinceSweep = sinceSweep + (elapsed or 0)
		if sinceSweep >= (IsInRaid and IsInRaid() and SWEEP_RAID or SWEEP) then
			sinceSweep = 0
			MarkAll()
		end
	else
		self:Hide()
	end
end)

events:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		plates[unit] = true
		Mark(unit)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		plates[unit], dirty[unit] = nil, nil
		Hide(unit)
	elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_TARGET" or event == "UNIT_FLAGS" then
		Mark(unit) -- (only nameplates count: the group's own targets and flags change all the time)
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
		MarkAll() -- (someone's threat changed: often in a fight, so the group isn't read again)
	else
		-- The group, its roles, pets, forms, combat starting or ending (forms are up by then).
		rosterDirty = true
		if event == "PLAYER_REGEN_DISABLED" then
			CheckSweep(true)
		elseif event == "PLAYER_REGEN_ENABLED" then
			CheckSweep(false)
		elseif event == "GROUP_ROSTER_UPDATE" then
			CheckSweep()
		end
		MarkAll()
	end
end)

local PLATE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_THREAT_LIST_UPDATE", "UNIT_TARGET",
	"UNIT_FLAGS", "UNIT_THREAT_SITUATION_UPDATE" }
-- The group, its roles, pets, forms, combat starting or ending: the roster is read again.
local ROSTER_EVENTS = { "GROUP_ROSTER_UPDATE", "UNIT_PET", "PLAYER_ROLES_ASSIGNED", "PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }

-- Called by Tweaks.lua when the switch changes (on the next frame, never in a callback).
function ns.ApplyAggro(want)
	on = want
	events:UnregisterAllEvents()
	if on then
		for _, list in ipairs({ PLATE_EVENTS, ROSTER_EVENTS }) do
			for _, event in ipairs(list) do
				pcall(events.RegisterEvent, events, event)
			end
		end
		for i = 1, 40 do -- (the nameplates already up)
			if Value(UnitExists, "nameplate" .. i) then
				plates["nameplate" .. i] = true
			end
		end
	else
		for unit in pairs(shownOn) do
			Hide(unit)
		end
		wipe(plates)
		wipe(dirty)
	end
	rosterDirty = true
	CheckSweep()
	MarkAll()
end

-- Examples on the enemy nameplates in sight for a few seconds; returns how many there are.
function ns.AggroPreview()
	previewUntil = GetTime() + PREVIEW_FOR
	MarkAll()
	C_Timer.After(PREVIEW_FOR + 0.1, MarkAll)
	local count = 0
	for unit in pairs(plates) do
		if Value(UnitCanAttack, "player", unit) then
			count = count + 1
		end
	end
	return count
end

-- Blizzard's role check (the group's leader or an assistant): everyone picks a role in Blizzard's
-- window. Returns a line for chat (English, like the other chat lines).
function ns.AggroRoleCheck()
	if not (IsInGroup and IsInGroup()) then
		return "you're not in a group."
	elseif not InitiateRolePoll then
		return "this game has no role check."
	end
	local ok, started = pcall(InitiateRolePoll)
	if ok and started then
		return "role check started: everyone picks tank, healer or damage in Blizzard's window."
	end
	return "only the group's leader or an assistant can start a role check."
end

---------------------------------------------------------------------------
-- For the fight stream's battle row (Beacon: StreamSense.lua, StreamNet.lua, StreamBattle.lua)
---------------------------------------------------------------------------

-- Whom a mob is on (a unit: a nameplate, "target"), read at the sensor's look, also with this tweak
-- off: nil when you're not in a group or nobody is known; else the holder's role ("TANK", "HEALER",
-- "DAMAGER", "NONE", "PET" or "OUTSIDER"), name (nil: hidden) and whether it's you.
function ns.AggroHolder(mob)
	if not (IsInGroup and IsInGroup()) then
		return nil
	end
	if rosterDirty then
		BuildRoster()
	end
	local holder = Holder(mob)
	if holder then
		return RoleOf(holder), holder.name, holder.you == true
	end
end

-- A tag's text and colour ({ r, g, b }, shared: don't change it), as on the nameplates.
ns.AggroTag = Tag

-- The first three letters of a name, whole UTF-8 letters (what a tag shows, and what goes to friends).
ns.AggroShort = Short

-- While the fight stream's sensor runs, the group's roster is read again when it changes, also with
-- this tweak off (a flag each, read at the next look).
local rosterWatch = CreateFrame("Frame")
rosterWatch:SetScript("OnEvent", function()
	rosterDirty = true
end)

function ns.AggroWatch(want)
	rosterWatch:UnregisterAllEvents()
	if want then
		for _, event in ipairs(ROSTER_EVENTS) do
			pcall(rosterWatch.RegisterEvent, rosterWatch, event)
		end
	end
	rosterDirty = true -- (the tweak off, nobody kept it fresh meanwhile)
end

-- For tests: the tag showing on a nameplate (nil: none).
function ns.GetAggroTag(unit)
	return shownOn[unit]
end
