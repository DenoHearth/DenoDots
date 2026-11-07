-- The ways in to the editor besides /dots (his ask, 2026-11-05: "I dont see deno dots in my
-- interface options or my minimap button drawer"): a page in the game's Options > AddOns and a
-- minimap button. The button is named like a LibDBIcon button so minimap button collectors
-- (Button Drawer) pick it up. Left-click opens the editor, drag moves it around the minimap rim.
local ADDON, ns = ...

local button

local function Place()
	local angle = math.rad(ns.db.minimapAngle)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
	if button then button:SetShown(ns.db.minimapShow and true or false) end
end

local function CreateMinimapButton()
	button = CreateFrame("Button", "LibDBIcon10_DenoDots", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture("Interface\\Icons\\Spell_Shadow_AbominationExplosion")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", function() ns.OpenEditor() end)

	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
			Place()
		end)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Deno Dots")
		GameTooltip:AddLine("Click: open the editor (the DoTs and buffs it tracks)", 1, 1, 1)
		GameTooltip:AddLine("Drag: move", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	Place()
	ns.UpdateMinimapButton()
end

-- Options > AddOns > Deno Dots: everything is set in the editor, so the page is a way to it,
-- plus the minimap button switch.
local function CreateOptionsPage()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local page = CreateFrame("Frame")

	local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Deno Dots")

	local text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetWidth(560)
	text:SetJustifyH("LEFT")
	text:SetText("The DoTs, debuffs, buffs, reminders and cooldowns shown above your player frame, "
		.. "their order, the glow, the pet bars, the size and the place are all set in the editor. "
		.. "It opens out of combat. Also: /dots")

	local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	open:SetSize(160, 26)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
	open:SetText("Open Editor")
	open:SetScript("OnClick", function() ns.OpenEditor() end)

	local show = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	show:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -2, -14)
	show.label = show:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	show.label:SetPoint("LEFT", show, "RIGHT", 4, 0)
	show.label:SetText("Show Minimap Button")
	show:SetScript("OnClick", function(self)
		ns.db.minimapShow = self:GetChecked() and true or false
		ns.UpdateMinimapButton()
	end)
	page:SetScript("OnShow", function() show:SetChecked(ns.db.minimapShow and true or false) end)

	local category = Settings.RegisterCanvasLayoutCategory(page, "Deno Dots")
	Settings.RegisterAddOnCategory(category)
	ns.category = category
end

-- On the next frame after login, not in the login event: setup work in the client's own login
-- run tainted it (Deno Nameplate, probe 2026-10-19).
function ns.StartMenu()
	C_Timer.After(0, function()
		CreateMinimapButton()
		CreateOptionsPage()
	end)
end
