-- Custody, evidence chain, lab, telemetry, use-of-force and personnel pages (batch 21, unit 21B).
--
-- The pages (html/pages/custody.js, evidence_coc.js, lab.js, timeline.js, uof.js, personnel_ext.js)
-- reach the server through client/main.lua's one NUI bridge (pfMdtCall). This file adds the server
-- callbacks those pages use to the bridge's allowlist; it adds no NUI callback of its own and trusts
-- nothing: every name below is gated again on the server (server/access.lua: police job; duty and
-- grade for writes; then each owner's own rules in pf-justice and pfm-policejob).
-- The use-of-force, IA, review and qualification names of server/personnel_ext.lua are already on
-- the list in client/main.lua; listing them again is harmless and keeps these pages working if that
-- list changes.

local PAGE_ENDPOINTS = {
    -- server/pages_ext.lua (relays to pf-justice and pfm-policejob)
    'pf_mdt:pages:access',
    'pf_mdt:custody:get', 'pf_mdt:custody:log',
    'pf_mdt:evidence:list', 'pf_mdt:evidence:get', 'pf_mdt:evidence:transfer',
    'pf_mdt:lab:queue', 'pf_mdt:lab:submit', 'pf_mdt:lab:release',
    'pf_mdt:timeline:get',
    -- server/personnel_ext.lua
    'pf_mdt:force:list', 'pf_mdt:force:get', 'pf_mdt:force:draft', 'pf_mdt:force:update', 'pf_mdt:force:refresh',
    'pf_mdt:force:submit', 'pf_mdt:force:review', 'pf_mdt:force:close',
    'pf_mdt:ia:list', 'pf_mdt:ia:get', 'pf_mdt:ia:file', 'pf_mdt:ia:assign', 'pf_mdt:ia:note', 'pf_mdt:ia:finding', 'pf_mdt:ia:close',
    'pf_mdt:reviews:list', 'pf_mdt:reviews:create', 'pf_mdt:personnel:qualifications',
    -- existing reads the pages pick from (citizen search; officer names for the personnel pickers)
    'pf_mdt:searchCitizens', 'pf_mdt:officers:list',
}

PFMdtPagesExt = { endpoints = PAGE_ENDPOINTS }

if type(PFMdtBridge) == 'table' and type(PFMdtBridge.Allow) == 'function' then
    PFMdtBridge.Allow(PAGE_ENDPOINTS)
else
    -- client/main.lua must load first (fxmanifest client_scripts); without the bridge these pages
    -- show "not_allowed" on every call instead of reaching the server some other way
    print('^1[pf-policemdt]^7 pages_ext: the page bridge (PFMdtBridge, client/main.lua) is missing')
end
