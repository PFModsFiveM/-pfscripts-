// Hospital workstation (pf-devices module app 'hospital', batch 21D): reception queue, triage board,
// bed board, admissions with a patient panel, discharge orders, lab / imaging / pharmacy queues and
// bills. Everything shown comes from server/hospital_app.lua, which re-checks the player and asks
// pf-ambulancejob; every action is decided there (tier, position, beds, results). Server strings are
// put into the DOM as text only (ctx.h); the pages offered are the ones the server's init lists.
(function () {
    const APP = 'hospital';
    const ERRORS = {
        offline: 'You are not loaded yet.', not_staff: 'Only hospital staff use the workstation.', not_on_duty: 'Go on duty first.',
        not_authorized: 'Only on-duty hospital staff use the workstation.', hospital_offline: 'The hospital system is offline.',
        patient_offline: 'The patient is not in the city.', bad_args: 'Check the form.', not_found: 'Not found (it may have closed meanwhile).',
        no_permission: 'That is outside your scope of practice.', too_far: 'You must be with the patient in the hospital.',
        invalid_state: 'The record changed; refresh and try again.', conflict: 'That conflicts with the current record.',
        busy: 'Busy; try again in a moment.', rate_limited: 'Slow down.', db_unavailable: 'Hospital records are unavailable right now.',
        no_answer: 'The hospital did not answer in time; refresh to see whether it went through.', server_error: 'Something went wrong.',
        timeout: 'The server did not answer in time.', request_failed: 'The request did not reach the server.', key_reused: 'That was already recorded differently.',
        not_allowed: 'The hospital refused this workstation.', unknown_method: 'This action is not available.', payload_too_large: 'Too much text.',
    };
    const errText = (res) => (res && typeof res.message === 'string' && res.message) || ERRORS[res && res.error]
        || (res && res.error ? String(res.error).replace(/_/g, ' ') : 'That did not work.');

    const TRIAGE_ORDER = { red: 1, orange: 2, yellow: 3, green: 4, blue: 5 };
    const STATE_LABEL = {
        arrived: 'Arrived', checked_in: 'Checked in', triaged: 'Triaged', waiting: 'Waiting', in_treatment: 'In treatment', admitted: 'Admitted',
        discharged: 'Discharged', transferred: 'Transferred', left_ama: 'Left (AMA)', deceased: 'Deceased',
    };
    const RECEPTION = { arrived: true, checked_in: true, waiting: true };
    const PAGE_LABEL = {
        reception: 'Reception', triage: 'Triage board', beds: 'Beds', admissions: 'Admissions', discharge: 'Discharge',
        lab: 'Lab', imaging: 'Imaging', pharmacy: 'Pharmacy', bills: 'Bills',
    };
    const BILL_STATES = ['open', 'charging', 'payment_pending', 'invoiced', 'paid', 'waived'];
    const cleanups = new WeakMap();

    PFApps.register(APP, {
        mount(container, ctx) {
            const { h, money, timeAgo } = ctx;
            const S = {
                init: null, initError: null, facility: null, page: null,
                board: null, boardError: null, boardLoading: false, selected: null,
                view: 'open', history: null, historyError: null, historyState: '', filter: '', sort: 'triage',
                orders: { lab: null, imaging: null }, ordersError: {}, ordersOpen: { lab: true, imaging: true },
                pharmacy: { q: '', page: 1, data: null, error: null }, log: null,
                bills: { q: '', state: '', page: 1, data: null, error: null, open: null, lines: null },
                results: null, dischargeFor: null, busy: false,
            };
            let reloadTimer = null;
            cleanups.set(ctx, () => { if (reloadTimer) clearTimeout(reloadTimer); });

            const title = h('div.pf-app-sub', 'Loading…');
            const facilitySelect = h('select.pf-select.hosp-facility', { 'aria-label': 'Hospital', 'data-action': 'facility' });
            const headerInfo = h('div.hosp-header-info');
            const tabs = h('div.pf-tabs.hosp-tabs', { role: 'tablist' });
            const body = h('div.pf-app-body.hosp-body');
            container.appendChild(h('div.pf-app.hosp-app',
                h('div.pf-app-header',
                    h('div.pf-app-title', h('span.pf-icon', '🏥'), h('div', 'Hospital', title)),
                    h('div.pf-row.hosp-header-tools', headerInfo, facilitySelect,
                        h('button.pf-btn.sm.ghost', { 'data-action': 'refresh', onclick: () => reloadPage() }, 'Refresh'))),
                tabs, body));

            facilitySelect.addEventListener('change', () => {
                S.facility = facilitySelect.value;
                S.selected = null; S.board = null; S.history = null; S.orders = { lab: null, imaging: null };
                S.pharmacy.data = null; S.bills.data = null; S.log = null; S.results = null;
                reloadPage();
            });
            container.addEventListener('keydown', (e) => {
                if (e.key === 'Escape' && S.selected != null) { S.selected = null; S.results = null; render(); }
            });

            // ── helpers ───────────────────────────────────────────────────────
            const when = (ts) => (ts ? timeAgo(ts) : '');
            const inSeconds = (ts) => {
                if (!ts) return '';
                const s = Math.round(ts - Date.now() / 1000);
                if (s <= 0) return 'due now';
                return s < 120 ? `in ${s} s` : `in ${Math.round(s / 60)} min`;
            };
            const loading = (text) => h('div.pf-empty.hosp-loading', { role: 'status' }, text || 'Loading…');
            const empty = (text) => h('div.pf-empty', text);
            const errorBox = (res, retry) => h('div.pf-card.hosp-error', { role: 'alert' }, h('div', errText(res)),
                retry ? h('button.pf-btn.sm', { 'data-action': 'retry', onclick: retry }, 'Try again') : null);
            const triageBadge = (t) => (t ? h('span.hosp-triage.hosp-triage-' + (TRIAGE_ORDER[t] ? t : 'none'), t) : h('span.hosp-triage.hosp-triage-none', 'none'));
            const stateBadge = (s) => h('span.pf-badge' + (s === 'admitted' || s === 'in_treatment' ? '.ok' : s === 'discharged' ? '' : s === 'left_ama' || s === 'deceased' ? '.bad' : '.warn'),
                STATE_LABEL[s] || s || '');
            const patientCell = (a) => h('td', h('div.pf-strong', a.name || 'Unknown'),
                h('div.pf-small.pf-muted', a.citizenid || ''),
                a.online === false && a.open ? h('span.pf-badge.bad', 'offline') : null,
                a.custody ? h('span.pf-badge.accent', 'custody') : null,
                a.mode === 'ai' ? h('span.pf-badge', 'AI care') : null);
            const deptLabel = (d) => {
                const map = (S.init && S.init.options && S.init.options.departments) || {};
                return map[d] || d || '';
            };
            const admissions = () => (S.board && S.board.admissions) || [];
            const byId = (id) => admissions().find((a) => a.id === id);
            const scroll = (el) => h('div.hosp-scroll', el);
            const select = (attrs, options, current) => h('select.pf-select', attrs, options.map(([v, label]) =>
                h('option', { value: String(v), selected: String(v) === String(current == null ? '' : current) }, label)));

            async function call(method, payload, okText) {
                if (S.busy) return null;
                S.busy = true;
                let res;
                try { res = await ctx.rpc(method, payload); } finally { S.busy = false; }
                if (!res || !res.ok) { ctx.notify(errText(res), 'error'); return res || { ok: false }; }
                if (okText) ctx.notify(typeof okText === 'function' ? okText(res) : okText, 'success');
                return res;
            }

            // ── loading ───────────────────────────────────────────────────────
            async function loadInit() {
                const res = await ctx.rpc('init');
                if (!res || !res.ok) { S.initError = res || { ok: false }; render(); return; }
                S.init = res; S.initError = null;
                S.facility = res.facility;
                S.page = (res.pages || [])[0] || null;
                facilitySelect.textContent = '';
                (res.facilities || []).forEach((f) => facilitySelect.appendChild(h('option', { value: f.id, selected: f.id === S.facility }, f.label || f.id)));
                await reloadPage();
            }

            async function loadBoard() {
                S.boardLoading = true;
                if (!S.board) render();
                const res = await ctx.rpc('board', { facility: S.facility });
                S.boardLoading = false;
                if (!res || !res.ok) { S.boardError = res || { ok: false }; S.board = null; } else { S.board = res; S.boardError = null; }
                if (S.selected != null && !byId(S.selected)) { S.selected = null; S.results = null; }
                render();
            }

            async function loadHistory() {
                S.history = null; S.historyError = null; render();
                const res = await ctx.rpc('history', { facility: S.facility, state: S.historyState, limit: 100 });
                if (!res || !res.ok) S.historyError = res || { ok: false }; else S.history = res.admissions || [];
                render();
            }

            async function loadOrders(kind) {
                S.orders[kind] = null; S.ordersError[kind] = null; render();
                const res = await ctx.rpc('orders', { facility: S.facility, kind, open: S.ordersOpen[kind] });
                if (!res || !res.ok) S.ordersError[kind] = res || { ok: false }; else S.orders[kind] = res.orders || [];
                render();
            }

            async function loadPharmacy() {
                const P = S.pharmacy;
                P.data = null; P.error = null; render();
                const res = await ctx.rpc('pharmacy', { facility: S.facility, q: P.q, page: P.page });
                if (!res || !res.ok) P.error = res || { ok: false }; else P.data = res;
                render();
            }

            async function loadBills() {
                const B = S.bills;
                B.data = null; B.error = null; B.open = null; B.lines = null; render();
                const res = await ctx.rpc('bills', { facility: S.facility, state: B.state, q: B.q, page: B.page });
                if (!res || !res.ok) B.error = res || { ok: false }; else B.data = res;
                render();
            }

            async function reloadPage() {
                if (!S.init) return;
                const p = S.page;
                const needsBoard = ['reception', 'triage', 'beds', 'admissions', 'discharge', 'lab', 'imaging', 'pharmacy'].includes(p);
                const jobs = [];
                if (needsBoard) jobs.push(loadBoard());
                if (p === 'admissions' && S.view === 'history') jobs.push(loadHistory());
                if (p === 'lab' || p === 'imaging') jobs.push(loadOrders(p));
                if (p === 'pharmacy') jobs.push(loadPharmacy());
                if (p === 'bills') jobs.push(loadBills());
                render();
                await Promise.all(jobs);
            }

            function scheduleBoard() {
                if (reloadTimer) clearTimeout(reloadTimer);
                reloadTimer = setTimeout(() => { reloadTimer = null; if (S.init) loadBoard(); }, 400);
            }

            ctx.on('changed', (p) => { if (p && p.hospitalId === S.facility) scheduleBoard(); });
            ctx.on('orders', (p) => {
                if (p && p.hospitalId === S.facility && (S.page === p.kind)) loadOrders(p.kind);
            });
            ctx.on('imaging', (p) => {
                if (!p) return;
                if (p.ok) {
                    const found = (p.findings || []).map((f) => f.label + (f.structure ? ` (${f.structure})` : '')).join(', ');
                    ctx.notify(`Scan #${p.orderId} done: ${found || 'no abnormal findings'}`, 'success');
                } else ctx.notify(`Scan #${p.orderId}: ${errText(p)}`, 'error');
                if (S.page === 'imaging') loadOrders('imaging');
            });

            function go(page) {
                S.page = page;
                reloadPage();
            }

            function openPatient(id) {
                S.selected = id; S.results = null;
                S.page = 'admissions';
                render();
            }

            // ── tabs and header ───────────────────────────────────────────────
            function renderTabs() {
                tabs.textContent = '';
                ((S.init && S.init.pages) || []).forEach((page) => {
                    tabs.appendChild(h('button.pf-tab' + (S.page === page ? '.active' : ''), {
                        type: 'button', role: 'tab', 'aria-selected': S.page === page ? 'true' : 'false', 'data-page': page, onclick: () => go(page),
                    }, PAGE_LABEL[page] || page));
                });
            }

            function renderHeader() {
                headerInfo.textContent = '';
                if (!S.init) { title.textContent = S.initError ? 'Unavailable' : 'Loading…'; return; }
                const f = (S.init.facilities || []).find((x) => x.id === S.facility);
                title.textContent = (f && f.label) || S.facility || '';
                if (S.board) {
                    headerInfo.appendChild(h('span.pf-badge', `${S.board.staffOnDuty} staff on duty`));
                    if (S.board.aiActive) headerInfo.appendChild(h('span.pf-badge.warn', { title: 'Few staff on duty: the hospital AI treats patients nobody takes' }, 'AI care active'));
                }
            }

            // ── reception ─────────────────────────────────────────────────────
            function boardGate() {
                if (S.boardError) return errorBox(S.boardError, loadBoard);
                if (!S.board) return loading('Loading the hospital board…');
                return null;
            }

            function quickTriage(a) {
                const sel = select({ 'aria-label': 'Triage colour', 'data-field': 'triage' }, S.init.options.triage.map((t) => [t, t]), a.triage || 'yellow');
                return h('div.pf-row.hosp-inline', sel, h('button.pf-btn.sm', {
                    'data-action': 'triage', onclick: async () => {
                        const res = await call('triage', { facility: S.facility, admissionId: a.id, level: sel.value }, 'Triage recorded.');
                        if (res && res.ok) loadBoard();
                    },
                }, 'Triage'));
            }

            function renderReception() {
                const gate = boardGate();
                if (gate) return gate;
                const list = admissions().filter((a) => RECEPTION[a.state])
                    .sort((x, y) => (TRIAGE_ORDER[x.triage] || 9) - (TRIAGE_ORDER[y.triage] || 9) || (x.arrivedAt || 0) - (y.arrivedAt || 0));
                if (!list.length) return empty('Nobody is waiting at reception.');
                return scroll(h('table.pf-table.hosp-table',
                    h('thead', h('tr', ['Patient', 'Arrived', 'Triage', 'State', 'Reason', ''].map((t) => h('th', t)))),
                    h('tbody', list.map((a) => h('tr', { 'data-admission': String(a.id) },
                        patientCell(a),
                        h('td', when(a.arrivedAt)),
                        h('td', triageBadge(a.triage)),
                        h('td', stateBadge(a.state)),
                        h('td', a.reason || ''),
                        h('td.hosp-actions', quickTriage(a),
                            h('button.pf-btn.sm.primary', { 'data-action': 'open', onclick: () => openPatient(a.id) }, 'Open')))))));
            }

            // ── triage board ──────────────────────────────────────────────────
            function renderTriage() {
                const gate = boardGate();
                if (gate) return gate;
                const list = admissions();
                if (!list.length) return empty('No open admissions.');
                const cols = [...S.init.options.triage, 'none'];
                return h('div.hosp-triage-board', cols.map((t) => {
                    const items = list.filter((a) => (a.triage || 'none') === t).sort((x, y) => (x.arrivedAt || 0) - (y.arrivedAt || 0));
                    return h('div.hosp-triage-col.hosp-col-' + (TRIAGE_ORDER[t] ? t : 'none'), { 'data-triage': t },
                        h('div.hosp-col-head', triageBadge(t === 'none' ? null : t), h('span.pf-muted', String(items.length))),
                        items.length ? items.map((a) => h('button.hosp-patient-card', { type: 'button', 'data-admission': String(a.id), onclick: () => openPatient(a.id) },
                            h('div.pf-strong', a.name || 'Unknown'),
                            h('div.pf-small', STATE_LABEL[a.state] || a.state || ''),
                            h('div.pf-small.pf-muted', a.bedId ? `${deptLabel(a.dept)} · bed ${a.bedId}` : when(a.arrivedAt)),
                            a.custody ? h('span.pf-badge.accent', 'custody') : null))
                            : h('div.pf-small.pf-muted', '—'));
                }));
            }

            // ── beds ──────────────────────────────────────────────────────────
            function renderBeds() {
                const gate = boardGate();
                if (gate) return gate;
                const beds = S.board.beds || [];
                if (!beds.length) return empty('This hospital has no beds.');
                return h('div.pf-grid.hosp-beds', beds.map((d) => {
                    const occupied = admissions().filter((a) => a.dept === d.dept && a.bedId && (a.state === 'in_treatment' || a.state === 'admitted'))
                        .sort((x, y) => String(x.bedId).localeCompare(String(y.bedId)));
                    return h('div.pf-card.hosp-dept', { 'data-dept': d.dept },
                        h('div.pf-row.between', h('div.pf-strong', d.label || d.dept),
                            h('span.pf-badge' + (d.free === 0 ? '.bad' : d.free <= 1 ? '.warn' : '.ok'), `${d.free}/${d.total} free`)),
                        h('div.hosp-bed-meter', { 'aria-hidden': 'true' }, h('div', { style: { width: (d.total ? Math.round(((d.total - d.free) / d.total) * 100) : 0) + '%' } })),
                        occupied.length ? h('div.pf-list', occupied.map((a) => h('button.pf-list-item.hosp-bed', { type: 'button', 'data-admission': String(a.id), onclick: () => openPatient(a.id) },
                            h('span.pf-strong', a.bedId), h('span', a.name || 'Unknown'), triageBadge(a.triage), h('span.pf-small.pf-muted', when(a.admittedAt)))))
                            : h('div.pf-small.pf-muted', 'No bed taken.'));
                }), h('div.pf-small.pf-muted.hosp-note', 'Free beds are assigned by the hospital when you admit; name a bed only to choose one.'));
            }

            // ── admissions and the patient panel ──────────────────────────────
            function admissionsToolbar() {
                const search = h('input.pf-input', { type: 'search', placeholder: 'Filter by name or citizen id', value: S.filter, 'aria-label': 'Filter', 'data-field': 'filter' });
                search.addEventListener('keydown', (e) => { if (e.key === 'Enter') { S.filter = search.value; render(); } });
                const viewSel = select({ 'aria-label': 'Which admissions', 'data-field': 'view' }, [['open', 'Open now'], ['history', 'Recent (incl. closed)']], S.view);
                viewSel.addEventListener('change', () => { S.view = viewSel.value; if (S.view === 'history') loadHistory(); else render(); });
                const sortSel = select({ 'aria-label': 'Sort', 'data-field': 'sort' }, [['triage', 'Triage first'], ['arrived', 'Longest waiting'], ['newest', 'Newest']], S.sort);
                sortSel.addEventListener('change', () => { S.sort = sortSel.value; render(); });
                const items = [viewSel, sortSel, search, h('button.pf-btn.sm', { 'data-action': 'filter', onclick: () => { S.filter = search.value; render(); } }, 'Filter')];
                if (S.view === 'history') {
                    const stSel = select({ 'aria-label': 'State', 'data-field': 'historyState' }, [['', 'Any state'], ...Object.keys(STATE_LABEL).map((s) => [s, STATE_LABEL[s]])], S.historyState);
                    stSel.addEventListener('change', () => { S.historyState = stSel.value; loadHistory(); });
                    items.splice(1, 0, stSel);
                }
                return h('div.pf-toolbar.pf-row.hosp-toolbar', items);
            }

            function sorted(list) {
                const q = S.filter.trim().toLowerCase();
                const out = list.filter((a) => !q || String(a.name || '').toLowerCase().includes(q) || String(a.citizenid || '').toLowerCase().includes(q));
                if (S.sort === 'triage') out.sort((x, y) => (TRIAGE_ORDER[x.triage] || 9) - (TRIAGE_ORDER[y.triage] || 9) || (x.arrivedAt || 0) - (y.arrivedAt || 0));
                else if (S.sort === 'arrived') out.sort((x, y) => (x.arrivedAt || 0) - (y.arrivedAt || 0));
                else out.sort((x, y) => (y.arrivedAt || 0) - (x.arrivedAt || 0));
                return out;
            }

            function admissionsTable(list, clickable) {
                if (!list.length) return empty(S.filter ? 'Nothing matches the filter.' : 'No admissions.');
                return scroll(h('table.pf-table.hosp-table',
                    h('thead', h('tr', ['#', 'Patient', 'Triage', 'State', 'Department', 'Arrived', ''].map((t) => h('th', t)))),
                    h('tbody', list.map((a) => h('tr' + (S.selected === a.id ? '.hosp-selected' : ''), { 'data-admission': String(a.id) },
                        h('td', String(a.id)), patientCell(a), h('td', triageBadge(a.triage)), h('td', stateBadge(a.state)),
                        h('td', a.dept ? deptLabel(a.dept) + (a.bedId ? ` · ${a.bedId}` : '') : ''),
                        h('td', when(a.arrivedAt), a.dischargedAt ? h('div.pf-small.pf-muted', 'closed ' + when(a.dischargedAt)) : null),
                        h('td', clickable && a.open ? h('button.pf-btn.sm', { 'data-action': 'open', onclick: () => openPatient(a.id) }, 'Open') : null))))));
            }

            function resultsView() {
                if (!S.results) return null;
                if (S.results.loading) return loading('Loading results…');
                if (!S.results.ok) return errorBox(S.results);
                const list = S.results.list || [];
                if (!list.length) return empty('No lab or imaging orders for this patient.');
                return h('div.pf-list.hosp-results', list.map((o) => {
                    const r = o.result || {};
                    const values = Object.entries(r.values || {}).map(([k, v]) => `${k}: ${Array.isArray(v) ? (v.length ? v.join(', ') : 'none') : v}`);
                    const findings = (r.findings || []).map((f) => (f.label || '') + (f.structure ? ` (${f.structure})` : '') + (f.value ? ` ${f.value}` : ''));
                    return h('div.pf-list-item', { 'data-order': String(o.id) },
                        h('div', h('div.pf-strong', `#${o.id} ${o.label || o.test || ''}`), h('div.pf-small.pf-muted', `${o.state} · ${when(o.orderedAt)}`)),
                        h('div.hosp-result-text', o.state === 'resulted' ? ([...values, ...findings].join(' · ') || 'Nothing abnormal found') : (o.readyAt ? 'result ' + inSeconds(o.readyAt) : '')));
                }));
            }

            function patientPanel(a) {
                const o = S.init.options;
                const facility = S.facility;
                const base = { facility, admissionId: a.id };
                const after = (res) => { if (res && res.ok) loadBoard(); };

                const triageSel = select({ 'aria-label': 'Triage colour', 'data-field': 'triage' }, o.triage.map((t) => [t, t]), a.triage || 'yellow');
                const deptSel = select({ 'aria-label': 'Department', 'data-field': 'dept' }, ((S.board && S.board.beds) || []).map((d) => [d.dept, `${d.label || d.dept} (${d.free} free)`]), a.dept);
                const bedInput = h('input.pf-input', { maxlength: '32', placeholder: 'Bed (optional)', 'aria-label': 'Bed', 'data-field': 'bed' });
                const levelSel = select({ 'aria-label': 'Care level', 'data-field': 'careLevel' }, o.careLevels.map((l) => [l.id, l.label]), 'standard');
                const others = (S.init.facilities || []).filter((f) => f.id !== facility);
                const toSel = select({ 'aria-label': 'Transfer to', 'data-field': 'transferTo' }, others.map((f) => [f.id, f.label]), others[0] && others[0].id);
                const labSel = select({ 'aria-label': 'Lab test', 'data-field': 'labTest' }, o.lab.map((t) => [t.id, t.label]), o.lab[0].id);
                const imgSel = select({ 'aria-label': 'Imaging', 'data-field': 'imagingTest' }, o.imaging.map((t) => [t.id, t.label]), o.imaging[0].id);
                const drugSel = select({ 'aria-label': 'Drug', 'data-field': 'drug' }, o.formulary.map((d) => [d.id, d.label]), o.formulary[0].id);
                const units = h('input.pf-input.hosp-num', { type: 'number', min: '1', step: '1', value: '1', 'aria-label': 'Units per fill', 'data-field': 'units' });
                const fills = h('input.pf-input.hosp-num', { type: 'number', min: '1', step: '1', value: '1', 'aria-label': 'Fills', 'data-field': 'fills' });
                const rxNote = h('input.pf-input', { maxlength: '255', placeholder: 'Note (optional)', 'aria-label': 'Prescription note', 'data-field': 'rxNote' });

                const btn = (label, action, fn, cls) => h('button.pf-btn.sm' + (cls || ''), { type: 'button', 'data-action': action, onclick: fn }, label);
                return h('div.pf-card.hosp-panel', { 'data-panel': String(a.id), role: 'region', 'aria-label': 'Patient' },
                    h('div.pf-row.between',
                        h('div', h('div.pf-strong.hosp-panel-name', a.name || 'Unknown'),
                            h('div.pf-small.pf-muted', `${a.citizenid || ''} · admission #${a.id} · arrived ${when(a.arrivedAt)}`)),
                        h('div.pf-row', triageBadge(a.triage), stateBadge(a.state),
                            a.custody ? h('span.pf-badge.accent', 'custody') : null,
                            btn('Close', 'closePanel', () => { S.selected = null; S.results = null; render(); }, '.ghost'))),
                    a.custody ? h('div.pf-small.hosp-note', 'Custody patient: leaving is reported to the custody officers; a transfer out needs an escort.') : null,
                    h('div.pf-grid.hosp-panel-grid',
                        h('div.hosp-box', h('div.hosp-box-title', 'Triage'), h('div.pf-row', triageSel,
                            btn('Set', 'triage', async () => after(await call('triage', { ...base, level: triageSel.value }, 'Triage recorded.'))))),
                        h('div.hosp-box', h('div.hosp-box-title', 'Admit / move'), h('div.pf-row.hosp-wrap', deptSel, bedInput,
                            btn('Admit', 'admit', async () => after(await call('admit', { ...base, dept: deptSel.value, bedId: bedInput.value.trim() || undefined },
                                (r) => `Admitted to ${deptLabel(r.dept)}, bed ${r.bedId}.`)), '.primary'))),
                        a.bedId ? h('div.hosp-box', h('div.hosp-box-title', 'Care level'), h('div.pf-row', levelSel,
                            btn('Set', 'careLevel', async () => after(await call('careLevel', { ...base, level: levelSel.value }, 'Care level set.'))))) : null,
                        others.length ? h('div.hosp-box', h('div.hosp-box-title', 'Transfer'), h('div.pf-row', toSel,
                            btn('Transfer', 'transfer', async () => after(await call('transfer', { ...base, to: toSel.value }, 'Transfer recorded.'))))) : null,
                        h('div.hosp-box', h('div.hosp-box-title', 'Lab'), h('div.pf-row', labSel,
                            btn('Order', 'labOrder', async () => call('labOrder', { ...base, test: labSel.value }, (r) => (r.duplicate ? `Already ordered (#${r.orderId}).` : `Lab order #${r.orderId}.`))))),
                        h('div.hosp-box', h('div.hosp-box-title', 'Imaging'), h('div.pf-row', imgSel,
                            btn('Order', 'imagingOrder', async () => call('imagingOrder', { ...base, test: imgSel.value }, (r) => (r.duplicate ? `Already ordered (#${r.orderId}).` : `Imaging order #${r.orderId}.`))))),
                        h('div.hosp-box', h('div.hosp-box-title', 'Prescribe'), h('div.pf-row.hosp-wrap', drugSel, units, fills, rxNote,
                            btn('Prescribe', 'prescribe', async () => call('prescribe', { ...base, drug: drugSel.value, units: Number(units.value), fills: Number(fills.value), note: rxNote.value },
                                (r) => (r.duplicate ? 'Already prescribed on this admission.' : `Prescription #${r.prescriptionId} written.`))))),
                        h('div.hosp-box', h('div.hosp-box-title', 'Results and discharge'), h('div.pf-row.hosp-wrap',
                            btn('Show results', 'results', async () => {
                                S.results = { loading: true }; render();
                                const res = await ctx.rpc('results', base);
                                S.results = res || { ok: false }; render();
                            }),
                            btn('Discharge orders…', 'toDischarge', () => { S.dischargeFor = a.id; go('discharge'); }, '.primary')))),
                    resultsView());
            }

            function renderAdmissions() {
                const parts = [admissionsToolbar()];
                if (S.view === 'history') {
                    if (S.historyError) parts.push(errorBox(S.historyError, loadHistory));
                    else if (!S.history) parts.push(loading());
                    else parts.push(admissionsTable(sorted(S.history), true));
                } else {
                    const gate = boardGate();
                    if (gate) parts.push(gate); else parts.push(admissionsTable(sorted(admissions()), true));
                }
                const sel = S.selected != null ? byId(S.selected) : null;
                if (sel) parts.unshift(patientPanel(sel));
                return h('div.pf-stack', parts);
            }

            // ── discharge orders ──────────────────────────────────────────────
            function renderDischarge() {
                const gate = boardGate();
                if (gate) return gate;
                const o = S.init.options;
                const list = admissions().filter((a) => a.open);
                if (!list.length) return empty('No open admissions to discharge.');
                const current = list.find((a) => a.id === S.dischargeFor) ? S.dischargeFor : list[0].id;
                const who = select({ 'aria-label': 'Patient', 'data-field': 'dischargeAdmission' }, list.map((a) => [a.id, `#${a.id} ${a.name || 'Unknown'} (${STATE_LABEL[a.state] || a.state})`]), current);
                who.addEventListener('change', () => { S.dischargeFor = Number(who.value); });
                const restrictions = o.restrictions.map((r) => {
                    const box = h('input', { type: 'checkbox', 'data-restriction': r.id, id: undefined });
                    const hours = h('input.pf-input.hosp-num', { type: 'number', min: '1', max: String(o.maxRestrictionHours), step: '1', value: '24', 'aria-label': `${r.label} hours`, 'data-hours': r.id });
                    return { r, box, hours, el: h('label.pf-row.hosp-check', box, h('span', r.label), hours, h('span.pf-small.pf-muted', 'h')) };
                });
                const follow = h('input.pf-input.hosp-num', { type: 'number', min: '1', max: String(o.maxFollowUpDays * 24), step: '1', placeholder: 'hours', 'aria-label': 'Follow-up in hours', 'data-field': 'followUp' });
                const note = h('textarea.pf-textarea', { rows: '3', maxlength: '255', placeholder: 'Note for the patient (shown in the follow-up)', 'aria-label': 'Note', 'data-field': 'note' });
                const rxRows = h('div.pf-stack.hosp-rx-rows');
                const addRx = () => {
                    if (rxRows.children.length >= 8) return;
                    const drug = select({ 'aria-label': 'Drug', 'data-rx': 'drug' }, o.formulary.map((d) => [d.id, d.label]), o.formulary[0].id);
                    const units = h('input.pf-input.hosp-num', { type: 'number', min: '1', step: '1', value: '1', 'aria-label': 'Units per fill', 'data-rx': 'units' });
                    const fills = h('input.pf-input.hosp-num', { type: 'number', min: '1', step: '1', value: '1', 'aria-label': 'Fills', 'data-rx': 'fills' });
                    const row = h('div.pf-row.hosp-wrap.hosp-rx', drug, units, fills);
                    row.appendChild(h('button.pf-btn.sm.ghost', { type: 'button', 'data-action': 'removeRx', onclick: () => row.remove() }, 'Remove'));
                    rxRows.appendChild(row);
                };
                const submit = h('button.pf-btn.primary', {
                    type: 'button', 'data-action': 'discharge', onclick: async () => {
                        const id = Number(who.value);
                        const orders = {
                            restrictions: restrictions.filter((x) => x.box.checked).map((x) => ({ kind: x.r.id, hours: Number(x.hours.value) })),
                            note: note.value.trim() || undefined,
                            prescriptions: [...rxRows.querySelectorAll('.hosp-rx')].map((row) => ({
                                drug: row.querySelector('[data-rx="drug"]').value,
                                units: Number(row.querySelector('[data-rx="units"]').value),
                                fills: Number(row.querySelector('[data-rx="fills"]').value),
                            })),
                        };
                        if (follow.value !== '') orders.followUpHours = Number(follow.value);
                        const res = await call('discharge', { facility: S.facility, admissionId: id, orders }, (r) => (r.duplicate ? 'Already discharged.' : `Admission #${id} discharged.`));
                        if (res && res.ok) { S.dischargeFor = null; if (S.selected === id) S.selected = null; loadBoard(); }
                    },
                }, 'Discharge');
                return h('div.pf-card.hosp-form', { 'data-form': 'discharge' },
                    h('div.pf-field', h('label', 'Patient'), who),
                    h('div.pf-field', h('label', 'Restrictions'), h('div.hosp-checks', restrictions.map((x) => x.el))),
                    h('div.pf-row.hosp-wrap',
                        h('div.pf-field', h('label', 'Follow-up visit in (hours, optional)'), follow),
                        h('div.pf-field.hosp-grow', h('label', 'Note'), note)),
                    h('div.pf-field', h('label', 'Take-home prescriptions (a physician)'), rxRows,
                        h('button.pf-btn.sm.ghost', { type: 'button', 'data-action': 'addRx', onclick: addRx }, 'Add prescription')),
                    h('div.pf-small.pf-muted', 'The bill is made by the hospital from its own records when the admission closes.'),
                    h('div.pf-row', submit));
            }

            // ── lab and imaging queues ────────────────────────────────────────
            function ordersPage(kind) {
                const o = S.init.options;
                const openList = admissions().filter((a) => a.open);
                const toolbar = h('div.pf-toolbar.pf-row.hosp-toolbar',
                    select({ 'aria-label': 'Which orders', 'data-field': 'ordersOpen', onchange: (e) => { S.ordersOpen[kind] = e.target.value === 'open'; loadOrders(kind); } },
                        [['open', 'Open orders'], ['all', 'Recent (incl. resulted)']], S.ordersOpen[kind] ? 'open' : 'all'));
                const parts = [toolbar];
                if (openList.length) {
                    const who = select({ 'aria-label': 'Patient', 'data-field': 'orderAdmission' }, openList.map((a) => [a.id, `#${a.id} ${a.name || 'Unknown'}`]), openList[0].id);
                    const tests = kind === 'lab' ? o.lab : o.imaging;
                    const test = select({ 'aria-label': 'Test', 'data-field': 'orderTest' }, tests.map((t) => [t.id, t.label]), tests[0].id);
                    parts.push(h('div.pf-card.pf-row.hosp-wrap.hosp-form', { 'data-form': kind + 'Order' }, h('span.pf-strong', 'New order'), who, test,
                        h('button.pf-btn.sm.primary', {
                            type: 'button', 'data-action': kind + 'Order', onclick: async () => {
                                const res = await call(kind + 'Order', { facility: S.facility, admissionId: Number(who.value), test: test.value },
                                    (r) => (r.duplicate ? `Already ordered (#${r.orderId}).` : `Order #${r.orderId} placed.`));
                                if (res && res.ok) loadOrders(kind);
                            },
                        }, 'Order')));
                }
                if (S.ordersError[kind]) parts.push(errorBox(S.ordersError[kind], () => loadOrders(kind)));
                else if (!S.orders[kind]) parts.push(loading());
                else if (!S.orders[kind].length) parts.push(empty(S.ordersOpen[kind] ? 'The queue is empty.' : 'No orders yet.'));
                else {
                    parts.push(scroll(h('table.pf-table.hosp-table',
                        h('thead', h('tr', ['#', 'Patient', 'Test', 'State', 'Ordered', 'Result', ''].map((t) => h('th', t)))),
                        h('tbody', S.orders[kind].map((r) => {
                            const actions = [];
                            if (r.state === 'ordered') {
                                actions.push(kind === 'lab'
                                    ? h('button.pf-btn.sm.primary', { type: 'button', 'data-action': 'labDraw', onclick: async () => { const res = await call('labDraw', { orderId: r.id }, (x) => `Sample sent; result ${inSeconds(x.readyAt)}.`); if (res && res.ok) loadOrders(kind); } }, 'Draw sample')
                                    : h('button.pf-btn.sm.primary', { type: 'button', 'data-action': 'imagingPerform', onclick: async () => { const res = await call('imagingPerform', { orderId: r.id }, 'Scan started: stay with the patient.'); if (res && res.ok) loadOrders(kind); } }, 'Run scan'));
                            }
                            if (r.state === 'ordered' || r.state === 'in_progress') {
                                actions.push(h('button.pf-btn.sm.danger', { type: 'button', 'data-action': 'orderCancel', onclick: async () => { const res = await call('orderCancel', { orderId: r.id }, 'Order cancelled.'); if (res && res.ok) loadOrders(kind); } }, 'Cancel'));
                            }
                            const adm = r.admissionId && byId(r.admissionId);
                            if (r.hasResult && adm) actions.push(h('button.pf-btn.sm', { type: 'button', 'data-action': 'openResults', onclick: () => openPatient(adm.id) }, 'Patient'));
                            return h('tr', { 'data-order': String(r.id) },
                                h('td', String(r.id)), patientCell({ ...r, open: true }), h('td', r.label || r.test || ''),
                                h('td', h('span.pf-badge' + (r.state === 'resulted' ? '.ok' : r.state === 'cancelled' ? '' : '.warn'), r.state || '')),
                                h('td', when(r.orderedAt)),
                                h('td', r.state === 'in_progress' && r.readyAt ? inSeconds(r.readyAt) : r.state === 'resulted' ? 'ready (open the patient)' : ''),
                                h('td.hosp-actions', actions));
                        })))));
                }
                return h('div.pf-stack', parts);
            }

            // ── pharmacy ──────────────────────────────────────────────────────
            function pager(state, load) {
                const d = state.data;
                if (!d) return null;
                return h('div.pf-row.hosp-pager',
                    h('button.pf-btn.sm.ghost', { type: 'button', 'data-action': 'prevPage', disabled: d.page <= 1, onclick: () => { state.page = Math.max(1, d.page - 1); load(); } }, 'Previous'),
                    h('span.pf-small.pf-muted', `Page ${d.page}`),
                    h('button.pf-btn.sm.ghost', { type: 'button', 'data-action': 'nextPage', disabled: !d.more, onclick: () => { state.page = d.page + 1; load(); } }, 'Next'));
            }

            function searchBar(state, load, placeholder, extra) {
                const input = h('input.pf-input', { type: 'search', value: state.q, placeholder, 'aria-label': 'Search', 'data-field': 'q', maxlength: '48' });
                const run = () => { state.q = input.value.trim(); state.page = 1; load(); };
                input.addEventListener('keydown', (e) => { if (e.key === 'Enter') run(); });
                return h('div.pf-toolbar.pf-row.hosp-toolbar', extra || null, input, h('button.pf-btn.sm', { type: 'button', 'data-action': 'search', onclick: run }, 'Search'));
            }

            function renderPharmacy() {
                const P = S.pharmacy;
                const parts = [searchBar(P, loadPharmacy, 'Name or citizen id',
                    h('button.pf-btn.sm.ghost', { type: 'button', 'data-action': 'controlledLog', onclick: async () => {
                        S.log = { loading: true }; render();
                        const res = await ctx.rpc('controlledLog');
                        S.log = res || { ok: false }; render();
                    } }, 'Controlled-substance log'))];
                if (S.log) {
                    if (S.log.loading) parts.push(loading('Loading the log…'));
                    else if (!S.log.ok) parts.push(errorBox(S.log));
                    else parts.push(h('div.pf-card', h('div.pf-row.between', h('div.pf-strong', 'Controlled-substance log (the hospital you are in)'),
                        h('button.pf-btn.sm.ghost', { type: 'button', 'data-action': 'closeLog', onclick: () => { S.log = null; render(); } }, 'Hide')),
                    (S.log.list || []).length ? scroll(h('table.pf-table.hosp-table', h('thead', h('tr', ['When', 'Kind', 'Drug', 'Qty', 'Patient', 'By'].map((t) => h('th', t)))),
                        h('tbody', S.log.list.map((r) => h('tr', h('td', when(r.at)), h('td', r.kind || ''), h('td', r.drug || ''), h('td', String(r.qty == null ? '' : r.qty)),
                            h('td', r.patient || ''), h('td', r.by || '')))))) : empty('No controlled-drug moves logged.')));
                }
                if (P.error) parts.push(errorBox(P.error, loadPharmacy));
                else if (!P.data) parts.push(loading());
                else if (!(P.data.list || []).length) parts.push(empty(P.q ? 'No prescription matches.' : 'No prescriptions waiting at the counter.'));
                else {
                    parts.push(scroll(h('table.pf-table.hosp-table',
                        h('thead', h('tr', ['#', 'Patient', 'Drug', 'Fills', 'Next fill', 'Expires', ''].map((t) => h('th', t)))),
                        h('tbody', P.data.list.map((r) => h('tr', { 'data-rx': String(r.id) },
                            h('td', String(r.id)),
                            h('td', h('div.pf-strong', r.name || 'Unknown'), h('div.pf-small.pf-muted', r.citizenid || '')),
                            h('td', r.label || r.drug || '', h('div.pf-small.pf-muted', `${r.units} per fill`), r.controlled ? h('span.pf-badge.bad', 'controlled') : null),
                            h('td', `${r.filled}/${r.fills}`),
                            h('td', r.nextAt && r.nextAt * 1000 > Date.now() ? inSeconds(r.nextAt) : 'ready'),
                            h('td', r.expiresAt ? new Date(r.expiresAt * 1000).toLocaleDateString() : ''),
                            h('td', h('button.pf-btn.sm.danger', { type: 'button', 'data-action': 'rxCancel', onclick: async () => {
                                const res = await call('rxCancel', { rxId: r.id }, 'Prescription cancelled.');
                                if (res && res.ok) loadPharmacy();
                            } }, 'Cancel'))))))));
                    parts.push(pager(P, loadPharmacy));
                }
                parts.push(h('div.pf-small.pf-muted.hosp-note', 'Patients collect at the pharmacy counter; write a prescription from the patient panel (Admissions) or with the discharge orders.'));
                return h('div.pf-stack', parts);
            }

            // ── bills ─────────────────────────────────────────────────────────
            function renderBills() {
                const B = S.bills;
                const stateSel = select({ 'aria-label': 'Bill state', 'data-field': 'billState' }, [['', 'Any state'], ...BILL_STATES.map((s) => [s, s.replace(/_/g, ' ')])], B.state);
                stateSel.addEventListener('change', () => { B.state = stateSel.value; B.page = 1; loadBills(); });
                const parts = [searchBar(B, loadBills, 'Name or citizen id', stateSel)];
                if (B.error) parts.push(errorBox(B.error, loadBills));
                else if (!B.data) parts.push(loading());
                else if (!(B.data.list || []).length) parts.push(empty('No bills match.'));
                else {
                    const badge = (s) => h('span.pf-badge' + (s === 'paid' ? '.ok' : s === 'waived' ? '' : s === 'invoiced' ? '.accent' : '.warn'), String(s || '').replace(/_/g, ' '));
                    const rows = [];
                    B.data.list.forEach((b) => {
                        rows.push(h('tr', { 'data-bill': String(b.id) },
                            h('td', String(b.id)),
                            h('td', h('div.pf-strong', b.name || 'Unknown'), h('div.pf-small.pf-muted', b.citizenid || '')),
                            h('td', b.admissionId ? '#' + b.admissionId : ''),
                            h('td', money(b.total), b.discount ? h('div.pf-small.pf-muted', '−' + money(b.discount) + ' coverage') : null),
                            h('td.pf-strong', money(b.due)),
                            h('td', badge(b.state)),
                            h('td', when(b.createdAt)),
                            h('td', h('button.pf-btn.sm', { type: 'button', 'data-action': 'billLines', 'aria-expanded': B.open === b.id ? 'true' : 'false', onclick: async () => {
                                if (B.open === b.id) { B.open = null; B.lines = null; render(); return; }
                                B.open = b.id; B.lines = { loading: true }; render();
                                const res = await ctx.rpc('billLines', { billId: b.id });
                                B.lines = res || { ok: false }; render();
                            } }, B.open === b.id ? 'Hide' : 'Lines'))));
                        if (B.open === b.id) {
                            let inner;
                            if (!B.lines || B.lines.loading) inner = loading();
                            else if (!B.lines.ok) inner = errorBox(B.lines);
                            else if (!(B.lines.lines || []).length) inner = empty('This bill has no lines.');
                            else inner = h('table.pf-table.hosp-lines', h('tbody', B.lines.lines.map((l) => h('tr',
                                h('td', l.label || ''), h('td.pf-muted', l.kind || ''), h('td', `${l.qty} × ${money(l.unitPrice)}`), h('td', money(l.amount))))));
                            rows.push(h('tr.hosp-lines-row', h('td', { colspan: '8' }, inner)));
                        }
                    });
                    parts.push(scroll(h('table.pf-table.hosp-table',
                        h('thead', h('tr', ['#', 'Patient', 'Admission', 'Total', 'Due', 'State', 'Created', ''].map((t) => h('th', t)))),
                        h('tbody', rows))));
                    parts.push(pager(B, loadBills));
                }
                return h('div.pf-stack', parts);
            }

            // ── render ────────────────────────────────────────────────────────
            function render() {
                renderTabs();
                renderHeader();
                body.textContent = '';
                if (S.initError) { body.appendChild(errorBox(S.initError, loadInit)); return; }
                if (!S.init) { body.appendChild(loading()); return; }
                if (!S.page) { body.appendChild(empty('Nothing to show.')); return; }
                const pages = {
                    reception: renderReception, triage: renderTriage, beds: renderBeds, admissions: renderAdmissions, discharge: renderDischarge,
                    lab: () => ordersPage('lab'), imaging: () => ordersPage('imaging'), pharmacy: renderPharmacy, bills: renderBills,
                };
                const fn = pages[S.page];
                body.appendChild(fn ? fn() : empty('Nothing to show.'));
            }

            render();
            loadInit();
        },
        unmount(ctx) {
            const fn = cleanups.get(ctx);
            if (fn) fn();
            cleanups.delete(ctx);
        },
    });
})();
