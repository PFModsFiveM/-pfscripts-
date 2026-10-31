-- pf-citizen settings. A separate table (not Config) so it never clashes with other resources
-- loaded in the same test VM, and so the phone or the government config cannot shadow it.
CitizenConfig = {
    Mail = {
        MaxSubject = 120,
        MaxMessage = 4000,
        MaxSender = 60,
        MaxAttachments = 5,
        MaxRecipients = 5,            -- one compose may go to a few people at once
        PageSize = 50,
        -- player-to-player sending: at most `burst` mails, refilled at one every `refillSeconds`
        SendBurst = 5,
        SendRefillSeconds = 20,
        DraftLimit = 50,
        TrashKeepDays = 30,           -- trash older than this is deleted for good
        BroadcastKeepDays = 14,       -- an announcement is still delivered to citizens who log in within this
        Domain = 'ls.mail',           -- shown as <phone>@ls.mail in the address book
        BossRoles = { owner = true, boss = true, manager = true },
    },
    Bills = {
        PollSeconds = 45,             -- how often new bills are looked for (pushes and mail)
        MailNewBills = true,
        HistoryLimit = 40,
        -- government bills are paid into the same ledger account pf-government's own bill:pay uses
        GovFinesAccount = 'system:pf-government-fines',
    },
    Documents = {
        MaxTitle = 120,
        MaxBody = 20000,
        MaxPerCitizen = 200,
        ShareBurst = 6,
        ShareRefillSeconds = 15,
    },
    Calendar = {
        MaxTitle = 100,
        MaxDescription = 1000,
        MaxLocation = 100,
        MaxPersonalUpcoming = 200,
        -- pf-government permissions that may post public city events (the Mayor has 'all')
        CityPermissions = { 'events', 'laws' },
        ReminderCheckSeconds = 30,
        DefaultRemindMinutes = 15,
        MaxRemindMinutes = 24 * 60,
        CreateBurst = 6,
        CreateRefillSeconds = 20,
    },
}
