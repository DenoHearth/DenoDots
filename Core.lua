-- Deno Dots for WoW: Forever (interface 16001).
-- A row of small icons above the player frame: your effects on the target, buffs on you
-- and your pet, reminders for buffs that are missing and cooldowns, each with its time
-- left. Under the row, pet health and mana.
--
-- The addon never reads an aura. Blizzard's aura container fills an icon while the aura is
-- up and hides it when it is not; the "missing" picture simply lies underneath.
local ADDON, ns = ...

ns.WHITE = "Interface\\Buttons\\WHITE8X8"
ns.ICON = 30          -- icon size
ns.GAP = 4            -- space between icons
ns.MAX_TRACKS = 10

-- What an icon watches and how it behaves. unit + filter go to the aura container.
ns.KINDS = {
	dot = { label = "DoT", unit = "target", filter = "HARMFUL|PLAYER", color = { 0.72, 0.42, 0.95 },
		hint = "Your own effect on the target. Timer, glow when it runs out, grey when missing." },
	debuff = { label = "Debuff", unit = "target", filter = "HARMFUL", color = { 0.95, 0.42, 0.36 },
		hint = "The effect on the target, whoever cast it." },
	buff = { label = "Buff", unit = "player", filter = "HELPFUL", color = { 0.36, 0.78, 0.44 },
		hint = "A buff on you. Shown while it is up, grey when missing." },
	reminder = { label = "Reminder", unit = "player", filter = "HELPFUL", color = { 0.96, 0.74, 0.28 },
		onlyWhenMissing = true, hint = "A buff on you. No icon while it is up; a grey icon when it is missing." },
	pet = { label = "Pet buff", unit = "pet", filter = "HELPFUL", color = { 0.38, 0.68, 0.96 },
		hint = "A buff on your pet." },
	cooldown = { label = "Cooldown", color = { 0.62, 0.66, 0.72 },
		hint = "One of your spells: the time until it is ready again." },
}
ns.KIND_ORDER = { "dot", "debuff", "buff", "reminder", "pet", "cooldown" }

-- Which switches a kind has in the editor.
ns.KIND_SWITCHES = {
	dot = { missing = true, glow = true, timer = true, combat = true },
	debuff = { missing = true, glow = true, timer = true, combat = true },
	buff = { missing = true, glow = true, timer = true, combat = true },
	reminder = { glow = true, combat = true },
	pet = { missing = true, glow = true, timer = true, combat = true },
	cooldown = { timer = true, glow = true, combat = true },
}

-- A track is one icon.
--   label    shown in the editor
--   kind     a key of ns.KINDS
--   spells   spell names (every rank is looked up in Data.lua) and/or spell ids; the icon
--            shows the first of them that is found
--   missing  show the grey icon while none of the spells is up
--   glow     proc glow in the last seconds
--   timer    seconds left on the icon
--   always   show the icon even when the character knows none of the spells
local CLASS_DEFAULTS = {
	WARLOCK = {
		{ label = "Corruption", kind = "dot", spells = { "corruption" } },
		{ label = "Immolate", kind = "dot", spells = { "immolate" } },
		{ label = "Bane", kind = "dot", spells = { "bane of agony", "bane of doom", "bane of havoc" } },
		{ label = "Curse", kind = "dot", spells = { "curse of the elements", "curse of weakness",
			"curse of recklessness", "curse of tongues", "curse of exhaustion", "curse of idiocy" } },
		{ label = "Armor", kind = "reminder", spells = { "demon skin", "demon armor", "fel armor" } },
	},
	-- 1.5.0 (his ask, 2026-11-10, after the mock-up: "build it with better glows"). On Forever
	-- Judgement no longer uses up the Seal and its debuff lasts 40 s, so the Seal, the
	-- Judgement on the target and the Judgement cooldown are three icons. The tank icons start
	-- switched off; one tick in the editor each.
	PALADIN = {
		{ label = "Seal", kind = "buff", glow = true, spells = { "seal of righteousness", "seal of command",
			"seal of the crusader", "seal of light", "seal of wisdom", "seal of justice", "seal of fury",
			"seal of martyrdom" } },
		{ label = "Judgement", kind = "dot", bar = "judgement", spells = { "judgement of righteousness", "judgement of command",
			"judgement of the crusader", "judgement of light", "judgement of wisdom", "judgement of justice",
			"judgement of fury", "judgement of martyrdom" } },
		{ label = "Judgement ready", kind = "cooldown", glow = true, spells = { "judgement" } },
		{ label = "Consecration", kind = "cooldown", glow = false, spells = { "consecration" } },
		{ label = "Holy Shield", kind = "cooldown", glow = true, enabled = false, spells = { "holy shield" } },
		{ label = "Aura", kind = "reminder", spells = { "devotion aura", "retribution aura", "concentration aura",
			"shadow resistance aura", "frost resistance aura", "fire resistance aura" } },
		{ label = "Blessing", kind = "reminder", spells = { "blessing of might", "blessing of wisdom",
			"blessing of kings", "blessing of light", "blessing of salvation", "greater blessing of might",
			"greater blessing of wisdom", "greater blessing of kings", "greater blessing of light",
			"greater blessing of salvation" } },
		{ label = "Righteous Fury", kind = "reminder", enabled = false, spells = { "righteous fury" } },
	},
}

ns.defaults = {
	x = 88, y = -6,       -- offset from the top left corner of the player frame
	scale = 1,
	-- off since 1.3.1 (his ask, 2026-11-05: the pet showed twice, here and in Deno Nameplate's
	-- demon frame; "remove the upper one"); the editor's Pet health / Pet mana switches bring them back
	petHealth = false,
	petMana = false,
	numbers = true,
	minimapShow = true,   -- 1.4.0: minimap button (Menu.lua), picked up by Button Drawer
	minimapAngle = 220,
	glowSeconds = 3,      -- the glow and the red number start this many seconds before the end
	clickCast = true,     -- a click on an icon casts its spell
	barMode = false,      -- 1.7.0: no icon row, the glows sit on the action buttons instead
	classes = {},
}

function ns.Print(text)
	print("|cff9482c9Deno Dots|r: " .. text)
end

-- A value the client may hand back as a secret is never tested; the fallback is used.
function ns.Plain(value, fallback)
	if issecretvalue and issecretvalue(value) then return fallback end
	return value
end

-- Fills in what a track does not say, and reads the fields of version 1.0.
function ns.Normalize(track)
	if not ns.KINDS[track.kind] then
		if track.unit == "player" then
			track.kind = track.hideWhenUp == false and "buff" or "reminder"
		else
			track.kind = "dot"
		end
	end
	track.unit, track.hideWhenUp = nil, nil
	local onTarget = track.kind == "dot" or track.kind == "debuff"
	if track.enabled == nil then track.enabled = true end
	if track.missing == nil then track.missing = true end
	-- 1.5.0: reminders glow while missing and cooldowns glow in combat once ready; a new one
	-- starts with the glow on. Saved tracks keep what they had.
	if track.glow == nil then track.glow = onTarget or track.kind == "reminder" or track.kind == "cooldown" end
	if track.timer == nil then track.timer = true end
	-- 1.6.0 (his ask, 2026-11-10): Judgement, DoTs and buffs only in combat, reminders all the
	-- time. Saved tracks from before take the same split.
	if track.combat == nil then track.combat = track.kind ~= "reminder" end
	track.spells = track.spells or {}
	track.label = track.label or "?"
	return track
end

function ns.NewTrack(label, kind, spells, always)
	return ns.Normalize({ label = label, kind = kind, spells = spells, always = always or nil })
end

function ns.OnlyWhenMissing(track)
	return ns.KINDS[track.kind].onlyWhenMissing == true
end

function ns.DefaultTracks()
	local tracks = {}
	for i, track in ipairs(CLASS_DEFAULTS[ns.class] or {}) do
		local spells = {}
		for index, spell in ipairs(track.spells) do spells[index] = spell end
		tracks[i] = ns.NewTrack(track.label, track.kind, spells)
		tracks[i].bar = track.bar   -- the spell on the action bar when it is not one of the list
		if track.glow ~= nil then tracks[i].glow = track.glow end
		if track.enabled ~= nil then tracks[i].enabled = track.enabled end
	end
	return tracks
end

-- Spell ids and the icon of a track. Names go through the generated table, so one name
-- covers every rank; a name the table does not know is asked of the client.
function ns.Resolve(track)
	local ids, icon = {}, nil
	for _, spell in ipairs(track.spells) do
		if type(spell) == "number" then
			ids[spell] = true
			icon = icon or C_Spell.GetSpellTexture(spell)
		else
			local family = ns.families[spell]
			if family then
				icon = icon or family[1]
				for i = 2, #family do ids[family[i]] = true end
			else
				local info = C_Spell.GetSpellInfo(spell)
				if info and info.spellID then
					ids[info.spellID] = true
					icon = icon or info.iconID
				end
			end
		end
	end
	return ids, icon or 134400
end

-- The spell a click on the icon casts, by name (the game then takes the highest rank you
-- know). Several spells in one icon: a buff or reminder takes the last one you know (Fel
-- Armor before Demon Skin), an effect on the target the first (the list order is yours).
function ns.CastName(track)
	local kind = ns.KINDS[track.kind]
	local first, last, step = 1, #track.spells, 1
	if kind and kind.unit ~= "target" then first, last, step = #track.spells, 1, -1 end
	for index = first, last, step do
		local spell = track.spells[index]
		if type(spell) == "number" then
			if C_SpellBook.IsSpellKnown(spell) then return C_Spell.GetSpellName(spell) end
		else
			local family = ns.families[spell]
			if family then
				for rank = #family, 2, -1 do
					if C_SpellBook.IsSpellKnown(family[rank]) then return C_Spell.GetSpellName(family[rank]) end
				end
			end
		end
	end
end

-- One of the ids the character knows, or nil.
function ns.KnownSpell(ids)
	for id in pairs(ids) do
		if C_SpellBook.IsSpellKnown(id) then return id end
	end
end

-- An effect whose own ids are never "known" (the Judgement debuffs): known when the spell
-- that puts it there (track.bar) is. Returns that spell's id.
function ns.BarSpellKnown(track)
	if not track.bar then return end
	local info = C_Spell.GetSpellInfo(track.bar)
	if info and info.spellID and C_SpellBook.IsSpellKnown(info.spellID) then return info.spellID end
end

function ns.IsKnown(ids)
	return ns.KnownSpell(ids) ~= nil
end

------------------------------------------------------------------------------------------
-- Changes to the row wait for the end of combat: aura containers are set up out of combat.
------------------------------------------------------------------------------------------
local pending = false

-- Each class keeps its own list.
local function SelectClass()
	local class = UnitClassBase("player")
	if class == ns.class and ns.tracks then return end
	ns.class = class
	if not ns.db.classes[class] then ns.db.classes[class] = { tracks = ns.DefaultTracks() } end
	-- 1.5.0, once: a class that had no defaults before (a paladin logged in with 1.4.0 saved
	-- an empty list) gets the new ones; a list with anything in it stays as it is
	local saved = ns.db.classes[class]
	if not saved.defaults15 then
		saved.defaults15 = true
		if #saved.tracks == 0 then saved.tracks = ns.DefaultTracks() end
	end
	-- 1.7.1, once: lists saved before the "bar" field (paladin Judgement) take it from the defaults
	if not saved.bar171 then
		saved.bar171 = true
		for _, default in ipairs(CLASS_DEFAULTS[class] or {}) do
			if default.bar then
				for _, track in ipairs(saved.tracks) do
					if track.bar == nil and track.label == default.label and track.kind == default.kind then
						track.bar = default.bar
					end
				end
			end
		end
	end
	ns.tracks = saved.tracks
	for _, track in ipairs(ns.tracks) do ns.Normalize(track) end
end

-- force: rebuild although the lockdown flag may already be set (PLAYER_REGEN_DISABLED)
function ns.Refresh(force)
	if InCombatLockdown() and not force then
		pending = true
		return
	end
	pending = false
	SelectClass()
	ns.BuildTracks()
	ns.LayoutPetBars()
	ns.UpdateMarkers()
	ns.UpdateCooldowns()
	ns.UpdateReadyGlows(ns.inCombat)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		DenoDotsDB = DenoDotsDB or {}
		ns.db = DenoDotsDB
		for key, value in pairs(ns.defaults) do
			if ns.db[key] == nil then ns.db[key] = type(value) == "table" and {} or value end
		end
		-- 1.3.1: once, saved settings from before take the new default too
		if not ns.db.petBarsOff then
			ns.db.petBarsOff = true
			ns.db.petHealth, ns.db.petMana = false, false
		end
		ns.db.glowSeconds = ns.SetGlowSeconds(ns.db.glowSeconds)
		ns.inCombat = InCombatLockdown()
		ns.CreateHolder()
		ns.CreatePetBars()
		ns.Refresh()
		ns.StartMenu()
		for _, name in ipairs({ "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
			"PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_COOLDOWN",
			"EDIT_MODE_LAYOUTS_UPDATED", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED" }) do
			events:RegisterEvent(name)
		end
		events:RegisterUnitEvent("UNIT_PET", "player")
	elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_PET" then
		ns.UpdateMarkers()
		if event == "PLAYER_TARGET_CHANGED" then ns.RescanAuras(true) end
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		ns.UpdateCooldowns()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- the lockdown starts after this event: the last moment the row can be rebuilt, so the
		-- "in combat only" icons come in here
		ns.inCombat = true
		ns.LockHolder()
		if ns.CloseEditor then ns.CloseEditor() end
		ns.LayoutRow()
		ns.RescanAuras()
		ns.UpdateCooldowns()
		ns.UpdateReadyGlows(true)
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.inCombat = false
		if pending then ns.Refresh() else ns.LayoutRow() end
		ns.UpdateReadyGlows(false)
	elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" then
		-- the glows follow the spells on the bars; many of these come at once
		if not ns.barQueued then
			ns.barQueued = true
			C_Timer.After(0.3, function()
				ns.barQueued = false
				ns.Refresh()
			end)
		end
	elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
		if not InCombatLockdown() then ns.Refresh() end
		-- the player frame may have moved: above it if there is room, under it if not
		if not InCombatLockdown() then ns.PlaceHolder() end
	else
		if event == "PLAYER_ENTERING_WORLD" and not InCombatLockdown() then ns.PlaceHolder() end
		ns.Refresh()
	end
end)

SLASH_DENODOTS1 = "/denodots"
SLASH_DENODOTS2 = "/dots"
SlashCmdList.DENODOTS = function()
	ns.OpenEditor()
end
