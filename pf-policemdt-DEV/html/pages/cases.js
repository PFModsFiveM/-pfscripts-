// Cases and investigations (batch 21A): the pf_mdt:cases:* endpoints of server/cases.lua.
// A case is listed and read from the server (cursor paging, status/search/mine filters); every change
// is a server call and the page re-reads the case after it. What an officer may do comes from the
// server's `can` answer on cases:get (manage, edit, submit, supervise), never from the page.
(function () {
    'use strict';
    if (!window.PFMdtPages) return;

    const STATUSES = ['open', 'active', 'suspended', 'ready_for_court', 'submitted', 'closed'];
    const STATUS_KIND = { open: 'accent', active: 'ok', suspended: 'warn', ready_for_court: 'warn', submitted: 'accent', closed: '' };
    // the moves server/cases.lua offers by hand (it checks them again; ready_for_court/submitted come from a submission)
    const MOVES = {
        open: ['active', 'suspended', 'closed'], active: ['suspended', 'closed'], suspended: ['active', 'closed'],
        ready_for_court: ['active', 'closed'], submitted: ['active', 'closed'], closed: ['active'],
    };
    const ROLES = [['suspect', 'Suspect'], ['witness', 'Witness'], ['victim', 'Victim'], ['person_of_interest', 'Person of interest']];
    const ENTRY_KINDS = [['note', 'Note'], ['statement', 'Statement'], ['interview', 'Interview'], ['lead', 'Lead'], ['surveillance', 'Surveillance log'], ['assignment', 'Assignment']];
    const ENTRY_STATUS = { lead: ['open', 'followed', 'dismissed'], assignment: ['open', 'done', 'cancelled'] };
    // records an officer links by hand (server/cases.lua Cases.LinkTypes)
    const LINK_TYPES = [['incident', 'Incident (id)'], ['report', 'Report (id)'], ['warrant', 'Warrant (id)'], ['bolo', 'BOLO (number)'],
        ['evidence', 'Evidence (id)'], ['custody', 'Custody (citizen id)'], ['order', 'Court order (number)'], ['citation', 'Citation (order number)']];
    const LINK_LABEL = { incident: 'Incident', report: 'Report', warrant: 'Warrant', bolo: 'BOLO', evidence: 'Evidence', custody: 'Custody',
        order: 'Court order', citation: 'Citation', death_record: 'Death record', telemetry: 'Telemetry' };
    const label = (s) => String(s || '').replace(/_/g, ' ');

    let state = null;

    function render(root, ctx) {
        const { h, ui } = ctx;
        state = { ctx, root, list: [], next: null, selected: null, data: null, tab: 'overview', filters: { q: '', status: '', mine: false } };

        const search = ui.input({ placeholder: 'Search title or case number', 'aria-label': 'Search cases' });
        search.addEventListener('input', ui.debounce(() => { state.filters.q = search.value.trim(); loadList(true); }, 300));
        const status = ui.select([['', 'Open cases'], ['all', 'All (incl. closed)']].concat(STATUSES.map((s) => [s, label(s)])), '', { 'aria-label': 'Status filter' });
        status.addEventListener('change', () => { state.filters.status = status.value; loadList(true); });
        const mine = h('input', { type: 'checkbox', 'aria-label': 'Only my cases' });
        mine.addEventListener('change', () => { state.filters.mine = mine.checked; loadList(true); });

        const head = h('div', { class: 'pfp-head' },
            h('div', null, h('h2', null, 'Cases'), h('div', { class: 'pfp-sub' }, 'Investigations, people, linked records and court submissions')),
            ctx.can('caseCreate') ? ui.btn('+ New case', 'primary', () => openCreate()) : null);
        const toolbar = h('div', { class: 'pfp-toolbar' }, search, status, h('label', { class: 'pfp-muted' }, mine, ' Mine'));
        state.formSlot = h('div');
        state.listEl = h('div', { class: 'pfp-list', role: 'list' });
        state.moreEl = h('div', { class: 'pfp-pager' });
        state.detailEl = h('div', { class: 'pfp-card', 'aria-live': 'polite' });
        ctx.state(state.detailEl, 'empty', 'Pick a case.');
        root.appendChild(head);
        root.appendChild(toolbar);
        root.appendChild(state.formSlot);
        root.appendChild(h('div', { class: 'pfp-split' }, h('div', { class: 'pfp-card' }, state.listEl, state.moreEl), state.detailEl));

        loadList(true);
        const want = Number(ctx.params && ctx.params.caseId);
        if (want > 0) select(want);
    }

    async function loadList(reset) {
        const { ctx, h, ui } = { ctx: state.ctx, h: state.ctx.h, ui: state.ctx.ui };
        const s = state;
        const f = s.filters;
        const payload = { limit: 25 };
        if (f.q) payload.q = f.q;
        if (f.status === 'all') payload.includeClosed = true;
        else if (f.status) payload.status = f.status;
        if (f.mine) payload.mine = true;
        if (!reset && s.next) payload.after = s.next;
        if (reset) { s.list = []; s.next = null; ctx.state(s.listEl, 'loading'); }
        const res = await ctx.call('pf_mdt:cases:list', payload);
        if (!ctx.alive() || state !== s) return;
        if (!res.ok) { ctx.state(s.listEl, 'error', ctx.errorText(res, 'Cases could not be loaded.')); s.moreEl.textContent = ''; return; }
        s.list = s.list.concat(Array.isArray(res.list) ? res.list : []);
        s.next = res.next || null;
        s.listEl.textContent = '';
        if (!s.list.length) ctx.state(s.listEl, 'empty', 'No cases match.');
        for (const c of s.list) {
            const row = h('button', { type: 'button', class: 'pfp-row' + (c.id === s.selected ? ' active' : ''), role: 'listitem', dataset: { caseId: c.id }, onClick: () => select(c.id) },
                h('span', { class: 'pfp-row-main' },
                    h('span', { class: 'pfp-row-title' }, `${c.caseNo || ''} ${c.title || ''}`.trim()),
                    h('span', { class: 'pfp-muted' }, `Lead: ${c.leadName || c.leadCid || 'none'} · P${c.priority || '-'} · ${ctx.time(c.updatedAt)}`)),
                ui.badge(label(c.status), STATUS_KIND[c.status]));
            s.listEl.appendChild(row);
        }
        s.moreEl.textContent = '';
        if (s.next) s.moreEl.appendChild(ui.btn('Load more', 'sm', () => loadList(false)));
    }

    async function select(caseId) {
        const s = state;
        const ctx = s.ctx;
        s.selected = caseId;
        s.listEl.querySelectorAll('.pfp-row').forEach((r) => r.classList.toggle('active', Number(r.dataset.caseId) === caseId));
        ctx.state(s.detailEl, 'loading');
        const res = await ctx.call('pf_mdt:cases:get', { caseId });
        if (!ctx.alive() || state !== s || s.selected !== caseId) return;
        if (!res.ok) { ctx.state(s.detailEl, 'error', ctx.errorText(res, 'The case could not be loaded.')); return; }
        s.data = res;
        drawDetail();
    }

    // runs one write, shows the refusal in `errEl` (and a toast), re-reads the case on success
    async function act(endpoint, payload, errEl, okText) {
        const s = state;
        const ctx = s.ctx;
        if (errEl) errEl.textContent = '';
        const res = await ctx.call(endpoint, payload);
        if (!ctx.alive() || state !== s) return res;
        if (!res.ok) {
            const msg = ctx.errorText(res);
            if (errEl) errEl.textContent = msg;
            ctx.toast(msg, 'error');
            return res;
        }
        if (okText) ctx.toast(res.duplicate ? 'Already on the case' : okText, 'success');
        if (s.selected) await select(s.selected);
        loadList(true);
        return res;
    }

    function drawDetail() {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        const d = s.data;
        const c = d.case || {};
        const can = d.can || {};
        const box = s.detailEl;
        box.textContent = '';

        const actions = h('div', { class: 'pfp-toolbar' });
        const err = ui.formError();
        if (can.manage && can.edit) {
            const moves = MOVES[c.status] || [];
            if (moves.length) {
                const sel = ui.select([['', 'Change status...']].concat(moves.map((m) => [m, label(m)])), '', { 'aria-label': 'Change status' });
                sel.addEventListener('change', () => { if (sel.value) act('pf_mdt:cases:setStatus', { caseId: c.id, status: sel.value }, err, 'Status changed'); });
                actions.appendChild(sel);
            }
        } else if (can.manage && c.status === 'closed') {
            actions.appendChild(ui.btn('Reopen', 'sm', () => act('pf_mdt:cases:setStatus', { caseId: c.id, status: 'active' }, err, 'Case reopened')));
        }
        if (!c.leadCid && can.edit && ctx.user.citizenid) {
            actions.appendChild(ui.btn('Take lead', 'sm', () => act('pf_mdt:cases:setLead', { caseId: c.id, leadCid: ctx.user.citizenid }, err, 'You lead the case')));
        }
        if (can.manage && can.edit) actions.appendChild(ui.btn('Assign lead', 'sm ghost', () => openLeadForm(c, err)));
        if (can.manage && can.edit) actions.appendChild(ui.btn('Edit', 'sm ghost', () => openEdit(c)));

        box.appendChild(h('div', { class: 'pfp-head' },
            h('div', null, h('h3', null, `${c.caseNo || ''} · ${c.title || ''}`),
                h('div', { class: 'pfp-sub' }, `Lead: ${c.leadName || c.leadCid || 'none'} · created by ${c.createdByName || c.createdBy || 'unknown'} ${ctx.time(c.createdAt)}`)),
            ui.badge(label(c.status), STATUS_KIND[c.status])));
        box.appendChild(actions);
        box.appendChild(err);
        s.editSlot = h('div');
        box.appendChild(s.editSlot);

        const tabs = [['overview', 'Overview'], ['people', `People (${(d.people || []).length})`], ['links', `Records (${(d.links || []).length})`],
            ['entries', `Log (${(d.entries || []).length})`], ['evidence', 'Evidence'], ['court', `Court (${(d.submissions || []).length})`]];
        const bar = h('div', { class: 'pfp-tabs', role: 'tablist' });
        const body = h('div', { role: 'tabpanel' });
        for (const [k, l] of tabs) {
            bar.appendChild(h('button', { type: 'button', class: 'pfp-tab' + (s.tab === k ? ' active' : ''), role: 'tab', 'aria-selected': s.tab === k ? 'true' : 'false', dataset: { tab: k },
                onClick: () => { s.tab = k; drawDetail(); } }, l));
        }
        box.appendChild(bar);
        box.appendChild(body);
        const draw = { overview: drawOverview, people: drawPeople, links: drawLinks, entries: drawEntries, evidence: drawEvidence, court: drawCourt }[s.tab] || drawOverview;
        draw(body, d, can);
    }

    function drawOverview(body, d) {
        const { h, ui, time } = state.ctx;
        const c = d.case || {};
        body.appendChild(ui.kv([['Case', c.caseNo], ['Status', label(c.status)], ['Priority', c.priority ? `P${c.priority}` : ''],
            ['Court case', c.courtCaseId ? `#${c.courtCaseId}` : ''], ['Updated', time(c.updatedAt)]]));
        body.appendChild(h('h4', null, 'Summary'));
        body.appendChild(h('div', { class: 'pfp-pre' }, c.summary || 'No summary yet.'));
    }

    function drawPeople(body, d, can) {
        const { ctx } = state;
        const { h, ui } = ctx;
        const people = d.people || [];
        if (!people.length) body.appendChild(h('div', { class: 'pfp-state' }, 'Nobody is on this case yet.'));
        else {
            const t = h('table', { class: 'pfp-table' }, h('thead', null, h('tr', null, h('th', null, 'Role'), h('th', null, 'Name'), h('th', null, 'Citizen'), h('th', null, 'Note'), h('th'))));
            const tb = h('tbody');
            for (const p of people) {
                const err = ui.formError();
                tb.appendChild(h('tr', null, h('td', null, label(p.role)), h('td', null, p.name || ''),
                    h('td', null, p.citizenid ? h('button', { type: 'button', class: 'pfp-link', onClick: () => openCitizen(p.citizenid) }, p.citizenid) : (p.manualId ? `manual #${p.manualId}` : '-')),
                    h('td', null, p.note || ''),
                    h('td', null, can.manage && can.edit ? ui.btn('Remove', 'sm danger', () => act('pf_mdt:cases:removePerson', { personId: p.id }, err, 'Removed')) : null, err)));
            }
            t.appendChild(tb);
            body.appendChild(t);
        }
        if (!can.edit) return;
        const role = ui.select(ROLES, 'suspect', { 'aria-label': 'Role' });
        const cid = ui.input({ placeholder: 'Citizen id (preferred)', maxlength: 64 });
        const name = ui.input({ placeholder: 'or a name (unidentified person)', maxlength: 128 });
        const note = ui.input({ placeholder: 'Note', maxlength: 255 });
        const err = ui.formError();
        const add = ui.btn('Add person', 'primary sm', () => {
            const payload = { caseId: d.case.id, role: role.value };
            if (cid.value.trim()) payload.citizenid = cid.value.trim(); else payload.name = name.value.trim();
            if (note.value.trim()) payload.note = note.value.trim();
            act('pf_mdt:cases:addPerson', payload, err, 'Person added');
        });
        body.appendChild(h('h4', null, 'Add a person'));
        body.appendChild(h('div', { class: 'pfp-form' }, ui.field('Role', role), ui.field('Citizen id', cid), ui.field('Name', name), ui.field('Note', note)));
        body.appendChild(h('div', { class: 'pfp-toolbar' }, add, err));
    }

    // where a linked record opens: another page when it exists, else a plain line
    function linkTarget(l) {
        const { ctx } = state;
        const { h } = ctx;
        const id = String(l.refId || '');
        const btn = (text, fn) => h('button', { type: 'button', class: 'pfp-link', onClick: fn }, text);
        switch (l.type) {
            case 'incident': return typeof window.openIncidentDetailsModal === 'function' ? btn(id, () => window.openIncidentDetailsModal(id)) : id;
            case 'warrant': return btn(id, () => ctx.open('warrant', { warrantId: id }));
            case 'bolo': return btn(`#${id}`, () => ctx.open('bolos', { boloId: Number(id) }));
            case 'citation': case 'order': return h('span', null, `#${id} `, h('span', { class: 'pfp-muted' }, '(pf-justice court order)'));
            // the evidence chain page of unit 21B (html/pages/evidence_coc.js) opens an item by { id }
            case 'evidence': return ctx.has('evidencecoc') ? btn(id, () => ctx.open('evidencecoc', { id })) : id;
            case 'custody': return `#${id}`;
            case 'telemetry': return id;
            // the morgue attaches it (pf-ambulancejob AttachExternalRecord); its findings are the medical examiner's,
            // read through pf_mdt:cases:deathRecord (the server checks the link and audits the read)
            case 'death_record': return h('span', null, `#${id} `, h('span', { class: 'pfp-muted' }, '(medical examiner record, attached by the morgue) '),
                btn('Details', () => showDeathRecord(l)));
            default: return id;
        }
    }

    // the death record view under the links table (text only)
    async function showDeathRecord(link) {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        const slot = s.detailEl.querySelector('.pfp-death-record') || s.detailEl.appendChild(h('div', { class: 'pfp-card pfp-death-record', 'aria-live': 'polite' }));
        ctx.state(slot, 'loading', 'Reading the morgue record...');
        const caseId = s.data && s.data.case ? s.data.case.id : null;
        const res = await ctx.call('pf_mdt:cases:deathRecord', { caseId, linkId: link.id });
        if (!ctx.alive() || state !== s) return;
        if (!res.ok || !res.record) { ctx.state(slot, 'error', ctx.errorText(res, 'The death record could not be read.')); return; }
        const r = res.record;
        slot.textContent = '';
        slot.appendChild(h('div', { class: 'pfp-head' }, h('h3', null, `Death record #${r.id}`), ui.badge(label(r.state), r.state === 'released' ? '' : 'warn')));
        slot.appendChild(ui.kv([['Citizen', r.cid], ['Cause', r.cause], ['Manner', r.manner], ['Time of death', r.todText], ['Hospital', r.hospital],
            ['Recorded', ctx.time(r.createdAt)], ['Released', r.releasedAt ? ctx.time(r.releasedAt) : ''], ['Examiner', r.examinerCid]]));
        if (!r.autopsy) { slot.appendChild(h('div', { class: 'pfp-note' }, 'No autopsy yet: cause and manner are the intake values.')); return; }
        const a = r.autopsy;
        if (a.suggestedManner) slot.appendChild(h('div', { class: 'pfp-muted' }, `Manner the findings suggest: ${a.suggestedManner}`));
        if (a.note) { slot.appendChild(h('h4', null, 'Examiner note')); slot.appendChild(h('div', { class: 'pfp-pre' }, a.note)); }
        const inj = Array.isArray(a.injuries) ? a.injuries : [];
        if (inj.length) {
            slot.appendChild(h('h4', null, 'Injuries'));
            const t = h('table', { class: 'pfp-table' }, h('thead', null, h('tr', null, h('th', null, 'Injury'), h('th', null, 'Region'), h('th', null, 'Lethal'), h('th', null, 'Inflicted'))));
            const tb = h('tbody');
            for (const i of inj) tb.appendChild(h('tr', null, h('td', null, i.text || ''), h('td', null, i.region || ''), h('td', null, i.lethal ? 'yes' : ''),
                h('td', null, i.attacker === 'self' ? 'self' : (i.attacker === 'other' ? 'by another person' : ''))));
            t.appendChild(tb);
            slot.appendChild(t);
        }
        const tox = Array.isArray(a.toxins) ? a.toxins : [];
        if (tox.length) slot.appendChild(h('div', { class: 'pfp-muted' }, 'Toxicology: ' + tox.map((x) => `${x.name} ${x.level}`).join(', ')));
    }

    function drawLinks(body, d, can) {
        const { ctx } = state;
        const { h, ui } = ctx;
        const links = d.links || [];
        if (!links.length) body.appendChild(h('div', { class: 'pfp-state' }, 'No records linked yet.'));
        else {
            const t = h('table', { class: 'pfp-table' }, h('thead', null, h('tr', null, h('th', null, 'Type'), h('th', null, 'Record'), h('th', null, 'Note'), h('th', null, 'By'), h('th'))));
            const tb = h('tbody');
            for (const l of links) {
                const err = ui.formError();
                const system = !LINK_TYPES.some(([k]) => k === l.type);
                const canRemove = can.manage && can.edit && (!system || can.supervise);
                tb.appendChild(h('tr', { dataset: { linkType: l.type } }, h('td', null, LINK_LABEL[l.type] || label(l.type)), h('td', null, linkTarget(l)), h('td', null, l.note || ''),
                    h('td', null, String(l.by || '').startsWith('system:') ? 'system' : (l.by || ''), h('div', { class: 'pfp-muted' }, ctx.time(l.at))),
                    h('td', null, canRemove ? ui.btn('Unlink', 'sm danger', () => act('pf_mdt:cases:unlink', { linkId: l.id }, err, 'Unlinked')) : null, err)));
            }
            t.appendChild(tb);
            body.appendChild(t);
        }
        if (!can.edit) return;
        const type = ui.select(LINK_TYPES, 'incident', { 'aria-label': 'Record type' });
        const ref = ui.input({ placeholder: 'Record id', maxlength: 64 });
        const cid = ui.input({ placeholder: 'Citizen id (custody)', maxlength: 64 });
        const note = ui.input({ placeholder: 'Note', maxlength: 255 });
        const err = ui.formError();
        const add = ui.btn('Link record', 'primary sm', () => {
            const payload = { caseId: d.case.id, refType: type.value };
            if (type.value === 'custody') { payload.citizenid = cid.value.trim(); if (ref.value.trim()) payload.refId = Number(ref.value.trim()); }
            else if (['bolo', 'order', 'citation'].includes(type.value)) payload.refId = Number(ref.value.trim());
            else payload.refId = ref.value.trim();
            if (note.value.trim()) payload.note = note.value.trim();
            act('pf_mdt:cases:link', payload, err, 'Record linked');
        });
        body.appendChild(h('h4', null, 'Link a record'));
        body.appendChild(h('div', { class: 'pfp-form' }, ui.field('Type', type), ui.field('Id', ref), ui.field('Citizen id (custody only)', cid), ui.field('Note', note)));
        body.appendChild(h('div', { class: 'pfp-toolbar' }, add, err));
    }

    function drawEntries(body, d, can) {
        const { ctx } = state;
        const { h, ui } = ctx;
        const people = d.people || [];
        const entries = d.entries || [];
        if (can.edit) {
            const kind = ui.select(ENTRY_KINDS, 'note', { 'aria-label': 'Entry kind' });
            const person = ui.select([['', 'Person (statements, interviews)']].concat(people.map((p) => [p.id, `${p.name || p.citizenid} (${label(p.role)})`])), '');
            const assignee = ui.input({ placeholder: 'Officer citizen id (assignments)', maxlength: 64 });
            const text = ui.textarea({ placeholder: 'Entry', maxlength: 4000 });
            const err = ui.formError();
            const add = ui.btn('Add entry', 'primary sm', () => {
                const payload = { caseId: d.case.id, kind: kind.value, body: text.value };
                if (person.value) payload.personId = Number(person.value);
                if (assignee.value.trim()) payload.assigneeCid = assignee.value.trim();
                act('pf_mdt:cases:addEntry', payload, err, 'Entry added');
            });
            body.appendChild(h('div', { class: 'pfp-form' }, ui.field('Kind', kind), ui.field('Person', person), ui.field('Assign to', assignee), ui.field('Text', text, true)));
            body.appendChild(h('div', { class: 'pfp-toolbar' }, add, err));
        }
        if (!entries.length) { body.appendChild(h('div', { class: 'pfp-state' }, 'No entries yet.')); return; }
        const list = h('div', { class: 'pfp-list' });
        for (const e of entries) {
            const err = ui.formError();
            const statuses = ENTRY_STATUS[e.kind];
            let control = null;
            if (statuses && can.edit) {
                control = ui.select(statuses.map((st) => [st, label(st)]), e.status, { 'aria-label': 'Entry status' });
                control.addEventListener('change', () => act('pf_mdt:cases:setEntryStatus', { entryId: e.id, status: control.value }, err, 'Updated'));
            } else if (e.status) control = ui.badge(label(e.status));
            const person = e.personId ? people.find((p) => p.id === e.personId) : null;
            list.appendChild(h('div', { class: 'pfp-card', dataset: { entryId: e.id } },
                h('div', { class: 'pfp-head' }, h('strong', null, label(e.kind)), control),
                h('div', { class: 'pfp-muted' }, `${e.byName || e.by || ''} · ${ctx.time(e.at)}${person ? ` · ${person.name || person.citizenid}` : ''}${e.assigneeCid ? ` · assigned to ${e.assigneeName || e.assigneeCid}` : ''}`),
                h('div', { class: 'pfp-pre' }, e.body || ''), err));
        }
        body.appendChild(list);
    }

    function drawEvidence(body, d) {
        const { ctx } = state;
        const { h } = ctx;
        if (!Array.isArray(d.evidence)) { body.appendChild(h('div', { class: 'pfp-state pfp-state-error' }, d.evidenceNote || 'Evidence storage is not available right now.')); return; }
        if (!d.evidence.length) { body.appendChild(h('div', { class: 'pfp-state' }, 'No evidence linked. Link evidence under Records.')); return; }
        const t = h('table', { class: 'pfp-table' }, h('thead', null, h('tr', null, h('th', null, 'Id'), h('th', null, 'Kind'), h('th', null, 'Label'), h('th', null, 'State'))));
        const tb = h('tbody');
        for (const ev of d.evidence) {
            const id = String(ev.id ?? ev.evidenceId ?? '');
            tb.appendChild(h('tr', null,
                h('td', null, ctx.has('evidencecoc') ? h('button', { type: 'button', class: 'pfp-link', onClick: () => ctx.open('evidencecoc', { id }) }, id) : id),
                h('td', null, label(ev.kind || ev.type || '')), h('td', null, ev.label || ev.description || ''), h('td', null, label(ev.state || ev.status || ''))));
        }
        t.appendChild(tb);
        body.appendChild(t);
    }

    function drawCourt(body, d, can) {
        const { ctx } = state;
        const { h, ui } = ctx;
        const subs = d.submissions || [];
        const people = d.people || [];
        const SUB_KIND = { pending: 'warn', filed: 'ok', refused: 'bad', cancelled: '' };
        if (!subs.length) body.appendChild(h('div', { class: 'pfp-state' }, 'Nothing submitted to court yet.'));
        for (const sub of subs) {
            const p = people.find((x) => x.id === sub.personId);
            const err = ui.formError();
            const charges = Array.isArray(sub.charges) ? sub.charges.map((c) => (c && (c.code || c.name)) ? `${c.code || ''} ${c.name || ''}`.trim() : String(c)).join(', ') : '';
            const canWithdraw = (sub.state === 'pending' || sub.state === 'refused') && can.manage;
            body.appendChild(h('div', { class: 'pfp-card', dataset: { submissionId: sub.id } },
                h('div', { class: 'pfp-head' }, h('strong', null, `${p ? (p.name || p.citizenid) : sub.citizenid}`), ui.badge(label(sub.state), SUB_KIND[sub.state])),
                h('div', { class: 'pfp-muted' }, `Charges: ${charges || '-'}`),
                sub.courtCaseId ? h('div', { class: 'pfp-muted' }, `Court case #${sub.courtCaseId}`) : null,
                sub.state === 'pending' ? h('div', { class: 'pfp-note' }, 'Stored as ready for court; it is handed to the court system as soon as it accepts it.') : null,
                sub.lastError ? h('div', { class: 'pfp-muted' }, `Last answer: ${sub.lastError}`) : null,
                canWithdraw ? ui.btn('Withdraw', 'sm danger', () => act('pf_mdt:cases:withdrawSubmission', { submissionId: sub.id }, err, 'Withdrawn')) : null, err));
        }
        if (!can.submit) return;
        const suspects = people.filter((p) => p.role === 'suspect' && p.citizenid);
        if (!suspects.length) { body.appendChild(h('div', { class: 'pfp-note' }, 'Add an identified suspect (citizen id) to submit the case.')); return; }
        const who = ui.select(suspects.map((p) => [p.id, `${p.name || p.citizenid} (${p.citizenid})`]), suspects[0].id, { 'aria-label': 'Suspect' });
        const chargeBox = h('div', { class: 'pfp-grid' }, h('div', { class: 'pfp-muted' }, 'Loading charges...'));
        const prosecutor = ui.input({ placeholder: 'Prosecutor citizen id (DOJ, optional)', maxlength: 64 });
        const note = ui.textarea({ placeholder: 'Note for the court', maxlength: 1000 });
        const err = ui.formError();
        const submit = ui.btn('Submit to court', 'primary sm', () => {
            const charges = Array.from(chargeBox.querySelectorAll('input[type=checkbox]:checked')).map((i) => i.value);
            const payload = { caseId: d.case.id, personId: Number(who.value), charges };
            if (prosecutor.value.trim()) payload.prosecutorCid = prosecutor.value.trim();
            if (note.value.trim()) payload.note = note.value.trim();
            act('pf_mdt:cases:submit', payload, err, 'Submitted');
        });
        body.appendChild(h('h4', null, 'Submit a suspect'));
        body.appendChild(h('div', { class: 'pfp-form' }, ui.field('Suspect', who), ui.field('Prosecutor', prosecutor), ui.field('Note', note, true)));
        body.appendChild(h('h4', null, 'Charges'));
        body.appendChild(chargeBox);
        body.appendChild(h('div', { class: 'pfp-toolbar' }, submit, err));
        ctx.call('pf_mdt:getAllCharges', {}).then((res) => {
            if (!ctx.alive()) return;
            chargeBox.textContent = '';
            const rows = Array.isArray(res.data) ? res.data : (Array.isArray(res.list) ? res.list : []);
            if (!res.ok || !rows.length) { chargeBox.appendChild(h('div', { class: 'pfp-state pfp-state-error' }, res.ok ? 'No charges in the criminal code.' : ctx.errorText(res))); return; }
            for (const c of rows) {
                if (!c || !c.code) continue;
                chargeBox.appendChild(h('label', { class: 'pfp-muted' }, h('input', { type: 'checkbox', value: c.code }), ` ${c.code} ${c.name || ''}`));
            }
        });
    }

    // the citizen profile modal of app-extended.js (router is app.js's global)
    function openCitizen(cid) {
        try { if (typeof router !== 'undefined' && router) { router.openCitizenProfile(cid); return; } } catch (_) {}
    }

    function openCreate() {
        const s = state;
        const { h, ui } = s.ctx;
        s.formSlot.textContent = '';
        const title = ui.input({ placeholder: 'Title', maxlength: 128 });
        const prio = ui.select([['1', 'P1 (urgent)'], ['2', 'P2'], ['3', 'P3'], ['4', 'P4 (low)']], '2');
        const summary = ui.textarea({ placeholder: 'Summary', maxlength: 4000 });
        const err = ui.formError();
        const close = () => { s.formSlot.textContent = ''; };
        const save = ui.btn('Create case', 'primary', async () => {
            err.textContent = '';
            const res = await s.ctx.call('pf_mdt:cases:create', { title: title.value, priority: Number(prio.value), summary: summary.value });
            if (!s.ctx.alive() || state !== s) return;
            if (!res.ok) { err.textContent = s.ctx.errorText(res); return; }
            s.ctx.toast(`Case ${res.caseNo || ''} created`, 'success');
            close();
            await loadList(true);
            if (res.caseId) select(Number(res.caseId));
        });
        const card = ui.escCloses(h('div', { class: 'pfp-card' }, h('h3', null, 'New case'),
            h('div', { class: 'pfp-form' }, ui.field('Title', title), ui.field('Priority', prio), ui.field('Summary', summary, true)),
            h('div', { class: 'pfp-toolbar' }, save, ui.btn('Cancel', 'ghost', close), err)), close);
        s.formSlot.appendChild(card);
        title.focus();
    }

    function openEdit(c) {
        const s = state;
        const { h, ui } = s.ctx;
        s.editSlot.textContent = '';
        const title = ui.input({ value: c.title || '', maxlength: 128 });
        const prio = ui.select([['1', 'P1'], ['2', 'P2'], ['3', 'P3'], ['4', 'P4']], String(c.priority || 2));
        const summary = ui.textarea({ maxlength: 4000 });
        summary.value = c.summary || '';
        const err = ui.formError();
        const close = () => { s.editSlot.textContent = ''; };
        const save = ui.btn('Save', 'primary sm', () => act('pf_mdt:cases:update', { caseId: c.id, title: title.value, priority: Number(prio.value), summary: summary.value }, err, 'Saved'));
        s.editSlot.appendChild(ui.escCloses(h('div', { class: 'pfp-card' },
            h('div', { class: 'pfp-form' }, ui.field('Title', title), ui.field('Priority', prio), ui.field('Summary', summary, true)),
            h('div', { class: 'pfp-toolbar' }, save, ui.btn('Cancel', 'ghost sm', close), err)), close));
    }

    async function openLeadForm(c, err) {
        const s = state;
        const { h, ui } = s.ctx;
        s.editSlot.textContent = '';
        const sel = ui.select([['', 'Loading officers...']], '');
        const close = () => { s.editSlot.textContent = ''; };
        const save = ui.btn('Assign', 'primary sm', () => act('pf_mdt:cases:setLead', { caseId: c.id, leadCid: sel.value }, err, 'Lead assigned'));
        s.editSlot.appendChild(ui.escCloses(h('div', { class: 'pfp-card' }, ui.field('Lead detective', sel), h('div', { class: 'pfp-toolbar' }, save, ui.btn('Cancel', 'ghost sm', close))), close));
        const res = await s.ctx.call('pf_mdt:getPoliceOfficers', {});
        if (!s.ctx.alive() || state !== s) return;
        const list = Array.isArray(res.data) ? res.data : [];
        sel.textContent = '';
        if (!list.length) sel.appendChild(h('option', { value: '' }, res.ok ? 'No officers found' : s.ctx.errorText(res)));
        for (const o of list) {
            if (!o || !o.citizenid) continue;
            sel.appendChild(h('option', { value: o.citizenid }, `${o.callsign ? o.callsign + ' ' : ''}${o.name || o.citizenid}`));
        }
    }

    window.PFMdtPages.register('cases', {
        title: 'Cases',
        section: 'documentation',
        order: 5,
        icon: ['M3 7h18v13H3z', 'M8 7V4h8v3', 'M3 12h18'],
        render,
        unmount() { state = null; },
        onMessage() {},
    });
})();
