-- The icon row. One slot per track. An aura slot has, underneath, the "missing" picture
-- (grey icon, red frame) and on top Blizzard's aura container, which draws the live icon
-- and its time while the aura is up and nothing at all while it is not. A reminder shows
-- only the grey picture, a cooldown slot is an ordinary frame of our own.
local ADDON, ns = ...

local ICON, GAP = ns.ICON, ns.GAP
local SLOT_KEY = "track"
local GROUP_KEY = "gate"
local slots = {}

-- Time left: white, then yellow, then red for the last seconds (the same seconds the glow
-- runs, see ns.SetGlowSeconds). The client evaluates the curve.
local timeColor = C_CurveUtil.CreateColorCurve()
timeColor:SetType(Enum.LuaCurveType.Step)

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
-- addons use), running only while less than the chosen number of seconds are left.
--
-- Addon code may not read the time left, and no script runs inside an aura button, so the
-- glow cannot be switched on or animated from Lua. A second, otherwise empty aura slot lies
-- over the icon. Its "time text" comes from a number formatter with one rule per 1/30 second:
-- each rule's text is one frame of Blizzard's proc glow flipbook as an inline picture, and
-- from the chosen number of seconds up the text is blank. The client picks the rule from
-- the time left, so it plays the animation and starts it at the right moment by itself.
ns.GLOW_MIN, ns.GLOW_MAX = 1, 10
local GLOW_SIZE = 46                   -- the glow reaches a little past the 30 px icon
local GLOW_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local GLOW_COLUMNS, GLOW_ROWS, GLOW_FRAMES = 5, 6, 30   -- as in ActionButtonSpellAlerts.xml

local glowFormat, glowBinding, glowFrames
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
		glowFrames = frames
		glowFormat = C_StringUtil.CreateNumericRuleFormatter()
		-- redrawn every frame of the animation
		glowBinding = C_DurationUtil.CreateDurationTextBinding()
		glowBinding:SetUpdateInterval(1 / GLOW_FRAMES)
	end
end

-- How many seconds before the end the glow starts and the number turns red. The icons keep
-- the same formatter and curve, so a change shows at once.
function ns.SetGlowSeconds(seconds)
	seconds = math.max(ns.GLOW_MIN, math.min(ns.GLOW_MAX, math.floor(tonumber(seconds) or 3)))
	timeColor:ClearPoints()
	timeColor:AddPoint(0, CreateColor(1, 0.25, 0.25, 1))
	timeColor:AddPoint(seconds, CreateColor(1, 0.85, 0.2, 1))
	timeColor:AddPoint(seconds + 2, CreateColor(1, 1, 1, 1))
	if glowFormat then
		local rules = {}
		local steps = seconds * GLOW_FRAMES
		for step = 0, steps - 1 do
			-- time runs down, the animation runs forward
			rules[#rules + 1] = { threshold = step / GLOW_FRAMES, format = glowFrames[(steps - 1 - step) % GLOW_FRAMES] }
		end
		rules[#rules + 1] = { threshold = seconds, format = " " }
		glowFormat:SetBreakpoints(rules)
	end
	return seconds
end
ns.SetGlowSeconds(3)

-- 1.5.0 (his ask: "better glows"): the same proc glow as a real, looping flipbook texture
-- for the places where no secret decides when it shows. A reminder's grey picture only
-- exists while the buff is missing, so a glow next to it needs no test at all.
local GLOW_PAD = (GLOW_SIZE - ICON) / 2
local function LoopGlow(parent, anchor, red)
	local glow = parent:CreateTexture(nil, "OVERLAY")
	glow:SetAtlas(GLOW_ATLAS)
	glow:SetSize(GLOW_SIZE, GLOW_SIZE)
	glow:SetPoint("CENTER", anchor, "CENTER")
	if red then
		glow:SetDesaturated(true)
		glow:SetVertexColor(1, 0.22, 0.18)
	end
	local loop = parent:CreateAnimationGroup()
	loop:SetLooping("REPEAT")
	local flip = loop:CreateAnimation("FlipBook")
	flip:SetTarget(glow)
	flip:SetFlipBookRows(GLOW_ROWS)
	flip:SetFlipBookColumns(GLOW_COLUMNS)
	flip:SetFlipBookFrames(GLOW_FRAMES)
	flip:SetFlipBookFrameWidth(0)
	flip:SetFlipBookFrameHeight(0)
	flip:SetDuration(1)
	loop:Play()
	glow.loop = loop
	return glow
end

local function HasAuraContainer()
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo
		and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") ~= nil
end

------------------------------------------------------------------------------------------
-- Holder: sits above the player frame, can be dragged while unlocked.
------------------------------------------------------------------------------------------
-- Is there room for the row above the player frame? In the game's default layout the
-- player frame sits in the top corner of the screen and there is not: the screen edge would
-- push the row down over the health bar.
local function RoomAbove()
	local top, screenTop = PlayerFrame:GetTop(), UIParent:GetTop()
	if not top or not screenTop then return true end
	local screen = UIParent:GetEffectiveScale()
	local rowTop = top * PlayerFrame:GetEffectiveScale() + (ns.db.y + ICON + 16) * ns.db.scale * screen
	return rowTop <= screenTop * screen
end

local BELOW_GAP = -4      -- under the player frame and the pet frame

function ns.PlaceHolder()
	local holder = ns.holder
	holder:ClearAllPoints()
	holder:SetScale(ns.db.scale)
	local untouched = ns.db.x == ns.defaults.x and ns.db.y == ns.defaults.y
	if PlayerFrame and untouched and not RoomAbove() then
		-- never moved by the player and no room above: under the frame instead
		holder:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", ns.db.x, BELOW_GAP)
	elseif PlayerFrame then
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

-- While the row is being dragged the cast buttons are out of the way. They are secure
-- buttons, so they are only shown and hidden out of combat.
local function ShowCastButtons(shown)
	if InCombatLockdown() then return end
	for _, slot in ipairs(slots) do
		if slot.cast then slot.cast:SetShown(shown and slot.track ~= nil and slot.cast.spellName ~= nil) end
	end
end

function ns.UnlockHolder()
	if InCombatLockdown() then return end
	ns.unlocked = true
	ShowCastButtons(false)
	ns.holder:EnableMouse(true)
	ns.holder.handle:Show()
	ns.holder.handleText:Show()
	ns.LayoutRow()
end

function ns.LockHolder()
	if not ns.unlocked then return end
	ns.unlocked = false
	ns.holder:StopMovingOrSizing()
	ns.holder:EnableMouse(false)
	ns.holder.handle:Hide()
	ns.holder.handleText:Hide()
	ShowCastButtons(ns.db.clickCast)
	ns.LayoutRow()
end

------------------------------------------------------------------------------------------
-- Slot parts
------------------------------------------------------------------------------------------
local function GreyPicture(parent, anchor)
	local frame = parent:CreateTexture(nil, "BACKGROUND")
	frame:SetAllPoints(anchor)
	frame:SetColorTexture(0.75, 0, 0, 1)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", anchor, "TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetDesaturated(true)
	icon:SetVertexColor(0.5, 0.5, 0.5)
	icon.frame = frame
	return icon
end

local function CreateSlot()
	local slot = CreateFrame("Frame", nil, ns.holder)
	slot:SetSize(ICON, ICON)
	slot.containers = {}      -- "timer" and "plain": the time text is fixed when a button is built
	slot.missing = CreateFrame("Frame", nil, slot)
	slot.missing:SetAllPoints()
	slot.missing.icon = GreyPicture(slot.missing, slot.missing)
	return slot
end

-- The live icon. A container is made once per slot and variant, out of combat, and
-- re-pointed afterwards.
local function EnsureAura(slot, kind, ids, showTimer)
	local key = showTimer and "timer" or "plain"
	local filters = { includeSpellIDs = ids }
	for other, container in pairs(slot.containers) do
		if other ~= key then container:SetAuraSlotEnabled(SLOT_KEY, false) end
	end
	local container = slot.containers[key]
	if container then
		container:SetUnit(kind.unit)
		container:SetAuraSlotFilterString(SLOT_KEY, kind.filter)
		container:SetAuraSlotCandidateFilters(SLOT_KEY, filters)
		container:SetAuraSlotEnabled(SLOT_KEY, true)
		return
	end
	container = CreateFrame("AuraContainer", nil, slot, "CustomAuraContainerTemplate")
	slot.containers[key] = container
	container:SetPoint("CENTER")
	container:SetSize(ICON, ICON)
	container:SetFrameLevel(slot:GetFrameLevel() + 5)
	container:SetUnit(kind.unit)
	container:AddAuraSlot(SLOT_KEY, kind.filter, {
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
			if showTimer then
				local time = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
				time:SetPoint("CENTER", 0, 0)
				button:SetDurationText(time, {
					textFormatter = timeFormat,
					textColor = { curve = timeColor, property = Enum.DurationTextBindingProperty.RemainingDuration },
				})
			end
		end,
	})
end

-- The glow slot: same aura, nothing drawn but the glow text.
local function EnsureGlow(slot, kind, ids, enabled)
	if not enabled or not glowFormat then
		if slot.glow then slot.glow:SetAuraSlotEnabled(SLOT_KEY, false) end
		return
	end
	local filters = { includeSpellIDs = ids }
	if slot.glow then
		slot.glow:SetUnit(kind.unit)
		slot.glow:SetAuraSlotFilterString(SLOT_KEY, kind.filter)
		slot.glow:SetAuraSlotCandidateFilters(SLOT_KEY, filters)
		slot.glow:SetAuraSlotEnabled(SLOT_KEY, true)
		return
	end
	local glow = CreateFrame("AuraContainer", nil, slot, "CustomAuraContainerTemplate")
	slot.glow = glow
	glow:SetPoint("CENTER")
	glow:SetSize(ICON, ICON)
	glow:SetFrameLevel(slot:GetFrameLevel() + 10)
	glow:SetUnit(kind.unit)
	glow:AddAuraSlot(SLOT_KEY, kind.filter, {
		candidateFilters = filters,
		initializeFrame = function(button)
			button:SetSize(ICON, ICON)
			button:SetPoint("CENTER", glow, "CENTER")
			local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			text:SetPoint("CENTER", 0, 0)
			button:SetDurationText(text, { binding = glowBinding, textFormatter = glowFormat })
		end,
	})
end

-- "Only when missing": nothing while the aura is up, the grey picture while it is not.
-- An aura slot cannot do that (its button would have to cover the picture with something),
-- so this uses a group of at most one button that draws nothing. Blizzard sizes the
-- container to 1 px while the aura is absent and to the button width while it is present,
-- and a clipping frame from the container right edge to the slot right edge is therefore
-- as wide as the slot when the aura is missing and zero wide when it is up. The grey
-- picture lives inside that clip. Frames anchored to a container that owns a group have to
-- come from DisableUntrustedLayoutScriptsTemplate.
local function EnsureGate(slot, kind, ids)
	local filters = { includeSpellIDs = ids }
	if slot.gate then
		slot.gate:SetUnit(kind.unit)
		slot.gate:SetAuraGroupFilterString(GROUP_KEY, kind.filter)
		slot.gate:SetAuraGroupCandidateFilters(GROUP_KEY, filters)
		slot.gate:SetAuraGroupEnabled(GROUP_KEY, true)
		return
	end
	-- 1.5.0: the host reaches GLOW_PAD past the slot on every side so the red glow around the
	-- grey picture fits inside the clip; the hidden button is as wide as the host, so the clip
	-- still closes completely while the buff is up.
	local host = CreateFrame("Frame", nil, slot, "DisableUntrustedLayoutScriptsTemplate")
	host:SetSize(ICON + 2 * GLOW_PAD, ICON + 2 * GLOW_PAD)
	host:SetPoint("CENTER", slot, "CENTER")
	slot.gateHost = host
	local width = ICON + 2 * GLOW_PAD + 1
	local gate = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
	slot.gate = gate
	gate:SetPoint("TOPLEFT", host, "TOPLEFT")      -- one point only: Blizzard sets the size
	gate:SetUnit(kind.unit)
	gate:AddAuraGroup(GROUP_KEY, kind.filter, {
		candidateFilters = filters,
		maxFrameCount = 1,
		layout = { elementWidth = width, elementHeight = ICON },
		initializeFrame = function(button) button:SetSize(width, ICON) end,   -- draws nothing
	})
	local clip = CreateFrame("Frame", nil, host, "DisableUntrustedLayoutScriptsTemplate")
	clip:SetClipsChildren(true)
	clip:SetPoint("TOPLEFT", gate, "TOPRIGHT", -1, 0)
	clip:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT")
	slot.gateIcon = GreyPicture(clip, slot)
	slot.gateGlow = LoopGlow(clip, host, true)
end

-- A cooldown: our own frame, nothing sealed. The duration object goes straight from the
-- API into the swipe and the text; it is never read.
local function EnsureCooldown(slot, spellID, icon, showTimer)
	local cool = slot.cool
	if not cool then
		cool = CreateFrame("Frame", nil, slot)
		slot.cool = cool
		cool:SetAllPoints()
		local frame = cool:CreateTexture(nil, "BACKGROUND")
		frame:SetAllPoints()
		frame:SetColorTexture(0, 0, 0, 1)
		cool.icon = cool:CreateTexture(nil, "ARTWORK")
		cool.icon:SetPoint("TOPLEFT", 2, -2)
		cool.icon:SetPoint("BOTTOMRIGHT", -2, 2)
		cool.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		cool.swipe = CreateFrame("Cooldown", nil, cool, "CooldownFrameTemplate")
		cool.swipe:SetPoint("TOPLEFT", 2, -2)
		cool.swipe:SetPoint("BOTTOMRIGHT", -2, 2)
		cool.swipe:SetHideCountdownNumbers(true)
		cool.swipe:SetSwipeColor(0, 0, 0, 0.6)   -- 1.7.4: the icon stays visible under the swipe
		cool.swipe:SetDrawEdge(false)            -- 1.7.5: no yellow edge line (the action bar has none)
		-- 1.7.4 (his report: the ready glow came back only after casting another spell): no
		-- SPELL_UPDATE_COOLDOWN comes when a cooldown ends, the swipe's own end does
		cool.swipe:SetScript("OnCooldownDone", function() ns.UpdateCooldowns() end)
		local textFrame = CreateFrame("Frame", nil, cool)
		textFrame:SetAllPoints()
		textFrame:SetFrameLevel(cool.swipe:GetFrameLevel() + 2)
		cool.time = textFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
		cool.time:SetPoint("CENTER", 0, 0)
		cool.binding = C_DurationUtil.CreateDurationTextBinding()
		cool.binding:SetFormatter(timeFormat or C_StringUtil.CreateSecondsFormatter())
		cool.binding:SetZeroDurationText("")
		cool.binding:SetExpiredText("")
		cool.binding:SetFontString(cool.time)
		cool.visual = { frame, cool.icon, textFrame }   -- the swipe is faded, not hidden (it would reappear)
		-- 1.7.5 (audit after "I feel like you fixed nothing"): the ready glow no longer waits for
		-- an event. The client sends none when a cooldown ends, and the text-width trick of
		-- 1.7.2-1.7.4 only changed on SPELL_UPDATE_COOLDOWN. While shown (in combat), it asks the
		-- client every 0.1 s and hands the (secret) "still cooling" answer straight to
		-- SetAlphaFromBoolean; the addon never reads it. 0 / 255 works whether the call counts
		-- alpha from 0 to 1 or from 0 to 255.
		do
			local ready = CreateFrame("Frame", nil, cool)
			cool.ready = ready
			ready:SetSize(ICON, ICON)
			ready:SetPoint("CENTER", cool, "CENTER")
			ready:SetFrameLevel(textFrame:GetFrameLevel() + 1)
			ready.host = CreateFrame("Frame", nil, ready)
			ready.host:SetAllPoints()
			LoopGlow(ready.host, ready)
			ready.wait = 0
			ready:SetScript("OnUpdate", function(self, elapsed)
				self.wait = self.wait + elapsed
				if self.wait < 0.1 then return end
				self.wait = 0
				local duration = cool.spellID and C_Spell.GetSpellCooldownDuration(cool.spellID, true)
				if duration then
					self.host:SetAlphaFromBoolean(duration:IsActive(), 0, 255)
				else
					self.host:SetAlpha(1)
				end
			end)
			ready:Hide()
		end
	end
	cool.spellID = spellID
	cool.icon:SetTexture(icon)
	cool.time:SetShown(showTimer)
	cool.binding:SetEnabled(showTimer)
end

-- Switches off the parts of a slot that the other modes use.
-- Click to cast: an invisible secure button over the icon. It is set up out of combat and
-- then works in combat too. A reminder that only shows when missing keeps its button while
-- the buff is up: the spot is empty, a click there simply casts the buff again.
local function EnsureCast(slot, spellName)
	local cast = slot.cast
	if not ns.db.clickCast or not spellName then
		if cast then
			cast.spellName = nil
			cast:Hide()
		end
		return
	end
	if not cast then
		cast = CreateFrame("Button", nil, slot, "SecureActionButtonTemplate")
		slot.cast = cast
		cast:SetAllPoints()
		cast:SetFrameLevel(slot:GetFrameLevel() + 20)
		cast:RegisterForClicks("AnyDown", "AnyUp")
		cast:SetAttribute("type", "spell")
		local light = cast:CreateTexture(nil, "HIGHLIGHT")
		light:SetAllPoints()
		light:SetColorTexture(1, 1, 1, 0.18)
		cast:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText("Click: " .. (self.spellName or ""), 1, 1, 1)
			GameTooltip:Show()
		end)
		cast:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	cast.spellName = spellName
	cast:SetAttribute("spell", spellName)
	cast:SetShown(not ns.unlocked)
end

local function SetSlotMode(slot, mode)
	if mode ~= "aura" then
		for _, container in pairs(slot.containers) do container:SetAuraSlotEnabled(SLOT_KEY, false) end
		if slot.glow then slot.glow:SetAuraSlotEnabled(SLOT_KEY, false) end
	end
	if slot.gate then slot.gate:SetAuraGroupEnabled(GROUP_KEY, mode == "gate") end
	if slot.cool then slot.cool:SetShown(mode == "cooldown") end
	slot.mode = mode
end

------------------------------------------------------------------------------------------
-- 1.7.0 (his ask, 2026-11-10): "toggle only glow and tracker off, and the glow shows up on my
-- action bar instead". With ns.db.barMode the row draws nothing; each icon's glow parts move
-- over the action button that holds its spell. They stay our own frames (only anchored to
-- the button, never parented to it), and the client still decides when they show.
------------------------------------------------------------------------------------------
local BAR_NAMES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
	"MultiBarLeftButton", "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

-- The first shown action button whose slot holds one of the spells (any rank), or nil.
local function FindBarButton(ids, extra)
	if not (C_ActionBar and C_ActionBar.FindSpellActionButtons) then return end
	local wanted = {}
	local set = Enum.ActionBarSet and Enum.ActionBarSet.Mkb
	local function Add(id)
		local found = C_ActionBar.FindSpellActionButtons(id, set)
		if found then
			for _, actionSlot in ipairs(found) do wanted[actionSlot] = true end
		end
	end
	for id in pairs(ids) do Add(id) end
	if extra then Add(extra) end
	if not next(wanted) then return end
	for _, prefix in ipairs(BAR_NAMES) do
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button and button.action and wanted[button.action] and button:IsVisible() then return button end
		end
	end
end

-- Puts a glow part over the button (scaled to its size, above it) or back on the slot.
local function Put(frame, slot, button)
	frame:ClearAllPoints()
	frame:SetScale(1)
	if button then
		local scale = button:GetWidth() * button:GetEffectiveScale() / (ICON * frame:GetEffectiveScale())
		frame:SetScale(scale)
		frame:SetPoint("CENTER", button, "CENTER")
		frame:SetFrameStrata("HIGH")
	else
		frame:SetPoint("CENTER", slot, "CENTER")
		frame:SetFrameStrata(ns.holder:GetFrameStrata())
	end
end

-- 1.7.5: each icon chooses: on the row, or its glow on the action bar ("Row" / "Bar" in the
-- editor). An icon that never chose follows the global switch.
function ns.OnBar(track)
	if track.place then return track.place == "bar" end
	return ns.db.barMode == true
end

local function PlaceParts(slot, entry, track)
	local bar = ns.OnBar(track)
	local button
	if bar then
		local extra = track.bar and C_Spell.GetSpellInfo(track.bar)
		button = FindBarButton(entry.ids, extra and extra.spellID)
	end
	local glowAlpha = (bar and not button) and 0 or 1   -- spell not on a bar: nothing to glow on
	if slot.mode == "aura" then
		for _, container in pairs(slot.containers) do container:SetAlpha(bar and 0 or 1) end
		if slot.glow then
			Put(slot.glow, slot, button)
			slot.glow:SetAlpha(glowAlpha)
		end
	elseif slot.mode == "gate" then
		Put(slot.gateHost, slot, button)
		slot.gateHost:SetAlpha(glowAlpha)
		slot.gateIcon:SetShown(not bar)
		slot.gateIcon.frame:SetShown(not bar)
	elseif slot.mode == "cooldown" and slot.cool then
		for _, part in ipairs(slot.cool.visual) do part:SetShown(not bar) end
		-- a Cooldown frame shows itself again on every new cooldown: fade it instead (the
		-- dark square with a yellow line that stayed on the row in bar mode)
		slot.cool.swipe:SetAlpha(bar and 0 or 1)
		if slot.cool.ready then
			Put(slot.cool.ready, slot, button)
			slot.cool.ready:SetAlpha(glowAlpha)
		end
	end
end

------------------------------------------------------------------------------------------
-- The row
------------------------------------------------------------------------------------------
-- Tracks that are switched on and, unless marked "always", known to this character.
-- Icons that are always there come first, reminders that only appear when something is
-- missing go to the end: a hidden reminder then leaves no gap in the row.
function ns.VisibleTracks()
	local visible, reminders = {}, {}
	for _, track in ipairs(ns.tracks) do
		-- 1.7.4: "in combat only" icons are built like the others and only hidden out of combat
		-- (ns.LayoutRow). Building them at the start of combat missed a Seal that was already up.
		if track.enabled ~= false and #visible + #reminders < ns.MAX_TRACKS then
			local ids, icon = ns.Resolve(track)
			local known = ns.KnownSpell(ids) or ns.BarSpellKnown(track)
			if next(ids) and (track.always or known) then
				local list = ns.OnlyWhenMissing(track) and reminders or visible
				list[#list + 1] = { track = track, ids = ids, icon = icon, spellID = known or next(ids) }
			end
		end
	end
	local steady = #visible
	for _, entry in ipairs(reminders) do visible[#visible + 1] = entry end
	return visible, steady
end

function ns.BuildTracks()
	if not HasAuraContainer() then
		if not ns.warned then
			ns.warned = true
			ns.Print("this client has no aura container; the icons cannot be shown.")
		end
		return
	end
	local visible, steady = ns.VisibleTracks()
	for index, entry in ipairs(visible) do
		local slot = slots[index] or CreateSlot()
		slots[index] = slot
		local track = entry.track
		local kind = ns.KINDS[track.kind]
		slot.track = track
		slot.combatOnly = track.combat == true
		slot.reminder = kind.onlyWhenMissing == true
		slot.missing.icon:SetTexture(entry.icon)
		if track.kind == "cooldown" then
			EnsureCooldown(slot, entry.spellID, entry.icon, track.timer ~= false)
			SetSlotMode(slot, "cooldown")
		elseif kind.onlyWhenMissing then
			EnsureGate(slot, kind, entry.ids)
			slot.gateIcon:SetTexture(entry.icon)
			slot.gateGlow:SetShown(track.glow ~= false)
			SetSlotMode(slot, "gate")
		else
			EnsureAura(slot, kind, entry.ids, track.timer ~= false)
			EnsureGlow(slot, kind, entry.ids, track.glow ~= false)
			SetSlotMode(slot, "aura")
		end
		EnsureCast(slot, not ns.OnBar(track) and ns.CastName(track) or nil)
		slot:Show()
		PlaceParts(slot, entry, track)
	end
	for index = #visible + 1, #slots do
		local slot = slots[index]
		slot.track = nil
		EnsureCast(slot, nil)
		SetSlotMode(slot, "off")
		slot:Hide()
	end
	ns.LayoutRow()
end

-- Places the icons: "in combat only" ones are see-through and out of the way out of combat
-- (all of them show while the row is unlocked), the rest close up. Only moves and fades our
-- own frames; the cast buttons are shown or hidden only out of combat. Runs in
-- PLAYER_REGEN_DISABLED, before the lockdown.
function ns.LayoutRow()
	local showAll = ns.inCombat or ns.unlocked
	local position, steady, count = 0, 0, 0
	for _, slot in ipairs(slots) do
		if slot.track then
			local shown = showAll or not slot.combatOnly
			slot:ClearAllPoints()
			slot:SetPoint("TOPLEFT", ns.holder, "TOPLEFT", (shown and position or 0) * (ICON + GAP), 0)
			slot:SetAlpha(shown and 1 or 0)
			if shown then
				position = position + 1
				count = count + 1
				if not slot.reminder then steady = steady + 1 end
			end
			if slot.cast and not InCombatLockdown() then
				slot.cast:SetShown(shown and not ns.unlocked and slot.cast.spellName ~= nil)
			end
		end
	end
	-- the pet bars are exactly as wide as the icons that are always there (reminders at the
	-- end do not stretch them); with no such icon, as wide as all of them or three icons
	local wide = steady > 0 and steady or count
	ns.rowWidth = wide > 0 and (wide * (ICON + GAP) - GAP) or 98
	ns.holder:SetSize(ns.rowWidth, ICON + 14)
	if ns.LayoutPetBars then ns.LayoutPetBars() end
end

-- The grey "missing" picture shows only while there is something the effect could be on:
-- an attackable target, the player, a pet. Whether those exist is plain data, also in combat.
function ns.UpdateMarkers()
	local present = {
		player = true,
		target = ns.Plain(UnitExists("target"), false) and ns.Plain(UnitCanAttack("player", "target"), false)
			and not ns.Plain(UnitIsDead("target"), false),
		pet = ns.Plain(UnitExists("pet"), false) and true or false,
	}
	for _, slot in ipairs(slots) do
		local track = slot.track
		if track then
			local kind = ns.KINDS[track.kind]
			local there = kind.unit and present[kind.unit] and true or false
			-- the plain picture under an aura slot, or the clipped one of a reminder
			slot.missing:SetShown(slot.mode == "aura" and track.missing ~= false and there and not ns.OnBar(track))
			if slot.gateHost then slot.gateHost:SetShown(slot.mode == "gate" and there) end
		end
	end
end

function ns.UpdateCooldowns()
	for _, slot in ipairs(slots) do
		local cool = slot.cool
		if slot.mode == "cooldown" and cool and cool.spellID then
			-- true: leave the global cooldown off the icon
			local duration = C_Spell.GetSpellCooldownDuration(cool.spellID, true)
			cool.swipe:SetCooldownFromDurationObject(duration, true)
			cool.binding:SetDuration(duration)
		end
	end
end

-- 1.7.5: aura containers listen to UNIT_AURA only, not to a target change (Blizzard's own
-- target frame calls UpdateAllAuras on PLAYER_TARGET_CHANGED). This asks every container to
-- look at the unit again; target: only the target ones. Reads nothing.
function ns.RescanAuras(onlyTarget)
	for _, slot in ipairs(slots) do
		local kind = slot.track and ns.KINDS[slot.track.kind]
		if kind and kind.unit and (not onlyTarget or kind.unit == "target") then
			for _, container in pairs(slot.containers) do
				if container.UpdateAllAuras then container:UpdateAllAuras() end
			end
			if slot.glow and slot.glow.UpdateAllAuras then slot.glow:UpdateAllAuras() end
			if slot.gate and slot.gate.UpdateAllAuras then slot.gate:UpdateAllAuras() end
		end
	end
end

-- Cooldown ready glows only in combat (out of combat every spell is ready and the row would
-- glow all the time). inCombat comes from the event: during PLAYER_REGEN_DISABLED the lockdown
-- has not started yet.
function ns.UpdateReadyGlows(inCombat)
	if inCombat == nil then inCombat = InCombatLockdown() end
	for _, slot in ipairs(slots) do
		local cool = slot.cool
		if cool and cool.ready then
			cool.ready:SetShown(inCombat and slot.mode == "cooldown" and slot.track ~= nil and slot.track.glow ~= false)
		end
	end
end
