local PlayerInjuries = {}
local PlayerWeaponWounds = {}
local QBCore = exports['pfm-core']:GetCoreObject({ 'Functions', 'Commands' })
local sharedItems = exports['pfm-core']:GetShared('Items')
local doctorCount = 0
local doctorCalled = false
local Doctors = {}
local BedOccupants = {} -- ['<hospitalIndex>:<bedId>'] = src, ['jail:<bedId>'] = src

-- Hospital bills go through the pfm-banking ledger (PFPayout, '@pfm-banking/payouts.lua'): the patient's
-- bank pays first, and the ambulance account is credited only for a bill that was paid. (The bill was
-- not checked, so the ambulance account was credited even when a patient could not pay.) A patient
-- who cannot pay is still treated, as before.
local function ChargeHospitalBill(Player)
	-- hospital treatment (check-in bed or respawn) heals every recorded injury, critical ones included
	if ClearCitizenInjuries then ClearCitizenInjuries(Player.PlayerData.citizenid) end
	local key = ('%s:bill:%s:%s'):format(GetCurrentResourceName(), Player.PlayerData.citizenid, PFPayout.NewId())
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

local function GetHospitalBed(hospitalIndex, bedId)
	local hospital = Config.Locations['hospital'][hospitalIndex]
	if not hospital or not hospital['beds'] then return nil end
	return hospital['beds'][bedId]
end

-- ── EMS dispatch (pf-services) ─────────────────────────────────────
-- A player who goes down gets one 'ems.patient' service request at their server position (medics see
-- it in the Dispatch app); it closes as completed when a medic (or a first-aid kit) revives them and as
-- cancelled when they respawn at hospital, check in, are revived by an admin, get up or log off.
-- The down state itself is reported by the player's own client (hospital:server:SetLaststandStatus /
-- SetDeathStatus); the server only acts on a real up -> down change, uses its own position and allows
-- one new request per citizen per PATIENT_COOLDOWN, so toggling cannot flood the medics.
local PATIENT_COOLDOWN = 60
local lastPatientRequest = {} -- [citizenid] = os.time()
local downBySource = {}       -- [src] = citizenid while that player is down

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
	if lastPatientRequest[cid] and now - lastPatientRequest[cid] < PATIENT_COOLDOWN then return nil end
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
	pcall(function() svc:Emit('ems.patient', {}, { title = 'Person down', coords = coords, actor = cid, dedupe = cid }) end)
	return ok and res or nil
end

--- Closes the patient's request(s). status 'completed' credits the medic who accepted it (if any).
function PFEmsRequests.Close(cid, status, reason, includeCitizenCall)
	local svc = Services()
	if not svc or not cid then return end
	pcall(function() svc:CloseByRef('patient', cid, status, reason) end)
	-- a citizen who called a medic from the Services app (or /911e) has been seen to as well
	if includeCitizenCall then pcall(function() svc:CloseByRef('citizen:ems.patient', cid, status, reason) end) end
end

-- the metadata flags changed: open on up -> down, close on down -> up
local function DownStateChanged(Player, wasDown)
	local isDown = IsDown(Player)
	local src, cid = Player.PlayerData.source, Player.PlayerData.citizenid
	if isDown and not wasDown then
		downBySource[src] = cid
		PFEmsRequests.Open(Player)
	elseif wasDown and not isDown then
		downBySource[src] = nil
		PFEmsRequests.Close(cid, 'cancelled', 'recovered')
	end
end

-- Events

-- Compatibility with txAdmin Menu's heal options.
-- This is an admin only server side event that will pass the target player id or -1.
AddEventHandler('txAdmin:events:healedPlayer', function(eventData)
	if GetInvokingResource() ~= 'monitor' or type(eventData) ~= 'table' or type(eventData.id) ~= 'number' then
		return
	end

	TriggerClientEvent('hospital:client:Revive', eventData.id)
	TriggerClientEvent('hospital:client:HealInjuries', eventData.id, 'full')
	local Patient = exports['pfm-core']:GetPlayer(eventData.id)
	if Patient then PFEmsRequests.Close(Patient.PlayerData.citizenid, 'cancelled', 'admin_revive') end
end)

RegisterNetEvent('hospital:server:SendToBed', function(bedId, isRevive, hospitalIndex)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if not Player then return end
	local bed = GetHospitalBed(hospitalIndex, bedId)
	if not bed then return end
	local bedKey = tostring(hospitalIndex) .. ':' .. tostring(bedId)
	if BedOccupants[bedKey] and BedOccupants[bedKey] ~= src then
		TriggerClientEvent('QBCore:Notify', src, Lang:t('error.beds_taken'), 'error')
		return
	end
	BedOccupants[bedKey] = src
	TriggerClientEvent('hospital:client:SendToBed', src, bedId, bed, isRevive)
	TriggerClientEvent('hospital:client:SetBed', -1, bedId, true, hospitalIndex)
	-- checked in at the hospital desk: no medic needs to drive out any more
	if isRevive then PFEmsRequests.Close(Player.PlayerData.citizenid, 'cancelled', 'checked_in', true) end
	ChargeHospitalBill(Player)
	TriggerClientEvent('hospital:client:SendBillEmail', src, Config.BillCost, Config.Locations['hospital'][hospitalIndex]['name'])
end)

RegisterNetEvent('hospital:server:RespawnAtHospital', function(hospitalIndex)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if not Player then return end
	PFEmsRequests.Close(Player.PlayerData.citizenid, 'cancelled', 'respawned', true)
	if Player.PlayerData.metadata['injail'] > 0 then
		for i = 1, #Config.Locations['jailbeds'] do
			local v = Config.Locations['jailbeds'][i]
			if not v.taken and not BedOccupants['jail:' .. i] then
				BedOccupants['jail:' .. i] = src
				TriggerClientEvent('hospital:client:SendToBed', src, i, v, true)
				TriggerClientEvent('hospital:client:SetBed2', -1, i, true)
				if Config.WipeInventoryOnRespawn then
					Player.ClearInventory()
					MySQL.Async.execute('UPDATE players SET inventory = ? WHERE citizenid = ?', { json.encode({}), Player.PlayerData.citizenid })
					TriggerClientEvent('QBCore:Notify', src, Lang:t('error.possessions_taken'), 'error')
				end
				ChargeHospitalBill(Player)
				TriggerClientEvent('hospital:client:SendBillEmail', src, Config.BillCost)
				return
			end
		end

		TriggerClientEvent('hospital:client:SendToBed', src, 1, Config.Locations['jailbeds'][1], true)
		TriggerClientEvent('hospital:client:SetBed', -1, 1, true)
		if Config.WipeInventoryOnRespawn then
			Player.ClearInventory()
			MySQL.Async.execute('UPDATE players SET inventory = ? WHERE citizenid = ?', { json.encode({}), Player.PlayerData.citizenid })
			TriggerClientEvent('QBCore:Notify', src, Lang:t('error.possessions_taken'), 'error')
		end
		ChargeHospitalBill(Player)
		TriggerClientEvent('hospital:client:SendBillEmail', src, Config.BillCost)
	else
		if not Config.Locations['hospital'][hospitalIndex] then return end
		for i = 1, #Config.Locations['hospital'][hospitalIndex]['beds'] do
			local v = Config.Locations['hospital'][hospitalIndex]['beds'][i]
			if not v.taken and not BedOccupants[tostring(hospitalIndex) .. ':' .. i] then
				BedOccupants[tostring(hospitalIndex) .. ':' .. i] = src
				TriggerClientEvent('hospital:client:SendToBed', src, i, v, true)
				TriggerClientEvent('hospital:client:SetBed', -1, i, true, hospitalIndex)
				if Config.WipeInventoryOnRespawn then
					Player.ClearInventory()
					MySQL.update('UPDATE players SET inventory = ? WHERE citizenid = ?', { json.encode({}), Player.PlayerData.citizenid })
					TriggerClientEvent('QBCore:Notify', src, Lang:t('error.possessions_taken'), 'error')
				end
				ChargeHospitalBill(Player)
				TriggerClientEvent('hospital:client:SendBillEmail', src, Config.BillCost, Config.Locations['hospital'][hospitalIndex]['name'])
				return
			end
		end
		-- All beds were full, placing in first bed as fallback
		TriggerClientEvent('hospital:client:SendToBed', src, 1, Config.Locations['hospital'][hospitalIndex]['beds'][1], true)
		TriggerClientEvent('hospital:client:SetBed', -1, 1, true, hospitalIndex)
		if Config.WipeInventoryOnRespawn then
			Player.ClearInventory()
			MySQL.update('UPDATE players SET inventory = ? WHERE citizenid = ?', { json.encode({}), Player.PlayerData.citizenid })
			TriggerClientEvent('QBCore:Notify', src, Lang:t('error.possessions_taken'), 'error')
		end
		ChargeHospitalBill(Player)
		TriggerClientEvent('hospital:client:SendBillEmail', src, Config.BillCost, Config.Locations['hospital'][hospitalIndex]['name'])
	end
end)

RegisterNetEvent('hospital:server:ambulanceAlert', function(text)
	local src = source
	local ped = GetPlayerPed(src)
	local coords = GetEntityCoords(ped)
	local players = QBCore.Functions.GetQBPlayers()
	for _, v in pairs(players) do
		if v.PlayerData.job.name == 'ambulance' and v.PlayerData.job.onduty then
			TriggerClientEvent('hospital:client:ambulanceAlert', v.PlayerData.source, coords, text)
		end
	end
end)

RegisterNetEvent('hospital:server:LeaveBed', function(id, hospitalIndex)
	local src = source
	local bedKey = tostring(hospitalIndex) .. ':' .. tostring(id)
	if BedOccupants[bedKey] and BedOccupants[bedKey] ~= src then return end
	BedOccupants[bedKey] = nil
	TriggerClientEvent('hospital:client:SetBed', -1, id, false, hospitalIndex)
end)

RegisterNetEvent('hospital:server:SyncInjuries', function(data)
	local src = source
	if type(data) ~= 'table' then return end
	PlayerInjuries[src] = data
end)

RegisterNetEvent('hospital:server:SetWeaponDamage', function(data)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player and (data == nil or type(data) == 'table') then
		PlayerWeaponWounds[Player.PlayerData.source] = data
	end
end)

RegisterNetEvent('hospital:server:RestoreWeaponDamage', function()
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	PlayerWeaponWounds[Player.PlayerData.source] = nil
end)

RegisterNetEvent('hospital:server:SetDeathStatus', function(isDead)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player then
		local wasDown = IsDown(Player)
		Player.SetMetaData('isdead', isDead)
		DownStateChanged(Player, wasDown)
	end
end)

RegisterNetEvent('hospital:server:SetLaststandStatus', function(bool)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player then
		local wasDown = IsDown(Player)
		Player.SetMetaData('inlaststand', bool)
		DownStateChanged(Player, wasDown)
	end
end)

RegisterNetEvent('hospital:server:SetArmor', function(amount)
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if Player and Player.PlayerData.job.name == 'ambulance' then
		local sanitizedAmount = tonumber(amount) or 0
		sanitizedAmount = math.floor(sanitizedAmount)
		sanitizedAmount = math.max(0, math.min(100, sanitizedAmount))
		Player.SetMetaData('armor', sanitizedAmount)
	end
end)

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

RegisterNetEvent('hospital:server:AddDoctor', function(job)
	if job == 'ambulance' then
		local src = source
		local Player = exports['pfm-core']:GetPlayer(src)
		if not Player or Player.PlayerData.job.name ~= 'ambulance' then return end
		if Doctors[src] then return end
		doctorCount = doctorCount + 1
		TriggerClientEvent('hospital:client:SetDoctorCount', -1, doctorCount)
		Doctors[src] = true
	end
end)

RegisterNetEvent('hospital:server:RemoveDoctor', function(job)
	if job == 'ambulance' then
		local src = source
		if not Doctors[src] then return end
		doctorCount = doctorCount - 1
		TriggerClientEvent('hospital:client:SetDoctorCount', -1, doctorCount)
		Doctors[src] = nil
	end
end)

AddEventHandler('playerDropped', function()
	local src = source
	if downBySource[src] then
		PFEmsRequests.Close(downBySource[src], 'cancelled', 'left')
		downBySource[src] = nil
	end
	if Doctors[src] then
		doctorCount = doctorCount - 1
		TriggerClientEvent('hospital:client:SetDoctorCount', -1, doctorCount)
		Doctors[src] = nil
	end
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

RegisterNetEvent('hospital:server:RevivePlayer', function(playerId, isOldMan)
	local src = source
	local Patient = exports['pfm-core']:GetPlayer(playerId)
	if Patient and IsAllowedInvoker() then
		TriggerClientEvent('hospital:client:Revive', Patient.PlayerData.source)
		PFEmsRequests.Close(Patient.PlayerData.citizenid, 'cancelled', 'admin_revive')
		return
	end
	local Player = exports['pfm-core']:GetPlayer(src)
	if not Player then return end
	local oldMan = isOldMan or false
	if Patient then
		if IsOnDutyEms(Player) or QBCore.Functions.HasItem(src, 'firstaid', 1) then
			if oldMan then
				if PFPayout.Charge(Player, 'cash', 5000, { key = ('%s:revive:%s:%s'):format(GetCurrentResourceName(), Player.PlayerData.citizenid, PFPayout.NewId()), kind = 'purchase', reason = 'Revive', quiet = true }) then
					exports['pfm-inventory']:RemoveItem(src, 'firstaid', 1, false, 'hospital:server:RevivePlayer')
					TriggerClientEvent('qb-inventory:client:ItemBox', src, sharedItems['firstaid'], 'remove')
					TriggerClientEvent('hospital:client:Revive', Patient.PlayerData.source)
					PFEmsRequests.Close(Patient.PlayerData.citizenid, 'completed', 'revived', true)
				else
					TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_enough_money'), 'error')
				end
			else
				exports['pfm-inventory']:RemoveItem(src, 'firstaid', 1, false, 'hospital:server:RevivePlayer')
				TriggerClientEvent('qb-inventory:client:ItemBox', src, sharedItems['firstaid'], 'remove')
				TriggerClientEvent('hospital:client:Revive', Patient.PlayerData.source)
				-- the request completes (and credits the medic who had accepted it, if any)
				PFEmsRequests.Close(Patient.PlayerData.citizenid, 'completed', 'revived', true)
			end
		elseif Player.PlayerData.job.name == 'ambulance' then
			-- off-duty medic without a firstaid kit: deny, don't ban
			TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_ems'), 'error')
		else
			MySQL.insert('INSERT INTO bans (name, license, discord, ip, reason, expire, bannedby) VALUES (?, ?, ?, ?, ?, ?, ?)', {
				GetPlayerName(src),
				QBCore.Functions.GetIdentifier(src, 'license'),
				QBCore.Functions.GetIdentifier(src, 'discord'),
				QBCore.Functions.GetIdentifier(src, 'ip'),
				'Trying to revive theirselves or other players',
				2147483647,
				'qb-ambulancejob'
			})
			TriggerEvent('qb-log:server:CreateLog', 'ambulancejob', 'Player Banned', 'red', string.format('%s was banned by %s for %s', GetPlayerName(src), 'qb-ambulancejob', 'Trying to revive theirselves or other players'), true)
			DropPlayer(src, 'You were permanently banned by the server for: Exploiting')
		end
	end
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

RegisterNetEvent('hospital:server:UseFirstAid', function(targetId)
	local src = source
	if not QBCore.Functions.HasItem(src, 'firstaid', 1) then return end
	local Target = exports['pfm-core']:GetPlayer(targetId)
	if Target then
		TriggerClientEvent('hospital:client:CanHelp', targetId, src)
	end
end)

RegisterNetEvent('hospital:server:CanHelp', function(helperId, canHelp)
	local src = source
	if canHelp then
		TriggerClientEvent('hospital:client:HelpPerson', helperId, src)
	else
		TriggerClientEvent('QBCore:Notify', helperId, Lang:t('error.cant_help'), 'error')
	end
end)

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

RegisterNetEvent('hospital:server:resetHungerThirst', function()
	local Player = exports['pfm-core']:GetPlayer(source)

	if not Player then return end

	Player.SetMetaData('hunger', 100)
	Player.SetMetaData('thirst', 100)

	TriggerClientEvent('hud:client:UpdateNeeds', source, 100, 100)
end)

RegisterNetEvent('qb-ambulancejob:server:stash', function()
	local src = source
	local Player = exports['pfm-core']:GetPlayer(src)
	if not Player then return end
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

QBCore.Functions.CreateCallback('hospital:GetPlayerStatus', function(_, cb, playerId)
	local Player = exports['pfm-core']:GetPlayer(playerId)
	local injuries = {}
	injuries['WEAPONWOUNDS'] = {}
	if Player then
		if PlayerInjuries[Player.PlayerData.source] then
			if (PlayerInjuries[Player.PlayerData.source].isBleeding > 0) then
				injuries['BLEED'] = PlayerInjuries[Player.PlayerData.source].isBleeding
			end
			for k, _ in pairs(PlayerInjuries[Player.PlayerData.source].limbs) do
				if PlayerInjuries[Player.PlayerData.source].limbs[k].isDamaged then
					injuries[k] = PlayerInjuries[Player.PlayerData.source].limbs[k]
				end
			end
		end
		if PlayerWeaponWounds[Player.PlayerData.source] then
			for k, v in pairs(PlayerWeaponWounds[Player.PlayerData.source]) do
				injuries['WEAPONWOUNDS'][k] = v
			end
		end
	end
	cb(injuries)
end)

QBCore.Functions.CreateCallback('hospital:GetPlayerBleeding', function(source, cb)
	local src = source
	if PlayerInjuries[src] and PlayerInjuries[src].isBleeding then
		cb(PlayerInjuries[src].isBleeding)
	else
		cb(nil)
	end
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
	if args[1] then
		local Player = exports['pfm-core']:GetPlayer(tonumber(args[1]))
		if Player then
			TriggerClientEvent('hospital:client:Revive', Player.PlayerData.source)
			PFEmsRequests.Close(Player.PlayerData.citizenid, 'cancelled', 'admin_revive')
		else
			TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_online'), 'error')
		end
	else
		TriggerClientEvent('hospital:client:Revive', src)
		local Self = exports['pfm-core']:GetPlayer(src)
		if Self then PFEmsRequests.Close(Self.PlayerData.citizenid, 'cancelled', 'admin_revive') end
	end
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
	if args[1] then
		local Player = exports['pfm-core']:GetPlayer(tonumber(args[1]))
		if Player then
			TriggerClientEvent('hospital:client:KillPlayer', Player.PlayerData.source)
		else
			TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_online'), 'error')
		end
	else
		TriggerClientEvent('hospital:client:KillPlayer', src)
	end
end, 'admin')

QBCore.Commands.Add('aheal', Lang:t('info.heal_player_a'), { { name = 'id', help = Lang:t('info.player_id') } }, false, function(source, args)
	local src = source
	if args[1] then
		local Player = exports['pfm-core']:GetPlayer(tonumber(args[1]))
		if Player then
			TriggerClientEvent('hospital:client:adminHeal', Player.PlayerData.source)
		else
			TriggerClientEvent('QBCore:Notify', src, Lang:t('error.not_online'), 'error')
		end
	else
		TriggerClientEvent('hospital:client:adminHeal', src)
	end
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
