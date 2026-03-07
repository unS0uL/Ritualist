-- Ritualist.lua
-- Pure Lua Edition for WoW 1.12.1 (v1.1.5)
-- Optimized for Nampower & pfUI Style.
--
-- Disclaimer: This project is an independent community-driven modification for World of Warcraft 1.12.1.
-- It is not affiliated with, endorsed by, or connected to Blizzard Entertainment,
-- Turtle WoW administration, or any other private server entity.
-- The code is provided "as is" for educational and interface enhancement purposes only.

Ritualist = _G.Ritualist or {}
Ritualist.version = "1.1.5"
Ritualist.currentTab = 1
Ritualist.Registry = Ritualist.Registry or {}
Ritualist.BlockedRegistry = Ritualist.BlockedRegistry or {}
Ritualist.History = Ritualist.History or {}
Ritualist.State = Ritualist.State or {}
Ritualist.State.Cache = Ritualist.State.Cache or { UI = {} }
Ritualist.State.ShardPool = Ritualist.State.ShardPool or {}
Ritualist.State.LastSync = Ritualist.State.LastSync or 0
Ritualist.State.Sort = Ritualist.State.Sort or { field = "status", asc = true }
Ritualist.State.RemoteVersion = nil
Ritualist.State.LastChatAlert = 0
Ritualist.State.PendingSummons = {}
Ritualist.State.AutoSummonTimeouts = {}
Ritualist.State.ActiveClickers = {}
Ritualist.State.AddonUsers = {}
Ritualist.State.LastClickerCount = 0
Ritualist.State.SentClickInstruction = false
Ritualist.State.Last30sAlert = 0

local B64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz./"
local function toB64(val)
	return string.sub(B64, val + 1, val + 1)
end
local function fromB64(char)
	return (string.find(B64, char, 1, true) or 1) - 1
end

local CLASS_MAP = {
	WARRIOR = 1,
	PRIEST = 2,
	MAGE = 3,
	ROGUE = 4,
	DRUID = 5,
	PALADIN = 6,
	HUNTER = 7,
	SHAMAN = 8,
	WARLOCK = 9,
}
local CLASS_REV = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "PALADIN", "HUNTER", "SHAMAN", "WARLOCK" }
local STATUS_MAP = {
	WAITING = 1,
	SUMMONING = 2,
	NEARBY = 3,
	WRONG_ZONE = 4,
	COMBAT = 5,
	DEAD = 6,
	OFFLINE = 7,
	TIMEOUT = 8,
	DONE = 9,
}
local STATUS_REV = { "WAITING", "SUMMONING", "NEARBY", "WRONG_ZONE", "COMBAT", "DEAD", "OFFLINE", "TIMEOUT", "DONE" }

function Ritualist:GetChecksum(name)
	if not name or name == "" then
		return 0
	end
	local sum = 0
	for i = 1, string.len(name) do
		sum = sum + string.byte(string.sub(name, i, i))
	end
	return math.mod(sum, 64)
end

Ritualist.UNIT_ID_CACHE = { RAID = {}, PARTY = {}, RAID_TARGET = {}, PARTY_TARGET = {} }
Ritualist.GUID_NAME_CACHE = {}
Ritualist.NAME_UNIT_CACHE = {}
Ritualist.WARLOCK_CACHE = {} -- [guid] = { name = name, unit = unit, targetUnit = targetUnit }
local WORLD_ZONES_CACHE = {}

function Ritualist:UpdateWorldZonesCache()
	for k in pairs(WORLD_ZONES_CACHE) do
		WORLD_ZONES_CACHE[k] = nil
	end
	local continents = { GetMapContinents() }
	for i = 1, table.getn(continents) do
		local zones = { GetMapZones(i) }
		for _, zName in ipairs(zones) do
			WORLD_ZONES_CACHE[zName] = true
		end
	end
	WORLD_ZONES_CACHE["Azeroth"] = true
	WORLD_ZONES_CACHE["Kalimdor"] = true
	WORLD_ZONES_CACHE["Eastern Kingdoms"] = true
end

function Ritualist:UpdateGUIDCache()
	for k in pairs(Ritualist.GUID_NAME_CACHE) do
		Ritualist.GUID_NAME_CACHE[k] = nil
	end
	for k in pairs(Ritualist.NAME_UNIT_CACHE) do
		Ritualist.NAME_UNIT_CACHE[k] = nil
	end
	for k in pairs(Ritualist.WARLOCK_CACHE) do
		Ritualist.WARLOCK_CACHE[k] = nil
	end

	local currentNames = {}
	local num = GetNumRaidMembers()
	local unitBase = "RAID"
	if num == 0 then
		num = GetNumPartyMembers()
		unitBase = "PARTY"
	end

	local function ScanUnit(u, t)
		if u and UnitExists(u) and UnitGUID then
			local guid = UnitGUID(u)
			if guid then
				local name = UnitName(u)
				Ritualist.GUID_NAME_CACHE[guid] = name
				Ritualist.NAME_UNIT_CACHE[name] = u
				currentNames[name] = true
				local _, class = UnitClass(u)
				if class == "WARLOCK" then
					Ritualist.WARLOCK_CACHE[guid] = { name = name, unit = u, targetUnit = t }
				end
			end
		end
	end

	if num > 0 then
		for i = 1, num do
			ScanUnit(Ritualist.UNIT_ID_CACHE[unitBase][i], Ritualist.UNIT_ID_CACHE[unitBase .. "_TARGET"][i])
		end
		Ritualist_EventFrame:RegisterEvent("UNIT_CASTEVENT")
	else
		Ritualist_EventFrame:UnregisterEvent("UNIT_CASTEVENT")
	end

	if num > 0 then
		ScanUnit("player", "target")
	end

	self.State.AddonUsers[UnitName("player")] = true
	for name in pairs(self.State.ShardPool) do
		if not currentNames[name] then
			self.State.ShardPool[name] = nil
		end
	end
	for name in pairs(self.State.AddonUsers) do
		if not currentNames[name] then
			self.State.AddonUsers[name] = nil
		end
	end

	self.State.Cache.DisplayDirty = true
end

for i = 1, 40 do
	Ritualist.UNIT_ID_CACHE.RAID[i] = "raid" .. i
	Ritualist.UNIT_ID_CACHE.RAID_TARGET[i] = "raid" .. i .. "target"
end
for i = 1, 4 do
	Ritualist.UNIT_ID_CACHE.PARTY[i] = "party" .. i
	Ritualist.UNIT_ID_CACHE.PARTY_TARGET[i] = "party" .. i .. "target"
end

Ritualist.isSummoning = false
Ritualist.summonStartTime = 0
Ritualist.lastPingTime = 0

local EventFrame = CreateFrame("Frame", "Ritualist_EventFrame")
EventFrame:SetScript("OnEvent", function()
	if Ritualist.OnEvent then
		Ritualist:OnEvent(event)
	end
end)
_G["Ritualist_EventFrame"] = EventFrame

SLASH_RITUALIST1 = "/rit"
SLASH_RITUALIST2 = "/ritualist"
SlashCmdList["RITUALIST"] = function(msg)
	local cmd = string.lower(msg or "")
	if cmd == "options" or cmd == "config" then
		if not RitualistOptionsFrame then
			Ritualist:CreateOptionsFrame()
		end
		if RitualistOptionsFrame:IsShown() then
			RitualistOptionsFrame:Hide()
		else
			RitualistOptionsFrame:Show()
		end
	elseif cmd == "debug" then
		RitualistDB.debug = not RitualistDB.debug
		DEFAULT_CHAT_FRAME:AddMessage(
			"Ritualist Debug: " .. (RitualistDB.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r")
		)
		Ritualist:OnDebugToggle()
	else
		if not Ritualist_MainFrame then
			Ritualist:CreateMainFrame()
		end
		if Ritualist_MainFrame:IsShown() then
			Ritualist_MainFrame:Hide()
			Ritualist.State.UserOpened = false
		else
			Ritualist.State.UserOpened = true
			Ritualist:RefreshDisplay()
			Ritualist_MainFrame:Show()
		end
	end
end

function RitualistDB_Init()
	RitualistDB = RitualistDB or {}
	local defaults = {
		language = GetLocale() == "ukUA" and "ukUA" or "enUS",
		whisper = true,
		zone = true,
		ritual = true,
		rangeCheck = true,
		debug = false,
		showAnchor = true,
		monSay = true,
		monRaid = true,
		monParty = true,
		monWhisper = true,
		monGuild = true,
		monYell = true,
		summonMessage = "Summoning {targetname}",
		whisperMessage = "Summoning you to {zone}",
		broadcastMsg = "[Ritualist]: Type 123 if you need a summon!",
		swSay = false,
		swRaid = false,
		swParty = false,
		swGuild = false,
		swYell = true,
		soulwellMsg = "Cookie {HP}",
	}
	for k, v in pairs(defaults) do
		if RitualistDB[k] == nil then
			RitualistDB[k] = v
		end
	end
end

function Ritualist:OnEvent(event)
	if RitualistDB.debug then
		if event ~= "UNIT_AURA" and event ~= "BAG_UPDATE" and event ~= "UNIT_CASTEVENT" then
			local detail = ""
			if event == "CHAT_MSG_ADDON" then
				if arg1 and string.find(arg1, "^RIT_") and arg1 ~= "RIT_SHARDS" then
					detail = " [" .. arg1 .. "] from [" .. (arg4 or "nil") .. "]"
					DEFAULT_CHAT_FRAME:AddMessage(
						"|cff9482c9Ritualist Debug:|r OnEvent: " .. (event or "nil") .. detail
					)
				end
			else
				DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9Ritualist Debug:|r OnEvent: " .. (event or "nil") .. detail)
			end
		end
	end

	if event == "VARIABLES_LOADED" then
		RitualistDB_Init()
	elseif event == "PLAYER_ENTERING_WORLD" or event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
		if event == "PLAYER_ENTERING_WORLD" then
			self:UpdateWorldZonesCache()
			self:CreateOptionsFrame()
			self:CreateAnchor()
			self:RestoreFramePosition()
			self:CreateMainFrame()
			self.Ticker:Init()
			self:SyncVersion()
			self:RequestQueueSync()
		end
		self:UpdateGUIDCache()
		self:SyncShards(true)
	elseif event == "SPELLCAST_START" then
		if arg1 == "Ritual of Summoning" then
			local now = GetTime()
			self.isSummoning = true
			self.summonStartTime = now
			self.lastPingTime = 0
			self.State.Last30sAlert = now
			if self.CurrentSummonGUID and self.Registry[self.CurrentSummonGUID] then
				self.Registry[self.CurrentSummonGUID].isCasting = true
				self:RefreshDisplay()
			end
		elseif arg1 == "Ritual of Souls" then
			if RitualistRitualofSouls_OnEvent then
				RitualistRitualofSouls_OnEvent(event)
			end
		end
	elseif event == "SPELLCAST_STOP" or event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
		local isFailure = (event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED")
		local guid = self.CurrentSummonGUID

		if guid and self.Registry[guid] then
			local data = self.Registry[guid]
			data.isCasting = false
			if isFailure then
				data.status = "INTERRUPTED"
				data.interruptedTime = GetTime()
				data.attempts = (data.attempts or 0) + 1
				-- Clear pending summons and timeouts on failure
				self.State.PendingSummons[guid] = nil
				if data.name then
					self.State.AutoSummonTimeouts[data.name] = nil
				end
			end
			self:RefreshDisplay()
		end

		-- Common cleanup
		self.isSummoning = false
		self.summonStartTime = 0
		-- We clear GUID only on STOP to allow FAILED/INTERRUPTED to process it first
		-- if they fire in the same event frame, or we clear it always but at the end.
		if event == "SPELLCAST_STOP" then
			self.CurrentSummonGUID = nil
		end

		for k in pairs(self.State.ActiveClickers) do
			self.State.ActiveClickers[k] = nil
		end
		self.State.LastClickerCount = 0
		self.State.SentClickInstruction = false
		self.State.Last30sAlert = 0
	elseif event == "UNIT_CASTEVENT" then
		if arg4 == 23598 then
			local isGroupMember = Ritualist.GUID_NAME_CACHE[arg1] ~= nil
			local isMySummon = (arg2 == UnitGUID("player"))
			if isGroupMember and isMySummon then
				if arg3 == 1 then
					self.State.ActiveClickers[arg1] = true
				elseif arg3 >= 2 then
					self.State.ActiveClickers[arg1] = nil
				end
			end
		end
		local warlock = Ritualist.WARLOCK_CACHE[arg1]
		if warlock then
			if arg3 == 1 then
				local spellName = nil
				if arg4 == 17928 then
					spellName = "Ritual of Summoning"
				elseif arg4 == 29893 then
					spellName = "Ritual of Souls"
				end
				if spellName then
					if RitualistDB.debug then
						DEFAULT_CHAT_FRAME:AddMessage(
							"|cff9482c9Ritualist Debug:|r Detect Cast: ["
								.. spellName
								.. "] from ["
								.. (warlock.name or "nil")
								.. "]"
						)
					end
					if spellName == "Ritual of Summoning" then
						-- Auto-add to registry if not present (to track external warlocks)
						local targetName = Ritualist.GUID_NAME_CACHE[arg2]
						if targetName and not self.Registry[arg2] and not self.BlockedRegistry[arg2] then
							self:AddRequest(targetName, "External")
						end
						self:ProcessClaim(arg2, warlock.name, "SUMMONING", true)
					elseif spellName == "Ritual of Souls" then
						if RitualistRitualofSouls_OnEvent then
							RitualistRitualofSouls_OnEvent("SPELLCAST_START")
						end
					end
				end
			elseif arg3 == 4 then
				if self.Registry[arg2] and self.Registry[arg2].status == "SUMMONING" then
					self.Registry[arg2].isCasting = false
					self:RefreshDisplay()
				end
			elseif arg3 == 2 or arg3 == 3 then
				if self.Registry[arg2] and self.Registry[arg2].status == "SUMMONING" then
					self.Registry[arg2].status = "WAITING"
					self.Registry[arg2].isCasting = false
					self:RefreshDisplay()
				end
			end
		end
	elseif string.find(event or "", "CHAT_MSG") then
		if event == "CHAT_MSG_ADDON" then
			if arg1 and string.find(arg1, "^RIT_") then
				self.State.AddonUsers[arg4] = true
			end
			if arg1 == "RIT_SHARDS" then
				self.State.ShardPool[arg4] = tonumber(arg2) or 0
				self:UpdateShardHUD()
			elseif arg1 == "RIT_CLAIM" then
				self:ProcessClaim(arg2, arg4, "SUMMONING")
			elseif arg1 == "RIT_TARGET" then
				self:ProcessClaim(arg2, arg4, "TARGETED")
			elseif arg1 == "RIT_VER" then
				self:ProcessVersion(arg2)
			elseif arg1 == "RIT_ALERT" then
				self.State.LastChatAlert = GetTime()
			elseif arg1 == "RIT_BATCH" then
				self:ProcessBatch(arg2, arg4)
			elseif arg1 == "RIT_REQ_QUEUE" then
				self:BroadcastFullQueue()
			elseif arg1 == "RIT_ADD" then
				self:ProcessRemoteAdd(arg2)
			end
		elseif string.find(event, "CHAT_MSG") then
			local opt = RitualistDB
			local listen = false
			if event == "CHAT_MSG_SAY" then
				listen = opt.monSay
			elseif event == "CHAT_MSG_YELL" then
				listen = opt.monYell
			elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
				listen = opt.monRaid
			elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
				listen = opt.monParty
			elseif event == "CHAT_MSG_WHISPER" then
				listen = opt.monWhisper
			elseif event == "CHAT_MSG_GUILD" then
				listen = opt.monGuild
			end
			if listen and arg1 and string.find(arg1, "123") then
				if RitualistDB.debug then
					DEFAULT_CHAT_FRAME:AddMessage(
						"|cff9482c9Ritualist Debug:|r Found '123' in " .. event .. " from [" .. (arg2 or "nil") .. "]"
					)
				end
				self:AddRequest(arg2, "Chat")
				self.State.AutoSummonTimeouts[arg2] = nil
			elseif RitualistDB.debug and arg1 and string.find(arg1, "123") then
				DEFAULT_CHAT_FRAME:AddMessage(
					"|cff9482c9Ritualist Debug:|r Ignored '123' from ["
						.. (arg2 or "nil")
						.. "] because "
						.. event
						.. " monitoring is OFF."
				)
			end
		end
	elseif event == "UNIT_AURA" or event == "BAG_UPDATE" then
		if event == "BAG_UPDATE" or (event == "UNIT_AURA" and arg1 == "player") then
			self.State.ShardUpdatePending = true
		end
	end
end

function Ritualist:SetTab(id)
	self.currentTab = id
	for i = 1, 2 do
		local tab = _G["Ritualist_MainFrameTab" .. i]
		if i == id then
			PanelTemplates_SelectTab(tab)
		else
			PanelTemplates_DeselectTab(tab)
		end
	end
	self.State.Cache.DisplayDirty = true
	self:RefreshDisplay()
end

function Ritualist:SetSort(field)
	if self.State.Sort.field == field then
		self.State.Sort.asc = not self.State.Sort.asc
	else
		self.State.Sort.field = field
		self.State.Sort.asc = true
	end
	self.State.Cache.DisplayDirty = true
	self:RefreshDisplay()
end

Ritualist.State.Cache.StatusPriority = {
	WAITING = 1,
	SUMMONING = 2,
	NEARBY = 3,
	WRONG_ZONE = 4,
	COMBAT = 5,
	DEAD = 6,
	OFFLINE = 7,
	TIMEOUT = 8,
	DONE = 9,
	Arrived = 9,
	Summoned = 9,
}

function Ritualist:RefreshDisplay()
	if not Ritualist_MainFrame or not Ritualist_MainFrame:IsVisible() then
		return
	end
	local ui = self.State.Cache.UI
	Ritualist.State.Cache.DisplayData = Ritualist.State.Cache.DisplayData or {}
	local displayData = Ritualist.State.Cache.DisplayData

	-- 1. Lazy Data Gathering & Sorting
	if self.State.Cache.DisplayDirty or table.getn(displayData) == 0 then
		for k in pairs(displayData) do
			displayData[k] = nil
		end
		if table.setn then
			table.setn(displayData, 0)
		end

		if self.currentTab == 1 then
			for guid, entry in pairs(self.Registry) do
				entry.guid = guid
				table.insert(displayData, entry)
			end
			for guid, entry in pairs(self.BlockedRegistry) do
				entry.guid = guid
				table.insert(displayData, entry)
			end
		else
			for guid, entry in pairs(self.History) do
				entry.guid = guid
				table.insert(displayData, entry)
			end
		end

		local statusPriority = Ritualist.State.Cache.StatusPriority
		table.sort(displayData, function(a, b)
			if not a or not b then
				return false
			end
			local valA, valB
			local sort = self.State.Sort
			if sort.field == "name" then
				valA, valB = a.name, b.name
			elseif sort.field == "executor" then
				valA, valB = a.executor or "", b.executor or ""
			elseif sort.field == "status" then
				local pA = statusPriority[a.status] or 10
				local pB = statusPriority[b.status] or 10
				if pA == pB then
					if a.status == "WAITING" then
						local isLockA = (a.classEng == "WARLOCK") and 0 or 1
						local isLockB = (b.classEng == "WARLOCK") and 0 or 1
						if isLockA ~= isLockB then
							return isLockA < isLockB
						end
					end
					valA, valB = a.name, b.name
				else
					valA, valB = pA, pB
				end
			else
				if self.currentTab == 1 then
					valA, valB = a.addedTime, b.addedTime
				else
					valA, valB = a.lastTime, b.lastTime
				end
			end
			if valA == valB then
				return false
			end
			if sort.asc then
				return valA < valB
			else
				return valA > valB
			end
		end)
		self.State.Cache.DisplayDirty = false
	end

	-- 2. Standard Scroll Frame Update
	local rowCount = table.getn(displayData)
	FauxScrollFrame_Update(Ritualist_MainScroll, rowCount, 10, 18)
	local offset = FauxScrollFrame_GetOffset(Ritualist_MainScroll)

	for i = 1, 10 do
		local cache = ui["Ritualist_Row" .. i]
		if cache then
			local entry = displayData[i + offset]
			if entry then
				local nameText = entry.name or "Unknown"
				if entry.attempts and entry.attempts > 0 then
					nameText = nameText .. " |cff888888(" .. entry.attempts .. ")|r"
				end
				cache.name:SetText(nameText)
				local c = self:GetClassColor(entry.classEng)
				cache.name:SetTextColor(c.r, c.g, c.b)
				local status = entry.status or "WAITING"
				if self.currentTab == 2 then
					status = entry.result or "DONE"
				end
				local icon = "Interface\\Icons\\Spell_Nature_TimeStop"
				local tt = "TT_STATUS_WAITING"
				local showIcon = true

				if status == "NEARBY" then
					showIcon = false
					cache.statusText:SetText("[" .. (entry.distance or "?") .. "y]")
					cache.statusText:Show()
					tt = "TT_STATUS_NEARBY"
				elseif status == "SUMMONING" then
					icon = "Interface\\Icons\\Spell_Shadow_Twilight"
					tt = "TT_STATUS_SUMMONING"
					if entry.isCasting then
						cache.summonAnim:Show()
					else
						cache.summonAnim:Hide()
					end
				elseif status == "INTERRUPTED" then
					icon = "Interface\\Icons\\Ability_Stealth"
					tt = "TT_STATUS_INTERRUPTED"
				elseif status == "Arrived" or status == "Summoned" or status == "DONE" then
					icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing"
					tt = "TT_STATUS_DONE"
				elseif status == "Timeout" or status == "TIMEOUT" then
					icon = "Interface\\Icons\\Spell_ChargeNegative"
					tt = "TT_STATUS_TIMEOUT"
				elseif status == "OFFLINE" then
					icon = "Interface\\Icons\\Spell_Shadow_SacrificialShield"
					tt = "TT_STATUS_OFFLINE"
				elseif status == "DEAD" then
					icon = "Interface\\Icons\\Spell_Shadow_AnimateDead"
					tt = "TT_STATUS_DEAD"
				elseif status == "COMBAT" then
					icon = "Interface\\Icons\\Ability_DualWield"
					tt = "TT_STATUS_COMBAT"
				elseif status == "WRONG_ZONE" then
					icon = "Interface\\Icons\\Spell_Arcane_PortalIronForge"
					tt = "TT_STATUS_WRONG_ZONE"
				end

				if showIcon then
					cache.statusIcon:SetTexture(icon)
					cache.statusIcon:SetTexCoord(0, 1, 0, 1)
					cache.statusIcon:Show()
					cache.statusText:Hide()
				else
					cache.statusIcon:Hide()
				end

				if status ~= "SUMMONING" then
					cache.summonAnim:Hide()
				end
				cache.frame.tooltipKey = tt
				cache.frame.targetName = entry.name
				cache.frame.targetGuid = entry.guid or i
				cache.executor:SetText(entry.executor or "")
				cache.frame:Show()
			else
				cache.frame:Hide()
				cache.summonAnim:Hide()
			end
		end
	end

	local displayCount = rowCount
	if displayCount > 10 then
		displayCount = 10
	end
	local newHeight = 120 + (displayCount * 18)
	Ritualist_MainFrame:SetHeight(newHeight)

	if Ritualist.UpdateColumnWidths then
		Ritualist:UpdateColumnWidths()
	end
end

function Ritualist:AutoSummonNext()
	-- 1. Snapshot Player State (Optimization)
	local playerInInstance = self:IsUnitInInstance("player")
	local myZone = GetRealZoneText() or GetZoneText() or ""
	local px, py = nil, nil
	if UnitPosition then
		px, py = UnitPosition("player")
	end
	local mapPx, mapPy = GetPlayerMapPosition("player")

	-- 2. Snapshot Roster Zones (O(N) Optimization)
	-- Iterate Raid Roster ONCE to cache everyone's zone
	local rosterZoneCache = {}
	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, numRaid do
			local n, _, _, _, _, _, z = GetRaidRosterInfo(i)
			if n then
				rosterZoneCache[n] = z
			end
		end
	end

	-- Helper: Detailed validation logic using CACHED state
	-- Returns: isValid (bool), distanceScore (number)
	-- distanceScore: 0=invalid, 1=visible/close, 2=same_zone_far, 3=diff_zone
	local function GetTargetScore(unit)
		if not UnitExists(unit) or not UnitIsConnected(unit) then
			return false, 0
		end
		if UnitIsUnit(unit, "player") then
			return false, 0
		end
		if UnitIsDeadOrGhost(unit) then
			return false, 0
		end
		if UnitAffectingCombat(unit) then
			return false, 0
		end

		local name = UnitName(unit)
		if not name then
			return false, 0
		end

		-- Check Timeout
		local timeout = self.State.AutoSummonTimeouts[name]
		if timeout and (GetTime() - timeout < 300) then
			return false, 0
		end

		-- Zone Logic (Cached)
		local targetZone = rosterZoneCache[name]
		-- Fallback for Party/Solo if not in raid or not found
		if not targetZone then
			if UnitIsVisible(unit) then
				targetZone = GetRealZoneText()
			else
				targetZone = "Far Away"
			end
		end

		-- Instance Logic
		-- We use the same 'IsUnitInInstance' helper logic but optimized:
		-- If targetZone is known and NOT in WorldZones -> In Instance
		local targetInInstance = false
		if targetZone and targetZone ~= "" and targetZone ~= "Far Away" and not WORLD_ZONES_CACHE[targetZone] then
			targetInInstance = true
		end

		-- 1. Target is INSIDE an instance
		if targetInInstance then
			-- If I am OUTSIDE, never pull them out
			if not playerInInstance then
				return false, 0
			end
			-- If I am INSIDE too, check if it's the SAME instance
			if playerInInstance and targetZone ~= myZone then
				return false, 0
			end
			-- Same instance -> Allow
		end

		-- 2. Target is OUTSIDE, I am INSIDE
		if playerInInstance and not targetInInstance then
			return false, 0
		end

		-- Logic: Different Zones -> High Priority
		if targetZone and targetZone ~= "" and targetZone ~= myZone then
			-- Treat "Far Away" as different zone (valid)
			return true, 3
		end

		-- Logic: Same Zone
		-- If Visible (approx < 100y) -> Skip (Too close)
		if UnitIsVisible(unit) then
			if CheckInteractDistance(unit, 4) then
				return false, 0
			end
			if px then
				local tx, ty = UnitPosition(unit)
				if tx then
					local dist = math.sqrt((px - tx) ^ 2 + (py - ty) ^ 2)
					if dist < 100 then
						return false, 0
					end
				end
			else
				return false, 0
			end
		end

		-- Map Distance Logic
		local tx, ty = GetPlayerMapPosition(unit)
		if tx == 0 and ty == 0 then
			-- Map 0,0 usually means different zone/loading. Treat as Far.
			return true, 2
		end

		local mapDist = math.sqrt((mapPx - tx) ^ 2 + (mapPy - ty) ^ 2)

		-- STRICT: Only allow if truly far away (> 5%)
		if mapDist > 0.05 then
			return true, 2 + mapDist
		end

		return false, 0
	end

	local bestUnit = nil
	local bestScore = 0
	local bestName = nil

	-- Integrated Scoring System (Warlocks > Queue > Rest)
	local num = GetNumRaidMembers()
	local unitBase = "raid"
	if num == 0 then
		num = GetNumPartyMembers()
		unitBase = "party"
	end

	for i = 1, num do
		local unit = unitBase .. i
		local name = UnitName(unit)
		if name then
			local guid = (UnitGUID and UnitGUID(unit)) or name
			local valid, distScore = GetTargetScore(unit)

			if valid and not self.BlockedRegistry[guid] then
				local bonus = 0
				local _, class = UnitClass(unit)
				if class == "WARLOCK" then
					bonus = bonus + 20
				end
				if self.Registry[guid] then
					bonus = bonus + 10
				end

				local totalScore = distScore + bonus
				if totalScore > bestScore then
					bestScore = totalScore
					bestUnit = unit
					bestName = name
				end
			end
		end
	end

	if bestUnit and bestName then
		local guid = (UnitGUID and UnitGUID(bestUnit)) or bestName
		self:StartSummon(bestUnit, "Auto", guid, bestName)
		-- 5-minute timeout is set here TEMPORARILY, but should ideally be on success.
		-- However, to prevent spam clicking 'Next', we set it now.
		-- If cast fails, we must clear it in OnEvent.
		self.State.AutoSummonTimeouts[bestName] = GetTime()
	else
		UIErrorsFrame:AddMessage(Ritualist_GetL("TT_STATUS_DONE"), 1, 1, 1)
	end
end

function Ritualist:Broadcast123()
	local msg = RitualistDB.broadcastMsg or "[Ritualist]: Type 123 for summon!"
	local chan = nil
	if UnitInRaid("player") then
		chan = "RAID"
	elseif GetNumPartyMembers() > 0 then
		chan = "PARTY"
	end
	if chan then
		SendChatMessage(msg, chan)
	end
end

function Ritualist:SyncShards(force)
	local count = self:GetItemCount(6265)
	local name = UnitName("player")
	self.State.ShardPool[name] = count
	local warlockCount = 0
	for _ in pairs(Ritualist.WARLOCK_CACHE) do
		warlockCount = warlockCount + 1
	end
	if warlockCount > 1 then
		if force or (count ~= self.State.LastShardSyncCount) then
			local chan = UnitInRaid("player") and "RAID" or (GetNumPartyMembers() > 0 and "PARTY" or nil)
			if chan then
				SendAddonMessage("RIT_SHARDS", count, chan)
				self.State.LastShardSyncCount = count
			end
		end
	end
	self:UpdateShardHUD()
end

function Ritualist:UpdateShardHUD()
	local total = 0
	for _, c in pairs(self.State.ShardPool) do
		total = total + c
	end
	local myCount = self:GetItemCount(6265)
	if Ritualist_ShardText then
		local displayTotal = total
		if total > 99 then
			displayTotal = "+99"
		end
		Ritualist_ShardText:SetText(displayTotal .. " (" .. myCount .. ")")
	end
end

function Ritualist:OnDebugToggle()
	if RIT_TestBtn then
		if RitualistDB.debug then
			RIT_TestBtn:Show()
		else
			RIT_TestBtn:Hide()
			self:ClearTestData()
		end
	end
end

function Ritualist:SyncVersion()
	local chan = UnitInRaid("player") and "RAID" or (GetNumPartyMembers() > 0 and "PARTY" or nil)
	if chan then
		SendAddonMessage("RIT_VER", self.version, chan)
	end
end

function Ritualist:ProcessVersion(remoteVer)
	if remoteVer and remoteVer > self.version then
		self.State.RemoteVersion = remoteVer
		if Ritualist_UpdateBtn then
			Ritualist_UpdateBtn:SetText("Update: v" .. remoteVer)
			Ritualist_UpdateBtn:Show()
		end
	end
end

function Ritualist:RequestQueueSync()
	self:SendAddonMessage("RIT_REQ_QUEUE", "1")
end

function Ritualist:BroadcastFullQueue()
	local warlockCount = 0
	for _ in pairs(Ritualist.WARLOCK_CACHE) do
		warlockCount = warlockCount + 1
	end
	if warlockCount <= 1 then
		return
	end

	local batch = ""
	local count = 0

	-- Helper to find Raid/Party Index
	local function GetUnitIndex(name)
		local num = GetNumRaidMembers()
		if num > 0 then
			for i = 1, num do
				if UnitName("raid" .. i) == name then
					return i
				end
			end
		else
			num = GetNumPartyMembers()
			for i = 1, num do
				if UnitName("party" .. i) == name then
					return i
				end
			end
		end
		return nil
	end

	for guid, data in pairs(self.Registry) do
		if not data.isTest then
			local idx = GetUnitIndex(data.name)
			if idx and idx <= 63 then
				local cSum = self:GetChecksum(data.name)
				local classID = CLASS_MAP[data.classEng] or 0
				local statusID = STATUS_MAP[data.status] or 1
				local attempts = math.min(data.attempts or 0, 15)

				-- Packing: 4 chars
				-- 1: Index (0-63)
				-- 2: Checksum (0-63)
				-- 3-4: 12 bits (4 class, 4 status, 4 attempts)
				local packed = (classID * 256) + (statusID * 16) + attempts
				local char3 = toB64(math.floor(packed / 64))
				local char4 = toB64(math.mod(packed, 64))

				batch = batch .. toB64(idx) .. toB64(cSum) .. char3 .. char4
				count = count + 1
			end
		end
	end

	if count > 0 then
		local chan = UnitInRaid("player") and "RAID" or (GetNumPartyMembers() > 0 and "PARTY" or nil)
		if chan then
			self:SendAddonMessage("RIT_BATCH", batch, chan)
		end
	end
end

function Ritualist:ProcessBatch(msg, sender)
	if not msg or sender == UnitName("player") then
		return
	end
	local len = string.len(msg)
	if math.mod(len, 4) ~= 0 then
		return
	end

	local isRaid = GetNumRaidMembers() > 0
	local unitBase = isRaid and "raid" or "party"
	local dirty = false

	for i = 1, len, 4 do
		local chunk = string.sub(msg, i, i + 3)
		local idx = fromB64(string.sub(chunk, 1, 1))
		local cSum = fromB64(string.sub(chunk, 2, 2))
		local p1 = fromB64(string.sub(chunk, 3, 3))
		local p2 = fromB64(string.sub(chunk, 4, 4))

		local packed = (p1 * 64) + p2
		local classID = math.floor(packed / 256)
		local statusID = math.floor(math.mod(packed, 256) / 16)
		local attempts = math.mod(packed, 16)

		local unit = unitBase .. idx
		if UnitExists(unit) then
			local name = UnitName(unit)
			local _, classEng = UnitClass(unit)
			-- Verification: Checksum + Class
			if self:GetChecksum(name) == cSum and (not classEng or classEng == CLASS_REV[classID]) then
				local guid = (UnitGUID and UnitGUID(unit)) or name
				if not self.Registry[guid] and not self.BlockedRegistry[guid] then
					self:AddRequest(name, "Batch")
				end

				local data = self.Registry[guid]
				if data then
					data.status = STATUS_REV[statusID] or data.status
					data.attempts = attempts
					dirty = true
				end
			end
		end
	end

	if dirty then
		self.State.Cache.DisplayDirty = true
		self:RefreshDisplay()
	end
end

function Ritualist:ProcessRemoteAdd(msg)
	if not msg then
		return
	end
	local fields = {}
	local start = 1
	while true do
		local pos = string.find(msg, "|", start)
		if not pos then
			table.insert(fields, string.sub(msg, start))
			break
		end
		table.insert(fields, string.sub(msg, start, pos - 1))
		start = pos + 1
	end
	local name = fields[1]
	local class = fields[2]
	local status = fields[3]
	local attempts = fields[4]
	if name and name ~= "" then
		self:AddRequest(name, "Sync")
		local guid = (UnitGUID and UnitGUID(self:GetUnitID(name) or "")) or name
		if self.Registry[guid] then
			if class and class ~= "nil" and class ~= "" then
				self.Registry[guid].classEng = class
			end
			if status and status ~= "nil" and status ~= "" then
				self.Registry[guid].status = status
			end
			if attempts then
				self.Registry[guid].attempts = tonumber(attempts) or 0
			end
			self.State.Cache.DisplayDirty = true
			self:RefreshDisplay()
		end
	end
end

function Ritualist:SendAddonMessage(prefix, msg)
	local chan = UnitInRaid("player") and "RAID" or (GetNumPartyMembers() > 0 and "PARTY" or nil)
	if chan then
		SendAddonMessage(prefix, msg, chan)
	end
end

function Ritualist:ProcessClaim(guid, sender, status, isCasting)
	-- 1. Clear previous claims by this sender
	for g, data in pairs(self.Registry) do
		if data.executor == sender and g ~= guid then
			data.executor = nil
			data.isCasting = false
			-- Instantly clear pending status for the old target to avoid UI lag
			self.State.PendingSummons[g] = nil
		end
	end
	for g, data in pairs(self.BlockedRegistry) do
		if data.executor == sender and g ~= guid then
			data.executor = nil
			data.isCasting = false
		end
	end

	-- 2. Set new claim
	if self.Registry[guid] then
		if status then
			self.Registry[guid].status = status
		end
		self.Registry[guid].executor = sender
		if isCasting ~= nil then
			self.Registry[guid].isCasting = isCasting
		elseif status == "SUMMONING" then
			self.Registry[guid].isCasting = true
		end
		self:RefreshDisplay()
	end
end

Ritualist.Ticker = Ritualist.Ticker or {}
function Ritualist.Ticker:Init()
	if self.frame then
		return
	end
	self.frame = CreateFrame("Frame")
	self.frame:SetScript("OnUpdate", function()
		local now = GetTime()
		if not this.lastUpdate or (now - this.lastUpdate > 1.0) then
			Ritualist:MonitorRegistry()
			Ritualist:CheckClickerHelper(now)
			if Ritualist.UpdateSoulstoneTicker then
				Ritualist:UpdateSoulstoneTicker()
			end
			if Ritualist.State.ShardUpdatePending then
				Ritualist:SyncShards()
				Ritualist.State.ShardUpdatePending = false
			end
			this.lastUpdate = now
		end
	end)
end

function Ritualist:CheckClickerHelper(now)
	if not self.isSummoning then
		return
	end
	local elapsed = now - self.summonStartTime
	if elapsed < 10 then
		return
	end

	-- 1. Count active clickers (must be in group)
	local numClickers = 0
	for _ in pairs(self.State.ActiveClickers) do
		numClickers = numClickers + 1
	end

	-- 2. Count nearby group members (20 yards)
	local numNearby = 0
	local px, py = nil, nil
	if UnitPosition then
		px, py = UnitPosition("player")
	end
	if px then
		local num = GetNumRaidMembers()
		local unitBase = "RAID"
		if num == 0 then
			num = GetNumPartyMembers()
			unitBase = "PARTY"
		end
		for i = 1, num do
			local u = Ritualist.UNIT_ID_CACHE[unitBase][i]
			if u and not UnitIsUnit(u, "player") then
				local tx, ty = UnitPosition(u)
				if tx then
					local dist = math.sqrt((px - tx) ^ 2 + (py - ty) ^ 2)
					if dist < 20 then
						numNearby = numNearby + 1
					end
				end
			end
		end
	end

	-- 3. Notification Logic
	local chan = UnitInRaid("player") and "RAID" or (GetNumPartyMembers() > 0 and "PARTY" or "YELL")

	if elapsed >= 10 and elapsed < 30 then
		-- Stage 1: Pings and One-time instruction if idle people are nearby
		if numNearby > numClickers and numClickers < 2 then
			if now - self.lastPingTime > 5 then
				Minimap:PingLocation(0, 0)
				self.lastPingTime = now
				if not self.State.SentClickInstruction then
					SendChatMessage("[Ritualist]: Click the portal for summon, please!", chan)
					self.State.SentClickInstruction = true
				end
			end
		end
	elseif elapsed >= 30 then
		-- Stage 2: Periodic Chat Alerts (No Pings)
		if numClickers < 2 then
			local shouldAlert = false
			-- Trigger 1: Every 30 seconds of inactivity or if goals not met
			if now - self.State.Last30sAlert > 30 then
				shouldAlert = true
				self.State.Last30sAlert = now
			end

			-- Trigger 2: If count changed (up or down), we just reset the 30s timer
			-- and wait for another 30s of inactivity before alerting again (anti-spam).
			if numClickers ~= self.State.LastClickerCount then
				self.State.Last30sAlert = now
				-- No immediate alert here as per "мгновенный аллерт ненужен" instruction.
			end

			if shouldAlert and (now - self.State.LastChatAlert > 5) then
				local needed = 2 - numClickers
				local clickerText = (needed == 1) and "clicker" or "clickers"
				local msg = string.format("[Ritualist]: Need %d more %s for summon!", needed, clickerText)
				SendChatMessage(msg, chan)
				self.State.LastChatAlert = now

				local addonChan = UnitInRaid("player") and "RAID" or (GetNumPartyMembers() > 0 and "PARTY" or nil)
				if addonChan then
					SendAddonMessage("RIT_ALERT", "1", addonChan)
				end
			end
		end
	end

	self.State.LastClickerCount = numClickers
end

function Ritualist:UpdateWatcher()
	-- Recycle Buffer
	self.State.Cache.WatcherBuffer = self.State.Cache.WatcherBuffer or {}
	local warlockTargets = self.State.Cache.WatcherBuffer
	for k in pairs(warlockTargets) do
		warlockTargets[k] = nil
	end

	-- Only check known Warlocks from the cache
	for guid, info in pairs(Ritualist.WARLOCK_CACHE) do
		if UnitExists(info.targetUnit) then
			local tName = UnitName(info.targetUnit)
			local tGuid = (UnitGUID and UnitGUID(info.targetUnit)) or tName
			warlockTargets[info.name] = tGuid
		end
	end

	-- Apply updates to Registry
	for guid, data in pairs(self.Registry) do
		local foundClaimer = nil
		local currentExecutorStillTargeting = false

		-- 1. Check if the current executor is still targeting this person
		if data.executor and warlockTargets[data.executor] == guid then
			currentExecutorStillTargeting = true
			foundClaimer = data.executor
		end

		-- 2. If not, find a new warlock targeting this person
		if not currentExecutorStillTargeting then
			for wName, tGuid in pairs(warlockTargets) do
				if tGuid == guid then
					foundClaimer = wName
					break
				end
			end
		end

		if foundClaimer then
			if data.executor ~= foundClaimer then
				if RitualistDB.debug then
					DEFAULT_CHAT_FRAME:AddMessage(
						"|cff9482c9Ritualist Debug:|r Watcher: ["
							.. foundClaimer
							.. "] claimed ["
							.. (data.name or "Unknown")
							.. "] via Target"
					)
				end
				data.executor = foundClaimer
				self.State.Cache.DisplayDirty = true
			end
		else
			if data.executor and data.status ~= "SUMMONING" then
				if RitualistDB.debug then
					DEFAULT_CHAT_FRAME:AddMessage(
						"|cff9482c9Ritualist Debug:|r Watcher: Executor ["
							.. data.executor
							.. "] lost target on ["
							.. (data.name or "Unknown")
							.. "]"
					)
				end
				data.executor = nil
				self.State.Cache.DisplayDirty = true
			end
		end
	end
end

function Ritualist:MonitorRegistry()
	local now = GetTime()
	self:UpdateWatcher()
	local px, py = nil, nil
	if UnitPosition then
		px, py = UnitPosition("player")
	end
	local inInstance = IsInInstance()
	local myZone = GetRealZoneText()
	for guid, startTime in pairs(self.State.PendingSummons) do
		if (now - startTime) > 120 then
			local entry = self.Registry[guid] or self.BlockedRegistry[guid] or self.History[guid]
			if entry then
				entry.status = "TIMEOUT"
				SendChatMessage("Your summon expired. Type 123 if you are back!", "WHISPER", nil, entry.name)
				-- Apply 5-minute block for Next button
				self.State.AutoSummonTimeouts[entry.name] = now
			end
			self.State.PendingSummons[guid] = nil
		end
	end
	for guid, data in pairs(self.Registry) do
		if not data.isTest then
			if (now - data.addedTime) > 300 then
				self:RemoveRequest(guid, "Timeout")
			else
				local unit = self:GetUnitID(data.name)
				if not unit then
					self:RemoveRequest(guid, "Left Group")
				else
					local blocked = nil
					if not UnitIsConnected(unit) then
						blocked = "OFFLINE"
						if not data.offlineStartTime then
							data.offlineStartTime = now
						end
					else
						data.offlineStartTime = nil
						if UnitIsDeadOrGhost(unit) then
							blocked = "DEAD"
						elseif UnitAffectingCombat(unit) then
							blocked = "COMBAT"
						elseif inInstance and Ritualist:GetUnitZone(unit) ~= myZone then
							blocked = "WRONG_ZONE"
						elseif CheckInteractDistance(unit, 4) then
							self:RemoveRequest(guid, "Arrived")
						else
							if px and UnitPosition then
								local tx, ty = UnitPosition(unit)
								if tx then
									local oldDist = data.distance
									data.distance = math.floor(math.sqrt((px - tx) ^ 2 + (py - ty) ^ 2) + 0.5)
									if oldDist ~= data.distance then
										self.State.Cache.DisplayDirty = true
									end
								end
							end
							local distStatus = (data.distance and data.distance < 40) and "NEARBY" or "WAITING"
							local oldStatus = data.status
							if data.status == "INTERRUPTED" then
								if now - (data.interruptedTime or 0) > 5 then
									data.status = distStatus
								end
							end
							local isPending = self.State.PendingSummons[guid] ~= nil
							if isPending and not data.executor then
								self.State.PendingSummons[guid] = nil
								isPending = false
							end
							if data.status ~= "SUMMONING" and data.status ~= "INTERRUPTED" and not isPending then
								data.status = distStatus
							elseif isPending then
								data.status = "SUMMONING"
							else
								-- Only reset if it's NOT pending and NOT being cast
								if data.status == "SUMMONING" and not data.executor then
									data.status = distStatus
								end
							end
							if oldStatus ~= data.status then
								self.State.Cache.DisplayDirty = true
							end
						end
					end
					if blocked then
						self.BlockedRegistry[guid] = data
						self.BlockedRegistry[guid].status = blocked
						self.Registry[guid] = nil
						self.State.Cache.DisplayDirty = true
					end
				end
			end
		end
	end
	for guid, data in pairs(self.BlockedRegistry) do
		if not data.isTest then
			local unit = self:GetUnitID(data.name)
			if not unit then
				self:RemoveRequest(guid, "Left Group")
			else
				local unitZone = unit and Ritualist:GetUnitZone(unit)
				local clear = (
					unit
					and UnitIsConnected(unit)
					and not UnitIsDeadOrGhost(unit)
					and not UnitAffectingCombat(unit)
				)
				if inInstance and unitZone ~= myZone then
					clear = false
				end
				if clear then
					self.Registry[guid] = data
					self.Registry[guid].status = "WAITING"
					self.BlockedRegistry[guid] = nil
					self.State.Cache.DisplayDirty = true
				else
					local oldStatus = data.status
					if not unit or not UnitIsConnected(unit) then
						data.status = "OFFLINE"
					elseif UnitIsDeadOrGhost(unit) then
						data.status = "DEAD"
					elseif UnitAffectingCombat(unit) then
						data.status = "COMBAT"
					elseif inInstance and unitZone ~= myZone then
						data.status = "WRONG_ZONE"
					end
					if oldStatus ~= data.status then
						self.State.Cache.DisplayDirty = true
					end
				end
			end
		end
	end
	self:RefreshDisplay()
	local hasActive = false
	for k in pairs(self.Registry) do
		hasActive = true
		break
	end
	if not hasActive then
		for k in pairs(self.BlockedRegistry) do
			hasActive = true
			break
		end
	end
	if not hasActive and Ritualist_MainFrame and Ritualist_MainFrame:IsShown() then
		if not self.State.UserOpened and not MouseIsOver(Ritualist_MainFrame) then
			Ritualist_MainFrame:Hide()
		end
	end
end

function Ritualist:IsUnitInInstance(unit)
	if not unit or not UnitExists(unit) then
		return false
	end
	local zone = self:GetUnitZone(unit)
	if not zone or zone == "" or zone == "Unknown" or zone == "Far Away" then
		return false
	end
	if not WORLD_ZONES_CACHE[zone] then
		return true
	end
	return false
end

function Ritualist:GetUnitZone(unit)
	if not unit or not UnitExists(unit) then
		return nil
	end
	if unit == "player" then
		return GetRealZoneText() or GetZoneText()
	end
	local name = UnitName(unit)
	if UnitInRaid("player") then
		for i = 1, GetNumRaidMembers() do
			local n, _, _, _, _, _, zone = GetRaidRosterInfo(i)
			if n == name then
				return zone
			end
		end
	end
	if UnitIsVisible(unit) then
		return GetRealZoneText() or GetZoneText()
	end
	return "Far Away"
end

function Ritualist:GetItemCount(itemId)
	local total = 0
	if GetBagItems then
		for bag = 0, 4 do
			local items = GetBagItems(bag)
			if items then
				for i = 1, table.getn(items) do
					local item = items[i]
					if item.itemId == itemId then
						total = total + (item.stackCount or 1)
					end
				end
			end
		end
		return total
	end
	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag)
		if slots and slots > 0 then
			for slot = 1, slots do
				local link = GetContainerItemLink(bag, slot)
				if link then
					local _, _, id = string.find(link, "item:(%d+):")
					if id and tonumber(id) == itemId then
						local _, count = GetContainerItemInfo(bag, slot)
						total = total + (count or 1)
					end
				end
			end
		end
	end
	return total
end

function Ritualist:AddRequest(name, source)
	if RitualistDB.debug then
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cff9482c9Ritualist Debug:|r AddRequest called for ["
				.. (name or "nil")
				.. "] from source ["
				.. (source or "nil")
				.. "]"
		)
	end
	if not name or name == UnitName("player") then
		if RitualistDB.debug then
			DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9Ritualist Debug:|r AddRequest ignored: Name is nil or is player.")
		end
		return
	end
	local inGroup = false
	if UnitInRaid("player") then
		for i = 1, GetNumRaidMembers() do
			if UnitName("raid" .. i) == name then
				inGroup = true
				break
			end
		end
	else
		for i = 1, GetNumPartyMembers() do
			if UnitName("party" .. i) == name then
				inGroup = true
				break
			end
		end
	end
	if not inGroup and not string.find(name, "TestBot") then
		if RitualistDB.debug then
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cff9482c9Ritualist Debug:|r AddRequest ignored: [" .. name .. "] is not in your group."
			)
		end
		return
	end
	if Ritualist_MainFrame and not Ritualist_MainFrame:IsShown() then
		Ritualist_MainFrame:Show()
		Ritualist.State.UserOpened = false
	end
	local guid = (UnitGUID and UnitGUID(self:GetUnitID(name) or "")) or name
	if self.BlockedRegistry[guid] then
		local data = self.BlockedRegistry[guid]
		data.addedTime = GetTime()
		data.status = "WAITING"
		data.isCasting = false
		data.attempts = 0
		self.Registry[guid] = data
		self.BlockedRegistry[guid] = nil
		if RitualistDB.debug then
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cff9482c9Ritualist Debug:|r Restored [" .. name .. "] from BlockedRegistry."
			)
		end
		self.State.Cache.DisplayDirty = true
		self:RefreshDisplay()
		return
	end
	if self.Registry[guid] then
		self.Registry[guid].addedTime = GetTime()
		-- Do NOT reset isCasting or attempts if already in queue
		if RitualistDB.debug then
			DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9Ritualist Debug:|r Updated existing request for [" .. name .. "].")
		end
		self.State.Cache.DisplayDirty = true
		self:RefreshDisplay()
		return
	end
	local unit = self:GetUnitID(name)
	local _, class = "Unknown", "UNKNOWN"
	if unit then
		_, class = UnitClass(unit)
	end
	if RitualistDB.debug then
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cff9482c9Ritualist Debug:|r Creating NEW request for ["
				.. name
				.. "] Class: ["
				.. (class or "nil")
				.. "]."
		)
	end
	self.Registry[guid] = {
		name = name,
		classEng = class,
		status = "WAITING",
		addedTime = GetTime(),
		isCasting = false,
		attempts = 0,
	}
	self.State.Cache.DisplayDirty = true
	self:RefreshDisplay()
end

function Ritualist:RemoveRequest(guid, reason)
	local entry = self.Registry[guid] or self.BlockedRegistry[guid]
	if entry then
		-- 1. Limit History Size (Prevent Memory Leak)
		local count = 0
		local oldestGuid = nil
		local oldestTime = GetTime()
		for g, h in pairs(self.History) do
			count = count + 1
			if h.lastTime < oldestTime then
				oldestTime = h.lastTime
				oldestGuid = g
			end
		end
		if count >= 50 and oldestGuid then
			self.History[oldestGuid] = nil
		end

		-- 2. Add to History
		self.History[guid] = {
			name = entry.name,
			classEng = entry.classEng,
			result = reason,
			lastTime = GetTime(),
			executor = entry.executor,
			attempts = (entry.attempts or 0) + (reason == "Arrived" and 1 or 0),
		}
		self.Registry[guid] = nil
		self.BlockedRegistry[guid] = nil
		self.State.PendingSummons[guid] = nil
		self.State.Cache.DisplayDirty = true
		self:RefreshDisplay()
	end
end

function Ritualist:StartSummon(unit, source, guid, name)
	if not unit or not name then
		return
	end

	TargetUnit(unit)
	if source == "Auto" then
		self:AddRequest(name, "Auto")
	end

	-- Whisper logic
	if RitualistDB.whisper then
		local msg = string.gsub(RitualistDB.whisperMessage or "Summoning you!", "{zone}", GetZoneText())
		SendChatMessage(msg, "WHISPER", nil, name)
	end

	CastSpellByName("Ritual of Summoning")

	-- State Update
	local targetGuid = guid or (UnitGUID and UnitGUID(unit)) or name
	self.CurrentSummonGUID = targetGuid

	if self.Registry[targetGuid] then
		self.Registry[targetGuid].status = "SUMMONING"
		self.Registry[targetGuid].executor = UnitName("player")
		self.State.Cache.DisplayDirty = true
		self:RefreshDisplay()
	end

	self:SendAddonMessage("RIT_CLAIM", targetGuid)
	-- PendingSummons is set here to track the cast start,
	-- but will be cleared if cast fails in OnEvent.
	self.State.PendingSummons[targetGuid] = GetTime()
end

function Ritualist:SummonTarget(name, guid, button)
	if RitualistDB.debug then
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cff9482c9Ritualist Debug:|r SummonTarget called for ["
				.. (name or "nil")
				.. "] Button ["
				.. (button or "nil")
				.. "]"
		)
	end
	if not name then
		return
	end
	local unit = self:GetUnitID(name)
	if not unit then
		if RitualistDB.debug then
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cff9482c9Ritualist Debug:|r SummonTarget: Could not find UnitID for [" .. name .. "]"
			)
		end
		return
	end

	if button == "LeftButton" then
		self:StartSummon(unit, "Manual", guid, name)
		if IsControlKeyDown() then
			return
		end
	elseif button == "RightButton" then
		if guid then
			local warlockCount = 0
			for _ in pairs(Ritualist.WARLOCK_CACHE) do
				warlockCount = warlockCount + 1
			end
			local addonUsersCount = 0
			for _ in pairs(self.State.AddonUsers) do
				addonUsersCount = addonUsersCount + 1
			end
			local canRemove = true
			if warlockCount > 1 or addonUsersCount > 1 then
				local data = self.Registry[guid] or self.BlockedRegistry[guid]
				local unit = self:GetUnitID(name)
				if unit then
					local isOffline = (data and data.status == "OFFLINE")
					local offlineDuration = isOffline and (GetTime() - (data.offlineStartTime or 0)) or 0
					if not isOffline or offlineDuration < 300 then
						canRemove = false
					end
				end
			end
			if canRemove then
				self:RemoveRequest(guid, "Removed")
			else
				UIErrorsFrame:AddMessage(Ritualist_GetL("ERR_SHARED_PROTECTION"), 1, 0.5, 0)
			end
		end
	end
end

function Ritualist:GetUnitID(name)
	if not name then
		return nil
	end
	if name == UnitName("player") then
		return "player"
	end

	-- O(1) Cache Lookup
	local unit = self.NAME_UNIT_CACHE[name]
	if unit and UnitExists(unit) and UnitName(unit) == name then
		return unit
	end

	-- Fallback (should rarely happen if cache is synced)
	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, numRaid do
			local u = Ritualist.UNIT_ID_CACHE.RAID[i]
			if UnitName(u) == name then
				self.NAME_UNIT_CACHE[name] = u -- Heal cache
				return u
			end
		end
	else
		local numParty = GetNumPartyMembers()
		if numParty > 0 then
			for i = 1, numParty do
				local u = Ritualist.UNIT_ID_CACHE.PARTY[i]
				if UnitName(u) == name then
					self.NAME_UNIT_CACHE[name] = u -- Heal cache
					return u
				end
			end
		end
	end
	return nil
end

local CLASS_COLORS = {
	WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
	DRUID = { r = 1, g = 0.49, b = 0.04 },
	HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
	MAGE = { r = 0.41, g = 0.8, b = 0.94 },
	PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
	PRIEST = { r = 1, g = 1, b = 1 },
	ROGUE = { r = 1, g = 0.96, b = 0.41 },
	SHAMAN = { r = 0, g = 0.44, b = 0.87 },
	WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
	DEFAULT = { r = 0.5, g = 0.5, b = 0.5 },
}

function Ritualist:GetClassColor(class)
	return CLASS_COLORS[class] or CLASS_COLORS.DEFAULT
end

function Ritualist:SaveFramePosition()
	if not Ritualist_AnchorFrame then
		return
	end
	local x = Ritualist_AnchorFrame:GetLeft()
	local y = Ritualist_AnchorFrame:GetTop()
	RitualistDB.anchorX, RitualistDB.anchorY = x, y
end

function Ritualist:RestoreFramePosition()
	local opt = RitualistDB
	if not Ritualist_AnchorFrame then
		return
	end
	Ritualist_AnchorFrame:ClearAllPoints()
	if opt and opt.anchorX and opt.anchorY then
		Ritualist_AnchorFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", opt.anchorX, opt.anchorY)
	else
		Ritualist_AnchorFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 5, -5)
	end
end

function Ritualist:SetLanguage(lang)
	RitualistDB.language = lang
	ReloadUI()
end

function Ritualist:ClearTestData()
	for k, v in pairs(self.Registry) do
		if v.isTest then
			self.Registry[k] = nil
		end
	end
	for k, v in pairs(self.BlockedRegistry) do
		if v.isTest then
			self.BlockedRegistry[k] = nil
		end
	end
	for k, v in pairs(self.History) do
		if v.isTest then
			self.History[k] = nil
		end
	end
	self:RefreshDisplay()
end

function Ritualist:RunTest()
	self:ClearTestData()
	local now = GetTime()
	local testRegistry = {
		{ n = "Arthas", c = "WARRIOR", s = "WAITING" },
		{ n = "Jaina", c = "MAGE", s = "SUMMONING", e = "Paduk" },
		{ n = "Uther", c = "PALADIN", s = "NEARBY", d = 15 },
		{ n = "Sylvanas", c = "HUNTER", s = "DEAD", blocked = true },
		{ n = "Thrall", c = "SHAMAN", s = "OFFLINE", blocked = true },
		{ n = "Illidan", c = "ROGUE", s = "COMBAT", blocked = true },
		{ n = "Tyrande", c = "PRIEST", s = "WAITING", d = 100 },
		{ n = "Kaelthas", c = "MAGE", s = "WRONG_ZONE", blocked = true },
		{ n = "Guldan", c = "WARLOCK", s = "SUMMONING", e = "Me" },
	}
	for _, d in ipairs(testRegistry) do
		local entry = {
			name = d.n,
			classEng = d.c,
			status = d.s,
			addedTime = now,
			distance = d.d,
			executor = d.e,
			isTest = true,
		}
		if d.blocked then
			self.BlockedRegistry["TEST_" .. d.n] = entry
		else
			self.Registry["TEST_" .. d.n] = entry
		end
	end
	local testHistory = {
		{ n = "Kelthuzad", c = "MAGE", r = "Arrived", t = now - 60, e = "Me" },
		{ n = "Anubarak", c = "WARRIOR", r = "Timeout", t = now - 300, e = "Arthas" },
		{ n = "Vashj", c = "SHAMAN", r = "Summoned", t = now - 120, e = "Me" },
	}
	for i, h in ipairs(testHistory) do
		self.History["TEST_HIST_" .. i] = {
			name = h.n,
			classEng = h.c,
			result = h.r,
			lastTime = h.t,
			executor = h.e,
			isTest = true,
		}
	end
	self:RefreshDisplay()
end

Ritualist_EventFrame:RegisterEvent("VARIABLES_LOADED")
Ritualist_EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
Ritualist_EventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
Ritualist_EventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
Ritualist_EventFrame:RegisterEvent("SPELLCAST_START")
Ritualist_EventFrame:RegisterEvent("SPELLCAST_STOP")
Ritualist_EventFrame:RegisterEvent("SPELLCAST_FAILED")
Ritualist_EventFrame:RegisterEvent("SPELLCAST_INTERRUPTED")
Ritualist_EventFrame:RegisterEvent("CHAT_MSG_SAY")
Ritualist_EventFrame:RegisterEvent("CHAT_MSG_YELL")
Ritualist_EventFrame:RegisterEvent("CHAT_MSG_RAID")
Ritualist_EventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
Ritualist_EventFrame:RegisterEvent("CHAT_MSG_PARTY")
Ritualist_EventFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
Ritualist_EventFrame:RegisterEvent("CHAT_MSG_WHISPER")
Ritualist_EventFrame:RegisterEvent("CHAT_MSG_GUILD")
Ritualist_EventFrame:RegisterEvent("CHAT_MSG_ADDON")
Ritualist_EventFrame:RegisterEvent("UNIT_AURA")
Ritualist_EventFrame:RegisterEvent("BAG_UPDATE")
Ritualist_EventFrame:RegisterEvent("UNIT_CASTEVENT")
DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9Ritualist v" .. Ritualist.version .. " loaded.|r")
