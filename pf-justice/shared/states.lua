-- pf-justice state machines as data (PF_ARCHITECTURE 5.4, 5.5, 5.6, 5.8, 5.12) plus a pure
-- transition checker. Every write in pf-justice asks PFJustice.States.Check before it changes a row,
-- and the row update itself compares the state it read (compare-and-set), so a transition that is
-- not listed here can never happen.
--
-- Additions to the architecture tables (kept small, each needed by a real flow):
--   custody        in_transport -> arrested       (taken out of the car again before booking)
--   incarceration  pending -> vacated, suspended -> vacated   (released before intake / while escaped)
--   fine           overdue -> payment_pending | paid | invoiced | waived   (paying late is still paying)
--                  invoiced -> issued             (the citizen declined the phone invoice)
--                  invoiced -> waived             only once the phone invoice is settled or cancelled:
--                                                 Orders.MoveLocked refuses it while the invoice is live
--                                                 (a waiver asked for then is recorded and applied later)
--                  referred -> paid | payment_pending | waived
--                  payment_pending -> overdue | referred   (a clearly refused payment returns the order
--                                                 to the state it was paid from, so a referral or a
--                                                 deadline is not lost)
--   citation       the fine machine plus issued -> contested -> upheld | dismissed; an upheld
--                  citation is payable like an issued one (payment_pending -> upheld as well)
--   bail           accepted -> offered            (the payment was clearly refused: nothing taken)
--   community_service overdue -> completed        (units finished late; the court item stays)
--   supervision    probation / parole: pending -> active -> completed | revoked | vacated, active <-> suspended

PFJustice = PFJustice or {}
PFJustice.States = PFJustice.States or {}
local S = PFJustice.States

local function set(list)
    local out = {}
    for _, v in ipairs(list) do out[v] = true end
    return out
end

-- machine = { initial = { states a new record may start in }, terminal = { ... }, edges = { from = { to... } } }
S.Machines = {
    custody = {
        initial = set({ 'detained', 'arrested' }),
        terminal = set({ 'released', 'transferred' }),
        edges = {
            detained = set({ 'arrested', 'hospital', 'released' }),
            arrested = set({ 'in_transport', 'booking', 'hospital', 'released' }),
            in_transport = set({ 'booking', 'arrested', 'hospital', 'released' }),
            booking = set({ 'booked', 'hospital', 'released' }),
            booked = set({ 'held', 'remanded', 'transferred', 'hospital', 'released' }),
            held = set({ 'remanded', 'transferred', 'hospital', 'released' }),
            remanded = set({ 'transferred', 'hospital', 'released' }),
            -- back to the state before the hospital (ReturnCustody checks it equals prev_state)
            hospital = set({ 'detained', 'arrested', 'in_transport', 'booking', 'booked', 'held', 'remanded', 'released' }),
        },
    },
    incarceration = {
        initial = set({ 'pending', 'active' }),
        terminal = set({ 'completed', 'vacated', 'revoked' }),
        edges = {
            pending = set({ 'active', 'vacated' }),
            active = set({ 'completed', 'suspended', 'vacated', 'revoked' }),
            suspended = set({ 'active', 'vacated' }),
        },
    },
    fine = {
        initial = set({ 'issued' }),
        terminal = set({ 'paid', 'waived' }),
        edges = {
            issued = set({ 'paid', 'payment_pending', 'invoiced', 'overdue', 'waived' }),
            payment_pending = set({ 'paid', 'issued', 'overdue', 'referred' }),
            invoiced = set({ 'paid', 'issued', 'waived' }),
            overdue = set({ 'referred', 'payment_pending', 'paid', 'invoiced', 'waived' }),
            referred = set({ 'paid', 'payment_pending', 'waived' }),
        },
    },
    citation = {
        initial = set({ 'issued' }),
        terminal = set({ 'paid', 'waived', 'dismissed' }),
        edges = {
            issued = set({ 'paid', 'payment_pending', 'invoiced', 'overdue', 'waived', 'contested' }),
            contested = set({ 'upheld', 'dismissed' }),
            upheld = set({ 'paid', 'payment_pending', 'invoiced', 'overdue', 'waived' }),
            payment_pending = set({ 'paid', 'issued', 'overdue', 'referred', 'upheld' }),
            invoiced = set({ 'paid', 'issued', 'waived' }),
            overdue = set({ 'referred', 'payment_pending', 'paid', 'invoiced', 'waived' }),
            referred = set({ 'paid', 'payment_pending', 'waived' }),
        },
    },
    community_service = {
        initial = set({ 'assigned' }),
        terminal = set({ 'completed', 'vacated' }),
        edges = {
            assigned = set({ 'active', 'overdue', 'vacated' }),
            active = set({ 'completed', 'overdue', 'vacated' }),
            overdue = set({ 'referred', 'completed', 'vacated' }),
            referred = set({ 'vacated' }),
        },
    },
    supervision = {
        initial = set({ 'pending', 'active' }),
        terminal = set({ 'completed', 'revoked', 'vacated' }),
        edges = {
            pending = set({ 'active', 'vacated' }),
            active = set({ 'completed', 'revoked', 'vacated', 'suspended' }),
            suspended = set({ 'active', 'revoked', 'vacated' }),
        },
    },
    bail = {
        initial = set({ 'offered' }),
        terminal = set({ 'refunded', 'forfeited', 'declined', 'expired' }),
        edges = {
            offered = set({ 'accepted', 'declined', 'expired' }),
            accepted = set({ 'posted', 'payment_pending', 'offered' }),
            payment_pending = set({ 'posted', 'offered' }),
            posted = set({ 'exonerated', 'forfeited' }),
            exonerated = set({ 'refunded' }),
        },
    },
}

-- Which machine an order kind follows.
S.KindMachine = {
    jail = 'incarceration', prison = 'incarceration', remand = 'incarceration',
    fine = 'fine', restitution = 'fine', citation = 'citation',
    community_service = 'community_service',
    probation = 'supervision', parole = 'supervision',
}

S.Kinds = {}
for kind in pairs(S.KindMachine) do S.Kinds[kind] = true end
S.IncarcerationKinds = { jail = true, prison = true, remand = true }
S.MoneyKinds = { fine = true, citation = true, restitution = true }
S.SupervisionKinds = { probation = true, parole = true }

-- States a fine-like order can be paid from (PayOrder). 'invoiced' is paid on the phone only.
S.Payable = { issued = true, overdue = true, upheld = true, referred = true }

--- The machine table for a machine name or an order kind.
function S.Machine(nameOrKind)
    return S.Machines[nameOrKind] or S.Machines[S.KindMachine[nameOrKind] or '']
end

--- Whether `from -> to` is listed. `from == nil` asks whether `to` is a valid initial state.
function S.Can(nameOrKind, from, to)
    local m = S.Machine(nameOrKind)
    if not m or type(to) ~= 'string' then return false end
    if from == nil then return m.initial[to] == true end
    local edges = m.edges[from]
    return edges ~= nil and edges[to] == true
end

--- Like Can, but returns the architecture result shape on refusal.
--- @return boolean ok, table|nil err  { ok = false, error = 'invalid_state', message }
function S.Check(nameOrKind, from, to)
    if S.Can(nameOrKind, from, to) then return true end
    return false, { ok = false, error = 'invalid_state',
        message = ('Cannot go from %s to %s'):format(tostring(from or 'new'), tostring(to)) }
end

function S.IsTerminal(nameOrKind, state)
    local m = S.Machine(nameOrKind)
    return m ~= nil and m.terminal[state] == true
end

--- Open = a known, non-terminal state of the machine.
function S.IsOpen(nameOrKind, state)
    local m = S.Machine(nameOrKind)
    if not m or m.terminal[state] then return false end
    return m.edges[state] ~= nil or m.initial[state] == true
end

--- Every state the machine knows, sorted (for specs and UI filters).
function S.StatesOf(nameOrKind)
    local m = S.Machine(nameOrKind)
    if not m then return {} end
    local seen, out = {}, {}
    local function add(s) if not seen[s] then seen[s] = true out[#out + 1] = s end end
    for s in pairs(m.initial) do add(s) end
    for s in pairs(m.terminal) do add(s) end
    for from, tos in pairs(m.edges) do
        add(from)
        for to in pairs(tos) do add(to) end
    end
    table.sort(out)
    return out
end

--- Open states of an order kind, as a list (used to build SQL filters).
function S.OpenStates(nameOrKind)
    local out = {}
    for _, s in ipairs(S.StatesOf(nameOrKind)) do
        if S.IsOpen(nameOrKind, s) then out[#out + 1] = s end
    end
    return out
end
