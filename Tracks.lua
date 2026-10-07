-- The icon row. One slot per track: underneath, the "missing" picture (grey icon, red
-- frame); on top, Blizzard's aura container, which draws the live icon and its time while
-- the aura is up and nothing at all while it is not.
local ADDON, ns = ...

local ICON, GAP = ns.ICON, ns.GAP
local SLOT_KEY = "track"
local slots = {}

-- Time left: white, yellow under 5 seconds, red under 3. The client evaluates the curve.
local timeColor = C_CurveUtil.CreateColorCurve()
timeColor:SetType(Enum.LuaCurveType.Step)
timeColor:AddPoint(0, CreateColor(1, 0.25, 0.25, 1))
timeColor:AddPoint(3, CreateColor(1, 0.85, 0.2, 1))
timeColor:AddPoint(5, CreateColor(1, 1, 1, 1))

-- Time left as a bare number of seconds, rounded up; nothing from 100 seconds on (a long
-- buff needs no countdown).
local timeFormat
if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
	timeFormat = C_StringUtil.CreateNumericRuleFormatter()
	timeFormat:SetBreakpoints({
		{ threshold = 0, format = "%d", step = 1, rounding = Enum.NumericRuleFormatRounding.Up },
		{ threshold = 100, format = " " },
	})
end

-- Glow for the last seconds: the proc glow of the action bars (the one WeakAuras-style glow
-- addons use), running only while less than GLOW_SECONDS are left.
--
-- Addon code may not read the time left, and no script runs inside an aura button, so the
-- glow cannot be switched on or animated from Lua. A second, otherwise empty aura slot lies
-- over the icon. Its "time text" comes from a number formatter with one rule per 1/30 second:
-- each rule's text is one frame of Blizzard's proc glow flipbook as an inline picture, and
-- from GLOW_SECONDS up the text is blank. The client picks the rule from the time left, so
-- it plays the animation and starts it at the right moment by itself.
local GLOW_SECONDS = 3
local GLOW_SIZE = 46                   -- the glow reaches a little past the 30 px icon
local GLOW_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local GLOW_COLUMNS, GLOW_ROWS, GLOW_FRAMES = 5, 6, 30   -- as in ActionButtonSpellAlerts.xml

local glowFormat, glowBinding
do
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(GLOW_ATLAS)
	if info and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
		-- the atlas entry in pixels of its file
		local fileWidth = info.width / (info.rightTexCoord - info.leftTexCoord)
		local fileHeight = info.height / (info.bottomTexCoord - info.topTexCoord)
		local left, top = info.leftTexCoord * fileWidth, info.topTexCoord * fileHeight
		local cellWidth, cellHeight = info.width / GLOW_COLUMNS, info.height / GLOW_ROWS
		local file = info.file or info.filename
		local frames = {}
		for frame = 0, GLOW_FRAMES - 1 do
			local x = left + (frame % GLOW_COLUMNS) * cellWidth
			local y = top + math.floor(frame / GLOW_COLUMNS) * cellHeight
			frames[frame] = string.format("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t", tostring(file), GLOW_SIZE, GLOW_SIZE,
				fileWidth + 0.5, fileHeight + 0.5, x + 0.5, x + cellWidth + 0.5, y + 0.5, y + cellHeight + 0.5)
		end
		local rules = {}
		local steps = GLOW_SECONDS * GLOW_FRAMES
		for step = 0, steps - 1 do
			-- time runs down, the animation runs forward
			rules[#rules + 1] = { threshold = step / GLOW_FRAMES, format = frames[(steps - 1 - step) % GLOW_FRAMES] }
		end
		rules[#rules + 1] = { threshold = GLOW_SECONDS, format = " " }
		glowFormat = C_StringUtil.CreateNumericRuleFormatter()
		glowFormat:SetBreakpoints(rules)
		-- redrawn every frame of the animation
		glowBinding = C_DurationUtil.CreateDurationTextBinding()
		glowBinding:SetUpdateInterval(1 / GLOW_FRAMES)
	end
end

local function HasAuraContainer()
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo
		and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") ~= nil
end

------------------------------------------------------------------------------------------
-- Holder: sits above the player frame, can be dragged while unlocked.
------------------------------------------------------------------------------------------
function ns.PlaceHolder()
	local holder = ns.holder
	holder:ClearAllPoints()
	holder:SetScale(ns.db.scale)
	if PlayerFrame then
		holder:SetPoint("BOTTOMLEFT", PlayerFrame, "TOPLEFT", ns.db.x, ns.db.y)
	else
		holder:SetPoint("CENTER", UIParent, "CENTER", ns.db.x, ns.db.y)
	end
end

function ns.CreateHolder()
	local holder = CreateFrame("Frame", "DenoDotsFrame", UIParent)
	ns.holder = holder
	holder:SetSize(98, ICON + 14)   -- the pet bars start inside it and end just below
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	holder:RegisterForDrag("LeftButton")

	holder.handle = holder:CreateTexture(nil, "BACKGROUND")
	holder.handle:SetPoint("TOPLEFT", -4, 4)
	holder.handle:SetPoint("BOTTOMRIGHT", 4, -12)
	holder.handle:SetColorTexture(0.2, 0.6, 1, 0.35)
	holder.handle:Hide()
	holder.handleText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	holder.handleText:SetPoint("BOTTOM", holder, "TOP", 0, 6)
	holder.handleText:SetText("Deno Dots - drag to move")
	holder.handleText:Hide()

	holder:SetScript("OnDragStart", function(self)
		if not InCombatLockdown() then self:StartMoving() end
	end)
	holder:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- back to an offset from the player frame, in the holder's own scale
		local left, bottom = self:GetLeft(), self:GetBottom()
		if PlayerFrame and left and bottom then
			local ratio = PlayerFrame:GetEffectiveScale() / self:GetEffectiveScale()
			ns.db.x = math.floor(left - PlayerFrame:GetLeft() * ratio + 0.5)
			ns.db.y = math.floor(bottom - PlayerFrame:GetTop() * ratio + 0.5)
		end
		ns.PlaceHolder()
	end)
	ns.PlaceHolder()
end

function ns.UnlockHolder()
	if InCombatLockdown() then return end
	ns.unlocked = true
	ns.holder:EnableMouse(true)
	ns.holder.handle:Show()
	ns.holder.handleText:Show()
end

function ns.LockHolder()
	if not ns.unlocked then return end
	ns.unlocked = false
	ns.holder:StopMovingOrSizing()
	ns.holder:EnableMouse(false)
	ns.holder.handle:Hide()
	ns.holder.handleText:Hide()
end

------------------------------------------------------------------------------------------
-- Slots
------------------------------------------------------------------------------------------
local function FilterFor(unit)
	-- on the target only what you cast; on yourself any copy of the buff counts
	return unit == "player" and "HELPFUL" or "HARMFUL|PLAYER"
end

local function CreateSlot(index)
	local slot = CreateFrame("Frame", nil, ns.holder)
	slot:SetSize(ICON, ICON)

	local missing = CreateFrame("Frame", nil, slot)
	missing:SetAllPoints()
	slot.missing = missing
	local frame = missing:CreateTexture(nil, "BACKGROUND")
	frame:SetAllPoints()
	frame:SetColorTexture(0.75, 0, 0, 1)
	missing.icon = missing:CreateTexture(nil, "ARTWORK")
	missing.icon:SetPoint("TOPLEFT", 2, -2)
	missing.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	missing.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	missing.icon:SetDesaturated(true)
	missing.icon:SetVertexColor(0.5, 0.5, 0.5)
	return slot
end

-- The container is made once per slot, out of combat, and re-pointed afterwards.
local function EnsureContainer(slot, unit, ids)
	local filters = { includeSpellIDs = ids }
	if slot.container then
		for _, container in ipairs({ slot.container, slot.glow }) do
			container:SetUnit(unit)
			container:SetAuraSlotFilterString(SLOT_KEY, FilterFor(unit))
			container:SetAuraSlotCandidateFilters(SLOT_KEY, filters)
			container:SetAuraSlotEnabled(SLOT_KEY, true)
		end
		return
	end
	local container = CreateFrame("AuraContainer", nil, slot, "CustomAuraContainerTemplate")
	slot.container = container
	container:SetPoint("CENTER")
	container:SetSize(ICON, ICON)
	container:SetFrameLevel(slot:GetFrameLevel() + 5)
	container:SetUnit(unit)
	container:AddAuraSlot(SLOT_KEY, FilterFor(unit), {
		candidateFilters = filters,
		-- Every region is built and handed over here; the button is sealed afterwards.
		initializeFrame = function(button)
			button:SetSize(ICON, ICON)
			button:SetPoint("CENTER", container, "CENTER")
			local frame = button:CreateTexture(nil, "BACKGROUND")
			frame:SetAllPoints()
			frame:SetColorTexture(0, 0, 0, 1)
			local icon = button:CreateTexture(nil, "ARTWORK")
			icon:SetPoint("TOPLEFT", 2, -2)
			icon:SetPoint("BOTTOMRIGHT", -2, 2)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			button:SetIcon(icon)
			local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
			count:SetPoint("BOTTOMRIGHT", 2, -1)
			button:SetApplicationCount(count)
			local time = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
			time:SetPoint("CENTER", 0, 0)
			button:SetDurationText(time, {
				textFormatter = timeFormat,
				textColor = { curve = timeColor, property = Enum.DurationTextBindingProperty.RemainingDuration },
			})
		end,
	})
end

-- The glow slot: same aura, nothing drawn but the glow text.
local function EnsureGlow(slot, unit, ids)
	if slot.glow or not glowFormat then return end
	local glow = CreateFrame("AuraContainer", nil, slot, "CustomAuraContainerTemplate")
	slot.glow = glow
	glow:SetPoint("CENTER")
	glow:SetSize(ICON, ICON)
	glow:SetFrameLevel(slot:GetFrameLevel() + 10)
	glow:SetUnit(unit)
	glow:AddAuraSlot(SLOT_KEY, FilterFor(unit), {
		candidateFilters = { includeSpellIDs = ids },
		initializeFrame = function(button)
			button:SetSize(ICON, ICON)
			button:SetPoint("CENTER", glow, "CENTER")
			local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			text:SetPoint("CENTER", 0, 0)
			button:SetDurationText(text, { binding = glowBinding, textFormatter = glowFormat })
		end,
	})
end

-- Tracks that are switched on and, unless marked "always", known to this character.
function ns.VisibleTracks()
	local visible = {}
	for _, track in ipairs(ns.tracks) do
		if track.enabled ~= false and #visible < ns.MAX_TRACKS then
			local ids, icon = ns.Resolve(track)
			if next(ids) and (track.always or ns.IsKnown(ids)) then
				visible[#visible + 1] = { track = track, ids = ids, icon = icon }
			end
		end
	end
	return visible
end

function ns.BuildTracks()
	if not HasAuraContainer() then
		if not ns.warned then
			ns.warned = true
			ns.Print("this client has no aura container; the icons cannot be shown.")
		end
		return
	end
	local visible = ns.VisibleTracks()
	for index, entry in ipairs(visible) do
		local slot = slots[index] or CreateSlot(index)
		slots[index] = slot
		slot.track = entry.track
		slot:ClearAllPoints()
		slot:SetPoint("TOPLEFT", ns.holder, "TOPLEFT", (index - 1) * (ICON + GAP), 0)
		slot.missing.icon:SetTexture(entry.icon)
		EnsureGlow(slot, entry.track.unit, entry.ids)
		EnsureContainer(slot, entry.track.unit, entry.ids)
		slot:Show()
	end
	for index = #visible + 1, #slots do
		local slot = slots[index]
		slot.track = nil
		if slot.container then
			slot.container:SetAuraSlotEnabled(SLOT_KEY, false)
			if slot.glow then slot.glow:SetAuraSlotEnabled(SLOT_KEY, false) end
		end
		slot:Hide()
	end
	-- the pet bars are exactly as wide as the icons; with no icon at all, three icons wide
	ns.rowWidth = #visible > 0 and (#visible * (ICON + GAP) - GAP) or 98
	ns.holder:SetSize(ns.rowWidth, ICON + 14)
end

-- The grey "missing" picture of a target track shows only while there is something to put
-- the effect on. Whether a target exists and can be attacked is plain data, also in combat.
function ns.UpdateTarget()
	local hostile = ns.Plain(UnitExists("target"), false) and ns.Plain(UnitCanAttack("player", "target"), false)
		and not ns.Plain(UnitIsDead("target"), false)
	for _, slot in ipairs(slots) do
		local track = slot.track
		if track then
			local show = track.missing ~= false and (track.unit == "player" or hostile)
			slot.missing:SetShown(show and true or false)
		end
	end
end
