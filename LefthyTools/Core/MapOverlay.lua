local _, ns = ...
local LT = ns.LT

-- Drawing on Blizzard's world map without touching it (LT.MapOverlay): Beacon's friends and pings,
-- the quest icons and areas of Misc Tweaks. docs/forever-platform.md, "The world map", has why.
--
-- The world map is Lua (Blizzard_MapCanvas, Blizzard_WorldMap), and the controller UI reads it from
-- Blizzard's code: its map cursor hovers the pins it finds (MapCanvasMixin:UpdateGamepadCursor runs
-- their OnMouseEnter), the map's OnHide clears the controller's bindings, SmartNavigation hooks
-- CreateFrame and rebuilds the map's buttons for a frame made on it. Anything an addon wrote into
-- the map's tables (a data provider, a pin from AcquirePin, a pin pool, the scale MarkCanvasDirty
-- keeps) runs there as the addon's: once tainted, every later SetPreferredGamepadInteractTarget of
-- the action bars and the B button's close chain are blocked. So nothing here writes into the map:
--
-- - no data provider, no AcquirePin, no hook on a map method; the map is only read: GetMapID,
--   GetCanvas, GetCanvasScale, HasZoomLevels, GetCanvasZoomPercent, GetGlobalPinScale,
--   GetPinFrameLevelsManager():GetValidFrameLevel, GetNormalizedCursorPosition,
--   IsCanvasMouseFocus, and the canvas's size and place;
-- - frames are made with no parent and then put on the canvas (SetParent isn't hooked), so the
--   map's buttons aren't rebuilt from our code; the canvas clips them and they show and hide with
--   the map;
-- - none of them is a button to the controller's navigation: no Button, no OnMouseDown or OnMouseUp
--   script. A click is read from GLOBAL_MOUSE_DOWN / GLOBAL_MOUSE_UP (Overlay.OnMouse), registered
--   only while the map is open.
--
-- One watcher frame on the canvas runs only while the map is shown (the client doesn't update a
-- hidden frame's children): each frame it compares the map, the canvas size, its scale and zoom and
-- the pin scale, and tells the layers what changed (Overlay.Watch). Every 0.05 s it also looks for
-- the controller's map cursor (SoftCursor): the map's own cursor no longer sees our frames, so the
-- frame nearest it shows its tooltip, on a tooltip of our own (GameTooltip from here would taint
-- the controller UI).
--
--   Overlay.Watch(name, fn)          fn(what): "show" (the map opened), "map" (another map),
--                                    "size" (the canvas resized), "scale" (zoom, scale or pin
--                                    scale), "hide" (the map closed)
--   Overlay.OnMouse(name, fn)        fn("down" | "up", button) for every click while the map is open
--   Overlay.MouseOnMap()             whether the mouse is on the map's canvas (or on one of our
--                                    frames there, which a click passes through)
--   Overlay.Frame(kind[, type, template])  a frame of ours on the canvas, hidden; nil before the map loads
--   Overlay.Place(f, x, y[, from, to])     centre f on (x, y) of the shown map (0-1), scaled like a map
--                                    pin with SetScalingLimits(1, from, to); hidden outside the map
--   Overlay.PlaceRect(f, left, right, top, bottom)  f over that part of the map, in canvas units
--   Overlay.Level(levelType[, index]) the frame level the map gives its pins of that level type
--   Overlay.SetHover(f, enter[, leave])  the controller cursor's hover: enter(f, tooltip), leave(f)
--   Overlay.TooltipOf(f)             the tooltip showing f now (GameTooltip or ours), or nil
--   Overlay.view                     shown, mapID, width, height, scale, zoom, pinScale

local Overlay = {}
LT.MapOverlay = Overlay

local HOVER_REACH = 12   -- UI units from the controller's map cursor, as for Blizzard's own pins
local HOVER_GAP = 0.05   -- seconds between looks for the frame nearest that cursor

local map, canvas, watcher
local view = { shown = false }
Overlay.view = view
local listeners, mouseListeners = {}, {}
local kindOf = {}   -- our frames on the canvas -> their kind
local madeOf = {}   -- kind -> { frame, ... } in the order made
local hoverOf, leaveOf, hoverList = {}, {}, {}
local tooltip, hovered, hoverWait = nil, nil, 0

local function Tell(list, ...)
	for i = 1, #list do
		LT.Guard(list[i][1], list[i][2], ...)
	end
end

-- What the map shows now; every call a read.
local function Read()
	local id = map:GetMapID()
	local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
	local s = map.GetCanvasScale and map:GetCanvasScale() or 1
	if not s or s <= 0 then
		s = 1
	end
	local z = 0
	if map.GetCanvasZoomPercent and (not map.HasZoomLevels or map:HasZoomLevels()) then
		z = map:GetCanvasZoomPercent() or 0
		if z ~= z or z < 0 then -- (NaN: a map without zoom levels)
			z = 0
		elseif z > 1 then
			z = 1
		end
	end
	local ps = map.GetGlobalPinScale and map:GetGlobalPinScale() or 1
	return id, w, h, s, z, ps
end

---------------------------------------------------------------------------
-- The controller's map cursor
---------------------------------------------------------------------------

local function Unhover()
	local f = hovered
	if not f then
		return
	end
	hovered = nil
	if tooltip then
		tooltip:Hide()
	end
	if leaveOf[f] then
		LT.Guard("MapOverlay.Leave", leaveOf[f], f)
	end
end

-- Our frame nearest the cursor within reach, in screen pixels: the cursor's centre, the frames'
-- from their map position and the canvas (no layout read per frame).
local function Nearest()
	local cursor = SoftCursor
	if not (cursor and cursor:IsShown()) or GetCVarBool("GamepadDisableTooltips") then -- (the right stick turns tooltips off)
		return nil
	end
	local x, y = cursor:GetCenter()
	local left, top = canvas:GetLeft(), canvas:GetTop()
	if not (x and y and left and top and view.width) then
		return nil
	end
	local cs, es = cursor:GetEffectiveScale(), canvas:GetEffectiveScale()
	x, y = x * cs, y * cs
	local reach = HOVER_REACH * UIParent:GetEffectiveScale()
	local best, bestD = nil, reach * reach
	for i = 1, #hoverList do
		local f = hoverList[i]
		if f.mapX and f:IsShown() then
			local dx = (left + view.width * f.mapX) * es - x
			local dy = (top - view.height * f.mapY) * es - y
			local d = dx * dx + dy * dy
			if d <= bestD then
				best, bestD = f, d
			end
		end
	end
	return best
end

local function Hover()
	local f = Nearest()
	-- The same frame with its tooltip still up: nothing to do. (One released and drawn again there,
	-- its tooltip hidden meanwhile, gets it anew.)
	if f == hovered and (not f or (tooltip and tooltip:IsShown())) then
		return
	end
	Unhover()
	if f then
		hovered = f
		if not tooltip then
			tooltip = CreateFrame("GameTooltip", "LefthyToolsMapTooltip", UIParent, "GameTooltipTemplate")
			tooltip:SetFrameStrata("TOOLTIP")
		end
		LT.Guard("MapOverlay.Hover", hoverOf[f], f, tooltip)
	end
end

---------------------------------------------------------------------------
-- The watcher (only while the map is shown) and the mouse
---------------------------------------------------------------------------

local mouse = CreateFrame("Frame")
mouse:SetScript("OnEvent", function(_, event, button)
	Tell(mouseListeners, event == "GLOBAL_MOUSE_DOWN" and "down" or "up", button)
end)

-- Every frame while the map is shown (through LT.Guard: one that fails rests instead of failing
-- every frame).
local function Update(elapsed)
	local id, w, h, s, z, ps = Read()
	local what
	if not view.shown then
		what = "show"
	elseif id ~= view.mapID then
		what = "map"
	elseif w ~= view.width or h ~= view.height then
		what = "size"
	elseif s ~= view.scale or z ~= view.zoom or ps ~= view.pinScale then
		what = "scale"
	end
	view.mapID, view.width, view.height, view.scale, view.zoom, view.pinScale = id, w, h, s, z, ps
	if what == "show" then
		view.shown = true
		mouse:RegisterEvent("GLOBAL_MOUSE_DOWN")
		mouse:RegisterEvent("GLOBAL_MOUSE_UP")
	end
	if what then
		Tell(listeners, what)
	end
	hoverWait = hoverWait - (elapsed or 0)
	if hoverWait <= 0 then
		hoverWait = HOVER_GAP
		Hover()
	end
end

local function OnHide()
	if not view.shown then
		return
	end
	view.shown = false
	mouse:UnregisterAllEvents()
	Unhover()
	Tell(listeners, "hide")
end

local function Install()
	if watcher or not (WorldMapFrame and WorldMapFrame.GetCanvas) then
		return watcher ~= nil
	end
	local c = WorldMapFrame:GetCanvas()
	if not c then
		return false
	end
	map, canvas = WorldMapFrame, c
	watcher = CreateFrame("Frame")
	watcher:SetParent(canvas)
	watcher:SetScript("OnUpdate", function(_, elapsed)
		LT.Guard("MapOverlay", Update, elapsed)
	end)
	watcher:SetScript("OnHide", OnHide)
	return true
end

-- The world map may load after us.
local loader = CreateFrame("Frame")
loader:SetScript("OnEvent", function(self, _, name)
	if name == "Blizzard_WorldMap" then
		self:UnregisterAllEvents()
		C_Timer.After(0, Install)
	end
end)
if not Install() then
	loader:RegisterEvent("ADDON_LOADED")
end

---------------------------------------------------------------------------
-- For the layers
---------------------------------------------------------------------------

function Overlay.Watch(name, fn)
	listeners[#listeners + 1] = { name, fn }
end

function Overlay.OnMouse(name, fn)
	mouseListeners[#mouseListeners + 1] = { name, fn }
end

function Overlay.Canvas()
	return canvas
end

function Overlay.MouseOnMap()
	if not (view.shown and map:IsShown()) then
		return false
	end
	if map.IsCanvasMouseFocus and map:IsCanvasMouseFocus() then
		return true
	end
	local focus = GetMouseFoci and GetMouseFoci()[1]
	if not focus or (focus.IsForbidden and focus:IsForbidden()) then
		return false
	end
	if kindOf[focus] then
		return true -- (ours take no clicks, or are clicked through OnMouse)
	end
	-- A Blizzard pin that takes no clicks (a group member's dot): the click goes through to the map.
	return focus.owningMap == map and focus.IsMouseClickEnabled and not focus:IsMouseClickEnabled() or false
end

function Overlay.CursorPosition()
	return map:GetNormalizedCursorPosition()
end

function Overlay.Frame(kind, frameType, template)
	if not canvas then
		return nil
	end
	local f = CreateFrame(frameType or "Frame", nil, nil, template)
	f:SetParent(canvas)
	f:Hide()
	kindOf[f] = kind
	madeOf[kind] = madeOf[kind] or {}
	table.insert(madeOf[kind], f)
	return f
end

-- The scale Blizzard gives a map pin with SetScalingLimits(1, from, to) (MapCanvasPinMixin:
-- ApplyCurrentScale): from zoomed out, to zoomed in, the same size on screen at any canvas scale.
function Overlay.PinScale(from, to)
	local zoom = view.zoom or 0
	return (from + (to - from) * zoom) / (view.scale or 1) * (view.pinScale or 1)
end

function Overlay.Place(f, x, y, from, to)
	if not (view.width and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
		f.mapX, f.mapY = nil, nil
		f:Hide()
		return false
	end
	local s = from and Overlay.PinScale(from, to or from) or 1
	f.mapX, f.mapY = x, y
	f:SetScale(s)
	f:ClearAllPoints()
	f:SetPoint("CENTER", canvas, "TOPLEFT", view.width * x / s, -view.height * y / s)
	f:Show()
	return true
end

function Overlay.PlaceRect(f, left, right, top, bottom)
	if not view.width then
		f:Hide()
		return false
	end
	f.mapX, f.mapY = (left + right) / 2, (top + bottom) / 2
	f:SetScale(1)
	f:SetSize(view.width * (right - left), view.height * (bottom - top))
	f:ClearAllPoints()
	f:SetPoint("CENTER", canvas, "TOPLEFT", view.width * f.mapX, -view.height * f.mapY)
	f:Show()
	return true
end

function Overlay.Level(levelType, index)
	local levels = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
	local level = levels and levels.GetValidFrameLevel and levels:GetValidFrameLevel(levelType, index)
	return level or (canvas and canvas:GetFrameLevel() + 1) or 1
end

function Overlay.SetHover(f, enter, leave)
	if not hoverOf[f] then
		hoverList[#hoverList + 1] = f
	end
	hoverOf[f], leaveOf[f] = enter, leave
end

function Overlay.TooltipOf(f)
	if GameTooltip:IsOwned(f) then
		return GameTooltip
	end
	if hovered == f and tooltip and tooltip:IsShown() then
		return tooltip
	end
end

-- Our frames of a kind shown on the map now (all: every one made), in the order made (tests).
function Overlay.Frames(kind, all)
	local list = {}
	for _, f in ipairs(madeOf[kind] or {}) do
		if all or f:IsShown() then
			list[#list + 1] = f
		end
	end
	return list
end
