-- The in-game editor: /denodots or /dots. Which effects and buffs are tracked, in which
-- order, whether a missing one is marked, the pet bars, the size and the position.
-- It only opens out of combat: the icon row is rebuilt on every change.
local ADDON, ns = ...

local ROWS = ns.MAX_TRACKS
local ROW_HEIGHT = 26
local editor
local rows = {}

local function Label(parent, text, template)
	local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
	label:SetText(text)
	return label
end

local function Button(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function Check(parent, text, onClick)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check.label = Label(parent, text)
	check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	check:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return check
end

local function Status(text, r, g, b)
	editor.status:SetText(text or "")
	editor.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local Update

local function Changed()
	ns.Refresh()
	Update()
end

------------------------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------------------------
local function CreateRow(index)
	local row = CreateFrame("Frame", nil, editor)
	row:SetSize(430, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 16, -58 - (index - 1) * ROW_HEIGHT)

	row.enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.enabled:SetSize(24, 24)
	row.enabled:SetPoint("LEFT", 0, 0)
	row.enabled:SetScript("OnClick", function(self)
		ns.tracks[index].enabled = self:GetChecked() and true or false
		Changed()
	end)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", row.enabled, "RIGHT", 2, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.label = Label(row, "")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetWidth(190)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row.missing = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.missing:SetSize(24, 24)
	row.missing:SetPoint("LEFT", row, "LEFT", 250, 0)
	row.missing:SetScript("OnClick", function(self)
		ns.tracks[index].missing = self:GetChecked() and true or false
		Changed()
	end)

	row.up = Button(row, "Up", 38, function()
		if index > 1 then
			ns.tracks[index], ns.tracks[index - 1] = ns.tracks[index - 1], ns.tracks[index]
			Changed()
		end
	end)
	row.up:SetPoint("LEFT", row, "LEFT", 292, 0)
	row.down = Button(row, "Down", 48, function()
		if index < #ns.tracks then
			ns.tracks[index], ns.tracks[index + 1] = ns.tracks[index + 1], ns.tracks[index]
			Changed()
		end
	end)
	row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
	row.remove = Button(row, "X", 24, function()
		table.remove(ns.tracks, index)
		Changed()
	end)
	row.remove:SetPoint("LEFT", row.down, "RIGHT", 2, 0)
	return row
end

Update = function()
	if not editor or not editor:IsShown() then return end
	for index = 1, ROWS do
		local row = rows[index]
		local track = ns.tracks[index]
		if track then
			local ids, icon = ns.Resolve(track)
			local note = track.unit == "player" and "my buff" or "on target"
			if not next(ids) then
				note = note .. ", spell not found"
			elseif not track.always and not ns.IsKnown(ids) then
				note = note .. ", not learned yet"
			end
			row.icon:SetTexture(icon)
			row.label:SetText(track.label .. "  |cff999999(" .. note .. ")|r")
			row.enabled:SetChecked(track.enabled ~= false)
			row.missing:SetChecked(track.missing ~= false)
			row:Show()
		else
			row:Hide()
		end
	end
	editor.petHealth:SetChecked(ns.db.petHealth)
	editor.petMana:SetChecked(ns.db.petMana)
	editor.numbers:SetChecked(ns.db.numbers)
	editor.scaleText:SetText(string.format("Size %d%%", math.floor(ns.db.scale * 100 + 0.5)))
	editor.move:SetText(ns.unlocked and "Lock position" or "Move with mouse")
end

------------------------------------------------------------------------------------------
-- Adding a track: one or more spell names or ids, separated by commas. Several spells in
-- one icon means "any of these" (one bane, one curse, one armor).
------------------------------------------------------------------------------------------
local function Add(unit)
	local text = editor.input:GetText() or ""
	local spells, label = {}, nil
	for part in string.gmatch(text, "[^,]+") do
		part = strtrim(part)
		if part ~= "" then
			local id = tonumber(part)
			if id then
				local name = C_Spell.GetSpellName(id)
				if not name then
					Status("No spell has the id " .. part .. ".", 1, 0.3, 0.3)
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
					Status("\"" .. part .. "\" is not a spell name I know. Try its spell id.", 1, 0.3, 0.3)
					return
				end
			end
		end
	end
	if #spells == 0 then
		Status("Type a spell name or a spell id first.", 1, 0.3, 0.3)
		return
	end
	if #ns.tracks >= ns.MAX_TRACKS then
		Status("The list is full (" .. ns.MAX_TRACKS .. "). Remove one first.", 1, 0.3, 0.3)
		return
	end
	ns.tracks[#ns.tracks + 1] = { label = label, unit = unit, spells = spells, enabled = true, missing = true, always = true }
	editor.input:SetText("")
	editor.input:ClearFocus()
	Status("Added " .. label .. ".", 0.3, 1, 0.3)
	Changed()
end

------------------------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------------------------
local function CreateEditor()
	editor = CreateFrame("Frame", "DenoDotsEditor", UIParent, "BasicFrameTemplateWithInset")
	editor:SetSize(470, 520)
	editor:SetPoint("CENTER")
	editor:SetFrameStrata("DIALOG")
	editor:SetMovable(true)
	editor:EnableMouse(true)
	editor:RegisterForDrag("LeftButton")
	editor:SetScript("OnDragStart", editor.StartMoving)
	editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
	editor:SetScript("OnHide", function() ns.LockHolder() end)
	tinsert(UISpecialFrames, "DenoDotsEditor")
	if editor.TitleText then editor.TitleText:SetText("Deno Dots") end

	local head = Label(editor, "On   Tracked", "GameFontNormalSmall")
	head:SetPoint("TOPLEFT", 18, -40)
	local headMissing = Label(editor, "Mark missing", "GameFontNormalSmall")
	headMissing:SetPoint("TOPLEFT", 240, -40)
	for index = 1, ROWS do rows[index] = CreateRow(index) end

	local top = -58 - ROWS * ROW_HEIGHT - 8
	local addLabel = Label(editor, "Add: spell name or id (several with commas = any of them)", "GameFontNormalSmall")
	addLabel:SetPoint("TOPLEFT", 18, top)
	editor.input = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
	editor.input:SetSize(200, 22)
	editor.input:SetPoint("TOPLEFT", 24, top - 16)
	editor.input:SetAutoFocus(false)
	editor.input:SetScript("OnEnterPressed", function() Add("target") end)
	editor.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	local addTarget = Button(editor, "On target", 96, function() Add("target") end)
	addTarget:SetPoint("LEFT", editor.input, "RIGHT", 8, 0)
	local addBuff = Button(editor, "My buff", 96, function() Add("player") end)
	addBuff:SetPoint("LEFT", addTarget, "RIGHT", 4, 0)
	editor.status = Label(editor, "")
	editor.status:SetPoint("TOPLEFT", 18, top - 44)
	editor.status:SetWidth(430)
	editor.status:SetJustifyH("LEFT")

	top = top - 66
	editor.petHealth = Check(editor, "Pet health bar", function(on) ns.db.petHealth = on; Changed() end)
	editor.petHealth:SetPoint("TOPLEFT", 16, top)
	editor.petMana = Check(editor, "Pet mana bar", function(on) ns.db.petMana = on; Changed() end)
	editor.petMana:SetPoint("TOPLEFT", 160, top)
	editor.numbers = Check(editor, "Numbers on the bars", function(on) ns.db.numbers = on; Changed() end)
	editor.numbers:SetPoint("TOPLEFT", 300, top)

	top = top - 32
	local smaller = Button(editor, "-", 24, function()
		ns.db.scale = math.max(0.6, ns.db.scale - 0.1)
		ns.PlaceHolder()
		Update()
	end)
	smaller:SetPoint("TOPLEFT", 18, top)
	editor.scaleText = Label(editor, "")
	editor.scaleText:SetPoint("LEFT", smaller, "RIGHT", 6, 0)
	editor.scaleText:SetWidth(70)
	local bigger = Button(editor, "+", 24, function()
		ns.db.scale = math.min(2, ns.db.scale + 0.1)
		ns.PlaceHolder()
		Update()
	end)
	bigger:SetPoint("LEFT", editor.scaleText, "RIGHT", 6, 0)
	editor.move = Button(editor, "Move with mouse", 130, function()
		if ns.unlocked then ns.LockHolder() else ns.UnlockHolder() end
		Update()
	end)
	editor.move:SetPoint("LEFT", bigger, "RIGHT", 14, 0)
	local resetPosition = Button(editor, "Reset position", 110, function()
		ns.db.x, ns.db.y, ns.db.scale = ns.defaults.x, ns.defaults.y, ns.defaults.scale
		ns.PlaceHolder()
		Update()
	end)
	resetPosition:SetPoint("LEFT", editor.move, "RIGHT", 4, 0)

	local resetList = Button(editor, "Reset list to class defaults", 200, function()
		wipe(ns.tracks)
		for i, track in ipairs(ns.DefaultTracks()) do ns.tracks[i] = track end
		Status("List reset.", 0.3, 1, 0.3)
		Changed()
	end)
	resetList:SetPoint("BOTTOMLEFT", 18, 14)
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
