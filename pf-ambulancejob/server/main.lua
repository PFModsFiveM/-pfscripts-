local QBCore = exports['pfm-core']:GetCoreObject({ 'Functions', 'Commands' })
local sharedItems = exports['pfm-core']:GetShared('Items')
local doctorCount = 0 -- on-duty ambulance staff, counted on the server (AddDoctor/RemoveDoctor are ignored)
local doctorCalled = false
local BedOccupants = {} -- ['<hospitalIndex>:<bedId>'] = src, ['jail:<bedId>'] = src

-- Hospital bills go through the pfm-banking ledger (PFPayout, '@pfm-banking/payouts.lua'): the patient's
-- bank pays first, and the ambulance account is credited only for a bill that was paid. (The bill was
-- not checked, so the ambulance account was credited even when a patient could not pay.) A patient
-- who cannot pay is still treated, as before.
-- `key` (optional) is a stable key for one real payment (a respawn: one bill per death).
local function ChargeHospitalBill(Player, key)
	-- hospital treatment (check-in bed or respawn) heals every recorded injury, critical ones included
	if ClearCitizenInjuries then ClearCitizenInjuries(Player.PlayerData.citizenid) end
	key = key or ('%s:bill:%s:%s'):format(GetCurrentResourceName(), Player.PlayerData.citizenid, PFPayout.NewId())
	if PFPayout.Charge(Player, 'bank', Config.BillCost, { key = key, kind = 'purchase', reason = 'Hospital treatment', quiet = true }) then
		PFPayout.PaySociety('ambulance', Config.BillCost, { key = key .. ':society', reason = 'Player treatment' })
		return true
	end
	return false
end

-- Resources allowed to trigger revive/heal server events directly (server-side TriggerEvent)
local AllowedResources = Config.AllowedRevivalResources or {
	[GetCurrentResourceName()] = true,
	['pfm-adminmenu'] = true,
}

local function IsAllowedInvoker()
	local invoker = GetInvokingResource()
	return invoker ~= nil and AllowedResources[invoker] == true
end

local function IsOnDutyEms(Player)
	return Player and Player.PlayerData.job.name == 'ambulance' and Player.PlayerData.job.onduty
end

-- Duty points (pfm-core registry): clocking in through QBCore:ToggleDuty needs the medic's server
-- position at one of the duty desks; clocking out works anywhere. Registered again when pfm-core
-- restarts (its registry starts empty).
local function RegisterEmsDutyPoints()
	pcall(function()
		exports['pfm-core']:RegisterDutyPoints({ job = 'ambulance', points = Config.Locations['duty'], radius = 2.5 })
	end)
end
RegisterEmsDutyPoints()
AddEventHandler('onResourceStart', function(resourceName)
	if resourceName == 'pfm-core' then RegisterEmsDutyPoints() end
end)

local function GetHospitalBed(hospitalIndex, bedId)
	local hospital = Config.Locations['hospital'][hospitalIndex]
	if not hospital or not hospital['beds'] then return nil end
	return hospital['beds'][bedId]
end

-- ── EMS dispatch (pf-services) ─────────────────────────────────────
-- A player who goes down gets one 'ems.patient' service request at their server position (medics see
-- it in the Dispatch app and on the EMS MDT, whose call leaves the board when the request closes); it
-- closes as completed when a medic (or a first-aid kit) revives them and as cancelled when they respawn
-- at hospital, check in, are revived by an admin, come to by themselves, log out or leave.
-- Since batch 16A the down state is the server's (server/medical/downstate.lua writes the metadata and
-- calls PFEmsRequests.OnDownChanged), so a client can no longer open or close calls by toggling flags.
-- A character who left while down keeps their record down; when they come back the call reopens even
-- inside the PATIENT_COOLDOWN (leftDown). A player has at most one open request.
-- A medic call the citizen made themselves (Services app or /911e, ref 'citizen:ems.patient') closes
-- with the patient request on a revive, check-in or respawn, and when they log out or leave.
local PATIENT_COOLDOWN = 60
local lastPatientRequest = {} -- [citizenid] = os.time() of the last request
local downBySource = {}       -- [src] = citizenid while that player has an open request
local leftDown = {}           -- [citizenid] = true: left with an open request, not seen up since
local opening = {}            -- [citizenid] = { status, reason } of a close while their request is being made

local function Services()
	if GetResourceState('pf-services') ~= 'started' then return nil end
	return exports['pf-services']
end

local function IsDown(Player)
	local m = Player and Player.PlayerData.metadata or {}
	return m['isdead'] == true or m['inlaststand'] == true
end

local function PatientName(Player)
	local ci = Player.PlayerData.charinfo or {}
	local n = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
	return n ~= '' and n or 'Unknown person'
end

PFEmsRequests = {}

function PFEmsRequests.Open(Player)
	local svc = Services()
	if not svc then return nil end
	local src, cid = Player.PlayerData.source, Player.PlayerData.citizenid
	local now = os.time()
	-- back from leaving while down (crash, logout): the call they had reopens even inside the cooldown
	if not leftDown[cid] and lastPatientRequest[cid] and now - lastPatientRequest[cid] < PATIENT_COOLDOWN then return nil end
	lastPatientRequest[cid] = now
	local p = GetEntityCoords(GetPlayerPed(src))
	local coords = vector3(p.x, p.y, p.z)
	local ok, res = pcall(function()
		return svc:CreateRequest({
			kind = 'ems.patient', title = 'Person down: ' .. PatientName(Player),
			details = 'Unconscious or badly injured person', coords = coords,
			ref = { type = 'patient', id = cid },
			from = { type = 'system', id = GetCurrentResourceName(), name = 'Medical alert' },
			meta = { patient = cid },
		})
	end)
	if not ok or type(res) ~= 'table' or not res.ok then return nil end
	res.coords = coords
	return res
end

-- The city event for a newly made request (the caller checks the patient is still down first).
function PFEmsRequests.Announce(cid, res)
	local svc = Services()
	if not svc or type(res) ~= 'table' or res.existing then return end
	pcall(function() svc:Emit('ems.patient', {}, { title = 'Person down', coords = res.coords, actor = cid, dedupe = cid }) end)
end

--- Closes the patient's request(s). status 'completed' credits the medic who accepted it (if any).
function PFEmsRequests.Close(cid, status, reason, includeCitizenCall)
	if not cid then return end
	-- the player no longer has an open request; after a revive (not under the patient's control) the
	-- next time they go down is a new emergency, so the cooldown does not hold it back
	for s, c in pairs(downBySource) do
		if c == cid then downBySource[s] = nil end
	end
	-- a request still being made gets this close too once it exists (see OnDownChanged)
	if opening[cid] then opening[cid].status, opening[cid].reason = status, reason end
	leftDown[cid] = nil
	if reason == 'revived' or reason == 'admin_revive' then lastPatientRequest[cid] = nil end
	local svc = Services()
	if not svc then return end
	pcall(function() svc:CloseByRef('patient', cid, status, reason) end)
	-- a citizen who called a medic from the Services app (or /911e) has been seen to as well
	if includeCitizenCall then pcall(function() svc:CloseByRef('citizen:ems.patient', cid, status, reason) end) end
end

-- The server's down state of a player changed (PFMed.Down already wrote the metadata). Down: one
-- request. Up: the request closes with the given status/reason (default: they came to by themselves).
function PFEmsRequests.OnDownChanged(src, status, reason, includeCitizenCall)
	local Player = exports['pfm-core']:GetPlayer(src)
	if not Player then return end
	local cid = Player.PlayerData.citizenid
	if IsDown(Player) then
		if downBySource[src] == cid then return end
		-- a request still held for another character of this player (they changed character)
		if downBySource[src] then PFEmsRequests.Close(downBySource[src], 'cancelled', 'left') end
		downBySource[src] = cid -- held across the request's database work, so a second change opens nothing
		opening[cid] = {}
		local res = PFEmsRequests.Open(Player)
		local closed = opening[cid] or {}
		opening[cid] = nil
		if downBySource[src] ~= cid then
			-- logged out, left, revived, respawned or checked in while the request was being made: that
			-- close found no row yet, so the new request (and its MDT call) would stay open until expiry
			if res then
				local svc = Services()
				if svc then pcall(function() svc:CloseByRef('patient', cid, closed.status or 'cancelled', closed.reason or 'left') end) end
			end
			return
		end
		if res then
			leftDown[cid] = nil
			PFEmsRequests.Announce(cid, res)
		else
			-- nothing opened (cooldown, pf-services down): RequestHelp may open it later
			downBySource[src] = nil
		end
	else
		leftDown[cid] = nil
		if downBySource[src] ~= cid then return end
		PFEmsRequests.Close(cid, status or 'cancelled', reason or 'recovered', includeCitizenCall)
	end
end

--- A down player asked for help (RequestHelp): opens their request when none is open (no cooldown:
--- the server has them down, and the ask itself is rate limited).
function PFEmsRequests.Help(src)
	local Player = exports['pfm-core']:GetPlayer(src)
	if not Player or not IsDown(Player) or downBySource[src] then return end
	local cid = Player.PlayerData.citizenid
	lastPatientRequest[cid] = nil
	PFEmsRequests.OnDownChanged(src)
end

-- The player left (dropped, or logged out to the character menu): their request closes, as no
-- patient is there any more. A character who was still down is remembered as seen down, so the
-- call opens again when they come back down (a dead player comes back at full health).
-- `unloading` (pfm-core's unload, raised once per leave while the character is still loaded, on a
-- drop too): a medic call the character made themselves closes as well, like their patient request
-- (pf-services keeps other citizen requests until they expire; a medic call has nobody left to treat).
local function PatientLeft(src, unloading)
	local cid = downBySource[src]
	local Player = exports['pfm-core']:GetPlayer(src)
	local caller = unloading and Player and Player.PlayerData.citizenid or nil
	if cid then
		local stillDown = Player ~= nil and Player.PlayerData.citizenid == cid and IsDown(Player)
		PFEmsRequests.Close(cid, 'cancelled', 'left')
		if stillDown then leftDown[cid] = true end
	end
	downBySource[src] = nil
	if caller then
		local svc = Services()
		if svc then pcall(function() svc:CloseByRef('citizen:ems.patient', caller, 'cancelled', 'left') end) end
	end
end

-- Events

-- Compatibility with txAdmin Menu's heal options.
-- This is an admin only server side event that will pass the target player id or -1.
AddEventHandler('txAdmin:events:healedPlayer', function(eventData)
	if GetInvokingResource() ~= 'monitor' or type(eventData) ~= 'table' or type(eventData.id) ~= 'number' then
		return
	end

	-- through the server's revive (token, health re-read, record reset); -1 = everyone
	local targets = {}
	if eventData.id == -1 then
		for src in pairs(QBCore.Functions.GetQBPlayers()) do targets[#targets + 1] = tonumber(src) end
	else
		targets[1] = eventData.id
	end
	for _, id in ipairs(targets) do
		if exports['pfm-core']:GetPlayer(id) then
			PFMed.Down.Revive(id, { mode = 'admin', reason = 'txadmin' })
			TriggerClientEvent('hospital:client:HealInjuries', id, 'full')
		end
	end
end)

local function DownCfg() return (Config.Medical and Config.Medical.Down) or {} end

local function ServerPos(src)
	local ped = GetPlayerPed(src)
	if not ped or ped == 0 then return nil end
	return GetEntityCoords(ped)
end

local function OnDutyDoctors()
	local n = 0
	for _, v in pairs(QBCore.Functions.GetQBPlayers()) do
		if v.PlayerData.job.name == 'ambulance' and v.PlayerData.job.onduty then n = n + 1 end
	end
	return n
end

-- Check-in (isRevive) at the reception point, or lying in a bed next to it. The server checks the
-- player's position, that no doctors are on duty for an AI check-in, and that they are not down;
-- the check-in heal is a server revive (token) that the bed's AI timer applies.
RegisterNetEvent('hospital:server:SendToBed', function(bedId, isRevive, hospitalIndex)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if not Player then return end
	if PFMed.Down.Limited(src, 'bed', 2) then return end
	local bed = GetHospitalBed(hospitalIndex, bedId)
	if not bed then return end
	local hospital = Config.Locations['hospital'][hospitalIndex]
	local pos = ServerPos(src)
	isRevive = isRevive == true
	if PFMed.Down.IsDown(src) then return end
	if isRevive then
		if PFMed.Down.Dist(pos, hospital['location']) > (DownCfg().ReceptionDistance or 4.0) then return end
		if OnDutyDoctors() >= Config.MinimalDoctors then
			TriggerClientEvent('QBCore:Notify', src, 'Doctors are on duty: call one at the desk', 'error')
			return
		end
	elseif PFMed.Down.Dist(pos, bed.coords) > (DownCfg().BedDistance or 3.0) then
		return
	end
	local bedKey = tostring(hospitalIndex) .. ':' .. tostring(bedId)
	if BedOccupants[bedKey] and BedOccupants[bedKey] ~= src then
		TriggerClientEvent('QBCore:Notify', src, Lang:t('error.beds_taken'), 'error')
		return
	end
	BedOccupants[bedKey] = src
	local token
	if isRevive then
		token = PFMed.Down.IssueReviveToken(src, 'checkin', { delay = Config.AIHealTimer, send = false })
		PFMed.Down.MoveGrace(src, (Config.AIHealTimer or 20) + 10)
	end
	TriggerClientEvent('hospital:client:SendToBed', src, bedId, bed, isRevive, token)
	TriggerClientEvent('hospital:client:SetBed', -1, bedId, true, hospitalIndex)
	-- checked in at the hospital desk: no medic needs to drive out any more
	if isRevive then PFEmsRequests.Close(Player.PlayerData.citizenid, 'cancelled', 'checked_in', true) end
	ChargeHospitalBill(Player)
	TriggerClientEvent('hospital:client:SendBillEmail', src, Config.BillCost, hospital['name'])
end)

local respawnDone = {} -- [citizenid] = { deadAt, hospital, bed }: one wipe, bill and respawned event per death

local function WipeInventory(Player, src)
	if not Config.WipeInventoryOnRespawn then return end
	Player.ClearInventory()
	MySQL.update('UPDATE players SET inventory = ? WHERE citizenid = ?', { json.encode({}), Player.PlayerData.citizenid })
	TriggerClientEvent('QBCore:Notify', src, Lang:t('error.possessions_taken'), 'error')
end

local function NearestHospital(src, hint)
	local list = Config.Locations['hospital']
	local pos = ServerPos(src)
	if Config.RespawnAtNearestHospital and pos then
		local best, bestDist
		for i = 1, #list do
			local d = PFMed.Down.Dist(pos, list[i]['location'])
			if not best or d < bestDist then best, bestDist = i, d end
		end
		if best then return best end
	end
	hint = math.tointeger(tonumber(hint))
	if hint and list[hint] then return hint end
	return 1
end

--- Hospital respawn of a dead player (RequestRespawn and the legacy RespawnAtHospital): only when
--- the server has them dead and the respawn time passed. The bed, inventory wipe, bill and the
--- 'respawned' event happen once per death; the revive (full heal) is applied by the bed's timer.
function RespawnPlayer(src, hint)
	local Player = exports['pfm-core']:GetPlayer(src)
	if not Player then return false end
	if PFMed.Down.Limited(src, 'respawn', 5) then return false end
	local ok, a, b = PFMed.Down.CanRespawn(src)
	local err, info = (not ok) and a or nil, ok and a or b
	if not ok then
		if err == 'too_soon' then TriggerClientEvent('QBCore:Notify', src, ('You can respawn in %d seconds'):format(math.max(0, (info.canRespawnAt or 0) - os.time())), 'error') end
		PFMed.Down.SendState(src)
		return false
	end
	local cid = Player.PlayerData.citizenid
	local done = respawnDone[cid]
	local first = not done or done.deadAt ~= info.deadAt
	local jail = (tonumber(Player.PlayerData.metadata['injail']) or 0) > 0
	local bedId, bed, hospitalIndex, bedKey
	if first then
		if jail then
			hospitalIndex = 'jail'
			for i = 1, #Config.Locations['jailbeds'] do
				if not BedOccupants['jail:' .. i] then bedId = i break end
			end
			bedId = bedId or 1
			bed = Config.Locations['jailbeds'][bedId]
			bedKey = 'jail:' .. bedId
		else
			hospitalIndex = NearestHospital(src, hint)
			local beds = Config.Locations['hospital'][hospitalIndex]['beds']
			for i = 1, #beds do
				if not BedOccupants[tostring(hospitalIndex) .. ':' .. i] then bedId = i break end
			end
			bedId = bedId or 1 -- all beds full: the first bed as before
			bed = beds[bedId]
			bedKey = tostring(hospitalIndex) .. ':' .. bedId
		end
		done = { deadAt = info.deadAt, hospital = hospitalIndex, bed = bedId }
		respawnDone[cid] = done
	else
		-- asked again for the same death (the revive was not applied yet): same bed, no second bill
		hospitalIndex, bedId = done.hospital, done.bed
		bed = hospitalIndex == 'jail' and Config.Locations['jailbeds'][bedId] or Config.Locations['hospital'][hospitalIndex]['beds'][bedId]
		bedKey = tostring(hospitalIndex) .. ':' .. bedId
	end
	BedOccupants[bedKey] = src
	local token = PFMed.Down.IssueReviveToken(src, 'respawn', { delay = Config.AIHealTimer, send = false })
	PFMed.Down.MoveGrace(src, (Config.AIHealTimer or 20) + 30)
	TriggerClientEvent('hospital:client:SendToBed', src, bedId, bed, true, token)
	if hospitalIndex == 'jail' then
		TriggerClientEvent('hospital:client:SetBed2', -1, bedId, true)
	else
		TriggerClientEvent('hospital:client:SetBed', -1, bedId, true, hospitalIndex)
	end
	if first then
		PFEmsRequests.Close(cid, 'cancelled', 'respawned', true)
		WipeInventory(Player, src)
		ChargeHospitalBill(Player, ('%s:bill:%s:respawn:%s'):format(GetCurrentResourceName(), cid, tostring(info.deadAt)))
		local name = hospitalIndex ~= 'jail' and Config.Locations['hospital'][hospitalIndex]['name'] or nil
		TriggerClientEvent('hospital:client:SendBillEmail', src, Config.BillCost, name)
		TriggerEvent('pf-ambulancejob:server:respawned', src, cid, hospitalIndex)
	end
	return true
end

RegisterNetEvent('pf-ambulancejob:server:RequestRespawn', function(hospitalId)
	RespawnPlayer(source, hospitalId)
end)

-- legacy name (old clients): the same server-checked respawn
RegisterNetEvent('hospital:server:RespawnAtHospital', function(hospitalIndex)
	RespawnPlayer(source, hospitalIndex)
end)

-- Legacy alert from a client (e.g. pfm-policejob's officer down): only from a player the server has
-- down, rate limited, and the text is built here (the client's text is not shown).
RegisterNetEvent('hospital:server:ambulanceAlert', function()
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if not Player then return end
	local down, state = PFMed.Down.IsDown(src)
	if not down or PFMed.Down.Limited(src, 'alert', DownCfg().AlertSeconds or 30) then return end
	local text = state == 'dead' and Lang:t('info.civ_died') or Lang:t('info.civ_down')
	local job = Player.PlayerData.job or {}
	if job.type == 'leo' then
		text = ('Officer down: %s %s'):format(PatientName(Player), tostring(Player.PlayerData.metadata['callsign'] or '')):gsub('%s+$', '')
	end
	PFMed.Down.AlertEms(src, text)
end)

RegisterNetEvent('hospital:server:LeaveBed', function(id, hospitalIndex)
	local src = source
	local bedKey = tostring(hospitalIndex) .. ':' .. tostring(id)
	if BedOccupants[bedKey] and BedOccupants[bedKey] ~= src then return end
	BedOccupants[bedKey] = nil
	TriggerClientEvent('hospital:client:SetBed', -1, id, false, hospitalIndex)
end)

-- Legacy client-reported injury memory, armour and down flags (architecture 9): accepted and dropped.
-- Injuries live in the engine, armour is read from the server ped (PFMed.Down.ArmourTick), and the
-- down flags are handled by server/medical/downstate.lua (a 'true' report is checked there).
RegisterNetEvent('hospital:server:SyncInjuries', function() end)
RegisterNetEvent('hospital:server:SetWeaponDamage', function() end)
RegisterNetEvent('hospital:server:RestoreWeaponDamage', function() end)
RegisterNetEvent('hospital:server:SetArmor', function() end)

RegisterNetEvent('hospital:server:TreatWounds', function(playerId)
	local src = source
	local Patient = exports['pfm-core']:GetPlayer(playerId)
	if not Patient then return end
	if IsAllowedInvoker() then
		TriggerClientEvent('hospital:client:HealInjuries', Patient.PlayerData.source, 'full')
		return
	end
	local Player = exports['pfm-core']:GetPlayer(src)
	if not IsOnDutyEms(Player) then return end
	if not exports['pfm-inventory']:RemoveItem(src, 'bandage', 1, false, 'hospital:server:TreatWounds') then
		TriggerClientEvent('QBCore:Notify', src, Lang:t('error.no_bandage'), 'error')
		return
	end
	TriggerClientEvent('qb-inventory:client:ItemBox', src, sharedItems['bandage'], 'remove')
	TriggerClientEvent('hospital:client:HealInjuries', Patient.PlayerData.source, 'full')
	-- a medic treated them: a medic call they made is done (a patient still down stays open)
	pcall(function() local svc = Services(); if svc then svc:CloseByRef('citizen:ems.patient', Patient.PlayerData.citizenid, 'completed', 'treated') end end)
end)

-- The doctor count is the server's (on-duty ambulance staff); the client events are ignored.
RegisterNetEvent('hospital:server:AddDoctor', function() end)
RegisterNetEvent('hospital:server:RemoveDoctor', function() end)

local function RefreshDoctorCount()
	local n = OnDutyDoctors()
	if n ~= doctorCount then
		doctorCount = n
		TriggerClientEvent('hospital:client:SetDoctorCount', -1, doctorCount)
	end
	return n
end
AddEventHandler('QBCore:Server:SetDuty', function() RefreshDoctorCount() end)
AddEventHandler('QBCore:Server:OnJobUpdate', function() RefreshDoctorCount() end)

-- Logging out to the character menu keeps the connection (no playerDropped): pfm-core raises this
-- server-local event while the character is still loaded (on a drop too, which PatientLeft takes once).
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
	src = tonumber(src)
	if src then PatientLeft(src, true) end
	RefreshDoctorCount()
end)

AddEventHandler('playerDropped', function()
	local src = source
	PatientLeft(src)
	SetTimeout(0, RefreshDoctorCount) -- after pfm-core dropped the player
	for bedKey, occupant in pairs(BedOccupants) do
		if occupant == src then
			BedOccupants[bedKey] = nil
			local hospitalIndex, bedId = bedKey:match('^(.+):(%d+)$')
			if hospitalIndex and hospitalIndex ~= 'jail' then
				TriggerClientEvent('hospital:client:SetBed', -1, tonumber(bedId), false, tonumber(hospitalIndex) or hospitalIndex)
			end
		end
	end
end)

-- A medic's revive or a citizen's first aid (architecture 9): the server checks the distance (2.5 m),
-- that the target is down, the rules per state (first aid only on an unconscious patient, after the
-- server started it) and consumes the first-aid kit; the patient's client then answers a revive
-- token. `isOldMan` (a client-chosen paid revive) is ignored; nobody is banned for a missing item.
RegisterNetEvent('hospital:server:RevivePlayer', function(playerId)
	local src = source
	if IsAllowedInvoker() then
		-- a server resource on Config.AllowedRevivalResources (its own server-side TriggerEvent)
		local id = math.tointeger(tonumber(playerId))
		if id and exports['pfm-core']:GetPlayer(id) then PFMed.Down.Revive(id, { mode = 'script', reason = GetInvokingResource() }) end
		return
	end
	src = tonumber(src)
	if not src or src <= 0 then return end
	PFMed.Down.RequestRevive(src, playerId)
end)

RegisterNetEvent('hospital:server:SendDoctorAlert', function(hospitalName)
	local src = source
	if not doctorCalled then
		doctorCalled = true
		local players = QBCore.Functions.GetQBPlayers()
		for _, v in pairs(players) do
			if v.PlayerData.job.name == 'ambulance' and v.PlayerData.job.onduty then
				TriggerClientEvent('QBCore:Notify', v.PlayerData.source, Lang:t('info.dr_needed', { hospital = hospitalName }), 'ambulance')
			end
		end
		SetTimeout(Config.DocCooldown * 60000, function()
			doctorCalled = false
		end)
	else
		TriggerClientEvent('QBCore:Notify', src, 'Doctor has already been notified', 'error')
	end
end)

-- Civilian first aid: the server checks the kit, the distance and the patient's state, then starts
-- the helper's progress bar itself (the target's client is no longer asked).
RegisterNetEvent('hospital:server:UseFirstAid', function(targetId)
	local src = tonumber(source)
	if not src or src <= 0 then return end
	PFMed.Down.StartFirstAid(src, targetId)
end)

-- The target's answer the old flow asked for: ignored (any client could aim it at anyone).
RegisterNetEvent('hospital:server:CanHelp', function() end)

RegisterNetEvent('hospital:server:removeBandage', function()
	local Player = exports['pfm-core']:GetPlayer(source)
	if not Player then return end
	exports['pfm-inventory']:RemoveItem(source, 'bandage', 1, false, 'hospital:server:removeBandage')
end)

RegisterNetEvent('hospital:server:removeIfaks', function()
	local Player = exports['pfm-core']:GetPlayer(source)
	if not Player then return end
	exports['pfm-inventory']:RemoveItem(source, 'ifaks', 1, false, 'hospital:server:removeIfaks')
end)

RegisterNetEvent('hospital:server:removePainkillers', function()
	local Player = exports['pfm-core']:GetPlayer(source)
	if not Player then return end
	exports['pfm-inventory']:RemoveItem(source, 'painkillers', 1, false, 'hospital:server:removePainkillers')
end)

-- Removed (free food and water for any client): a server revive resets the needs itself.
RegisterNetEvent('hospital:server:resetHungerThirst', function() end)

-- The personal EMS stash: ambulance job, on duty, at a stash point (server position).
RegisterNetEvent('qb-ambulancejob:server:stash', function()
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if not Player or not IsOnDutyEms(Player) then return end
	local pos, near = ServerPos(src), false
	for _, point in ipairs(Config.Locations['stash'] or {}) do
		if PFMed.Down.Dist(pos, point) <= (DownCfg().StashDistance or 3.0) then near = true break end
	end
	if not near then return end
	local citizenId = Player.PlayerData.citizenid
	local stashName = 'ambulancestash_' .. citizenId
	exports['pfm-inventory']:OpenInventory(src, stashName)
end)

-- Callbacks

QBCore.Functions.CreateCallback('hospital:GetDoctors', function(_, cb)
	local amount = 0
	local players = QBCore.Functions.GetQBPlayers()
	for _, v in pairs(players) do
		if v.PlayerData.job.name == 'ambulance' and v.PlayerData.job.onduty then
			amount = amount + 1
		end
	end
	cb(amount)
end)

-- An on-duty medic within StatusDistance reads a patient's injuries (from the engine, in the shape
-- this callback always returned); anyone else gets nothing.
QBCore.Functions.CreateCallback('hospital:GetPlayerStatus', function(source, cb, playerId)
	local src = tonumber(source)
	local target = math.tointeger(tonumber(playerId))
	local Medic = src and exports['pfm-core']:GetPlayer(src)
	local Patient = target and exports['pfm-core']:GetPlayer(target)
	if not Medic or not Patient or not IsOnDutyEms(Medic) or PFMed.Down.PlayerDistance(src, target) > (DownCfg().StatusDistance or 5.0) then
		return cb({ WEAPONWOUNDS = {} })
	end
	cb(PFMed.Down.LegacyStatus(Patient.PlayerData.citizenid))
end)

-- The caller's own visible bleeding level (0..4) from the engine.
QBCore.Functions.CreateCallback('hospital:GetPlayerBleeding', function(source, cb)
	cb(PFMed.Down.OwnBleeding(tonumber(source)))
end)

-- Commands

QBCore.Commands.Add('911e', Lang:t('info.ems_report'), { { name = 'message', help = Lang:t('info.message_sent') } }, false, function(source, args)
	local src = source
	local message
	if args[1] then message = table.concat(args, ' ') else message = Lang:t('info.civ_call') end
	local ped = GetPlayerPed(src)
	local coords = GetEntityCoords(ped)
	local players = QBCore.Functions.GetQBPlayers()
	for _, v in pairs(players) do
		if v.PlayerData.job.name == 'ambulance' and v.PlayerData.job.onduty then
			TriggerClientEvent('hospital:client:ambulanceAlert', v.PlayerData.source, coords, message)
		end
	end
	-- the call also lands in the medics' Dispatch app, under the same ref as a Services app call, so a
	-- caller has one open medic call at a time
	local Caller = exports['pfm-core']:GetPlayer(src)
	local svc = Caller and Services()
	if svc then
		local cid = Caller.PlayerData.citizenid
		pcall(function()
			svc:CreateRequest({
				kind = 'ems.patient', title = 'Medical call from ' .. PatientName(Caller),
				details = tostring(message):gsub('%c', ' '):sub(1, 300), coords = vector3(coords.x, coords.y, coords.z),
				ref = { type = 'citizen:ems.patient', id = cid }, requester = cid,
				from = { type = 'citizen', id = cid, name = PatientName(Caller) },
			})
		end)
	end
end)

QBCore.Commands.Add('status', Lang:t('info.check_health'), {}, false, function(source, _)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player.PlayerData.job.name == 'ambulance' then
		TriggerClientEvent('hospital:client:CheckStatus', src)
	else
		TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_ems'), 'error')
	end
end)

QBCore.Commands.Add('heal', Lang:t('info.heal_player'), {}, false, function(source, _)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player.PlayerData.job.name == 'ambulance' then
		TriggerClientEvent('hospital:client:TreatWounds', src)
	else
		TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_ems'), 'error')
	end
end)

QBCore.Commands.Add('revivep', Lang:t('info.revive_player'), {}, false, function(source, _)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player.PlayerData.job.name == 'ambulance' then
		TriggerClientEvent('hospital:client:RevivePlayer', src)
	else
		TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_ems'), 'error')
	end
end)

QBCore.Commands.Add('revive', Lang:t('info.revive_player_a'), { { name = 'id', help = Lang:t('info.player_id') } }, false, function(source, args)
	local src = source
	local id = args[1] and tonumber(args[1]) or src
	if not exports['pfm-core']:GetPlayer(id) then
		TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_online'), 'error')
		return
	end
	local Admin = exports['pfm-core']:GetPlayer(src)
	PFMed.Down.Revive(id, { mode = 'admin', reason = 'command', byInfo = { src = src, cid = Admin and Admin.PlayerData.citizenid, kind = 'admin' } })
end, 'admin')

QBCore.Commands.Add('setpain', Lang:t('info.pain_level'), { { name = 'id', help = Lang:t('info.player_id') } }, false, function(source, args)
	local src = source
	if args[1] then
		local Player = exports['pfm-core']:GetPlayer(tonumber(args[1]))
		if Player then
			TriggerClientEvent('hospital:client:SetPain', Player.PlayerData.source)
		else
			TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_online'), 'error')
		end
	else
		TriggerClientEvent('hospital:client:SetPain', src)
	end
end, 'admin')

QBCore.Commands.Add('kill', Lang:t('info.kill'), { { name = 'id', help = Lang:t('info.player_id') } }, false, function(source, args)
	local src = source
	local id = args[1] and tonumber(args[1]) or src
	if not exports['pfm-core']:GetPlayer(id) then
		TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_online'), 'error')
		return
	end
	PFMed.Down.Kill(id, { actor = { src = src, kind = 'admin' } })
end, 'admin')

QBCore.Commands.Add('aheal', Lang:t('info.heal_player_a'), { { name = 'id', help = Lang:t('info.player_id') } }, false, function(source, args)
	local src = source
	local id = args[1] and tonumber(args[1]) or src
	if not exports['pfm-core']:GetPlayer(id) then
		TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_online'), 'error')
		return
	end
	PFMed.Down.Revive(id, { mode = 'admin', reason = 'aheal' })
end, 'admin')

-- Items

QBCore.Functions.CreateUseableItem('ifaks', function(source, item)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player.GetItemByName(item.name) ~= nil then
		TriggerClientEvent('hospital:client:UseIfaks', src)
	end
end)

QBCore.Functions.CreateUseableItem('bandage', function(source, item)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player.GetItemByName(item.name) ~= nil then
		TriggerClientEvent('hospital:client:UseBandage', src)
	end
end)

QBCore.Functions.CreateUseableItem('painkillers', function(source, item)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player.GetItemByName(item.name) ~= nil then
		TriggerClientEvent('hospital:client:UsePainkillers', src)
	end
end)

QBCore.Functions.CreateUseableItem('firstaid', function(source, item)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player.GetItemByName(item.name) ~= nil then
		TriggerClientEvent('hospital:client:UseFirstAid', src)
	end
end)

exports('GetDoctorCount', function() return doctorCount end)

-- Vehicles this job may spawn through pfm-core (QBCore:Server:SpawnVehicle only spawns registered
-- job vehicles or vehicles the server granted a ticket for)
CreateThread(function()
    local models = { Config.Helicopter }
    for _, grade in pairs(Config.AuthorizedVehicles or {}) do
        for model in pairs(grade) do models[#models + 1] = model end
    end
    pcall(function() exports['pfm-core']:RegisterJobVehicles('ambulance', models) end)
end)
