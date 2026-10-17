local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Beacon's settings page and /lefthy beacon. The settings' defaults are with the module (Beacon.lua);
-- each command is done by the file it belongs to (B.PingMe, B.DingCommand, ...): this only routes them.

function M:BuildOptions(o)
	o:Header(L["Sharing"])
	o:Checkbox("share", L["Share my position"],
		L["Battle.net friends who also use LefthyTools see you on their maps, and whether you're dead or in combat. Not available in dungeons and raids."])
	o:Checkbox("shareQuest", L["Share the quest I'm tracking"],
		L["Friends see the quest you're tracking, and your progress, when they hover your dot."])
	o:Slider("interval", L["Update interval"],
		L["How often your position is sent while you move. Standing still sends almost nothing."],
		1, 10, 1, LT.Options.Seconds)

	o:Header(L["Map"])
	o:Checkbox("showFriends", L["Show friends on the world map"],
		L["Dots in their class colour, a skull when they're dead and a red ring in combat. Hover for details. Friends in your group are already shown by the game."])
	o:Checkbox("showMinimap", L["Show friends on the minimap"],
		L["The same dots on the minimap. Friends in your group are already shown by the game."])
	o:Checkbox("minimapEdge", L["Keep far-away friends at the minimap edge"],
		L["Friends beyond the minimap's range stay faded at its edge, so you can see which way they are."])
	o:Checkbox("showGroup", L["Show friends in my group too"],
		L["Friends in your group keep their Beacon dot, with a blue ring, on top of the game's own group dot, and the tooltip says they're in your group. Off: only the game's dot."])

	o:Header(L["Alerts"])
	o:Checkbox("deathAlert", L["Tell me when a friend dies"],
		L["A chat line when a friend dies: where, and what they were fighting."])
	o:Checkbox("shareItems", L["Show items to friends"],
		L["Ctrl+right-click any item (bags, bank, character, loot, chat links) to show it to your friends: they see it at the top of the screen, with the whisper sound. Ctrl+Shift+right-click offers an item you can trade: they can say Need or Pass, and if several need it, it is rolled out. The item stays reserved for the winner until you hand it over."])
	o:Button(L["Hand-over reminders"], L["Clear"], function() B.HandoverCommand("clear") end,
		L["Items you offered and someone won stay reserved until you trade or mail them to the winner: a tooltip line, a bag border, a question at vendors. This forgets all of them, in case one is stuck. /lefthy beacon handover lists them."])
	o:Checkbox("lefthyChat", L["LTC (LefthyTools chat)"],
		L["A chat for your Battle.net friends with LefthyTools, like guild or party chat: /ltc <text> (or /l) sends a line, and theirs show in your chat window as [LTC]."])
	o:Checkbox("lefthyChatSound", L["Soft sound for LTC"],
		L["A quiet tick when a friend writes in LTC."])
	o:Checkbox("announcements", L["Announcements"],
		L["/la <text> (or /lefthy announce <text>) puts a line in the middle of your friends' screens, like a shared item, with the whisper sound. Theirs show on yours."])
	o:Checkbox("pings", L["Map pings"],
		L["Alt+click on the world map shows your friends a spot: a marker on their maps for a minute, with a sound. Their pings show up on your maps. /lefthy beacon ping pings where you stand."])

	if B.BuildDingOptions then
		B.BuildDingOptions(o)
	end

	o:Header(L["Error reports"])
	o:Checkbox("sendReports", L["Send my LefthyTools errors to friends who collect them"],
		L["When LefthyTools has an error, it goes to your Battle.net friends who collect error reports (each error once per session), so whoever looks after LefthyTools can fix it. /lefthy report <what happened> sends a report in your own words."])
	o:Checkbox("collectReports", L["Collect my friends' error reports"],
		L["Your friends' LefthyTools send you their errors and the reports they write (/lefthy report). /lefthy reports shows them, ready to copy."])
	o:Button(L["Friends' error reports"], L["Show"], function() B.ShowReports() end,
		L["The reports your friends sent you, newest first, ready to copy. /lefthy reports does the same."])

	o:Header(L["Fight stream"])
	o:Checkbox("streamShare", L["Friends can watch my fights"],
		L["Friends with LefthyTools can open a small live view of your fight: you in the middle, the mobs around you on the map, what you're casting. Only while someone watches is anything sent."])
	o:Checkbox("streamWatchedDot", L["Show when friends watch me"],
		L["A tiny red dot with the number of watchers right of the calendar button at the minimap. Hover it to see who."])
	o:Checkbox("streamFlights", L["Friends' fights on flights"],
		L["A cinematic flight (Misc Tweaks) opens the stream of one friend who is fighting (or anyone, if nobody is). The top bar has a button for each friend to open or close theirs; they close when you land."])
	o:Checkbox("streamMapClick", L["Click a friend on the world map to watch"],
		L["Clicking a friend's dot on the world map opens their stream; clicking it again closes it. /lefthy stream watch <name> does the same."])
	o:Checkbox("streamButton", L["Minimap button for fight streams"],
		L["A spyglass on the edge of the minimap: click it for the friends who share their fights, and pick one to watch (or close their stream). A red dot on it while you watch someone. Drag it to move it."])
	o:Button(L["Your own stream"], L["Show"], function() B.StreamCommand("me") end,
		L["What friends see when they watch you, live. /lefthy stream me does the same."])
	o:Button(L["Stream window"], L["Preview"], function() B.StreamCommand("preview") end,
		L["The window with a made-up fight. Drag it to move it, the corner at the bottom right to resize it. /lefthy stream preview does the same."])
end

function M:OnSlashCommand(msg)
	local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" then
		LT:OpenSettings(self)
	elseif cmd == "status" or cmd == "friends" then
		B.PrintStatus()
	elseif cmd == "interval" then
		local n = tonumber(arg)
		if n then
			LT:SetModuleSetting(self, "interval", math.max(1, math.min(10, math.floor(n + 0.5))))
		end
		self:Print("update interval: " .. LT.Options.Seconds(self.db.interval) .. ".")
	elseif cmd == "ping" and arg == "clear" and B.ClearMyPing then
		B.ClearMyPing()
	elseif cmd == "ping" and B.PingMe then
		B.PingMe()
	elseif cmd == "sound" and B.SoundCommand then
		B.SoundCommand(arg)
	elseif cmd == "ding" and B.DingCommand then
		B.DingCommand(arg)
	elseif cmd == "handover" and B.HandoverCommand then
		B.HandoverCommand(arg)
	elseif (cmd == "show" or cmd == "offer") and B.ShareCommand then
		B.ShareCommand(cmd, arg)
	elseif cmd == "stream" and B.StreamCommand then
		B.StreamCommand(arg)
	else
		self:Print("/lefthy beacon - open settings")
		self:Print("/lefthy beacon status - friends with LefthyTools, their last update and the message traffic")
		self:Print("/lefthy beacon interval <1-10> - seconds between position updates while moving")
		self:Print("/lefthy beacon ping - show your friends where you stand (or Alt+click the world map)")
		self:Print("/lefthy beacon ping clear - take your ping back (or Alt+click it on the world map)")
		self:Print("/lefthy beacon ding <text> | reset | test - your level-up message; {name} and {level} are filled in")
		self:Print("/lefthy beacon sound [<number>] - list the level-up sounds, or pick one and hear it")
		self:Print("/lefthy beacon show <item> - show an item to friends, like Ctrl+right-click (Shift-click it into the chat box)")
		self:Print("/lefthy beacon offer <item> - offer it for Need or Pass, like Ctrl+Shift+right-click")
		self:Print("/lefthy beacon handover [clear] - items you offered that winners still have to get")
		self:Print("/ltc <text> (or /l) - LTC, LefthyTools chat: a line for every friend with LefthyTools, like guild chat")
		self:Print("/la <text> (or /lefthy announce <text>) - a line in the middle of your friends' screens")
	end
end
