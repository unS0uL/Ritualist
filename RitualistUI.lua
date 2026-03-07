-- RitualistUI.lua
-- ROADMAP v2.1.0 Compliant UI
-- Optimized for WoW 1.12.1 (Pure Lua)

Ritualist = _G.Ritualist or {}
if not Ritualist.State then
	Ritualist.State = { Cache = { UI = {} } }
end

local function AddTooltip(frame, text)
	if not text or text == "" then
		return
	end
	frame:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(Ritualist_GetL(text), 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

Ritualist.State.Cache.MaxNameWidth = 40
Ritualist.State.Cache.MaxExecWidth = 45

-- Hidden FontString for measurements (Match font with rows)
local measurer = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
measurer:Hide()

function Ritualist:UpdateColumnWidths()
	if not Ritualist_MainFrame then
		return
	end
	local ui = self.State.Cache.UI
	local displayData = self.State.Cache.DisplayData or {}

	-- 1. Recalculate Max Widths if Dirty
	-- (Optimization: We only do this when data changed)
	if self.State.Cache.DisplayDirty or self.State.Cache.MaxNameWidth == 40 then
		local maxN, maxE = 40, 45
		for i = 1, table.getn(displayData) do
			local entry = displayData[i]
			if entry then
				local nameText = entry.name or ""
				if entry.attempts and entry.attempts > 0 then
					nameText = nameText .. " (" .. entry.attempts .. ")"
				end
				measurer:SetText(nameText)
				local nw = measurer:GetStringWidth() or 0
				if nw > maxN then
					maxN = nw
				end

				measurer:SetText(entry.executor or "")
				local ew = measurer:GetStringWidth() or 0
				if ew > maxE then
					maxE = ew
				end
			end
		end
		-- Use very generous padding (+30) to prevent wrapping of the (attempts) text
		self.State.Cache.MaxNameWidth = maxN + 30
		self.State.Cache.MaxExecWidth = maxE + 10
	end

	local maxNameW = self.State.Cache.MaxNameWidth
	local maxLockW = self.State.Cache.MaxExecWidth
	local statusW = 30
	local gap = 12

	if Ritualist_Header_Name then
		Ritualist_Header_Name:SetWidth(maxNameW)
	end
	if Ritualist_Header_Exec then
		Ritualist_Header_Exec:SetWidth(maxLockW)
		Ritualist_Header_Exec:SetPoint("TOPLEFT", 8 + statusW + maxNameW + gap, -60)
	end

	for i = 1, 10 do
		local row = ui["Ritualist_Row" .. i]
		if row then
			row.name:SetWidth(maxNameW)
			row.name:SetHeight(18) -- Lock height to prevent wrapping
			row.name:SetJustifyV("MIDDLE")
			row.executor:SetWidth(maxLockW)
			row.executor:SetHeight(18)
			row.executor:SetJustifyV("MIDDLE")
			row.executor:SetPoint("LEFT", statusW + maxNameW + gap, 0)
			row.summonAnim:ClearAllPoints()
			row.summonAnim:SetPoint("CENTER", row.frame, "LEFT", statusW + maxNameW + (gap / 2), 0)
		end
	end

	local newTotalW = 8 + statusW + maxNameW + maxLockW + (gap * 2) + 15
	if newTotalW < 160 then
		newTotalW = 160
	end
	Ritualist_MainFrame:SetWidth(newTotalW)
end

function Ritualist:CreateAnchor()
	if Ritualist_AnchorFrame then
		if RitualistDB.showAnchor then
			Ritualist_AnchorFrame:Show()
		else
			Ritualist_AnchorFrame:Hide()
		end
		return
	end

	local a = CreateFrame("Button", "Ritualist_AnchorFrame", UIParent)
	a:SetWidth(24)
	a:SetHeight(24)
	a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -50)
	a:SetMovable(true)
	a:EnableMouse(true)
	a:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	a:SetBackdropColor(0, 0, 0, 0.8)
	a:SetFrameLevel(15)

	local icon = a:CreateTexture(nil, "ARTWORK")
	icon:SetWidth(16)
	icon:SetHeight(16)
	icon:SetPoint("CENTER", 0, 0)
	icon:SetTexture("Interface\\Icons\\Spell_Shadow_SummonFelHunter")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	a:SetScript("OnMouseDown", function()
		if arg1 == "LeftButton" and IsShiftKeyDown() then
			this:StartMoving()
		end
	end)
	a:SetScript("OnMouseUp", function()
		this:StopMovingOrSizing()
		if Ritualist_MainFrame:IsShown() then
			local screenW = GetScreenWidth()
			local windowW = Ritualist_MainFrame:GetWidth()
			if this:GetLeft() + windowW > screenW then
				local newLeft = screenW - windowW
				this:ClearAllPoints()
				this:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, this:GetTop())
			end
		end
		Ritualist:SaveFramePosition()
	end)
	a:SetScript("OnClick", function()
		if Ritualist_MainFrame:IsShown() then
			Ritualist_MainFrame:Hide()
			Ritualist.State.UserOpened = false
		else
			Ritualist.State.UserOpened = true
			Ritualist_MainFrame:Show()
			Ritualist:RefreshDisplay()
		end
	end)

	if not (RitualistDB and RitualistDB.showAnchor) then
		a:Hide()
	end
end

function Ritualist:CreateMainFrame()
	if Ritualist_MainFrame then
		return
	end

	local f = CreateFrame("Frame", "Ritualist_MainFrame", UIParent)
	f:SetWidth(160)
	f:SetHeight(120)
	f:SetPoint("TOPLEFT", Ritualist_AnchorFrame or UIParent, "TOPLEFT", 0, 0)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})

	f:SetScript("OnMouseDown", function()
		if arg1 == "LeftButton" and IsShiftKeyDown() then
			if Ritualist_AnchorFrame then
				Ritualist_AnchorFrame:StartMoving()
			else
				this:StartMoving()
			end
		end
	end)
	f:SetScript("OnMouseUp", function()
		if Ritualist_AnchorFrame then
			Ritualist_AnchorFrame:StopMovingOrSizing()
			local handler = Ritualist_AnchorFrame:GetScript("OnMouseUp")
			if handler then
				handler()
			end
		else
			this:StopMovingOrSizing()
			Ritualist:SaveFramePosition()
		end
	end)
	f:SetScript("OnSizeChanged", function()
		Ritualist:UpdateColumnWidths()
	end)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -8)
	title:SetText("|cff9482c9Ritualist|r |cffccccccv" .. Ritualist.version .. "|r")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetWidth(20)
	close:SetHeight(20)
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		f:Hide()
		Ritualist.State.UserOpened = false
	end)
	AddTooltip(close, "TT_CLOSE")

	local gear = CreateFrame("Button", nil, f)
	gear:SetWidth(14)
	gear:SetHeight(14)
	gear:SetPoint("TOPRIGHT", -22, -5)
	gear:SetNormalTexture("Interface\\Icons\\INV_Gizmo_01")
	local gTex = gear:GetNormalTexture()
	if gTex then
		gTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	gear:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	gear:SetScript("OnClick", function()
		if not RitualistOptionsFrame then
			Ritualist:CreateOptionsFrame()
		end
		if RitualistOptionsFrame:IsShown() then
			RitualistOptionsFrame:Hide()
		else
			RitualistOptionsFrame:Show()
		end
	end)
	AddTooltip(gear, "TT_SETTINGS")

	local test = CreateFrame("Button", "RIT_TestBtn", f)
	test:SetWidth(14)
	test:SetHeight(14)
	test:SetPoint("RIGHT", gear, "LEFT", -4, 0)
	local tTex = test:CreateTexture(nil, "ARTWORK")
	tTex:SetTexture("Interface\\Icons\\INV_Gizmo_02")
	tTex:SetAllPoints()
	tTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	test:SetNormalTexture(tTex)
	test:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	AddTooltip(test, "TT_TEST")
	test:SetScript("OnClick", function()
		if Ritualist.RunTest then
			Ritualist:RunTest()
		end
	end)

	local shardFrame = CreateFrame("Button", "Ritualist_ShardFrame", f)
	shardFrame:SetWidth(35)
	shardFrame:SetHeight(14)
	shardFrame:SetPoint("RIGHT", title, "LEFT", -5, 0)
	AddTooltip(shardFrame, "SHARD_POOL")
	local shardIcon = shardFrame:CreateTexture(nil, "ARTWORK")
	shardIcon:SetWidth(10)
	shardIcon:SetHeight(10)
	shardIcon:SetPoint("RIGHT", 0, 0)
	shardIcon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Amethyst_02")
	local shardText = shardFrame:CreateFontString("Ritualist_ShardText", "OVERLAY", "GameFontHighlightSmall")
	shardText:SetPoint("RIGHT", shardIcon, "LEFT", -1, 0)
	shardText:SetText("0")

	local updateBtn = CreateFrame("Button", "Ritualist_UpdateBtn", f)
	updateBtn:SetWidth(100)
	updateBtn:SetHeight(14)
	updateBtn:SetPoint("TOP", title, "BOTTOM", 0, 2)
	local updateFs = updateBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	updateFs:SetAllPoints()
	updateFs:SetText("|cffff0000Update Available!|r")
	updateBtn:SetFontString(updateFs)
	updateBtn:Hide()
	updateBtn:SetScript("OnClick", function()
		Ritualist:ShowUpdateModal()
	end)

	for i = 1, 2 do
		local tab = CreateFrame("Button", "Ritualist_MainFrameTab" .. i, f, "CharacterFrameTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(i == 1 and Ritualist_GetL("MAIN_TAB") or Ritualist_GetL("HISTORY_TAB"))
		if i == 1 then
			tab:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
		else
			tab:SetPoint("LEFT", _G["Ritualist_MainFrameTab" .. (i - 1)], "RIGHT", -16, 0)
		end
		tab:SetScript("OnClick", function()
			if Ritualist.SetTab then
				Ritualist:SetTab(this:GetID())
			end
		end)
	end

	local function CreateHeader(name, txt, w, x, field, tt)
		local h = CreateFrame("Button", name, f)
		h:SetWidth(w)
		h:SetHeight(16)
		h:SetPoint("TOPLEFT", x, -60)
		local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("LEFT", 0, 0)
		fs:SetText(txt)
		h:SetScript("OnClick", function()
			if Ritualist.SetSort then
				Ritualist:SetSort(field)
			end
		end)
		if tt then
			AddTooltip(h, tt)
		end
		return h
	end

	CreateHeader("Ritualist_Header_Status", "!", 30, 8, "status", "TT_HEAD_STATUS")
	CreateHeader("Ritualist_Header_Name", Ritualist_GetL("TARGET_COL"), 70, 38, "name", "TT_HEAD_TARGET")
	CreateHeader("Ritualist_Header_Exec", Ritualist_GetL("EXECUTOR_COL"), 45, 108, "executor", "TT_HEAD_EXECUTOR")

	local scroll = CreateFrame("ScrollFrame", "Ritualist_MainScroll", f, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -75)
	scroll:SetWidth(130)
	scroll:SetHeight(180)
	scroll:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(18, function()
			Ritualist:RefreshDisplay()
		end)
	end)
	local scrollBar = _G["Ritualist_MainScrollScrollBar"]
	scrollBar:ClearAllPoints()
	scrollBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -75)
	scrollBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 30)

	for i = 1, 10 do
		local name = "Ritualist_Row" .. i
		local btn = CreateFrame("Button", name, f)
		btn:SetWidth(144)
		btn:SetHeight(18)
		btn:SetPoint("TOPLEFT", 8, -75 - (i * 18))
		btn:SetScript("OnClick", function()
			if Ritualist.SummonTarget then
				Ritualist:SummonTarget(this.targetName, this.targetGuid, arg1)
			end
		end)

		local sIcon = btn:CreateTexture(nil, "ARTWORK")
		sIcon:SetWidth(16)
		sIcon:SetHeight(16)
		sIcon:SetPoint("LEFT", 0, 0)

		local sBtn = CreateFrame("Button", nil, btn)
		sBtn:SetWidth(16)
		sBtn:SetHeight(16)
		sBtn:SetPoint("LEFT", 0, 0)
		sBtn:SetScript("OnEnter", function()
			if btn.tooltipKey then
				GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
				GameTooltip:SetText(Ritualist_GetL(btn.tooltipKey), 1, 1, 1, 1, true)
				GameTooltip:Show()
			end
		end)
		sBtn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		local sTxt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sTxt:SetPoint("LEFT", 0, 0)
		sTxt:SetWidth(30)
		sTxt:SetJustifyH("LEFT")
		sTxt:Hide()

		local n = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		n:SetPoint("LEFT", 30, 0)
		n:SetWidth(70)
		n:SetJustifyH("LEFT")

		local animFrame = CreateFrame("Frame", nil, btn)
		animFrame:SetWidth(20)
		animFrame:SetHeight(20)
		animFrame:Hide()
		local anim = animFrame:CreateTexture(nil, "OVERLAY")
		anim:SetAllPoints()
		anim:SetTexture("Interface\\Cooldown\\star4")
		anim:SetBlendMode("ADD")

		animFrame:SetScript("OnUpdate", function()
			local t = GetTime()
			local alpha = 0.4 + (math.sin(t * 15) * 0.6)
			anim:SetAlpha(alpha)
			this:SetScale(0.8 + (math.sin(t * 10) * 0.2))
		end)

		local e = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		e:SetPoint("LEFT", 100, 0)
		e:SetWidth(45)
		e:SetJustifyH("LEFT")

		Ritualist.State.Cache.UI[name] = {
			frame = btn,
			name = n,
			statusIcon = sIcon,
			statusText = sTxt,
			executor = e,
			statusBtn = sBtn,
			summonAnim = animFrame,
		}
	end

	local footer = CreateFrame("Frame", nil, f)
	footer:SetWidth(144)
	footer:SetHeight(25)
	footer:SetPoint("BOTTOMLEFT", 8, 8)

	local bcast = CreateFrame("Button", "RIT_BcastBtn", footer, "UIPanelButtonTemplate")
	bcast:SetWidth(70)
	bcast:SetHeight(18)
	bcast:SetPoint("LEFT", 0, 0)
	bcast:SetText(Ritualist_GetL("BROADCAST_BTN"))
	AddTooltip(bcast, "TT_BROADCAST")
	bcast:SetScript("OnClick", function()
		if Ritualist.Broadcast123 then
			Ritualist:Broadcast123()
		end
	end)

	local auto = CreateFrame("Button", "RIT_AutoBtn", footer, "UIPanelButtonTemplate")
	auto:SetWidth(70)
	auto:SetHeight(18)
	auto:SetPoint("RIGHT", 0, 0)
	auto:SetText(Ritualist_GetL("AUTO_SUMMON_BTN"))
	AddTooltip(auto, "TT_AUTO")
	auto:SetScript("OnClick", function()
		if Ritualist.AutoSummonNext then
			Ritualist:AutoSummonNext()
		end
	end)

	Ritualist:UpdateColumnWidths()
	Ritualist:OnDebugToggle()
	f:Hide()
end

function Ritualist:ShowUpdateModal()
	if not Ritualist_UpdateFrame then
		local f = CreateFrame("Frame", "Ritualist_UpdateFrame", UIParent)
		f:SetWidth(300)
		f:SetHeight(120)
		f:SetPoint("CENTER", 0, 100)
		f:SetFrameStrata("DIALOG")
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOP", 0, -15)
		t:SetText("|cffff0000New Version Available!|r")
		local st = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		st:SetPoint("TOP", 0, -35)
		st:SetText("Copy link to download:")
		local eb = CreateFrame("EditBox", nil, f)
		eb:SetWidth(260)
		eb:SetHeight(24)
		eb:SetPoint("CENTER", 0, -10)
		eb:SetFontObject("GameFontHighlight")
		eb:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		eb:SetBackdropColor(0, 0, 0, 0.5)
		eb:SetText("https://github.com/unS0uL/Ritualist.git")
		eb:SetScript("OnEscapePressed", function()
			f:Hide()
		end)
		local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		close:SetWidth(80)
		close:SetHeight(20)
		close:SetPoint("BOTTOM", 0, 15)
		close:SetText(Ritualist_GetL("CLOSE_BTN"))
		close:SetScript("OnClick", function()
			f:Hide()
		end)
	end
	Ritualist_UpdateFrame:Show()
end

function Ritualist:CreateOptionsFrame()
	if RitualistOptionsFrame then
		return
	end

	local f = CreateFrame("Frame", "RitualistOptionsFrame", UIParent)
	f:SetWidth(340)
	f:SetHeight(580)
	f:SetPoint("CENTER", 0, 0)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetScript("OnMouseDown", function()
		if arg1 == "LeftButton" then
			this:StartMoving()
		end
	end)
	f:SetScript("OnMouseUp", function()
		this:StopMovingOrSizing()
	end)

	tinsert(UISpecialFrames, "RitualistOptionsFrame")

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -15)
	title:SetText(Ritualist_GetL("OPT_TITLE"))

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetWidth(30)
	close:SetHeight(30)
	close:SetPoint("TOPRIGHT", -5, -5)
	AddTooltip(close, "TT_CLOSE")

	local content = CreateFrame("Frame", nil, f)
	content:SetWidth(310)
	content:SetHeight(520)
	content:SetPoint("TOPLEFT", 15, -40)

	local function CreateCheckbox(label, key, parent, x, y, tt)
		local cb = CreateFrame("CheckButton", "RIT_Opt_" .. key, parent, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", x, y)
		_G[cb:GetName() .. "Text"]:SetText(label)
		cb:SetScript("OnShow", function()
			this:SetChecked(RitualistDB and RitualistDB[key])
		end)
		cb:SetScript("OnClick", function()
			if RitualistDB then
				RitualistDB[key] = this:GetChecked()
				if key == "debug" and Ritualist.OnDebugToggle then
					Ritualist:OnDebugToggle()
				elseif key == "showAnchor" and Ritualist.CreateAnchor then
					Ritualist:CreateAnchor()
				end
			end
		end)
		if tt then
			AddTooltip(cb, tt)
		end
		return cb
	end

	CreateCheckbox(Ritualist_GetL("OPT_WHISPER"), "whisper", content, 0, 0, "TT_WHISPER")
	CreateCheckbox(Ritualist_GetL("OPT_ZONE"), "zone", content, 0, -30, "TT_ZONE")
	CreateCheckbox(Ritualist_GetL("OPT_RITUAL"), "ritual", content, 0, -60, "TT_RITUAL")
	CreateCheckbox(Ritualist_GetL("OPT_RANGE"), "rangeCheck", content, 0, -90, "TT_RANGE")
	CreateCheckbox(Ritualist_GetL("OPT_DEBUG"), "debug", content, 0, -120, "TT_DEBUG")
	CreateCheckbox(Ritualist_GetL("OPT_ANCHOR"), "showAnchor", content, 0, -150, "TT_ANCHOR")

	local chanHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	chanHeader:SetPoint("TOPLEFT", 160, 0)
	chanHeader:SetText(Ritualist_GetL("OPT_MON_HEADER"))

	local channels = {
		{ n = "Say", k = "monSay", tt = "TT_MON_SAY" },
		{ n = "Party", k = "monParty", tt = "TT_MON_PARTY" },
		{ n = "Raid", k = "monRaid", tt = "TT_MON_RAID" },
		{ n = "Guild", k = "monGuild", tt = "TT_MON_GUILD" },
		{ n = "Yell", k = "monYell", tt = "TT_MON_YELL" },
		{ n = "Whisper", k = "monWhisper", tt = "TT_MON_WHISPER" },
	}
	for i, c in ipairs(channels) do
		CreateCheckbox(c.n, c.k, content, 160, -(i * 25), c.tt)
	end

	local langLbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	langLbl:SetPoint("TOPLEFT", 0, -200)
	langLbl:SetText(Ritualist_GetL("OPT_LANG"))
	local langDrop = CreateFrame("Frame", "RIT_LangDrop", content, "UIDropDownMenuTemplate")
	langDrop:SetPoint("TOPLEFT", -15, -215)
	UIDropDownMenu_SetWidth(100, langDrop)
	UIDropDownMenu_Initialize(langDrop, function()
		local langs = {
			{ t = "EN", v = "enUS" },
			{ t = "UA", v = "ukUA" },
			{ t = "DE", v = "deDE" },
			{ t = "FR", v = "frFR" },
			{ t = "ES", v = "esES" },
			{ t = "ZH", v = "zhCN" },
		}
		for _, l in ipairs(langs) do
			UIDropDownMenu_AddButton({
				text = l.t,
				value = l.v,
				func = function()
					Ritualist:SetLanguage(this.value)
					UIDropDownMenu_SetSelectedValue(langDrop, this.value)
				end,
			})
		end
	end)
	local langLabels = { enUS = "EN", ukUA = "UA", deDE = "DE", frFR = "FR", esES = "ES", zhCN = "ZH" }
	local currentLang = RitualistDB and RitualistDB.language or "enUS"
	UIDropDownMenu_SetSelectedValue(langDrop, currentLang)
	UIDropDownMenu_SetText(langLabels[currentLang] or "EN", langDrop)

	local function CreateEB(label, key, y, default, tt)
		local lbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		lbl:SetPoint("TOPLEFT", 0, y)
		lbl:SetText(label)
		local bg = CreateFrame("Frame", nil, content)
		bg:SetWidth(290)
		bg:SetHeight(24)
		bg:SetPoint("TOPLEFT", 5, y - 15)
		bg:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		bg:SetBackdropColor(0, 0, 0, 0.5)
		bg:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
		local eb = CreateFrame("EditBox", nil, bg)
		eb:SetPoint("TOPLEFT", 5, -3)
		eb:SetPoint("BOTTOMRIGHT", -5, 3)
		eb:SetFontObject("GameFontHighlight")
		eb:SetAutoFocus(false)
		eb:SetText(RitualistDB[key] or default or "")
		eb:SetScript("OnEnterPressed", function()
			RitualistDB[key] = this:GetText()
			this:ClearFocus()
		end)
		eb:SetScript("OnEscapePressed", function()
			this:ClearFocus()
		end)
		eb:SetScript("OnEditFocusLost", function()
			RitualistDB[key] = this:GetText()
		end)
		if tt then
			AddTooltip(eb, tt)
		end
	end

	CreateEB(Ritualist_GetL("EB_SUMMON"), "summonMessage", -270, nil, "TT_EB_SUMMON")
	CreateEB(Ritualist_GetL("EB_WHISPER"), "whisperMessage", -320, nil, "TT_EB_WHISPER")
	CreateEB(Ritualist_GetL("EB_BROADCAST"), "broadcastMsg", -370, nil, "TT_EB_BROADCAST")

	local swHead = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	swHead:SetPoint("TOPLEFT", 0, -410)
	swHead:SetText(Ritualist_GetL("OPT_SW_HEADER"))
	local function CreateSWCheck(label, key, x, y, tt)
		local cb = CreateFrame("CheckButton", "RIT_SW_" .. key, content, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", x, y)
		_G[cb:GetName() .. "Text"]:SetText(label)
		cb:SetScript("OnShow", function()
			this:SetChecked(RitualistDB and RitualistDB[key])
		end)
		cb:SetScript("OnClick", function()
			if RitualistDB then
				RitualistDB[key] = this:GetChecked()
			end
		end)
		if tt then
			AddTooltip(cb, tt)
		end
	end
	CreateSWCheck("Say", "swSay", 0, -425, "TT_SW_SAY")
	CreateSWCheck("Party", "swParty", 60, -425, "TT_SW_PARTY")
	CreateSWCheck("Raid", "swRaid", 120, -425, "TT_SW_RAID")
	CreateSWCheck("Guild", "swGuild", 180, -425, "TT_SW_GUILD")
	CreateSWCheck("Yell", "swYell", 240, -425, "TT_SW_YELL")

	CreateEB(Ritualist_GetL("EB_SOULWELL"), "soulwellMsg", -460, "Cookie {HP}", "TT_EB_SOULWELL")
	f:Hide()
end
