local _, ns = ...
local Bt = ns.Bestiary
local M = Bt.module
local NONE, Value, issecret = Bt.NONE, Bt.Value, Bt.issecret

-- The wish list: items you pin (Alt-click on a drop, /bestiary wish). Mobs that drop one show it with
-- a star. LefthyToolsBestiaryDB.wishes (only once there's one): { [item ID] = { pinned (time()),
-- kills (of mobs that drop it, since), expected (their chances added up: how many it should have
-- dropped in them), name, quality } }. A kill counts for a wish when the classic database or your own
-- record says that kind drops it (Bt.WishKill, from Recording.lua); when it drops (your loot of a
-- counted kill), a quiet chat line says after how many kills and how many you'd have expected (kills
-- / expected: 1 / its chance for one kind of mob), no sound, no popup, and it comes off the list.

function Bt.Wishes()
	local data = Bt.Data()
	return data and data.wishes or NONE
end

function Bt.Wish(id)
	local data = Bt.Data()
	return data and data.wishes and data.wishes[id]
end

-- An item's link for chat (as plain as it gets when the client doesn't know it yet).
local function LinkOf(id, name)
	if C_Item and C_Item.GetItemInfo then
		local ok, _, link = pcall(C_Item.GetItemInfo, ("item:%d"):format(id))
		if ok and type(link) == "string" and not issecret(link) then
			return link
		end
	end
	return "[" .. (name or Bt.ItemNameOf(id) or ("item " .. id)) .. "]"
end

-- Pins an item, or unpins it when it's pinned (drop: a Bt.Drops entry, for its name and quality);
-- returns whether it's on the list now.
function Bt.ToggleWish(id, drop)
	local data = Bt.Data()
	if not (data and type(id) == "number") then
		return false
	end
	local wish = data.wishes and data.wishes[id]
	if wish then
		data.wishes[id] = nil
		if not next(data.wishes) then
			data.wishes = nil
		end
		M:Print(("%s is off your wish list."):format(LinkOf(id, wish[4])))
	else
		local name = drop and drop.name or Bt.ItemNameOf(id)
		local quality = drop and drop.quality or C_Item and Value(C_Item.GetItemQualityByID, id)
		data.wishes = data.wishes or {}
		data.wishes[id] = { time(), 0, 0, name, type(quality) == "number" and quality or nil }
		M:Print(("%s is on your wish list: mobs that drop it show it with a star, and a line here says when it drops.")
			:format(LinkOf(id, name)))
	end
	if Bt.Redraw then
		Bt.Redraw() -- (its star everywhere)
	end
	return not wish
end

-- Where a wished item comes from: your own drops (your chance and kills: out) and the classic
-- database's (its chance), each kind of mob once, the likeliest first: { { creature, name, chance,
-- out }, ... }; and how many more the database lists that the Bestiary can't name (it has no names:
-- only mobs you've killed or seen are known).
function Bt.WishSources(id)
	local list, had, unnamed = {}, {}, 0
	for _, source in ipairs(Bt.Sources(id) or NONE) do
		if not source.skin then
			had[source.creature] = true
			list[#list + 1] = { creature = source.creature, name = source.mob.name or ("#" .. source.creature), chance = source.chance,
				out = source.out }
		end
	end
	for _, source in ipairs(Bt.KnownSources(id)) do
		if not had[source.creature] then
			local name = Bt.NameOf(source.creature)
			if name then
				list[#list + 1] = { creature = source.creature, name = name, chance = source.chance }
			else
				unnamed = unnamed + 1
			end
		end
	end
	table.sort(list, function(a, b)
		if a.chance ~= b.chance then
			return a.chance > b.chance
		end
		return a.creature < b.creature
	end)
	return list, unnamed
end

-- A kill counted (counted: before, when the game said its corpse was empty): it counts for each wish
-- its kind drops; got (item ID -> link): what it dropped. A wish that dropped comes off the list;
-- returns whether one did.
function Bt.WishKill(creature, mob, got, counted)
	local data = Bt.Data()
	local wishes = data and data.wishes
	if not wishes then
		return false
	end
	local fulfilled = false
	for id, wish in pairs(wishes) do
		if not counted then
			local chance = Bt.ChanceOf(creature, mob, id)
			if chance then
				wish[2], wish[3] = (wish[2] or 0) + 1, (wish[3] or 0) + chance
			end
		end
		if got and got[id] then
			local kills = math.max(1, wish[2] or 0)
			local expected = (wish[3] or 0) > 0 and math.max(1, math.floor(kills / wish[3] + 0.5)) or nil
			M:Print(("%s after %s%s; off your wish list."):format(got[id], kills == 1 and "1 kill" or (kills .. " kills"),
				expected and (" (about %d expected)"):format(expected) or ""))
			wishes[id], fulfilled = nil, true
		end
	end
	if not next(wishes) then
		data.wishes = nil
	end
	return fulfilled
end

-- /bestiary wishes: the list in chat (English, like the other chat lines).
function Bt.PrintWishes()
	local wishes, ids = Bt.Wishes(), {}
	for id in pairs(wishes) do
		ids[#ids + 1] = id
	end
	if #ids == 0 then
		M:Print("your wish list is empty: Alt-click a drop in the window or the ledger, or /bestiary wish <item link or ID>.")
		return
	end
	table.sort(ids, function(a, b)
		if wishes[a][1] ~= wishes[b][1] then
			return wishes[a][1] < wishes[b][1]
		end
		return a < b
	end)
	M:Print(("your wish list (%d):"):format(#ids))
	for _, id in ipairs(ids) do
		local wish = wishes[id]
		local best = Bt.WishSources(id)[1]
		print(("  %s: %d kills since you pinned it%s"):format(LinkOf(id, wish[4]), wish[2] or 0,
			best and (", likeliest from %s (%s)"):format(best.name, Bt.Percent and Bt.Percent(best.chance, true) or "?") or ""))
	end
end
