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
	dot = { missing = true, glow = true, timer = true },
	debuff = { missing = true, glow = true, timer = true },
	buff = { missing = true, glow = true, timer = true },
	reminder = {},
	pet = { missing = true, glow = true, timer = true },
	cooldown = { timer = true },
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
}

ns.defaults = {
	x = 88, y = -6,       -- offset from the top left corner of the player frame
	scale = 1,
	petHealth = true,
	petMana = true,
	numbers = true,
	glowSeconds = 3,      -- the glow and the red number start this many seconds before the end
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
	if track.glow == nil then track.glow = onTarget end
	if track.timer == nil then track.timer = true end
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

-- One of the ids the character knows, or nil.
function ns.KnownSpell(ids)
	for id in pairs(ids) do
		if C_SpellBook.IsSpellKnown(id) then return id end
	end
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
	ns.tracks = ns.db.classes[class].tracks
	for _, track in ipairs(ns.tracks) do ns.Normalize(track) end
end

function ns.Refresh()
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	SelectClass()
	ns.BuildTracks()
	ns.LayoutPetBars()
	ns.UpdateMarkers()
	ns.UpdateCooldowns()
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
		ns.db.glowSeconds = ns.SetGlowSeconds(ns.db.glowSeconds)
		ns.CreateHolder()
		ns.CreatePetBars()
		ns.Refresh()
		for _, name in ipairs({ "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
			"PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_COOLDOWN",
			"EDIT_MODE_LAYOUTS_UPDATED" }) do
			events:RegisterEvent(name)
		end
		events:RegisterUnitEvent("UNIT_PET", "player")
	elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_PET" then
		ns.UpdateMarkers()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		ns.UpdateCooldowns()
	elseif event == "PLAYER_REGEN_DISABLED" then
		ns.LockHolder()
		if ns.CloseEditor then ns.CloseEditor() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then ns.Refresh() end
	elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
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
