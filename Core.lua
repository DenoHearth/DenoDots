-- Deno Dots for WoW: Forever (interface 16001).
-- A row of small icons above the player frame: your effects on the target and your own
-- buffs, each with its time left, and a red-framed grey icon where one is missing. Under
-- the row, pet health and mana.
--
-- The addon never reads an aura. Blizzard's aura container fills an icon while the aura is
-- up and hides it when it is not; the "missing" picture simply lies underneath.
local ADDON, ns = ...

ns.WHITE = "Interface\\Buttons\\WHITE8X8"
ns.ICON = 30          -- icon size
ns.GAP = 4            -- space between icons
ns.MAX_TRACKS = 10

-- A track is one icon: the first aura found out of a list of spells, on one unit.
--   label    shown in the editor
--   unit     "target" (your harmful effects on it) or "player" (your buffs)
--   spells   spell names (every rank is looked up in Data.lua) and/or spell ids
--   missing  show the grey icon while none of the spells is up
--   always   show the icon even when the character knows none of the spells
local CLASS_DEFAULTS = {
	WARLOCK = {
		{ label = "Corruption", unit = "target", spells = { "corruption" } },
		{ label = "Immolate", unit = "target", spells = { "immolate" } },
		{ label = "Bane", unit = "target", spells = { "bane of agony", "bane of doom", "bane of havoc" } },
		{ label = "Curse", unit = "target", spells = { "curse of the elements", "curse of weakness",
			"curse of recklessness", "curse of tongues", "curse of exhaustion", "curse of idiocy" } },
		{ label = "Armor", unit = "player", spells = { "demon skin", "demon armor", "fel armor" } },
	},
}

ns.defaults = {
	x = 88, y = -6,       -- offset from the top left corner of the player frame
	scale = 1,
	petHealth = true,
	petMana = true,
	numbers = true,
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

local function CopyTrack(track)
	local copy = { label = track.label, unit = track.unit, spells = {}, enabled = track.enabled ~= false,
		missing = track.missing ~= false, always = track.always == true }
	for i, spell in ipairs(track.spells) do copy.spells[i] = spell end
	return copy
end

function ns.DefaultTracks()
	local tracks = {}
	for i, track in ipairs(CLASS_DEFAULTS[ns.class] or {}) do tracks[i] = CopyTrack(track) end
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

function ns.IsKnown(ids)
	for id in pairs(ids) do
		if C_SpellBook.IsSpellKnown(id) then return true end
	end
	return false
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
	ns.UpdateTarget()
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
		ns.CreateHolder()
		ns.CreatePetBars()
		ns.Refresh()
		for _, name in ipairs({ "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
			"PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD" }) do
			events:RegisterEvent(name)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		ns.UpdateTarget()
	elseif event == "PLAYER_REGEN_DISABLED" then
		ns.LockHolder()
		if ns.CloseEditor then ns.CloseEditor() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then ns.Refresh() end
	else
		ns.Refresh()
	end
end)

SLASH_DENODOTS1 = "/denodots"
SLASH_DENODOTS2 = "/dots"
SlashCmdList.DENODOTS = function()
	ns.OpenEditor()
end
