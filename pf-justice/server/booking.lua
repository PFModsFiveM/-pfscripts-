-- pf-justice booking (PF_ARCHITECTURE 4.7.4): booking number, identity read by the server,
-- medical screening and the property receipt.
--
--   * Booking number BK-<yyyymmdd>-<seq> (seq per day, 4 digits, unique in pf_justice_bookings).
--   * Fingerprint and blood type come from the citizen's server metadata, never from the client.
--   * The DNA sample reference is a new random token stored only here; it is handed to the lab
--     (PJ RegisterReferenceSample, batch 18) so DNA is no longer the reversible hex of a citizen id.
--   * A mugshot is an https URL from the client's screenshot upload: stored as client_supplied = 1.
--   * Medical screening reads pf-ambulancejob GetPatientSummary; a down / red / orange patient is
--     booked but cannot be put in a holding cell (AssignHoldingCell screens again).
--   * The citizen's items go into a property locker (property.lua) unless the officer says not to.

PFJustice = PFJustice or {}
PFJustice.Booking = PFJustice.Booking or {}
local Booking = PFJustice.Booking
PFJustice.CustodyKit = PFJustice.CustodyKit or {} -- filled by custody.lua; looked up when called
local K = PFJustice.CustodyKit

Booking.SQL = {
    insert = [[INSERT INTO pf_justice_bookings (custody_id, booking_no, citizenid, fingerprint, bloodtype, dna_sample_ref,
        mugshot_url, client_supplied, height_cm, marks, screening, notes, booked_by, at) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?)]],
    byCustody = 'SELECT * FROM pf_justice_bookings WHERE custody_id = ? LIMIT 1',
    maxNo = 'SELECT MAX(booking_no) AS no FROM pf_justice_bookings WHERE booking_no LIKE ?',
    anonymise = [[UPDATE pf_justice_bookings SET fingerprint = NULL, bloodtype = NULL, dna_sample_ref = NULL, mugshot_url = NULL,
        marks = NULL, notes = NULL WHERE citizenid = ?]],
}

Booking.Store = {
    --- id, or nil plus 'duplicate' when the booking number or the custody is already booked.
    insert = function(row)
        local ok, id = pcall(MySQL.insert.await, Booking.SQL.insert, { row.custody_id, row.booking_no, row.citizenid,
            row.fingerprint, row.bloodtype, row.dna_sample_ref, row.mugshot_url, row.height_cm, row.marks, row.screening,
            row.notes, row.booked_by, row.at })
        if not ok then
            if tostring(id):find('Duplicate', 1, true) then return nil, 'duplicate' end
            print(('^1[pf-justice]^7 booking insert: %s'):format(tostring(id)))
            return nil, 'db'
        end
        return tonumber(id)
    end,
    byCustody = function(custodyId)
        local r = K.db('single', Booking.SQL.byCustody, { custodyId })
        return type(r) == 'table' and r.id and r or nil
    end,
    maxNo = function(prefix)
        local r = K.db('single', Booking.SQL.maxNo, { prefix .. '%' })
        return type(r) == 'table' and r.no or nil
    end,
    anonymise = function(cid) K.db('update', Booking.SQL.anonymise, { cid }) end,
}

--- The next booking number for the day of `t` (seq continues from the highest stored one).
function Booking.NextNumber(t)
    local prefix = ('%s-%s-'):format(K.cfg('Custody', 'BookingPrefix', 'BK'), os.date('%Y%m%d', t))
    local last = Booking.Store.maxNo(prefix)
    local seq = last and tonumber(tostring(last):sub(#prefix + 1)) or 0
    return ('%s%04d'):format(prefix, (seq or 0) + 1)
end

local DNA_CHARS = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
--- A random sample token with no relation to the citizen id (only the lab links it). Lua 5.4
--- seeds math.random randomly at start.
function Booking.NewDnaRef()
    local out = {}
    for i = 1, 20 do
        local r = math.random(1, #DNA_CHARS)
        out[i] = DNA_CHARS:sub(r, r)
    end
    return 'DNA-' .. table.concat(out)
end

--- An https URL without spaces or quotes (the client uploaded it; stored as client supplied).
local function mugshot(v)
    if v == nil then return nil, true end
    if type(v) ~= 'string' or #v > 512 or not v:match('^https://[%w%-%.]+[:/]') or v:find('[%s"\'<>]') then return nil, false end
    local hosts = K.cfg('Custody', 'MugshotHosts', nil)
    if type(hosts) == 'table' and next(hosts) then
        local host = v:match('^https://([^/:]+)')
        if not host or not hosts[host:lower()] then return nil, false end
    end
    return v, true
end

local function readIdentity(P)
    local meta = P.PlayerData.metadata or {}
    local fp = type(meta.fingerprint) == 'string' and meta.fingerprint:sub(1, 64) or nil
    local bt = type(meta.bloodtype) == 'string' and meta.bloodtype:sub(1, 4) or nil
    return fp, bt
end

--- BookCustody(custodyId, booking, opts): booking = { mugshotUrl?, height?, marks?, notes?,
--- seize = true, keep = { item names }? }. opts = { actor = { src } }.
--- Returns { ok, bookingNo, receiptId, screening }.
function Booking.Book(custodyId, booking, opts)
    opts = type(opts) == 'table' and opts or {}
    booking = type(booking) == 'table' and booking or {}
    local Custody = PFJustice.Custody
    local url, urlOk = mugshot(booking.mugshotUrl)
    if not urlOk then return K.err('bad_args', 'mugshotUrl must be an https link') end
    local height = nil
    if booking.height ~= nil then
        height = K.int(booking.height, 100, 250)
        if not height then return K.err('bad_args', 'height must be 100-250 cm') end
    end
    local marks, notes = K.text(booking.marks, 255), K.text(booking.notes, 500)
    local keep = {}
    if booking.keep ~= nil then
        if type(booking.keep) ~= 'table' or #booking.keep > 20 then return K.err('bad_args', 'keep must be a list of item names') end
        for _, n in ipairs(booking.keep) do if type(n) == 'string' and #n <= 64 then keep[#keep + 1] = n end end
    end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if not K.isOfficer(actor) then return K.roleError(actor) end
    local row, err = Custody.LoadById(custodyId)
    if not row then return err end

    return K.withLock('custody:' .. row.id, function()
        row = Custody.Store.get(row.id)
        if row.closed_at then return K.err('invalid_state', 'The custody is closed') end
        local existing = Booking.Store.byCustody(row.id)
        if existing then
            local receipt = PFJustice.Property and PFJustice.Property.Store.byKey(('pf-justice:booking:%d:property'):format(row.id))
            return { ok = true, duplicate = true, bookingNo = existing.booking_no, receiptId = receipt and tonumber(receipt.id) or nil,
                screening = existing.screening }
        end
        local src = K.srcOf(row.citizenid)
        if not src then return K.err('offline', 'The citizen is not online') end
        local P = K.player(src)
        if not P then return K.err('offline', 'The citizen is not online') end
        -- arrested / in transport at a booking desk: step into booking first (both are listed moves)
        if row.state == 'arrested' or row.state == 'in_transport' then
            local zone = Custody.BookingZoneAt(K.coords(src))
            if not zone then return K.err('too_far', 'The citizen must be inside a booking area') end
            if not Custody.OfficerPresent(actor, src) then return K.err('too_far', 'You must be with the citizen') end
            local moved, moveErr = Custody.Move(row, 'booking', { facility = zone.facility or row.facility }, actor, 'state',
                { from = row.state, to = 'booking' })
            if not moved then return moveErr end
            row = moved
        end
        if row.state ~= 'booking' then return K.err('invalid_state', 'The custody is ' .. tostring(row.state) .. ', not at booking') end
        if not Custody.OfficerPresent(actor, src) then return K.err('too_far', 'You must be with the citizen') end

        local screening = Custody.Screen(row.citizenid, src)
        local receiptId
        if booking.seize ~= false and PFJustice.Property then
            local seized = PFJustice.Property.Seize(src, {
                custodyId = row.id, keep = keep, items = 'all', reason = 'booking',
                key = ('pf-justice:booking:%d:property'):format(row.id), actorResolved = actor,
            })
            if not seized.ok then return seized end
            receiptId = seized.receiptId
        end

        local fingerprint, bloodtype = readIdentity(P)
        local t = K.now()
        local dnaRef = Booking.NewDnaRef()
        local id, why, no
        for _ = 1, 5 do
            no = Booking.NextNumber(t)
            id, why = Booking.Store.insert({
                custody_id = row.id, booking_no = no, citizenid = row.citizenid, fingerprint = fingerprint, bloodtype = bloodtype,
                dna_sample_ref = dnaRef, mugshot_url = url, height_cm = height, marks = marks, screening = screening,
                notes = notes, booked_by = actor.cid or K.actorCid(actor) or 'system', at = t,
            })
            if id or why ~= 'duplicate' then break end
            -- a duplicate custody means another call booked it; a duplicate number is retried
            if Booking.Store.byCustody(row.id) then break end
        end
        if not id then
            local again = Booking.Store.byCustody(row.id)
            if again then return { ok = true, duplicate = true, bookingNo = again.booking_no, receiptId = receiptId, screening = again.screening } end
            return K.err('db_unavailable', 'The booking could not be saved; the property receipt is kept')
        end
        local new, moveErr = Custody.Move(row, 'booked', { booking_no = no }, actor, 'booked',
            { bookingNo = no, screening = screening, receiptId = receiptId })
        if not new then return moveErr end

        -- the arrest goes on the record (15B records); the lab gets the reference sample (b18)
        K.callApi('AddRecordEntry', row.citizenid, { kind = 'arrest', ref = { type = 'custody', id = tostring(row.id) },
            summary = ('Booked %s%s'):format(no, row.reason and (': ' .. row.reason) or '') }, { actor = { kind = 'system', label = 'booking' } })
        if K.started('pfm-policejob') then
            -- batch 18 adds the export; until then the call fails quietly and the booking row keeps the token
            pcall(function()
                exports['pfm-policejob']:RegisterReferenceSample(row.citizenid, 'dna', { custodyId = row.id, sampleRef = dnaRef, bookingNo = no },
                    { key = ('pf-justice:booking:%d:dna'):format(row.id) })
            end)
        end
        if screening == 'hospital_required' then
            K.notify(actor.src, 'Medical screening: take the citizen to a hospital before a holding cell', 'error')
        end
        return { ok = true, bookingNo = no, receiptId = receiptId, screening = screening }
    end)
end

--- GetBooking(custodyId): the booking record for officers and the booking page.
function Booking.Get(custodyId)
    local id = K.int(custodyId, 1)
    if not id then return K.err('bad_args', 'custodyId must be a positive integer') end
    local b = Booking.Store.byCustody(id)
    if not b then return K.err('not_found', 'No booking for this custody') end
    return { ok = true, booking = {
        id = tonumber(b.id), custodyId = tonumber(b.custody_id), bookingNo = b.booking_no, cid = b.citizenid,
        fingerprint = b.fingerprint, bloodtype = b.bloodtype, dnaSampleRef = b.dna_sample_ref, mugshotUrl = b.mugshot_url,
        clientSupplied = tonumber(b.client_supplied) == 1, height = tonumber(b.height_cm), marks = b.marks,
        screening = b.screening, notes = b.notes, bookedBy = b.booked_by, at = tonumber(b.at),
    } }
end

--- Character deleted: the booking stays for court history; identity data is removed.
function Booking.OnCharacterDeleted(cid)
    if K.validCid(cid) then Booking.Store.anonymise(cid) end
end

K.export('BookCustody', function(id, booking, opts) return Booking.Book(id, booking, opts) end)
K.export('GetBooking', function(id) return Booking.Get(id) end)
