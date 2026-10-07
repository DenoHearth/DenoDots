-- Pet health and mana under the icon row. Health and power are secret values in combat:
-- they go from the API straight into the bar and the text, never through a Lua operator.
local ADDON, ns = ...

local UNIT = "pet"
local HEIGHT = 9
local POWER_COLORS = {
	MANA = { 0.15, 0.35, 0.95 }, ENERGY = { 0.95, 0.85, 0.2 }, RAGE = { 0.9, 0.15, 0.15 },
	FOCUS = { 0.95, 0.55, 0.25 },
}
local health, power

local function NewBar(r, g, b)
	local bar = CreateFrame("StatusBar", nil, ns.holder)
	bar:SetHeight(HEIGHT)
	bar:SetStatusBarTexture(ns.WHITE)
	bar:SetStatusBarColor(r, g, b)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.7)
	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontWhiteTiny")
	bar.text:SetPoint("CENTER", 0, 0)
	bar:Hide()
	return bar
end

local function UpdateHealth()
	health:SetMinMaxValues(0, UnitHealthMax(UNIT))
	health:SetValue(UnitHealth(UNIT))
	if ns.db.numbers then
		health.text:SetFormattedText("%s", AbbreviateNumbers(UnitHealth(UNIT)))
	else
		health.text:SetText("")
	end
end

local function UpdatePower()
	power:SetMinMaxValues(0, UnitPowerMax(UNIT))
	power:SetValue(UnitPower(UNIT))
	if ns.db.numbers then
		power.text:SetFormattedText("%s", AbbreviateNumbers(UnitPower(UNIT)))
	else
		power.text:SetText("")
	end
end

local function UpdatePowerColor()
	local _, token = UnitPowerType(UNIT)
	local color = POWER_COLORS[token] or POWER_COLORS.MANA
	power:SetStatusBarColor(color[1], color[2], color[3])
end

-- Whether a pet exists is plain data. The bars are ours, so showing them in combat is free.
local function UpdateShown()
	local exists = ns.Plain(UnitExists(UNIT), false)
	health:SetShown(exists and ns.db.petHealth)
	power:SetShown(exists and ns.db.petMana)
	if exists then
		UpdatePowerColor()
		UpdateHealth()
		UpdatePower()
	end
end

function ns.LayoutPetBars()
	local top = -(ns.ICON + 4)
	health:ClearAllPoints()
	health:SetPoint("TOPLEFT", ns.holder, "TOPLEFT", 0, top)
	health:SetWidth(ns.rowWidth or 98)
	power:ClearAllPoints()
	power:SetPoint("TOPLEFT", ns.holder, "TOPLEFT", 0, ns.db.petHealth and (top - HEIGHT - 1) or top)
	power:SetWidth(ns.rowWidth or 98)
	UpdateShown()
end

function ns.CreatePetBars()
	health = NewBar(0.15, 0.7, 0.15)
	power = NewBar(0.15, 0.35, 0.95)
	local events = CreateFrame("Frame")
	events:RegisterUnitEvent("UNIT_PET", "player")
	events:RegisterUnitEvent("UNIT_HEALTH", UNIT)
	events:RegisterUnitEvent("UNIT_MAXHEALTH", UNIT)
	events:RegisterUnitEvent("UNIT_POWER_UPDATE", UNIT)
	events:RegisterUnitEvent("UNIT_MAXPOWER", UNIT)
	events:RegisterUnitEvent("UNIT_DISPLAYPOWER", UNIT)
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function(_, event)
		if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
			if health:IsShown() then UpdateHealth() end
		elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
			if power:IsShown() then UpdatePower() end
		else
			UpdateShown()
		end
	end)
end
