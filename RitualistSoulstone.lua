-- RitualistSoulstone.lua
-- Soulstone tracking module for Ritualist
-- Optimized for WoW 1.12.1 (Pure Lua)

Ritualist = _G.Ritualist or {}

-- Localized APIs
local GetTime = GetTime
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitInRaid = UnitInRaid
local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local UnitBuff = UnitBuff
local string_find = string.find
local GetBagItems = _G.GetBagItems

-- Soulstone Constants
local SOULSTONE_BUFF_ICON = "Spell_Shadow_SoulGem"

Ritualist.SoulstoneData = Ritualist.SoulstoneData or {}

function Ritualist:ScanSoulstones()
	-- Only warlocks can have/give soulstones in a meaningful way for tracking
	if Ritualist.WARLOCK_CACHE then
		for guid, info in pairs(Ritualist.WARLOCK_CACHE) do
			self:CheckUnitSS(info.unit)
		end
	end

	-- Always check player
	self:CheckUnitSS("player")
end

function Ritualist:CheckUnitSS(unit)
	local name = UnitName(unit)
	if not name then
		return
	end

	local hasSS = false
	for j = 1, 32 do
		local buff = UnitBuff(unit, j)
		if not buff then
			break
		end
		if string_find(buff, SOULSTONE_BUFF_ICON) then
			hasSS = true
			break
		end
	end

	if hasSS then
		if not self.SoulstoneData[name] then
			self.SoulstoneData[name] = { startTime = GetTime() }
		end
	else
		self.SoulstoneData[name] = nil
	end
end

function RitualistSoulstone_Initialize()
	-- Soulstone module is passive, scanned via Ticker
end

function Ritualist:UpdateSoulstoneTicker()
	self:ScanSoulstones()
end
