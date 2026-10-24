-- ============================================================================
-- PF MECHANIC JOB - TUNING STORE (Database Operations)
-- ============================================================================

local QBCore = exports['pfm-core']:GetCoreObject()
local EngineConfig = require('config.engineering')

local TuningStore = {}
TuningStore.Cache = {}             -- In-memory cache [plate] = tuningData
TuningStore.LastSync = {}          -- [plate] = lastUpdateTime
TuningStore.CacheDirty = {}        -- [plate] = true if needs saving

-- ============================================================================
-- Database Operations
-- ============================================================================

---Get or create a tuning record for a vehicle
---@param plate string Vehicle plate
---@param model string Vehicle model
---@return table tuningData
function TuningStore:GetOrCreateTuning(plate, model)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then
        print(string.format('[Engineering] Invalid plate: %s', plate))
        return nil
    end
    
    -- Check cache first
    if self.Cache[plate] then
        if Config.Debug then
            print(string.format('[Engineering] Cache hit for plate: %s', plate))
        end
        return self.Cache[plate]
    end
    
    -- Try to load from database
    local tuningRow = MySQL.single.await(
        'SELECT * FROM pf_vehicle_tuning WHERE plate = ? LIMIT 1',
        { plate }
    )
    
    if tuningRow then
        if Config.Debug then
            print(string.format('[Engineering] Loaded tuning for plate: %s', plate))
        end
        self.Cache[plate] = tuningRow
        return tuningRow
    end
    
    -- Create new entry
    if Config.Debug then
        print(string.format('[Engineering] Creating new tuning record for plate: %s', plate))
    end
    
    local newTuning = {
        plate = plate,
        model = model,
        engine_block = 'stock',
        internals = 'stock',
        forced_induction = 'none',
        intercooler = 'none',
        intake = 'stock',
        exhaust = 'stock',
        fuel_injectors = 'stock',
        fuel_pump = 'stock',
        fuel_type = 'pump',
        ecu_map = 'stock',
        ignition = 'stock',
        cooling = 'stock',
        oil_system = 'stock',
        clutch = 'stock',
        gearbox = 'stock',
        differential = 'stock',
        drivetrain_rating_nm = 300,
        target_boost_psi = 0,
        target_hp = nil,
        target_torque_nm = nil,
        power_limit_multiplier = 1.0,
        torque_limit_multiplier = 1.0,
        engine_wear = 0,
        turbo_wear = 0,
        clutch_wear = 0,
        gearbox_wear = 0,
        diff_wear = 0,
        oil_quality = 100,
        coolant_quality = 100,
        engine_heat = 0,
        turbo_heat = 0,
        tire_compound = 'street',
        tire_wear = 0,
        fuel_consumption_multiplier = 1.0,
        maintenance_cost_multiplier = 1.0
    }
    
    -- Save to database
    local result = MySQL.insert.await(
        'INSERT INTO pf_vehicle_tuning (plate, model, engine_block, internals, forced_induction, intercooler, intake, exhaust, fuel_injectors, fuel_pump, fuel_type, ecu_map, ignition, cooling, oil_system, clutch, gearbox, differential, drivetrain_rating_nm, target_boost_psi, power_limit_multiplier, torque_limit_multiplier, engine_wear, turbo_wear, clutch_wear, gearbox_wear, diff_wear, oil_quality, coolant_quality, engine_heat, turbo_heat, tire_compound, tire_wear, fuel_consumption_multiplier, maintenance_cost_multiplier) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {plate, model, 'stock', 'stock', 'none', 'none', 'stock', 'stock', 'stock', 'stock', 'pump', 'stock', 'stock', 'stock', 'stock', 'stock', 'stock', 'stock', 300, 0, 1.0, 1.0, 0, 0, 0, 0, 0, 100, 100, 0, 0, 'street', 0, 1.0, 1.0}
    )
    
    if result then
        newTuning.id = result
        self.Cache[plate] = newTuning
    end
    
    return newTuning
end

---Get tuning data from cache or database
---@param plate string Vehicle plate
---@return table tuningData or nil
function TuningStore:GetTuning(plate)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return nil end
    
    if self.Cache[plate] then
        return self.Cache[plate]
    end
    
    local tuningRow = MySQL.single.await(
        'SELECT * FROM pf_vehicle_tuning WHERE plate = ? LIMIT 1',
        { plate }
    )
    
    if tuningRow then
        self.Cache[plate] = tuningRow
    end
    
    return tuningRow
end

---Save tuning data to database
---@param plate string Vehicle plate
---@param tuningData table New tuning data
---@return boolean success
function TuningStore:SaveTuning(plate, tuningData)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return false end
    
    local updateQuery = [[
        UPDATE pf_vehicle_tuning 
        SET engine_block = ?, internals = ?, forced_induction = ?, intercooler = ?, intake = ?, 
            exhaust = ?, fuel_injectors = ?, fuel_pump = ?, fuel_type = ?, ecu_map = ?, 
            ignition = ?, cooling = ?, oil_system = ?, clutch = ?, gearbox = ?, differential = ?,
            drivetrain_rating_nm = ?, target_boost_psi = ?, target_hp = ?, target_torque_nm = ?,
            power_limit_multiplier = ?, torque_limit_multiplier = ?, 
            engine_wear = ?, turbo_wear = ?, clutch_wear = ?, gearbox_wear = ?, diff_wear = ?,
            oil_quality = ?, coolant_quality = ?, engine_heat = ?, turbo_heat = ?,
            tire_compound = ?, tire_wear = ?, fuel_consumption_multiplier = ?, maintenance_cost_multiplier = ?
        WHERE plate = ?
    ]]
    
    local success = MySQL.update.await(updateQuery, {
        tuningData.engine_block,
        tuningData.internals,
        tuningData.forced_induction,
        tuningData.intercooler,
        tuningData.intake,
        tuningData.exhaust,
        tuningData.fuel_injectors,
        tuningData.fuel_pump,
        tuningData.fuel_type,
        tuningData.ecu_map,
        tuningData.ignition,
        tuningData.cooling,
        tuningData.oil_system,
        tuningData.clutch,
        tuningData.gearbox,
        tuningData.differential,
        tuningData.drivetrain_rating_nm,
        tuningData.target_boost_psi,
        tuningData.target_hp,
        tuningData.target_torque_nm,
        tuningData.power_limit_multiplier,
        tuningData.torque_limit_multiplier,
        tuningData.engine_wear,
        tuningData.turbo_wear,
        tuningData.clutch_wear,
        tuningData.gearbox_wear,
        tuningData.diff_wear,
        tuningData.oil_quality,
        tuningData.coolant_quality,
        tuningData.engine_heat,
        tuningData.turbo_heat,
        tuningData.tire_compound,
        tuningData.tire_wear,
        tuningData.fuel_consumption_multiplier,
        tuningData.maintenance_cost_multiplier,
        plate
    })
    
    if success then
        self.Cache[plate] = tuningData
        self.CacheDirty[plate] = nil
        self.LastSync[plate] = GetGameTimer()
    end
    
    return success
end

---Mark a vehicle as dirty (needs saving)
---@param plate string Vehicle plate
function TuningStore:MarkDirty(plate)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return end
    self.CacheDirty[plate] = true
end

---Add a service history record
---@param plate string Vehicle plate
---@param serviceType string Type of service
---@param cost integer Cost of service
---@param mechanicId string ID of mechanic
function TuningStore:AddServiceHistory(plate, serviceType, cost, mechanicId)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return end
    
    MySQL.insert.await(
        'INSERT INTO pf_vehicle_service_history (plate, service_type, cost, mechanic_id) VALUES (?, ?, ?, ?)',
        { plate, serviceType, cost, mechanicId }
    )
end

---Flush all dirty records to database
function TuningStore:FlushDirty()
    for plate, _ in pairs(self.CacheDirty) do
        if self.Cache[plate] then
            self:SaveTuning(plate, self.Cache[plate])
        end
    end
end

---Clear old cache entries (older than 2 hours)
function TuningStore:PruneCache()
    local now = GetGameTimer()
    local maxAge = 2 * 60 * 60 * 1000  -- 2 hours
    
    for plate, syncTime in pairs(self.LastSync) do
        if (now - syncTime) > maxAge then
            self.Cache[plate] = nil
            self.LastSync[plate] = nil
            self.CacheDirty[plate] = nil
        end
    end
end

-- ============================================================================
-- Periodic Cache Flush
-- ============================================================================

SetInterval(function()
    if not EngineConfig.Enabled then return end
    TuningStore:FlushDirty()
    TuningStore:PruneCache()
end, EngineConfig.CacheFlushInterval or 30000)

return TuningStore
