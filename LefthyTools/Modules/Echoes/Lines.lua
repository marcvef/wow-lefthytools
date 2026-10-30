local _, ns = ...
local LT = ns.LT
local E = ns.Echoes

-- The line encoder: everything Echoes records goes through here as one line of text (docs/echoes.md,
-- Line format). The capture writes with E.Line, E.Anchor, E.Point, E.Mode, E.Zone and E.Name; the
-- pages start a page with E.PageStart, write its header with E.Raw, go on from the last page with
-- E.Continue, hear of every line through E.OnLine and take what's written with E.Take. Nothing is
-- written while Echoes doesn't record (switched off, or the beta).
--
-- E.buffer: the lines written and not taken yet (strings without their "\n": one short string per
-- line, never a concatenation of the page). E.bytes and E.count: the bytes (each line's "\n" counted)
-- and lines written since the page started.
--
-- E.state: what the encoder keeps, a plain table (the pages may keep it with an open page and put it
-- back after a /reload; every function here reads E.state anew):
--   t          the time of the last line (the next line's dt counts from it); nil: none yet
--   anchored   this page has an anchor (path points are written only then)
--   continent, north, west   the last position written: north and west in whole yards, nil after an
--              anchor without a position (an instance), when points aren't written either
--   mode       the travel mode last written (an anchor's or a mode line's)
--   map, sub   the last zone line's uiMapID and subzone text
--   names      what this page has named: names["c:327"] = true

local issecret = LT.IsSecret
local huge = math.huge

E.buffer, E.bytes, E.count = {}, 0, 0
E.state = { anchored = false, names = {} }

local onLine, onLineNames = {}, {}

-- fn(line, kind) after each line is written: kind is its first character, nil for a path point or a
-- line written with E.Raw. Through LT.Guard. Hooks only note things: a page is closed on the tick,
-- never inside a hook.
function E.OnLine(fn)
	onLine[#onLine + 1] = fn
	onLineNames[#onLine] = "E.OnLine " .. #onLine
end

-- The time lines are written in: the realm's clock, the same for every friend (whole seconds);
-- the computer's if the realm's isn't there.
function E.Now()
	local now = LT.Value(GetServerTime)
	if type(now) ~= "number" then
		now = time()
	end
	return math.floor(now)
end

local function Append(line, kind)
	local buffer = E.buffer
	buffer[#buffer + 1] = line
	E.bytes, E.count = E.bytes + #line + 1, E.count + 1
	for i = 1, #onLine do
		LT.Guard(onLineNames[i], onLine[i], line, kind)
	end
end

---------------------------------------------------------------------------
-- Fields
---------------------------------------------------------------------------

-- A number as written: whole numbers as integers ("12", "-9046", never "-0" or "1e+10"), others with
-- at most two decimals ("3.25"); nothing for not-a-number and infinity.
local function Number(v)
	if v ~= v or v == huge or v == -huge then
		return ""
	elseif v == math.floor(v) then
		return v == 0 and "0" or ("%.0f"):format(v)
	end
	local text = ("%.2f"):format(v):gsub("%.?0+$", "")
	return text == "-0" and "0" or text
end

-- Escaped: %, ;, , and | and every byte below 0x20 as %XX (upper-case hex); the rest (UTF-8
-- letters) as they are. (%c can match more in some locales: those stay.)
local function Escape(c)
	local b = c:byte()
	if b >= 32 and c ~= "%" and c ~= ";" and c ~= "," and c ~= "|" then
		return c
	end
	return ("%%%02X"):format(b)
end

local function LinkText(text)
	return text:match("^%[(.*)%]$") or text
end

-- A string as written: WoW's markup gone (textures, atlases, colours; a link becomes its text,
-- without the brackets), then escaped.
local function Text(s)
	if s:find("|", 1, true) then
		s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
		s = s:gsub("|H.-|h(.-)|h", LinkText)
	end
	if s:find("[%%;,|%c]") then
		s = s:gsub("[%%;,|%c]", Escape)
	end
	return s
end

-- A field as written: numbers (Number), strings (Text), true 1 and false 0; nothing for nil, a
-- secret and anything else.
local function Field(v)
	if v == nil or issecret(v) then
		return ""
	end
	local kind = type(v)
	if kind == "number" then
		return Number(v)
	elseif kind == "string" then
		return Text(v)
	elseif kind == "boolean" then
		return v and "1" or "0"
	end
	return ""
end
E.Field = Field -- (for tests, and for whoever builds a line of its own)

-- Whole yards, or nil when not a readable number.
local function Yards(v)
	if type(v) ~= "number" or issecret(v) or v ~= v or v == huge or v == -huge then
		return nil
	end
	return math.floor(v + 0.5)
end

---------------------------------------------------------------------------
-- Lines
---------------------------------------------------------------------------

-- Seconds since the last line, now its time. If the clock went back (or no line has a time yet), a
-- clock line goes first ("!0;<now>") and the time counts from it: 0.
local function Clock()
	local state, now = E.state, E.Now()
	if not state.t or now < state.t then
		state.t = now
		Append("!0;" .. Number(now), "!")
	end
	local dt = now - state.t
	state.t = now
	return dt
end

local fields = {} -- (one table for every line's fields: none made per line)

-- Writes kind..dt..";"..fields: kind one character (a letter or @ = ! .), dt the seconds since the
-- last line; fields as Field writes them, the empty ones at the end left out. The line, or nil when
-- nothing was written (not recording).
function E.Line(kind, ...)
	if type(kind) ~= "string" or not kind:find("^[%a@=!%.]$") then
		error("E.Line: a line's kind is one letter or @ = ! ., got " .. tostring(kind), 2)
	end
	if not E.recording then
		return nil
	end
	local line = kind .. Number(Clock()) -- (first: a clock line it writes is heard before fields is filled)
	local n, last = select("#", ...), 0
	for i = 1, n do
		local field = Field((select(i, ...)))
		fields[i] = field
		if field ~= "" then
			last = i
		end
	end
	if last > 0 then
		line = line .. ";" .. table.concat(fields, ";", 1, last)
	end
	for i = 1, n do
		fields[i] = nil
	end
	Append(line, kind)
	return line
end

-- A line written as it is (the pages' header), counted like the others. Nothing while not recording.
function E.Raw(line)
	if E.recording then
		Append(line)
	end
end

-- An anchor ("@"): a new segment of the path, no line drawn from the point before. continent (the
-- instance map ID: 0 Eastern Kingdoms, 1 Kalimdor, or a dungeon's), north and west (world yards,
-- written whole; nil in an instance: no points until the next anchor with a position), the travel
-- mode, why (what caused it: docs/echoes.md) and the spell that did (hearthstone, teleport). The
-- next points count from here.
function E.Anchor(continent, north, west, mode, why, spell)
	if not E.recording then
		return nil
	end
	north, west = Yards(north), Yards(west)
	if not (north and west) then
		north, west = nil, nil
	end
	local state = E.state
	state.anchored = true
	state.continent = not issecret(continent) and continent or nil
	state.north, state.west = north, west
	if mode ~= nil and not issecret(mode) then
		state.mode = mode
	end
	return E.Line("@", continent, north, west, mode, why, spell)
end

-- A path point: "dt,dnorth,dwest" (whole yards, from the last position). Nothing before the page's
-- first anchor, after an anchor without a position, or for a position that isn't readable.
function E.Point(north, west)
	local state = E.state
	if not (E.recording and state.anchored and state.north) then
		return nil
	end
	north, west = Yards(north), Yards(west)
	if not (north and west) then
		return nil
	end
	local dt = Clock()
	local line = Number(dt) .. "," .. Number(north - state.north) .. "," .. Number(west - state.west)
	state.north, state.west = north, west
	Append(line)
	return line
end

-- The travel mode changed ("m").
function E.Mode(mode)
	if E.recording and not issecret(mode) then
		E.state.mode = mode
	end
	return E.Line("m", mode)
end

-- The zone ("z"): its uiMapID and the subzone's text (in the client's language).
function E.Zone(uiMapID, subzone)
	if E.recording then
		local state = E.state
		state.map = not issecret(uiMapID) and uiMapID or nil
		state.sub = not issecret(subzone) and subzone or nil
	end
	return E.Line("z", uiMapID, subzone)
end

-- A name ("="), once per page for each namespace and id (c creature, q quest, i item). true if it
-- was written now; nothing for a name that's empty or secret, or an id that isn't there.
function E.Name(namespace, id, text)
	if not E.recording or id == nil or issecret(id) or issecret(namespace) or Field(text) == "" then
		return false
	end
	local key = tostring(namespace) .. ":" .. tostring(id)
	local names = E.state.names
	if names[key] then
		return false
	end
	names[key] = true
	E.Line("=", namespace, id, text)
	return true
end

-- A new page names everything again.
function E.ResetNames()
	wipe(E.state.names)
end

---------------------------------------------------------------------------
-- Pages (Pages.lua's): starting one, going on from the last, taking the lines
---------------------------------------------------------------------------

-- A new page starts at t0 (its header's time; now if nil): the next line's dt counts from it, it
-- names everything again, and points wait for its first anchor (E.Continue, or the capture's).
-- E.bytes and E.count start again. Take the last page's lines (E.Take) first.
function E.PageStart(t0)
	local state = E.state
	state.t = t0 or E.Now()
	state.anchored = false
	E.ResetNames()
	E.bytes, E.count = 0, 0
end

-- The page goes on where the last one left off: an anchor at the last position known, why "c"
-- (continued), and the zone again. false (nothing written) when no position is known yet.
function E.Continue()
	local state = E.state
	if not E.recording or (state.continent == nil and state.north == nil) then
		return false
	end
	E.Anchor(state.continent, state.north, state.west, state.mode, "c")
	if state.map ~= nil or state.sub ~= nil then
		E.Zone(state.map, state.sub)
	end
	return true
end

-- The lines written since the last take, as text (each line ending in "\n"; "" when none), and
-- E.buffer emptied.
function E.Take()
	local buffer = E.buffer
	if #buffer == 0 then
		return ""
	end
	local text = table.concat(buffer, "\n") .. "\n"
	wipe(buffer)
	return text
end
