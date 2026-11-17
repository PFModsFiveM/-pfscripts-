// Custody and booking record (batch 21, unit 21B).
//
// One citizen's custody as pf-justice holds it: the open custody (or the latest closed one), the
// booking, the active incarceration with the server's remaining time, recent orders and bail, read
// through server/pages_ext.lua (pf_mdt:custody:get). The sentence clock is read-only: the court and
// corrections change it, never the MDT. Jail and prison count online time only, so the page shows
// the server's figure "as of" the read instead of a countdown that would run while the inmate is
// offline. Officers on duty add custody log entries (rights read, meals, calls ...) to the open
// custody (pf_mdt:custody:log -> pf-justice AddCustodyLog). The custody log is read back newest
// first (the first page comes with the record, older pages through pf_mdt:custody:history), and the
// booking's property receipt (pf-justice GetPropertyReceipt) lists what is held in the locker.
// Every server string goes into the DOM as text (ctx.h); nothing here builds HTML from data.
(function () {
    'use strict';

    const LOG_KINDS = [
        ['rights_read', 'Rights read'], ['phone_call', 'Phone call'], ['attorney_visit', 'Attorney visit'],
        ['interview_start', 'Interview started'], ['interview_end', 'Interview ended'], ['meal', 'Meal'],
        ['medical_check', 'Medical check'], ['use_of_force', 'Use of force'], ['note', 'Note'],
    ];
    const LOG_LABEL = Object.fromEntries(LOG_KINDS);
    const ITEM_TONE = { held: 'warn', returned: 'ok', forfeited: 'bad' };
    const OPEN_TONE = { detained: 'warn', arrested: 'warn', in_transport: 'warn', booking: 'warn', held: 'bad', remanded: 'bad', hospital: 'warn' };

    function words(s) { return String(s == null ? '' : s).replace(/_/g, ' '); }

    // A log row's data ({ from, to, text ... } as the server wrote it) as one line of "key: value".
    function logDetail(data) {
        if (!data || typeof data !== 'object') return '';
        return Object.keys(data).slice(0, 12).map((k) => {
            const v = data[k];
            const shown = (v !== null && typeof v === 'object') ? JSON.stringify(v).slice(0, 120) : String(v);
            return k === 'text' ? shown : `${words(k)}: ${words(shown)}`;
        }).join(' · ');
    }

    // 3725 -> "1h 2m 5s"
    function duration(sec) {
        sec = Math.max(0, Math.floor(Number(sec) || 0));
        const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
        if (h) return `${h}h ${m}m`;
        if (m) return `${m}m ${s}s`;
        return `${s}s`;
    }

    function make(ctx) {
        const el = (tag, attrs, ...kids) => ctx.h(tag, attrs || {}, ...kids.flat().filter((k) => k !== null && k !== undefined && k !== false));
        const field = (label, value) => (value === null || value === undefined || value === '') ? null
            : el('div', { class: 'pfx-field' }, el('span', { class: 'pfx-label', text: label }), el('span', { class: 'pfx-value', text: String(value) }));
        const badge = (text, tone) => el('span', { class: `pfp-badge ${tone || ''}`.trim(), text: words(text) });
        return { el, field, badge };
    }

    const page = {
        title: 'Custody & Booking',
        label: 'Custody',
        section: 'records',
        order: 40,
        icon: ['M4 4h16v16H4z', 'M9 4v16', 'M15 4v16'],

        async render(root, ctx) {
            const { el, field, badge } = make(ctx);
            let access = null;

            const input = el('input', { class: 'pfp-input', type: 'search', placeholder: 'Name or citizen id', 'aria-label': 'Citizen', maxlength: '64' });
            const results = el('div', { class: 'pfx-results', role: 'list' });
            const record = el('div', { class: 'pfx-record' });
            const form = el('form', { class: 'pfp-toolbar', onSubmit: (e) => { e.preventDefault(); search(); } },
                input,
                el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Search' }),
                el('button', { class: 'pfp-btn', type: 'button', text: 'Open by citizen id', onClick: () => openCid(input.value.trim()) }));
            root.appendChild(el('div', { class: 'pfx-page pfx-custody' },
                el('div', { class: 'pfx-head' }, el('h2', { text: 'Custody & Booking' }),
                    el('p', { class: 'pfp-muted', text: 'Custody, booking and sentence records from the justice system. The sentence clock is read-only.' })),
                form, results, record));

            async function search() {
                const q = input.value.trim();
                results.textContent = '';
                if (q.length < 2) { ctx.state(results, 'error', 'Type at least two characters'); return; }
                ctx.state(results, 'loading', 'Searching citizens...');
                const res = await ctx.call('pf_mdt:searchCitizens', { query: q, page: 1, pageSize: 9 });
                if (!ctx.alive()) return;
                results.textContent = '';
                const rows = res && Array.isArray(res.data) ? res.data : null;
                if (!rows) { ctx.state(results, 'error', ctx.errorText(res, 'The search failed')); return; }
                if (!rows.length) { ctx.state(results, 'empty', 'No citizen matches'); return; }
                rows.forEach((c) => {
                    const cid = String(c.citizenId || c.citizenid || '');
                    results.appendChild(el('button', { class: 'pfx-result', type: 'button', role: 'listitem', dataset: { cid },
                        onClick: () => openCid(cid) },
                        el('strong', { text: String(c.name || cid) }), el('span', { class: 'pfp-muted', text: cid })));
                });
            }

            async function openCid(cid) {
                if (!/^[A-Za-z0-9_-]{1,32}$/.test(cid)) { ctx.toast('Enter a valid citizen id', 'error'); return; }
                results.textContent = '';
                record.textContent = '';
                ctx.state(record, 'loading', 'Reading the custody record...');
                if (!access) {
                    access = await ctx.call('pf_mdt:pages:access', {});
                    if (!ctx.alive()) return;
                }
                const res = await ctx.call('pf_mdt:custody:get', { cid });
                if (!ctx.alive()) return;
                record.textContent = '';
                if (!res || !res.ok) { ctx.state(record, 'error', ctx.errorText(res, 'The custody record could not be read')); return; }
                draw(res);
            }

            function draw(res) {
                const cu = res.custody;
                const cards = [];
                if (!cu) {
                    ctx.state(record, 'empty', 'No custody on record for this citizen');
                } else {
                    const open = !cu.closedAt;
                    cards.push(el('section', { class: 'pfp-card', 'aria-label': 'Custody' },
                        el('header', { class: 'pfx-card-head' }, el('h3', { text: `Custody #${cu.id}` }),
                            badge(cu.state, open ? (OPEN_TONE[cu.state] || 'warn') : 'ok'), open ? badge('open', 'accent') : badge('closed', '')),
                        el('div', { class: 'pfx-grid' },
                            field('Citizen', res.cid), field('Facility', words(cu.facility)), field('Cell', cu.cellId),
                            field('Since', ctx.time(cu.since)), field('Booking no.', cu.bookingNo),
                            field('Hold until', cu.holdUntil ? ctx.time(cu.holdUntil) : null), field('Arresting officer', cu.officerCid),
                            field('Reason', cu.reason), field('Incident', cu.incidentId),
                            field('Released', cu.closedAt ? ctx.time(cu.closedAt) : null), field('Release reason', words(cu.releaseReason))),
                        chargesList(cu.charges)));
                }
                if (res.booking) cards.push(bookingCard(res.booking));
                else if (res.bookingError) cards.push(el('p', { class: 'pfx-error', text: res.bookingError }));
                if (res.receipt) cards.push(receiptCard(res.receipt));
                else if (res.receiptError) cards.push(el('p', { class: 'pfx-error', text: res.receiptError }));
                cards.push(clockCard(res));
                if (res.bail) cards.push(bailCard(res.bail));
                cards.push(ordersCard(res));
                if (cu) cards.push(historyCard(cu, res));
                if (cu && !cu.closedAt) cards.push(logCard(cu));
                cards.forEach((c) => c && record.appendChild(c));
            }

            function chargesList(charges) {
                if (!Array.isArray(charges) || !charges.length) return null;
                return el('div', { class: 'pfx-sub' }, el('span', { class: 'pfx-label', text: 'Charges' }),
                    el('ul', { class: 'pfx-list' }, charges.map((c) => el('li', {
                        text: typeof c === 'object' && c ? `${c.label || c.name || c.code || 'Charge'}${c.count > 1 ? ` x${c.count}` : ''}` : String(c),
                    }))));
            }

            function bookingCard(b) {
                const pic = typeof window.safeImageUrl === 'function' ? window.safeImageUrl(b.mugshotUrl) : '';
                return el('section', { class: 'pfp-card', 'aria-label': 'Booking' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: `Booking ${b.bookingNo || ''}`.trim() }),
                        b.clientSupplied ? badge('photo supplied by officer client', 'warn') : null),
                    el('div', { class: 'pfx-row' },
                        pic ? el('img', { class: 'pfx-mugshot', src: pic, alt: 'Booking photo', referrerpolicy: 'no-referrer' }) : null,
                        el('div', { class: 'pfx-grid' },
                            field('Booked', ctx.time(b.at)), field('Booked by', b.bookedBy), field('Height (cm)', b.height),
                            field('Marks', b.marks), field('Medical screening', words(b.screening)), field('Fingerprint', b.fingerprint),
                            field('Blood type', b.bloodtype), field('DNA sample', b.dnaSampleRef), field('Notes', b.notes))));
            }

            function receiptCard(r) {
                const items = Array.isArray(r.items) ? r.items : [];
                const card = el('section', { class: 'pfp-card', 'aria-label': 'Property receipt' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: `Property receipt #${r.id}` }), badge(r.state, ITEM_TONE[r.state] || '')),
                    el('div', { class: 'pfx-grid' },
                        field('Seized', ctx.time(r.seizedAt)), field('Seized by', r.seizedBy), field('Reason', r.reason),
                        field('Order', r.orderId ? `#${r.orderId}` : null), field('Returned', r.returnedAt ? ctx.time(r.returnedAt) : null)));
                if (!items.length) { card.appendChild(el('p', { class: 'pfp-muted', text: 'Nothing was taken into the locker' })); return card; }
                card.appendChild(el('div', { class: 'pfx-table-wrap' }, el('table', { class: 'pfp-table' },
                    el('thead', {}, el('tr', {}, ['Item', 'Amount', 'State', 'Evidence'].map((t) => el('th', { scope: 'col', text: t })))),
                    el('tbody', {}, items.map((it) => el('tr', {},
                        el('td', { text: String(it.name || '') }), el('td', { text: String(it.amount == null ? '' : it.amount) }),
                        el('td', {}, badge(it.state, ITEM_TONE[it.state] || '')),
                        el('td', { text: it.evidenceId ? `#${it.evidenceId}` : '' })))))));
                return card;
            }

            function historyCard(cu, res) {
                const card = el('section', { class: 'pfp-card', 'aria-label': 'Custody log history' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Custody log' })));
                if (res.logError) { card.appendChild(el('p', { class: 'pfx-error', text: res.logError })); return card; }
                const list = el('ol', { class: 'pfx-list pfx-log' });
                const more = el('button', { class: 'pfp-btn', type: 'button', text: 'Load older entries' });
                let next = res.logNext || null;
                const add = (rows) => rows.forEach((l) => list.appendChild(el('li', { class: 'pfx-log-row', dataset: { id: String(l.id) } },
                    el('span', { class: 'pfp-muted', text: ctx.time(l.at) }), ' ',
                    el('strong', { text: LOG_LABEL[l.kind] || words(l.kind) }),
                    l.actorCid ? el('span', { class: 'pfp-muted', text: ` by ${l.actorCid}` }) : null,
                    logDetail(l.data) ? el('div', { class: 'pfx-log-detail', text: logDetail(l.data) }) : null)));
                const rows = Array.isArray(res.log) ? res.log : [];
                if (!rows.length) card.appendChild(el('p', { class: 'pfp-muted', text: 'No log entries' }));
                add(rows);
                card.appendChild(list);
                more.hidden = !next;
                more.addEventListener('click', async () => {
                    if (!next) return;
                    more.disabled = true;
                    const page = await ctx.call('pf_mdt:custody:history', { custodyId: cu.id, before: next });
                    if (!ctx.alive()) return;
                    more.disabled = false;
                    if (!page || !page.ok) { ctx.toast(ctx.errorText(page, 'The custody log could not be read'), 'error'); return; }
                    add(Array.isArray(page.log) ? page.log : []);
                    next = page.logNext || null;
                    more.hidden = !next;
                });
                card.appendChild(more);
                return card;
            }

            function clockCard(res) {
                const inc = res.incarceration;
                const card = el('section', { class: 'pfp-card', 'aria-label': 'Sentence clock' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Sentence clock' }), badge('read-only', '')));
                if (!inc || !inc.order) {
                    card.appendChild(el('p', { class: 'pfp-muted', text: res.incarcerationError || 'No active jail, prison or remand order' }));
                    return card;
                }
                const o = inc.order;
                const required = Math.max(0, Number(o.requiredSeconds) || 0);
                const remaining = Math.max(0, Number(inc.remainingSeconds) || 0);
                const done = required > 0 ? Math.min(100, Math.round(((required - Math.min(required, remaining)) / required) * 100)) : 0;
                const bar = el('div', { class: 'pfx-progress', role: 'progressbar', 'aria-valuemin': '0', 'aria-valuemax': '100', 'aria-valuenow': String(done) },
                    el('div', { class: 'pfx-progress-fill' }));
                bar.firstChild.style.width = `${done}%`;
                card.appendChild(el('div', { class: 'pfx-clock' },
                    el('div', { class: 'pfx-clock-main' }, el('span', { class: 'pfx-clock-time', text: duration(remaining) }),
                        el('span', { class: 'pfp-muted', text: `remaining as of ${ctx.time(res.at)}` })),
                    bar,
                    el('div', { class: 'pfx-grid' },
                        field('Order', `#${o.id} ${words(o.kind)}`), field('State', words(o.state)), field('Facility', words(inc.facility || o.facility)),
                        field('Clock', o.clock === 'online' ? 'online time (counts while the inmate is in the city)' : words(o.clock)),
                        field('Sentence', duration(required)), field('Served', duration(o.servedSeconds)),
                        field('Credit', o.creditSeconds ? duration(o.creditSeconds) : null), field('Forfeited', o.forfeitSeconds ? duration(o.forfeitSeconds) : null),
                        field('Release at', o.releaseAt ? ctx.time(o.releaseAt) : null)),
                    o.state === 'suspended' ? el('p', { class: 'pfx-warn', text: 'The order is suspended (escape or court hold): the clock is stopped.' }) : null,
                    el('button', { class: 'pfp-btn', type: 'button', text: 'Read again', onClick: () => openCid(res.cid) })));
                return card;
            }

            function bailCard(b) {
                return el('section', { class: 'pfp-card', 'aria-label': 'Bail' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: `Bail #${b.id}` }), badge(b.state, b.state === 'posted' ? 'ok' : '')),
                    el('div', { class: 'pfx-grid' }, field('Amount', b.amount != null ? `$${Number(b.amount).toLocaleString()}` : null),
                        field('Offered', ctx.time(b.offeredAt)), field('Expires', b.expiresAt ? ctx.time(b.expiresAt) : null),
                        field('Payer', b.payerName || b.payerCid), field('Posted', b.postedAt ? ctx.time(b.postedAt) : null)));
            }

            function ordersCard(res) {
                const card = el('section', { class: 'pfp-card', 'aria-label': 'Orders' }, el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Orders' })));
                if (res.ordersError) { card.appendChild(el('p', { class: 'pfx-error', text: res.ordersError })); return card; }
                const list = Array.isArray(res.orders) ? res.orders : [];
                if (!list.length) { card.appendChild(el('p', { class: 'pfp-muted', text: 'No orders' })); return card; }
                card.appendChild(el('div', { class: 'pfx-table-wrap' }, el('table', { class: 'pfp-table' },
                    el('thead', {}, el('tr', {}, ['#', 'Kind', 'State', 'Amount / time', 'Created'].map((t) => el('th', { scope: 'col', text: t })))),
                    el('tbody', {}, list.map((o) => el('tr', {},
                        el('td', { text: String(o.id) }), el('td', { text: words(o.kind) }), el('td', {}, badge(o.state, '')),
                        el('td', { text: o.requiredSeconds ? duration(o.requiredSeconds) : (o.amount != null ? `$${Number(o.amount).toLocaleString()}` : (o.units ? `${o.unitsDone || 0}/${o.units} units` : '')) }),
                        el('td', { text: ctx.time(o.createdAt) })))))));
                return card;
            }

            function logCard(cu) {
                const may = access && access.ok && access.can && access.can.custodyLog && access.onduty;
                const card = el('section', { class: 'pfp-card', 'aria-label': 'Custody log' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Add to the custody log' })));
                if (!may) {
                    card.appendChild(el('p', { class: 'pfp-muted', text: access && access.ok && !access.onduty ? 'Go on duty to add log entries.' : 'Your rank cannot add custody log entries.' }));
                    return card;
                }
                const kind = el('select', { class: 'pfp-select', 'aria-label': 'Entry' }, LOG_KINDS.map(([v, t]) => el('option', { value: v, text: t })));
                const note = el('input', { class: 'pfp-input', type: 'text', maxlength: '500', placeholder: 'Details (required for a note)', 'aria-label': 'Details' });
                const btn = el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Add entry' });
                card.appendChild(el('form', { class: 'pfp-toolbar', onSubmit: async (e) => {
                    e.preventDefault();
                    btn.disabled = true;
                    const res = await ctx.call('pf_mdt:custody:log', { custodyId: cu.id, kind: kind.value, text: note.value });
                    if (!ctx.alive()) return;
                    btn.disabled = false;
                    if (res && res.ok) { note.value = ''; ctx.toast('Added to the custody log', 'success'); }
                    else ctx.toast(ctx.errorText(res, 'The entry was not saved'), 'error');
                } }, kind, note, btn));
                return card;
            }

            const cid = ctx.params && ctx.params.cid;
            if (cid) { input.value = String(cid); await openCid(String(cid)); }
        },

    };

    if (window.PFMdtPages && typeof window.PFMdtPages.register === 'function') window.PFMdtPages.register('custody', page);
    window.PFMdtExtPages = window.PFMdtExtPages || {};
    window.PFMdtExtPages.custody = page;
})();
