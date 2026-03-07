-- RitualistRitualofSouls.lua
-- Ritual of Souls module for Ritualist
-- Optimized for Nampower & pfUI Style

Ritualist = _G.Ritualist or {}

local function GetImpHSBonus()
	local numTabs = GetNumTalentTabs()
	if numTabs < 2 then
		return 0
	end
	for i = 1, 20 do
		local name, icon, tier, column, rank, maxRank = GetTalentInfo(2, i)
		if name and string.find(name, "Healthstone") then
			return rank * 0.1
		end
	end
	return 0
end

function RitualistRitualofSouls_GetHealthstoneHealValue()
	local lvl = UnitLevel("player")
	local base = 100
	if lvl >= 58 then
		base = 1200
	elseif lvl >= 46 then
		base = 800
	elseif lvl >= 34 then
		base = 500
	elseif lvl >= 22 then
		base = 250
	end
	return math.floor(base * (1 + GetImpHSBonus()))
end

function RitualistRitualofSouls_OnEvent(event)
	if event == "SPELLCAST_START" then
		-- Ritual of Souls cast detected
		local hp = RitualistRitualofSouls_GetHealthstoneHealValue()
		local msg = RitualistDB.soulwellMsg or "Cookie {HP}"
		msg = string.gsub(msg, "{HP}", hp)

		local db = RitualistDB
		if db.swSay then
			SendChatMessage(msg, "SAY")
		end
		if db.swParty and GetNumPartyMembers() > 0 then
			SendChatMessage(msg, "PARTY")
		end
		if db.swRaid and UnitInRaid("player") then
			SendChatMessage(msg, "RAID")
		end
		if db.swGuild and IsInGuild() then
			SendChatMessage(msg, "GUILD")
		end
		if db.swYell then
			SendChatMessage(msg, "YELL")
		end
	end
end
