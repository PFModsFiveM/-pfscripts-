-- PF News configuration (server only). Owner-editable: grades, pay, ads, leads and the article
-- presets the City Desk publishes automatically from city events (pf-services).
Config = Config or {}

Config.Job = 'reporter'              -- the news job (pfm-core shared jobs)
Config.CompanyAccount = 'reporter'   -- ads are paid into society:<this>

-- Newsroom roles by job grade. When the job has fewer grades than a role asks for, the job's top
-- grade gets that role, so a newsroom with a single grade still works (everyone is an editor).
-- A boss grade (isboss) is always an editor when BossIsEditor is true.
Config.Grades = {
    write = 0,     -- write drafts, claim leads, submit for review
    publish = 2,   -- publish their own articles without review
    editor = 3,    -- approve / reject, retract, pin, breaking, edit any article, dismiss leads
    ads = 0,       -- reject (and refund) ads
}
Config.BossIsEditor = true

-- Sections of the paper. Automatic articles use the event's catalog category when it is listed here.
Config.Categories = {
    { id = 'city',          label = 'City' },
    { id = 'government',    label = 'City Hall' },
    { id = 'crime',         label = 'Crime' },
    { id = 'business',      label = 'Business' },
    { id = 'emergency',     label = 'Emergency' },
    { id = 'weather',       label = 'Weather' },
    { id = 'sports',        label = 'Sports' },
    { id = 'entertainment', label = 'Entertainment' },
    { id = 'opinion',       label = 'Opinion' },
}
Config.DefaultCategory = 'city'

Config.Limits = {
    titleMin = 6, titleMax = 120,
    summaryMax = 280,
    bodyMin = 40, bodyMax = 8000,     -- bodyMin applies when submitting or publishing
    images = 4,
    noteMax = 300,
    draftsPerAuthor = 25,
    searchMin = 2, searchMax = 60,
    pageSize = 20,
}

-- Article images: https only, no quotes or spaces, at most `maxLength` characters.
Config.Images = {
    maxLength = 300,
    requireExtension = true,
    extensions = { 'png', 'jpg', 'jpeg', 'gif', 'webp' },
    allowedHosts = {},   -- e.g. { 'i.imgur.com', 'cdn.discordapp.com' }; empty = any https host
}

Config.Reader = {
    latest = 20,          -- articles on the front page
    pinnedMax = 4,
    breakingHours = 6,    -- a breaking article shows in the banner for this long
    cacheSeconds = 10,    -- the front page is the same for everyone; rebuilt at most this often
}

Config.Breaking = {
    notify = true,          -- online players with the News app installed get a notification
    cooldownSeconds = 60,   -- at most one breaking notification per this many seconds
    duration = 9000,
}

-- Reporter bonus per published article, paid through the bank ledger (PFPayout.Pay) once per
-- article (key pf-news:bonus:<article id>). It is held for `holdSeconds` so an editor can retract
-- junk before it pays; a retracted article is never paid.
Config.Pay = {
    enabled = true,
    perArticle = 250,
    leadBonus = 200,          -- extra when the article covers a lead the author claimed
    minBodyLength = 400,      -- shorter articles publish but earn nothing
    dailyCap = 1500,          -- per reporter per day
    holdSeconds = 300,
    account = 'bank',
    fundFrom = 'system',      -- 'system' (system:pf-news, like state wages) or 'society' (the company account)
    maxAttempts = 10,
}

-- Leads: events reporters may cover. Never published by themselves.
Config.Leads = {
    openMinutes = 90,          -- an unclaimed lead expires after this
    claimedMinutes = 120,      -- a claimed lead stays this long after the claim
    maxClaimedPerReporter = 2,
    requireOnDuty = true,      -- reporters must be on duty (pfm-newsjob duty point) to claim
    mergeSeconds = 300,        -- the same kind in the same district within this window is one lead
    maxOpen = 60,              -- oldest open leads expire beyond this
    -- the only event data fields a lead shows (never citizen ids, plates or phone numbers)
    publicFields = {
        'businessName', 'business', 'bank', 'store', 'location', 'street', 'name', 'label',
        'reason', 'charge', 'charges', 'sentence', 'months', 'amount', 'license', 'licenseType',
        'item', 'items', 'shortage', 'winner', 'race', 'track', 'vehicle', 'model', 'weather',
        'department', 'details', 'summary',
    },
}

-- Automatic articles from city events.
Config.Auto = {
    enabled = true,
    byline = 'City Desk',
    coalesceSeconds = 90,       -- events of one group this close together update one article...
    coalesceMaxSeconds = 600,   -- ...until the article is this old
    catchupSeconds = 900,       -- on start, events this recent that were missed are processed
    bulletinLeads = true,       -- a breaking bulletin also gives the newsroom a lead for the full story
    -- per-kind override of the catalog's news mode: 'auto', 'lead' or 'none'
    modes = {
        -- ['crime.robbery.bank'] = 'lead',
    },
    -- events of the same group within the window share one article (a digest)
    groups = {
        ['gov.tax.changed'] = 'gov.tax', ['gov.tax.toggled'] = 'gov.tax',
        ['gov.law.published'] = 'gov.law', ['gov.law.repealed'] = 'gov.law',
        ['gov.budget.changed'] = 'gov.budget',
        ['gov.power.cut'] = 'gov.outage', ['gov.water.cut'] = 'gov.outage',
        ['gov.power.restored'] = 'gov.restored', ['gov.water.restored'] = 'gov.restored',
    },
    -- longest text taken from one event data field (others are cut at 200 characters)
    longFields = { content = 1500, message = 1500, body = 1500, description = 600, summary = 400, findings = 600, details = 600 },
}

-- Ads: a business boss or registered owner buys a slot on the front page, paid from the business
-- account into the news company account through the ledger (key pf-news:ad:<id>).
Config.Ads = {
    enabled = true,
    durations = {
        { id = '1d', label = '1 day',  hours = 24,  price = 400 },
        { id = '3d', label = '3 days', hours = 72,  price = 1000 },
        { id = '7d', label = '7 days', hours = 168, price = 2000 },
    },
    textMin = 10, textMax = 220,
    maxActive = 8,           -- ad slots on the front page
    maxPerBusiness = 2,
    bossJobs = true,         -- a job boss buys for the job (society:<job>)
    registryOwners = true,   -- an owner on the pf-government business registry buys for that business
    excludedJobs = { reporter = true, unemployed = true },
}

-- ── Presets ─────────────────────────────────────────────────────────
-- Template rules:
--   {field}           a value from the event data, or one of: headline (the event title), district,
--                     kindLabel, time, and the derived direction / fromWord / change / delta,
--                     taxName, state / stateVerb, deptName
--   {a,b,c}           the first of these fields that has a value
--   {field:fmt}       fmt = pct, money, num, lower, upper, title, cap
--   {field|text}      `text` when the field is missing
--   [ ... ]           an optional part: dropped when any field inside it is missing
-- A variant whose required fields (outside [ ] and without |) are missing is skipped. The LAST
-- variant of each preset is its fallback, used only when no other variant fits. The variant is
-- picked by event id, so the same event always gets the same text. `line` is the one-line form
-- used when several events share one article. A missing field never prints anything.
Config.Presets = {
    ['gov.tax.changed'] = {
        category = 'government',
        line = '{taxName|A tax}: [{oldRate:pct} → ]{newRate:pct|new rate set}',
        variants = {
            { title = '{taxName} {direction} to {newRate:pct}',
              summary = 'City Hall has set {taxName:lower} at {newRate:pct}[, {fromWord} {oldRate:pct}].',
              body = 'The mayor\'s office confirmed today that {taxName:lower} now stands at {newRate:pct}[, {fromWord} {oldRate:pct}]. The new rate applies across Los Santos from today.\n\nResidents and businesses will see the change on their next purchases and statements. Weazel News will follow up as City Hall publishes more details.' },
            { title = 'New rate for {taxName:lower}: {newRate:pct}',
              summary = 'Los Santos will pay {taxName:lower} at {newRate:pct}[ instead of {oldRate:pct}] after a decision by City Hall.',
              body = 'City Hall has changed {taxName:lower}. The rate is now {newRate:pct}[, {fromWord} {oldRate:pct}].\n\nThe change was published on the city record and takes effect immediately.' },
            { title = '{headline|City Hall changes a tax rate}',
              summary = 'City Hall has changed a tax rate[: {taxName:lower} is now {newRate:pct}].',
              body = 'City Hall has published a change to the city\'s tax schedule[: {taxName:lower} is now {newRate:pct}].\n\nThe full tax schedule is available on the city\'s website.' },
        },
    },
    ['gov.tax.toggled'] = {
        category = 'government',
        line = '{taxName|A tax} {state|changed}',
        variants = {
            { title = 'City Hall {stateVerb} {taxName:lower}',
              summary = '{taxName} has been {state} by City Hall[ at a rate of {rate:pct}].',
              body = 'City Hall has {state} {taxName:lower}[, which stands at {rate:pct}]. The change applies from today.\n\nWeazel News will report on how the decision affects residents and businesses.' },
            { title = '{headline|City Hall changes the tax schedule}',
              summary = 'City Hall has changed the tax schedule[: {taxName:lower} is {state}].',
              body = 'The tax schedule published by City Hall has changed[: {taxName:lower} is now {state}].' },
        },
    },
    ['gov.law.published'] = {
        category = 'government',
        line = 'New law: {name,lawTitle,law,title|unnamed}',
        variants = {
            { title = 'New law: {name,lawTitle,law,title}',
              summary = 'City Hall has published {name,lawTitle,law,title}[, a new {category:lower} law].',
              body = 'A new law, {name,lawTitle,law,title}, has been published by City Hall and is now in force.[\n\n{description,summary}][\n\nThe penalty: a fine of up to {fine:money}.][ Offenders face up to {jail} months in jail.]\n\nThe full text is available on the city\'s website.' },
            { title = 'City Hall passes {name,lawTitle,law,title}',
              summary = '{name,lawTitle,law,title} is now the law in Los Santos.',
              body = 'Lawmakers at City Hall have passed {name,lawTitle,law,title}.[\n\n{description,summary}][\n\nBreaking it can cost up to {fine:money}.]\n\nResidents can read the law in full on the city\'s website.' },
            { title = '{headline|City Hall publishes a new law}',
              summary = 'A new law has been published by City Hall.',
              body = 'City Hall has published a new law. It is in force from today and can be read on the city\'s website.' },
        },
    },
    ['gov.law.repealed'] = {
        category = 'government',
        line = 'Repealed: {name,lawTitle,law,title|a law}',
        variants = {
            { title = '{name,lawTitle,law,title} repealed',
              summary = 'City Hall has repealed {name,lawTitle,law,title}.',
              body = '{name,lawTitle,law,title} is no longer in force after City Hall repealed it today.[\n\n{reason,description}]\n\nWeazel News will report on what the decision means for residents.' },
            { title = '{headline|City Hall repeals a law}',
              summary = 'A law has been taken off the books by City Hall.',
              body = 'City Hall has repealed a law. The current law book is available on the city\'s website.' },
        },
    },
    ['gov.budget.changed'] = {
        category = 'government',
        line = '{deptName|A department}: [{oldBudget:money} → ]{newBudget:money|budget changed}',
        variants = {
            { title = '{deptName} budget {direction} to {newBudget:money}',
              summary = 'City Hall has set the {deptName} budget at {newBudget:money}[, {fromWord} {oldBudget:money}].',
              body = 'The {deptName} budget is now {newBudget:money} a month[, {fromWord} {oldBudget:money}], City Hall announced.\n\nDepartment budgets pay for staff, equipment and the services residents rely on.' },
            { title = 'City Hall sets {deptName} budget at {newBudget:money}',
              summary = 'The {deptName} department will work with {newBudget:money}[ instead of {oldBudget:money}].',
              body = 'City Hall has changed the monthly budget of the {deptName} department to {newBudget:money}[, {fromWord} {oldBudget:money}].' },
            { title = '{headline|City Hall changes a department budget}',
              summary = 'A department budget has changed[: {deptName}].',
              body = 'City Hall has changed a department budget[ for {deptName}]. Budget figures are published on the city\'s website.' },
        },
    },
    ['gov.infra.upgrade'] = {
        category = 'government',
        line = '{label,upgrade|An upgrade}[ for {deptName}]',
        variants = {
            { title = 'City invests in {label,upgrade}',
              summary = 'City Hall has approved {label,upgrade}[ for the {deptName} department][ at a cost of {cost:money}].',
              body = 'Los Santos is getting {label,upgrade}[ for the {deptName} department]. City Hall approved the investment[ at a cost of {cost:money}].\n\nThe upgrade is part of the city\'s infrastructure programme.' },
            { title = '{headline|City Hall upgrades city infrastructure}',
              summary = 'City Hall has approved an infrastructure upgrade[: {label,upgrade}].',
              body = 'City Hall has approved an upgrade to city infrastructure[: {label,upgrade}].' },
        },
    },
    ['gov.power.cut'] = {
        category = 'government',
        line = 'Power cut: {district|part of the city}',
        variants = {
            { title = 'Power cut hits {district}',
              summary = 'Residents and businesses in {district} are without power.[ The cause given: {reason:lower}.]',
              body = 'Power is out across {district}. Traffic lights, street lights and businesses in the area are affected.[\n\nThe city gave the cause as {reason:lower}.]\n\nWeazel News will report when power is restored.' },
            { title = 'Blackout in {district}',
              summary = 'The lights went out in {district} as the city cut power to the district.',
              body = 'The city has cut power to {district}.[ Reason: {reason}.] Residents should take care at junctions without signals.' },
            { title = '{headline|Power cut reported in the city}',
              summary = 'Part of the city is without power[: {district}].',
              body = 'Part of Los Santos is without power[, including {district}]. Weazel News will report when it is restored.' },
        },
    },
    ['gov.power.restored'] = {
        category = 'government',
        line = 'Power back: {district|part of the city}',
        variants = {
            { title = 'Power restored in {district}',
              summary = 'The lights are back on in {district}.',
              body = 'Power has been restored across {district}. Traffic signals and street lights in the district are working again.' },
            { title = '{headline|Power restored}',
              summary = 'Power is back[ in {district}].',
              body = 'The city has restored power[ to {district}].' },
        },
    },
    ['gov.water.cut'] = {
        category = 'government',
        line = 'Water cut: {district|part of the city}',
        variants = {
            { title = 'Water supply cut in {district}',
              summary = 'Homes and businesses in {district} are without running water.[ The cause given: {reason:lower}.]',
              body = 'The water supply to {district} has been cut.[ The city gave the cause as {reason:lower}.]\n\nBusinesses that need water may have to close until it returns.' },
            { title = '{headline|Water cut reported in the city}',
              summary = 'Part of the city is without water[: {district}].',
              body = 'Part of Los Santos is without water[, including {district}].' },
        },
    },
    ['gov.water.restored'] = {
        category = 'government',
        line = 'Water back: {district|part of the city}',
        variants = {
            { title = 'Water restored in {district}',
              summary = 'Running water is back in {district}.',
              body = 'The city has restored the water supply to {district}.' },
            { title = '{headline|Water supply restored}',
              summary = 'Water is back[ in {district}].',
              body = 'The city has restored the water supply[ to {district}].' },
        },
    },
    ['gov.utility.disconnected'] = {
        category = 'business',
        line = '{businessName,business,name|A business} loses {service|utility} service',
        variants = {
            { title = '{businessName,business,name} cut off from {service}',
              summary = 'The city has disconnected {service} at {businessName,business,name}[ over {reason:lower}].',
              body = 'City utilities have disconnected {service} at {businessName,business,name}[ over {reason:lower}].\n\nA business without utilities may not be able to trade until service is restored.' },
            { title = '{headline|City disconnects a business}',
              summary = 'The city has disconnected a utility at {businessName,business,name|a local business}.',
              body = 'City utilities have disconnected a service at {businessName,business,name|a local business}[ ({service})].' },
        },
    },
    ['gov.business.registered'] = {
        category = 'business',
        line = 'New business: {businessName,name,business|unnamed}',
        variants = {
            { title = '{businessName,name,business} opens its doors',
              summary = 'A new [{type:lower} ]business, {businessName,name,business}, has been registered with City Hall.',
              body = '{businessName,name,business} is the newest business in Los Santos after registering with City Hall[ as a {type:lower}].\n\nWeazel News wishes them luck. Business owners can advertise on Weazel News.' },
            { title = 'New in town: {businessName,name,business}',
              summary = '{businessName,name,business} has joined the city business registry.',
              body = 'City Hall has added {businessName,name,business} to the business registry[ ({type})].' },
            { title = '{headline|A new business registers with City Hall}',
              summary = 'A new business has registered with City Hall.',
              body = 'A new business has joined the city business registry.' },
        },
    },
    ['gov.business.closed'] = {
        category = 'business',
        line = 'Closed: {businessName,name,business|a business}',
        variants = {
            { title = 'City closes {businessName,name,business}',
              summary = 'City Hall has ordered {businessName,name,business} to close[ over {reason:lower}].',
              body = '{businessName,name,business} has been closed by order of City Hall.[\n\nThe reason given: {reason}.]\n\nThe business may not trade until the city allows it to reopen.' },
            { title = '{headline|City Hall closes a business}',
              summary = 'City Hall has closed {businessName,name,business|a local business}.',
              body = 'City Hall has ordered {businessName,name,business|a local business} to close.' },
        },
    },
    ['gov.business.reopened'] = {
        category = 'business',
        line = 'Reopened: {businessName,name,business|a business}',
        variants = {
            { title = '{businessName,name,business} reopens',
              summary = 'City Hall has allowed {businessName,name,business} to trade again.',
              body = '{businessName,name,business} is open for business again after City Hall lifted its closure.' },
            { title = '{headline|A closed business reopens}',
              summary = '{businessName,name,business|A business} closed by the city may trade again.',
              body = 'City Hall has allowed {businessName,name,business|a closed business} to reopen.' },
        },
    },
    ['gov.business.transferred'] = {
        category = 'business',
        line = '{businessName,name,business|A business} changes hands',
        variants = {
            { title = '{businessName,name,business} changes hands',
              summary = '{businessName,name,business} has a new owner, according to the city business registry.',
              body = 'The city business registry shows a new owner for {businessName,name,business}.\n\nWeazel News has asked the new management about their plans.' },
            { title = '{headline|A business changes owner}',
              summary = 'A business has changed owner[: {businessName,name,business}].',
              body = 'The city business registry records a change of owner[ for {businessName,name,business}].' },
        },
    },
    ['gov.inspection.failed'] = {
        category = 'business',
        line = 'Failed inspection: {businessName,name,business|a business}',
        variants = {
            { title = '{businessName,name,business} fails city inspection',
              summary = 'City inspectors found problems at {businessName,name,business}.',
              body = 'A city inspection of {businessName,name,business} ended with a failing result.[\n\nInspectors noted: {findings}]\n\nThe business can ask City Hall for a new inspection.' },
            { title = '{headline|A business fails a city inspection}',
              summary = 'City inspectors failed {businessName,name,business|a local business}.',
              body = 'A business failed its city inspection[: {businessName,name,business}].' },
        },
    },
    ['gov.loan.defaulted'] = {
        category = 'business',
        line = 'Loan default: {businessName,name,business|a business}',
        variants = {
            { title = '{businessName,name,business} defaults on city loan',
              summary = '{businessName,name,business} has defaulted on a loan from the city[ worth {amount:money}].',
              body = 'City records show {businessName,name,business} has defaulted on its city loan[ of {amount:money}].\n\nThe city may take further action to recover the money.' },
            { title = '{headline|A business defaults on a city loan}',
              summary = 'A business has defaulted on a city loan.',
              body = 'A business has defaulted on a loan from the city[: {businessName,name,business}].' },
        },
    },
    ['gov.announcement'] = {
        category = 'government',
        breakingWhen = { field = 'priority', values = { urgent = true } },
        line = 'City Hall: {title,headline|announcement}',
        variants = {
            { title = '{title,headline}',
              summary = '{summary,content,message,body}',
              body = '{content,message,body}\n\nIssued by City Hall[ ({category})].' },
            { title = '{headline|Announcement from City Hall}',
              summary = 'City Hall has issued an announcement.',
              body = '[{content,message,body}\n\n]Issued by City Hall.' },
        },
    },
    ['gov.staff.appointed'] = {
        category = 'government',
        line = '{name|An official} appointed[ {role,position}]',
        variants = {
            { title = '{name} named {role,position}',
              summary = 'City Hall has appointed {name} as {role,position}[ in the {deptName} department].',
              body = '{name} is the new {role,position}[ of the {deptName} department], City Hall announced.\n\nWeazel News will ask the new appointee about their plans.' },
            { title = '{headline|City Hall announces an appointment}',
              summary = 'City Hall has announced a new appointment[: {name}].',
              body = 'City Hall has made a new appointment[: {name} as {role,position}].' },
        },
    },

    -- breaking bulletins (catalog bulletin = true): short and to the point
    ['crime.robbery.bank'] = {
        category = 'crime',
        line = 'Bank robbery: {bank,location,name|a city bank}',
        variants = {
            { title = 'Robbery under way at {bank,location,name}',
              summary = 'Police are responding to a bank robbery at {bank,location,name}[ in {district}]. Avoid the area.',
              body = 'Police are responding to a robbery at {bank,location,name}[ in {district}].\n\nResidents are asked to stay away from the area. This is a developing story.' },
            { title = 'Armed robbery at {bank,location,name|a Los Santos bank}',
              summary = 'A bank robbery has been reported[ in {district}]. Officers are on the way.',
              body = 'A robbery has been reported at {bank,location,name|a Los Santos bank}[ in {district}]. Police are on scene or on the way.\n\nThis is a developing story.' },
        },
    },
    ['crime.robbery.jewelry'] = {
        category = 'crime',
        line = 'Jewelry heist: {store,location,name|Vangelico}',
        variants = {
            { title = 'Heist at {store,location,name|Vangelico jewelers}',
              summary = 'Thieves have hit {store,location,name|a jewelry store}[ in {district}]. Police are responding.',
              body = 'A heist is under way at {store,location,name|a jewelry store}[ in {district}]. Police are responding.\n\nThis is a developing story.' },
            { title = 'Smash-and-grab at {store,location,name|a jewelry store}',
              summary = 'Display cases smashed at {store,location,name|a city jewelry store}. Officers are on the way.',
              body = 'Witnesses report a smash-and-grab robbery at {store,location,name|a jewelry store}[ in {district}].\n\nThis is a developing story.' },
        },
    },
    ['crime.prison.escape'] = {
        category = 'crime',
        line = 'Prison escape[: {count} inmates]',
        variants = {
            { title = 'Prison break at Bolingbroke',
              summary = '[{count} inmates have escaped. ]Police are searching the area around Bolingbroke Penitentiary.',
              body = 'An escape from Bolingbroke Penitentiary has been reported.[ {count} inmates are at large.]\n\nDo not approach anyone you suspect is an escaped inmate; call the police.' },
            { title = 'Inmate escapes Bolingbroke Penitentiary',
              summary = 'A manhunt is under way after an escape from Bolingbroke Penitentiary.',
              body = 'Police have launched a search after an escape from Bolingbroke Penitentiary.\n\nThis is a developing story.' },
        },
    },
    ['weather.severe'] = {
        category = 'weather',
        line = 'Weather warning: {label,weather|severe weather}',
        variants = {
            { title = 'Severe weather warning: {label,weather}',
              summary = '{label,weather:cap} is expected[ in {district}]. Take care on the roads.',
              body = 'Forecasters warn of {label,weather:lower}[ in {district}].\n\nDrive carefully, secure loose objects and check on vulnerable neighbours.' },
            { title = 'Storm warning for Los Santos',
              summary = 'Severe weather is on the way[ for {district}]. Take care on the roads.',
              body = 'A severe weather warning is in place[ for {district}].\n\nDrive carefully and stay indoors if you can.' },
        },
    },
}

-- Digest presets: the article for several events of one group published close together.
-- Extra fields: count, more (count - 1), lines (a bullet list), short (one line), firstTitle.
Config.Digests = {
    ['gov.tax'] = {
        variants = {
            { title = 'City Hall revises {count} taxes',
              summary = 'Several tax settings changed in quick succession: {short}.',
              body = 'City Hall changed several tax settings within minutes of each other:\n\n{lines}\n\nThe new settings apply from today. The full tax schedule is available on the city\'s website.' },
            { title = 'Tax shake-up at City Hall: {count} changes',
              summary = '{short}.',
              body = 'The city\'s tax schedule has been reworked:\n\n{lines}\n\nWeazel News will report on what the changes mean for residents and businesses.' },
        },
    },
    ['gov.law'] = {
        variants = {
            { title = 'City Hall updates the law book: {count} changes',
              summary = '{short}.',
              body = 'City Hall made several changes to the law today:\n\n{lines}\n\nThe current law book is available on the city\'s website.' },
        },
    },
    ['gov.budget'] = {
        variants = {
            { title = 'City Hall reshuffles {count} department budgets',
              summary = '{short}.',
              body = 'Several department budgets changed at once:\n\n{lines}\n\nBudget figures are published on the city\'s website.' },
        },
    },
    ['gov.outage'] = {
        variants = {
            { title = 'Utility outages across the city',
              summary = '{short}.',
              body = 'City utilities are down in several places:\n\n{lines}\n\nWeazel News will report when service is restored.' },
        },
    },
    ['gov.restored'] = {
        variants = {
            { title = 'Utilities restored across the city',
              summary = '{short}.',
              body = 'Service is back in several places:\n\n{lines}' },
        },
    },
}

-- Used for any kind without a preset (new kinds registered at runtime) and for groups without a digest.
Config.GenericPreset = {
    line = '{headline,kindLabel|City update}[ ({district})]',
    variants = {
        { title = '{headline,kindLabel|City update}',
          summary = 'The City Desk reports: {kindLabel:lower|a new development in the city}[ in {district}].',
          body = '[{details,description,summary,content}\n\n]This report was published automatically from the city record. Weazel News will update it as more is known.' },
    },
}
Config.GenericDigest = {
    variants = {
        { title = '{firstTitle}[ and {more} more]',
          summary = '{short}.',
          body = 'Several updates came in from the city record:\n\n{lines}' },
    },
}

Config.Debug = false
