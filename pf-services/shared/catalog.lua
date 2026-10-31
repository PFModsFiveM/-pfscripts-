-- The shared catalog: every city event kind and every service request kind, in one place.
-- Emitters (pf-government, robberies, police, EMS, businesses) and listeners (pf-news, the dispatch
-- apps) agree on these names. A resource may add kinds at runtime with RegisterEventKind /
-- RegisterRequestKind; these are the built-in ones.
--
-- Event `news` mode decides what pf-news does with it:
--   'auto'  a preset article is published straight away (city-hall decisions, major public events);
--   'lead'  the newsroom gets a lead a reporter can cover (crime, court, business gossip) — never
--           published without a reporter, so the news job keeps its meaning;
--   'none'  timeline only.
-- `police = true` also raises a police dispatch request (police.assist) at the event's coordinates.

PFCatalog = PFCatalog or {}

PFCatalog.Events = {
    -- government decisions: always public, always automatic
    ['gov.tax.changed']          = { label = 'Tax rate changed',            news = 'auto', category = 'government' },
    ['gov.tax.toggled']          = { label = 'Tax switched on or off',      news = 'auto', category = 'government' },
    ['gov.law.published']        = { label = 'New law published',           news = 'auto', category = 'government' },
    ['gov.law.repealed']         = { label = 'Law repealed',                news = 'auto', category = 'government' },
    ['gov.budget.changed']       = { label = 'Department budget changed',   news = 'auto', category = 'government' },
    ['gov.infra.upgrade']        = { label = 'City infrastructure upgrade', news = 'auto', category = 'government' },
    ['gov.power.cut']            = { label = 'District power cut',          news = 'auto', category = 'government' },
    ['gov.power.restored']       = { label = 'District power restored',     news = 'auto', category = 'government' },
    ['gov.water.cut']            = { label = 'District water cut',          news = 'auto', category = 'government' },
    ['gov.water.restored']       = { label = 'District water restored',     news = 'auto', category = 'government' },
    ['gov.utility.disconnected'] = { label = 'Business utility disconnected', news = 'auto', category = 'government' },
    ['gov.business.registered']  = { label = 'New business registered',     news = 'auto', category = 'business' },
    ['gov.business.closed']      = { label = 'Business closed by the city', news = 'auto', category = 'business' },
    ['gov.business.reopened']    = { label = 'Business reopened',           news = 'auto', category = 'business' },
    ['gov.business.transferred'] = { label = 'Business changed owner',      news = 'auto', category = 'business' },
    ['gov.inspection.failed']    = { label = 'Business failed inspection',  news = 'auto', category = 'business' },
    ['gov.inspection.passed']    = { label = 'Business passed inspection',  news = 'none', category = 'business' },
    ['gov.loan.defaulted']       = { label = 'City loan defaulted',         news = 'auto', category = 'business' },
    ['gov.announcement']         = { label = 'City Hall announcement',      news = 'auto', category = 'government' },
    ['gov.staff.appointed']      = { label = 'Government appointment',      news = 'auto', category = 'government' },
    ['gov.license.revoked']      = { label = 'License revoked',             news = 'lead', category = 'government' },

    -- crime and emergencies: reporters cover them; major heists get a short automatic bulletin
    ['crime.robbery.bank']       = { label = 'Bank robbery',                news = 'auto', police = true, category = 'crime', bulletin = true },
    ['crime.robbery.jewelry']    = { label = 'Jewelry store heist',         news = 'auto', police = true, category = 'crime', bulletin = true },
    ['crime.robbery.store']      = { label = 'Store robbery',               news = 'lead', police = true, category = 'crime' },
    ['crime.robbery.house']      = { label = 'House burglary',              news = 'lead', police = true, category = 'crime' },
    ['crime.robbery.truck']      = { label = 'Armored truck robbery',       news = 'lead', police = true, category = 'crime' },
    ['crime.drugs.bust']         = { label = 'Drug seizure',                news = 'lead', category = 'crime' },
    ['crime.prison.escape']      = { label = 'Prison escape',               news = 'auto', police = true, category = 'crime', bulletin = true },
    ['police.sentenced']         = { label = 'Court sentence',              news = 'lead', category = 'crime' },
    ['police.warrant']           = { label = 'Warrant issued',              news = 'lead', category = 'crime' },
    ['police.impound']           = { label = 'Vehicle impounded',           news = 'none', category = 'crime' },
    ['ems.patient']              = { label = 'Person injured',              news = 'none', category = 'emergency' },

    -- businesses, economy, city life
    ['business.store.purchased'] = { label = 'Store changed hands',         news = 'lead', category = 'business' },
    ['business.closed.power']    = { label = 'Business closed: no power',   news = 'lead', category = 'business' },
    ['business.supply.shortage'] = { label = 'Supply shortage',             news = 'lead', category = 'business' },
    ['race.finished']            = { label = 'Street race result',          news = 'lead', category = 'city' },
    ['weather.severe']           = { label = 'Severe weather',              news = 'auto', category = 'city', bulletin = true },
    ['service.completed']        = { label = 'Service request completed',   news = 'none', category = 'city' },
}

-- Service request kinds. `job` is the job (or list of jobs) that works the request; `payer` the
-- ledger account that funds `reward` (escrowed when the request is made, paid to the worker who
-- completes it, refunded if nobody does): 'requester' (the citizen's bank), 'society:<name>' or
-- 'none'. `verify` names the check a worker resource registers (RegisterRequestHandler); a request
-- with a reward completes only when that check passes or the requester confirms it.
PFCatalog.Requests = {
    ['tow.impound'] = {
        label = 'Impound tow', icon = '🚨', job = 'tow', payer = 'society:government', reward = 250,
        verify = true, expires = 3600, citizen = false,
        description = 'Police ordered this vehicle to the impound lot',
    },
    ['tow.recovery'] = {
        label = 'Vehicle recovery', icon = '🛻', job = 'tow', payer = 'requester', reward = 175,
        verify = true, expires = 1800, citizen = true,
        description = 'Tow a broken-down vehicle to a mechanic shop',
    },
    ['mechanic.roadside'] = {
        label = 'Roadside repair', icon = '🔧', job = { 'mechanic', 'bennys', 'beeker' }, payer = 'requester', reward = 100,
        verify = false, expires = 1800, citizen = true,
        description = 'Call-out fee; parts and labour are billed at the register',
    },
    ['ems.patient'] = {
        label = 'Medical emergency', icon = '🚑', job = 'ambulance', payer = 'none', reward = 0,
        verify = false, expires = 900, citizen = true,
        description = 'Someone needs a medic at this location',
    },
    ['police.assist'] = {
        label = 'Police assistance', icon = '🚓', job = 'police', payer = 'none', reward = 0,
        verify = false, expires = 900, citizen = true,
        description = 'An officer is needed at this location',
    },
    ['taxi.ride'] = {
        label = 'Taxi pickup', icon = '🚕', job = 'taxi', payer = 'none', reward = 0,
        verify = false, expires = 900, citizen = true,
        description = 'A passenger is waiting; the fare is charged by the meter',
    },
    -- business requests to the government (worked on the government tablet)
    ['gov.request.slot'] = {
        label = 'Equipment slot request', icon = '📐', job = 'government', payer = 'none', reward = 0,
        verify = true, expires = 7 * 86400, citizen = false, business = true,
        description = 'A business asks for an approved equipment position',
    },
    ['gov.request.inspection'] = {
        label = 'Inspection request', icon = '🧾', job = 'government', payer = 'none', reward = 0,
        verify = true, expires = 7 * 86400, citizen = false, business = true,
        description = 'A business asks to be inspected (to reopen or certify)',
    },
    ['gov.request.license'] = {
        label = 'License request', icon = '🪪', job = 'government', payer = 'none', reward = 0,
        verify = true, expires = 7 * 86400, citizen = false, business = true,
        description = 'A business asks for a license',
    },
    ['gov.request.delivery_zone'] = {
        label = 'Delivery zone request', icon = '🚚', job = 'government', payer = 'none', reward = 0,
        verify = true, expires = 7 * 86400, citizen = false, business = true,
        description = 'A business asks for a delivery bay to be approved',
    },
}
