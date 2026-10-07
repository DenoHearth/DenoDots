-- The in-game editor: /denodots or /dots. What is tracked and how each icon behaves, the
-- order, the pet bars, the size and the position. It only opens out of combat: the icon
-- row is rebuilt on every change.
local ADDON, ns = ...

local ROWS = ns.MAX_TRACKS
local ROW_HEIGHT = 32
local WIDTH = 600
local PAD = 14

-- One flat, dark look for everything; the accent is the Warlock purple of the addon name.
local C = {
	panel = { 0.055, 0.055, 0.075, 0.97 },
	header = { 0.09, 0.085, 0.13, 1 },
	line = { 0.58, 0.51, 0.79, 0.9 },
	rowA = { 0.10, 0.10, 0.13, 1 },
	rowB = { 0.125, 0.125, 0.16, 1 },
	button = { 0.17, 0.17, 0.22, 1 },
	hover = { 0.25, 0.24, 0.33, 1 },
	accent = { 0.58, 0.51, 0.79, 1 },
	off = { 0.13, 0.13, 0.17, 1 },
	input = { 0.03, 0.03, 0.045, 1 },
	text = { 0.92, 0.92, 0.95 },
	dim = { 0.55, 0.55, 0.62 },
	danger = { 0.62, 0.2, 0.22, 1 },
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

local function Text(parent, text, template, color)
	local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
	label:SetText(text)
	color = color or C.text
	label:SetTextColor(color[1], color[2], color[3])
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

-- A flat button. SetColor changes its resting colour (kind tags, switches).
local function Flat(parent, text, width, height, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height or 22)
	button.color = C.button
	button.fill = Fill(button, C.button)
	button.label = Text(button, text)
	button.label:SetPoint("CENTER", 0, 0)
	function button:SetColor(color, textColor)
		self.color = color
		self.fill:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
		textColor = textColor or C.text
		self.label:SetTextColor(textColor[1], textColor[2], textColor[3])
	end
	button:SetScript("OnEnter", function(self)
		local c = self.color
		self.fill:SetColorTexture(math.min(1, c[1] + 0.09), math.min(1, c[2] + 0.09), math.min(1, c[3] + 0.11), 1)
	end)
	button:SetScript("OnLeave", function(self)
		local c = self.color
		self.fill:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	end)
	button:SetScript("OnClick", function(self) onClick(self) end)
	return button
end

-- A switch: lit in the accent colour when on.
local function Switch(parent, text, width, onClick)
	local button = Flat(parent, text, width, 20, function(self)
		onClick(not self.on)
	end)
	function button:Set(on)
		self.on = on and true or false
		if self.on then self:SetColor(C.accent, { 1, 1, 1 }) else self:SetColor(C.off, C.dim) end
	end
	button:Set(false)
	return button
end

local function KindColor(kindKey)
	local color = ns.KINDS[kindKey].color
	return { color[1] * 0.62, color[2] * 0.62, color[3] * 0.62, 1 }
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
	row:SetPoint("TOPLEFT", PAD, -86 - (index - 1) * ROW_HEIGHT)
	Fill(row, index % 2 == 1 and C.rowA or C.rowB)

	row.enabled = Switch(row, "On", 34, function(on)
		ns.tracks[index].enabled = on
		Changed()
	end)
	row.enabled:SetPoint("LEFT", 6, 0)
	Tooltip(row.enabled, "On / Off", "Off keeps the entry in the list without showing its icon.")

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(22, 22)
	row.icon:SetPoint("LEFT", row.enabled, "RIGHT", 8, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.label = Text(row, "", "GameFontHighlight")
	row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
	row.label:SetWidth(136)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.note = Text(row, "", "GameFontHighlightSmall", C.dim)
	row.note:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -2)
	row.note:SetWidth(136)
	row.note:SetJustifyH("LEFT")
	row.note:SetWordWrap(false)

	row.kind = Flat(row, "", 76, 20, function()
		local track = ns.tracks[index]
		track.kind = NextKind(track.kind)
		Changed()
	end)
	row.kind:SetPoint("LEFT", row, "LEFT", 218, 0)
	Tooltip(row.kind, function() return ns.KINDS[ns.tracks[index].kind].label end,
		function() return ns.KINDS[ns.tracks[index].kind].hint .. "\n\nClick for the next kind." end)

	local function Flag(key, text, width, x, title, body)
		local switch = Switch(row, text, width, function(on)
			ns.tracks[index][key] = on
			Changed()
		end)
		switch:SetPoint("LEFT", row, "LEFT", x, 0)
		Tooltip(switch, title, body)
		return switch
	end
	row.missing = Flag("missing", "Missing", 56, 300, "Mark missing", "A grey icon in a red frame while it is not up.")
	row.glow = Flag("glow", "Glow", 44, 360, "Glow", "The proc glow during the last 3 seconds.")
	row.timer = Flag("timer", "Timer", 46, 408, "Timer", "The seconds left, on the icon.")

	row.up = Flat(row, "Up", 30, 20, function()
		if index > 1 then
			ns.tracks[index], ns.tracks[index - 1] = ns.tracks[index - 1], ns.tracks[index]
			Changed()
		end
	end)
	row.up:SetPoint("LEFT", row, "LEFT", 466, 0)
	row.down = Flat(row, "Down", 40, 20, function()
		if index < #ns.tracks then
			ns.tracks[index], ns.tracks[index + 1] = ns.tracks[index + 1], ns.tracks[index]
			Changed()
		end
	end)
	row.down:SetPoint("LEFT", row.up, "RIGHT", 3, 0)
	row.remove = Flat(row, "X", 22, 20, function()
		table.remove(ns.tracks, index)
		Changed()
	end)
	row.remove:SetPoint("LEFT", row.down, "RIGHT", 3, 0)
	row.remove:SetColor(C.danger)
	Tooltip(row.remove, "Remove", "Takes the entry out of the list.")
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
			row.kind:SetColor(KindColor(track.kind), { 1, 1, 1 })
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
	editor.addKind:SetColor(KindColor(addKind), { 1, 1, 1 })
	editor.addHint:SetText(ns.KINDS[addKind].hint)
	editor.petHealth:Set(ns.db.petHealth)
	editor.petMana:Set(ns.db.petMana)
	editor.numbers:Set(ns.db.numbers)
	editor.move:Set(ns.unlocked)
	editor.scaleText:SetText(string.format("%d%%", math.floor(ns.db.scale * 100 + 0.5)))
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

------------------------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------------------------
local function CreateEditor()
	local listBottom = 86 + ROWS * ROW_HEIGHT
	editor = CreateFrame("Frame", "DenoDotsEditor", UIParent)
	editor:SetSize(WIDTH, listBottom + 196)
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

	-- a thin accent frame around the panel
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
		local line = editor:CreateTexture(nil, "BORDER")
		line:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		if edge[3] == 1 then line:SetWidth(1) else line:SetHeight(1) end
	end

	local header = CreateFrame("Frame", nil, editor)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(46)
	Fill(header, C.header)
	local stripe = header:CreateTexture(nil, "ARTWORK")
	stripe:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
	stripe:SetPoint("TOPLEFT")
	stripe:SetPoint("BOTTOMLEFT")
	stripe:SetWidth(4)
	local title = Text(header, "Deno Dots", "GameFontNormalLarge", { 1, 1, 1 })
	title:SetPoint("TOPLEFT", 16, -8)
	local subtitle = Text(header, "What you keep an eye on, and how each icon behaves", "GameFontHighlightSmall", C.dim)
	subtitle:SetPoint("TOPLEFT", 16, -27)
	local close = Flat(header, "X", 26, 22, function() editor:Hide() end)
	close:SetPoint("RIGHT", -10, 0)
	close:SetColor(C.danger)

	-- column titles
	for _, column in ipairs({ { "TRACKED", 46 }, { "KIND", 218 }, { "SHOW", 300 }, { "ORDER", 466 } }) do
		local label = Text(editor, column[1], "GameFontHighlightSmall", C.dim)
		label:SetPoint("TOPLEFT", PAD + column[2], -66)
	end
	for index = 1, ROWS do rows[index] = CreateRow(index) end
	editor.empty = Text(editor, "Nothing tracked yet. Add a spell below.", "GameFontHighlight", C.dim)
	editor.empty:SetPoint("TOP", 0, -140)

	-- add a spell
	local top = -listBottom - 8
	local addTitle = Text(editor, "ADD A SPELL", "GameFontHighlightSmall", C.dim)
	addTitle:SetPoint("TOPLEFT", PAD, top)
	local box = CreateFrame("Frame", nil, editor)
	box:SetSize(250, 24)
	box:SetPoint("TOPLEFT", PAD, top - 16)
	Fill(box, C.input)
	editor.input = CreateFrame("EditBox", nil, box)
	editor.input:SetPoint("TOPLEFT", 6, 0)
	editor.input:SetPoint("BOTTOMRIGHT", -6, 0)
	editor.input:SetFontObject(ChatFontNormal)
	editor.input:SetAutoFocus(false)
	editor.input:SetScript("OnEnterPressed", Add)
	editor.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	local placeholder = Text(box, "Spell name or id; several with commas", "GameFontHighlightSmall", C.dim)
	placeholder:SetPoint("LEFT", 6, 0)
	editor.input:SetScript("OnTextChanged", function(self) placeholder:SetShown(self:GetText() == "") end)
	local asLabel = Text(editor, "as", "GameFontHighlightSmall", C.dim)
	asLabel:SetPoint("LEFT", box, "RIGHT", 8, 0)
	editor.addKind = Flat(editor, "", 84, 24, function()
		addKind = NextKind(addKind)
		Update()
	end)
	editor.addKind:SetPoint("LEFT", asLabel, "RIGHT", 8, 0)
	Tooltip(editor.addKind, "Kind", "How the new icon behaves. Click for the next kind.")
	local addButton = Flat(editor, "Add", 70, 24, Add)
	addButton:SetPoint("LEFT", editor.addKind, "RIGHT", 8, 0)
	addButton:SetColor(C.accent, { 1, 1, 1 })
	editor.addHint = Text(editor, "", "GameFontHighlightSmall", C.dim)
	editor.addHint:SetPoint("TOPLEFT", PAD, top - 46)
	editor.addHint:SetWidth(WIDTH - 2 * PAD)
	editor.addHint:SetJustifyH("LEFT")
	editor.status = Text(editor, "", "GameFontHighlightSmall", C.dim)
	editor.status:SetPoint("TOPLEFT", PAD, top - 62)
	editor.status:SetWidth(WIDTH - 2 * PAD)
	editor.status:SetJustifyH("LEFT")

	-- display
	top = top - 86
	local rule = editor:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 1, 1, 0.06)
	rule:SetPoint("TOPLEFT", PAD, top + 4)
	rule:SetPoint("TOPRIGHT", -PAD, top + 4)
	rule:SetHeight(1)
	local displayTitle = Text(editor, "DISPLAY", "GameFontHighlightSmall", C.dim)
	displayTitle:SetPoint("TOPLEFT", PAD, top - 6)
	editor.petHealth = Switch(editor, "Pet health", 86, function(on) ns.db.petHealth = on; Changed() end)
	editor.petHealth:SetPoint("TOPLEFT", PAD, top - 24)
	editor.petMana = Switch(editor, "Pet mana", 80, function(on) ns.db.petMana = on; Changed() end)
	editor.petMana:SetPoint("LEFT", editor.petHealth, "RIGHT", 6, 0)
	editor.numbers = Switch(editor, "Bar numbers", 92, function(on) ns.db.numbers = on; Changed() end)
	editor.numbers:SetPoint("LEFT", editor.petMana, "RIGHT", 6, 0)

	local sizeLabel = Text(editor, "Size", "GameFontHighlightSmall", C.dim)
	sizeLabel:SetPoint("LEFT", editor.numbers, "RIGHT", 22, 0)
	local smaller = Flat(editor, "-", 22, 20, function()
		ns.db.scale = math.max(0.6, ns.db.scale - 0.1)
		ns.PlaceHolder()
		Update()
	end)
	smaller:SetPoint("LEFT", sizeLabel, "RIGHT", 8, 0)
	editor.scaleText = Text(editor, "")
	editor.scaleText:SetPoint("LEFT", smaller, "RIGHT", 4, 0)
	editor.scaleText:SetWidth(40)
	local bigger = Flat(editor, "+", 22, 20, function()
		ns.db.scale = math.min(2, ns.db.scale + 0.1)
		ns.PlaceHolder()
		Update()
	end)
	bigger:SetPoint("LEFT", editor.scaleText, "RIGHT", 4, 0)

	editor.move = Switch(editor, "Move with mouse", 116, function(on)
		if on then ns.UnlockHolder() else ns.LockHolder() end
		Update()
	end)
	editor.move:SetPoint("TOPLEFT", PAD, top - 52)
	Tooltip(editor.move, "Move", "While this is lit, drag the icon row with the left mouse button.")
	local resetPosition = Flat(editor, "Reset position", 104, 20, function()
		ns.db.x, ns.db.y, ns.db.scale = ns.defaults.x, ns.defaults.y, ns.defaults.scale
		ns.PlaceHolder()
		Update()
	end)
	resetPosition:SetPoint("LEFT", editor.move, "RIGHT", 6, 0)
	local resetList = Flat(editor, "Reset list to class defaults", 176, 20, function()
		wipe(ns.tracks)
		for i, track in ipairs(ns.DefaultTracks()) do ns.tracks[i] = track end
		Status("List reset.", 0.4, 1, 0.5)
		Changed()
	end)
	resetList:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -PAD, top - 52)
	resetList:SetColor(C.danger)
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
