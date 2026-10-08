-- The in-game editor: /denodots or /dots. What is tracked and how each icon behaves, the
-- order, the glow, the pet bars, the size and the position. It only opens out of combat:
-- the icon row is rebuilt on every change.
local ADDON, ns = ...

local ROWS = ns.MAX_TRACKS
local ROW_HEIGHT = 30
local WIDTH = 680
local PAD = 14
local LIST_TOP = 92

-- column positions inside a row
local COL_SPELL, COL_TYPE, COL_OPTIONS, COL_ORDER = 54, 244, 340, 556

-- One flat look: a grey window, darker rows, thin outlines, and blue only where something
-- is switched on or under the mouse.
local C = {
	panel = { 0.10, 0.10, 0.11, 0.97 },
	border = { 0.38, 0.38, 0.40, 1 },
	rowA = { 0.09, 0.10, 0.13, 1 },
	rowB = { 0.12, 0.13, 0.17, 1 },
	rowHover = { 0.18, 0.26, 0.36, 0.45 },
	button = { 0.15, 0.15, 0.16, 1 },
	edge = { 0.28, 0.29, 0.32, 1 },
	on = { 0.10, 0.20, 0.31, 1 },
	accent = { 0.52, 0.80, 1.00, 1 },
	hover = { 0.58, 0.80, 1.00, 1 },
	line = { 0.20, 0.24, 0.31, 1 },
	input = { 0.045, 0.05, 0.065, 1 },
	text = { 0.95, 0.95, 0.96 },
	dim = { 0.60, 0.62, 0.68 },
	danger = { 0.93, 0.32, 0.32, 1 },
}

local editor
local rows = {}
local addKind = "dot"
local Update

local function Fill(parent, color, layer)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
	texture:SetAllPoints()
	texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	return texture
end

-- A one pixel outline; the returned function recolours it.
local function Outline(frame, color)
	local edges = {}
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local edge = frame:CreateTexture(nil, "BORDER")
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		if side[3] then edge:SetHeight(1) else edge:SetWidth(1) end
		edges[#edges + 1] = edge
	end
	local function Paint(c)
		for _, edge in ipairs(edges) do edge:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
	end
	Paint(color)
	return Paint
end

local function Text(parent, text, template, color)
	local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
	label:SetText(text)
	color = color or C.text
	label:SetTextColor(color[1], color[2], color[3])
	return label
end

-- A section title with a short line under it.
local function Heading(parent, text)
	local label = Text(parent, text, "GameFontHighlightSmall", C.accent)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
	rule:SetSize(26, 1)
	rule:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.55)
	return label
end

local function Tooltip(frame, title, body)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
		local line = type(body) == "function" and body() or body
		if line then GameTooltip:AddLine(line, 0.8, 0.8, 0.85, true) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A dark button with a thin outline. SetColor(nil) is the plain look; a colour tints the
-- fill and the outline (the type of an icon, a destructive action).
local function PaintButton(button)
	local tint = button.tint
	local r, g, b = C.button[1], C.button[2], C.button[3]
	local edge, text = C.edge, button.textColor or C.text
	if button.lit then
		r, g, b = C.on[1], C.on[2], C.on[3]
		edge = C.accent
	elseif tint then
		r, g, b = tint[1] * 0.30, tint[2] * 0.30, tint[3] * 0.30
		edge = tint
	end
	if button.hovered then
		r, g, b = r + 0.05, g + 0.06, b + 0.08
		if edge == C.edge then edge = C.hover end
	end
	button.fill:SetColorTexture(r, g, b, 1)
	button.outline(edge)
	button.label:SetTextColor(text[1], text[2], text[3])
end

local function Flat(parent, text, width, height, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height or 22)
	button.fill = Fill(button, C.button)
	button.outline = Outline(button, C.edge)
	button.label = Text(button, text)
	button.label:SetPoint("CENTER", 0, 0)
	function button:SetColor(color)
		self.tint = color
		PaintButton(self)
	end
	button:SetScript("OnEnter", function(self) self.hovered = true PaintButton(self) end)
	button:SetScript("OnLeave", function(self) self.hovered = false PaintButton(self) end)
	button:SetScript("OnClick", function(self) onClick(self) end)
	PaintButton(button)
	return button
end

-- A switch: a button with a tick box. Blue and ticked when on.
local function Switch(parent, text, width, onClick)
	local button = Flat(parent, text, width, 20, function(self)
		onClick(not self.on)
	end)
	local box = CreateFrame("Frame", nil, button)
	box:SetSize(10, 10)
	box:SetPoint("LEFT", 6, 0)
	Fill(box, C.input)
	local boxEdge = Outline(box, C.border)
	local tick = box:CreateTexture(nil, "ARTWORK")
	tick:SetPoint("TOPLEFT", 2, -2)
	tick:SetPoint("BOTTOMRIGHT", -2, 2)
	tick:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
	button.label:ClearAllPoints()
	button.label:SetPoint("LEFT", box, "RIGHT", 5, 0)
	function button:Set(on)
		self.on = on and true or false
		self.lit = self.on
		self.textColor = self.on and C.text or C.dim
		tick:SetShown(self.on)
		boxEdge(self.on and C.accent or C.border)
		PaintButton(self)
	end
	button:Set(false)
	return button
end

local function NextKind(kindKey)
	for index, key in ipairs(ns.KIND_ORDER) do
		if key == kindKey then return ns.KIND_ORDER[index % #ns.KIND_ORDER + 1] end
	end
	return ns.KIND_ORDER[1]
end

local function Status(text, r, g, b)
	editor.status:SetText(text or "")
	editor.status:SetTextColor(r or C.dim[1], g or C.dim[2], b or C.dim[3])
end

local function Changed()
	ns.Refresh()
	Update()
end

------------------------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------------------------
local function CreateRow(index)
	local row = CreateFrame("Frame", nil, editor)
	row:SetSize(WIDTH - 2 * PAD, ROW_HEIGHT - 2)
	row:SetPoint("TOPLEFT", PAD, -LIST_TOP - (index - 1) * ROW_HEIGHT)
	row:EnableMouse(true)
	Fill(row, index % 2 == 1 and C.rowA or C.rowB)
	local glow = row:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])

	row.enabled = Switch(row, "On", 42, function(on)
		ns.tracks[index].enabled = on
		Changed()
	end)
	row.enabled:SetPoint("LEFT", 6, 0)
	Tooltip(row.enabled, "Show this icon", "Unticked keeps the spell in the list without showing its icon.")

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(22, 22)
	row.icon:SetPoint("LEFT", row, "LEFT", COL_SPELL, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.label = Text(row, "", "GameFontHighlight")
	row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
	row.label:SetWidth(150)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.note = Text(row, "", "GameFontHighlightSmall", C.dim)
	row.note:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -2)
	row.note:SetWidth(150)
	row.note:SetJustifyH("LEFT")
	row.note:SetWordWrap(false)

	row.kind = Flat(row, "", 86, 20, function()
		local track = ns.tracks[index]
		track.kind = NextKind(track.kind)
		Changed()
	end)
	row.kind:SetPoint("LEFT", row, "LEFT", COL_TYPE, 0)
	Tooltip(row.kind, function() return ns.KINDS[ns.tracks[index].kind].label end,
		function() return ns.KINDS[ns.tracks[index].kind].hint .. "\n\nClick for the next type." end)

	local function Flag(key, text, width, x, title, body)
		local switch = Switch(row, text, width, function(on)
			ns.tracks[index][key] = on
			Changed()
		end)
		switch:SetPoint("LEFT", row, "LEFT", x, 0)
		Tooltip(switch, title, body)
		return switch
	end
	row.missing = Flag("missing", "Missing", 76, COL_OPTIONS, "Show when missing",
		"A grey icon in a red frame while the effect is not up.")
	row.glow = Flag("glow", "Glow", 60, COL_OPTIONS + 79, "Glow before it ends",
		function() return "The proc glow during the last " .. ns.db.glowSeconds .. " seconds. The number of seconds is set below." end)
	row.timer = Flag("timer", "Timer", 64, COL_OPTIONS + 142, "Timer", "The seconds left, written on the icon.")

	row.up = Flat(row, "Up", 28, 20, function()
		if index > 1 then
			ns.tracks[index], ns.tracks[index - 1] = ns.tracks[index - 1], ns.tracks[index]
			Changed()
		end
	end)
	row.up:SetPoint("LEFT", row, "LEFT", COL_ORDER, 0)
	Tooltip(row.up, "Move up", "Icons are shown left to right in the order of this list.")
	row.down = Flat(row, "Down", 40, 20, function()
		if index < #ns.tracks then
			ns.tracks[index], ns.tracks[index + 1] = ns.tracks[index + 1], ns.tracks[index]
			Changed()
		end
	end)
	row.down:SetPoint("LEFT", row.up, "RIGHT", 3, 0)
	Tooltip(row.down, "Move down", "Icons are shown left to right in the order of this list.")
	row.remove = Flat(row, "X", 20, 20, function()
		table.remove(ns.tracks, index)
		Changed()
	end)
	row.remove:SetPoint("LEFT", row.down, "RIGHT", 3, 0)
	row.remove:SetColor(C.danger)
	Tooltip(row.remove, "Remove", "Takes the spell out of the list.")
	return row
end

Update = function()
	if not editor or not editor:IsShown() then return end
	for index = 1, ROWS do
		local row = rows[index]
		local track = ns.tracks[index]
		if track then
			local kind = ns.KINDS[track.kind]
			local switches = ns.KIND_SWITCHES[track.kind]
			local ids, icon = ns.Resolve(track)
			local note = #track.spells > 1 and (#track.spells .. " spells, any of them") or ""
			if not next(ids) then
				note = "|cffff5555spell not found|r"
			elseif not track.always and not ns.IsKnown(ids) then
				note = "not learned yet"
			end
			row.icon:SetTexture(icon)
			row.icon:SetDesaturated(track.enabled == false)
			row.label:SetText(track.label)
			row.note:SetText(note)
			row.enabled:Set(track.enabled ~= false)
			row.kind.label:SetText(kind.label)
			row.kind:SetColor(kind.color)
			for _, key in ipairs({ "missing", "glow", "timer" }) do
				row[key]:SetShown(switches[key] == true)
				row[key]:Set(track[key] ~= false)
			end
			row:Show()
		else
			row:Hide()
		end
	end
	editor.empty:SetShown(#ns.tracks == 0)
	editor.addKind.label:SetText(ns.KINDS[addKind].label)
	editor.addKind:SetColor(ns.KINDS[addKind].color)
	editor.addHint:SetText(ns.KINDS[addKind].label .. ": " .. ns.KINDS[addKind].hint)
	editor.petHealth:Set(ns.db.petHealth)
	editor.petMana:Set(ns.db.petMana)
	editor.numbers:Set(ns.db.numbers)
	editor.move:Set(ns.unlocked)
	editor.clickCast:Set(ns.db.clickCast)
	editor.scaleText:SetText(string.format("%d%%", math.floor(ns.db.scale * 100 + 0.5)))
	editor.glowText:SetText(ns.db.glowSeconds .. " s")
end

------------------------------------------------------------------------------------------
-- Adding a track: one or more spell names or ids, separated by commas. Several spells in
-- one icon mean "any of these" (one bane, one curse, one armor).
------------------------------------------------------------------------------------------
local function Add()
	local text = editor.input:GetText() or ""
	local spells, label = {}, nil
	for part in string.gmatch(text, "[^,]+") do
		part = strtrim(part)
		if part ~= "" then
			local id = tonumber(part)
			if id then
				local name = C_Spell.GetSpellName(id)
				if not name then
					Status("No spell has the id " .. part .. ".", 1, 0.35, 0.35)
					return
				end
				spells[#spells + 1] = id
				label = label or name
			else
				local key = string.lower(part)
				local info = not ns.families[key] and C_Spell.GetSpellInfo(part) or nil
				if ns.families[key] then
					spells[#spells + 1] = key
					label = label or (C_Spell.GetSpellName(ns.families[key][2]) or part)
				elseif info and info.spellID then
					spells[#spells + 1] = info.spellID
					label = label or info.name
				else
					Status("\"" .. part .. "\" is not a spell name I know. Try its spell id.", 1, 0.35, 0.35)
					return
				end
			end
		end
	end
	if #spells == 0 then
		Status("Type a spell name or a spell id first.", 1, 0.35, 0.35)
		return
	end
	if #ns.tracks >= ns.MAX_TRACKS then
		Status("The list is full (" .. ns.MAX_TRACKS .. "). Remove one first.", 1, 0.35, 0.35)
		return
	end
	ns.tracks[#ns.tracks + 1] = ns.NewTrack(label, addKind, spells, true)
	editor.input:SetText("")
	editor.input:ClearFocus()
	Status("Added " .. label .. " as " .. ns.KINDS[addKind].label .. ".", 0.4, 1, 0.5)
	Changed()
end

-- A "- value +" stepper; returns the value text and the plus button.
local function Stepper(parent, anchor, gap, width, onStep)
	local smaller = Flat(parent, "-", 22, 20, function() onStep(-1) end)
	smaller:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
	local value = Text(parent, "")
	value:SetPoint("LEFT", smaller, "RIGHT", 4, 0)
	value:SetWidth(width)
	local bigger = Flat(parent, "+", 22, 20, function() onStep(1) end)
	bigger:SetPoint("LEFT", value, "RIGHT", 4, 0)
	return value, bigger
end

------------------------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------------------------
local function CreateEditor()
	local listBottom = LIST_TOP + ROWS * ROW_HEIGHT
	editor = CreateFrame("Frame", "DenoDotsEditor", UIParent)
	editor:SetSize(WIDTH, listBottom + 210)
	editor:SetPoint("CENTER")
	editor:SetFrameStrata("DIALOG")
	editor:SetMovable(true)
	editor:EnableMouse(true)
	editor:SetClampedToScreen(true)
	editor:RegisterForDrag("LeftButton")
	editor:SetScript("OnDragStart", editor.StartMoving)
	editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
	editor:SetScript("OnHide", function() ns.LockHolder() end)
	tinsert(UISpecialFrames, "DenoDotsEditor")
	Fill(editor, C.panel)
	Outline(editor, C.border)

	-- header: the name in the middle, the version under it
	local title = Text(editor, "Deno Dots", "GameFontNormalLarge", { 1, 1, 1 })
	title:SetPoint("TOP", 0, -10)
	local version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or ""
	local subtitle = Text(editor, "v" .. version .. "  Forever", "GameFontHighlightSmall", C.dim)
	subtitle:SetPoint("TOP", title, "BOTTOM", 0, -2)
	local close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() editor:Hide() end)

	-- the list
	local listTitle = Heading(editor, "TRACKED SPELLS")
	listTitle:SetPoint("TOPLEFT", PAD, -52)
	for _, column in ipairs({ { "Spell", COL_SPELL }, { "Type (click)", COL_TYPE }, { "Options", COL_OPTIONS },
		{ "Order", COL_ORDER } }) do
		local label = Text(editor, column[1], "GameFontHighlightSmall", C.dim)
		label:SetPoint("TOPLEFT", PAD + column[2], -76)
	end
	for index = 1, ROWS do rows[index] = CreateRow(index) end
	editor.empty = Text(editor, "Nothing tracked yet. Add a spell below.", "GameFontHighlight", C.dim)
	editor.empty:SetPoint("TOP", 0, -LIST_TOP - 50)

	-- add a spell
	local top = -listBottom - 8
	local addTitle = Heading(editor, "ADD A SPELL")
	addTitle:SetPoint("TOPLEFT", PAD, top)
	local box = CreateFrame("Frame", nil, editor)
	box:SetSize(280, 24)
	box:SetPoint("TOPLEFT", PAD, top - 20)
	Fill(box, C.input)
	local boxEdge = Outline(box, C.line)
	editor.input = CreateFrame("EditBox", nil, box)
	editor.input:SetPoint("TOPLEFT", 6, 0)
	editor.input:SetPoint("BOTTOMRIGHT", -6, 0)
	editor.input:SetFontObject(ChatFontNormal)
	editor.input:SetAutoFocus(false)
	editor.input:SetScript("OnEnterPressed", Add)
	editor.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	editor.input:SetScript("OnEditFocusGained", function() boxEdge(C.hover) end)
	editor.input:SetScript("OnEditFocusLost", function() boxEdge(C.line) end)
	local placeholder = Text(box, "Spell name or id; several with commas", "GameFontHighlightSmall", C.dim)
	placeholder:SetPoint("LEFT", 6, 0)
	editor.input:SetScript("OnTextChanged", function(self) placeholder:SetShown(self:GetText() == "") end)
	local asLabel = Text(editor, "as", "GameFontHighlightSmall", C.dim)
	asLabel:SetPoint("LEFT", box, "RIGHT", 8, 0)
	editor.addKind = Flat(editor, "", 90, 24, function()
		addKind = NextKind(addKind)
		Update()
	end)
	editor.addKind:SetPoint("LEFT", asLabel, "RIGHT", 8, 0)
	Tooltip(editor.addKind, "Type", "How the new icon behaves. Click for the next type.")
	local addButton = Flat(editor, "Add", 70, 24, Add)
	addButton:SetPoint("LEFT", editor.addKind, "RIGHT", 8, 0)
	addButton.lit = true
	PaintButton(addButton)
	editor.addHint = Text(editor, "", "GameFontHighlightSmall", C.dim)
	editor.addHint:SetPoint("TOPLEFT", PAD, top - 50)
	editor.addHint:SetWidth(WIDTH - 2 * PAD)
	editor.addHint:SetJustifyH("LEFT")
	editor.addHint:SetWordWrap(false)
	editor.status = Text(editor, "", "GameFontHighlightSmall", C.dim)
	editor.status:SetPoint("TOPLEFT", PAD, top - 66)
	editor.status:SetWidth(WIDTH - 2 * PAD)
	editor.status:SetJustifyH("LEFT")

	-- look
	top = top - 90
	local rule = editor:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
	rule:SetPoint("TOPLEFT", PAD, top + 8)
	rule:SetPoint("TOPRIGHT", -PAD, top + 8)
	rule:SetHeight(1)
	local lookTitle = Heading(editor, "LOOK")
	lookTitle:SetPoint("TOPLEFT", PAD, top - 2)

	editor.petHealth = Switch(editor, "Pet health", 96, function(on) ns.db.petHealth = on; Changed() end)
	editor.petHealth:SetPoint("TOPLEFT", PAD, top - 22)
	Tooltip(editor.petHealth, "Pet health", "A health bar for your pet under the icons.")
	editor.petMana = Switch(editor, "Pet mana", 90, function(on) ns.db.petMana = on; Changed() end)
	editor.petMana:SetPoint("LEFT", editor.petHealth, "RIGHT", 6, 0)
	Tooltip(editor.petMana, "Pet mana", "A mana bar for your pet under the icons.")
	editor.numbers = Switch(editor, "Numbers on bars", 124, function(on) ns.db.numbers = on; Changed() end)
	editor.numbers:SetPoint("LEFT", editor.petMana, "RIGHT", 6, 0)
	Tooltip(editor.numbers, "Numbers on bars", "The pet's health and mana written on the bars.")

	local sizeLabel = Text(editor, "Size", "GameFontHighlightSmall", C.text)
	sizeLabel:SetPoint("LEFT", editor.numbers, "RIGHT", 24, 0)
	editor.scaleText = Stepper(editor, sizeLabel, 8, 40, function(step)
		ns.db.scale = math.max(0.6, math.min(2, ns.db.scale + 0.1 * step))
		ns.PlaceHolder()
		Update()
	end)

	local glowLabel = Text(editor, "Glow and red number start", "GameFontHighlightSmall", C.text)
	glowLabel:SetPoint("TOPLEFT", PAD, top - 52)
	local glowAfter
	editor.glowText, glowAfter = Stepper(editor, glowLabel, 8, 30, function(step)
		ns.db.glowSeconds = ns.SetGlowSeconds(ns.db.glowSeconds + step)
		Update()
	end)
	local glowTail = Text(editor, "before an effect ends  (" .. ns.GLOW_MIN .. " to " .. ns.GLOW_MAX .. " seconds)",
		"GameFontHighlightSmall", C.dim)
	glowTail:SetPoint("LEFT", glowAfter, "RIGHT", 8, 0)

	editor.move = Switch(editor, "Move with mouse", 126, function(on)
		if on then ns.UnlockHolder() else ns.LockHolder() end
		Update()
	end)
	editor.move:SetPoint("TOPLEFT", PAD, top - 78)
	Tooltip(editor.move, "Move", "While this is ticked, drag the icon row with the left mouse button.")
	local resetPosition = Flat(editor, "Reset position", 104, 20, function()
		ns.db.x, ns.db.y, ns.db.scale = ns.defaults.x, ns.defaults.y, ns.defaults.scale
		ns.PlaceHolder()
		Update()
	end)
	resetPosition:SetPoint("LEFT", editor.move, "RIGHT", 6, 0)
	Tooltip(resetPosition, "Reset position", "Back above the player frame, at normal size.")
	editor.clickCast = Switch(editor, "Click an icon to cast", 150, function(on) ns.db.clickCast = on; Changed() end)
	editor.clickCast:SetPoint("LEFT", resetPosition, "RIGHT", 6, 0)
	Tooltip(editor.clickCast, "Click to cast",
		"A click on an icon casts its spell, also in combat. Handy for a buff that is missing. "
		.. "Several spells in one icon: the best one you know.")
	local resetList = Flat(editor, "Reset list to class defaults", 176, 20, function()
		wipe(ns.tracks)
		for i, track in ipairs(ns.DefaultTracks()) do ns.tracks[i] = track end
		Status("List reset.", 0.4, 1, 0.5)
		Changed()
	end)
	resetList:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -PAD, top - 78)
	resetList:SetColor(C.danger)
	Tooltip(resetList, "Reset list", "Replaces your list with the starting list for your class.")
end

function ns.OpenEditor()
	if InCombatLockdown() then
		ns.Print("the editor opens out of combat.")
		return
	end
	if not editor then CreateEditor() end
	editor:Show()
	Status("")
	Update()
end

function ns.CloseEditor()
	if editor and editor:IsShown() then editor:Hide() end
end
