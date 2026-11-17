// Department app (pf-devices module, tablet and computer; batch 21 unit 21G). The screens behind
// server/apps/department.lua (20E): overview, roster and one employee (qualifications), shifts,
// training records, the asset register (issue, return and manager actions under the armory rules),
// purchasing (facility catalog and orders), the budget and payroll reports.
//
// The server decides everything. The sections a viewer gets come from overview.can (managers,
// budget readers); every action is checked again by its handler and its error message is shown as
// it comes back. Writes carry a request key: the same intent resent after an unclear answer (no
// reply, a server error, the bank still processing) reuses its key, so the server applies it once;
// after a clear answer the next attempt gets a new key. Server strings reach the DOM only as text
// (ctx.h makes text nodes); nothing here sets innerHTML from data.
(function () {
    'use strict';

    // Config.Departments.Assets.ArmoryRef (its default). Only used to hide buttons the server would
    // refuse anyway: armory equipment is booked in at the armory, a manager may only report it lost.
    const ARMORY_REF = 'armory';

    const ERRORS = {
        no_permission: 'You are not allowed to do that.',
        not_on_duty: 'You must be on duty.',
        bad_args: 'Check the form and try again.',
        not_found: 'Not found.',
        invalid_state: 'That is not possible in its current state.',
        key_reused: 'That request key was already used for something else. Try again.',
        busy: 'Still working on your last request.',
        db_unavailable: 'Department records are unavailable right now.',
        unavailable: 'That service is not available right now.',
        offline: 'You are not online.',
        conflict: 'Lost armory equipment of this person is unresolved.',
        payment_pending: 'The bank has not confirmed the payment yet. Nothing more will be charged; check back shortly.',
        insufficient_funds: 'The department account cannot cover this order.',
        payment_failed: 'The payment failed. Nothing was ordered.',
        not_allowed: 'Not allowed.',
        rate_limited: 'Too many requests. Wait a moment.',
        request_failed: 'No answer from the server. It may still have gone through: check before trying again.',
        server_error: 'The server hit an error. It may still have gone through: check before trying again.',
        not_authorized: 'You no longer have access to this app.',
        payload_too_large: 'That is too much at once.',
        unknown_method: 'This server does not offer that yet.',
    };
    // answers after which the server may or may not have applied the write: resending reuses the key
    const UNCLEAR = { request_failed: true, server_error: true, rate_limited: true, busy: true, payment_pending: true,
        db_unavailable: true, unavailable: true };

    const ASSET_STATES = [['in_stock', 'In stock'], ['issued', 'Issued'], ['maintenance', 'Maintenance'], ['lost', 'Lost'], ['retired', 'Retired']];
    const ASSET_TONE = { in_stock: 'ok', issued: 'active', maintenance: 'pending', lost: 'bad', retired: 'off' };
    const PROC_STATE = {
        created: ['Placing', 'pending'], paid: ['Ordered', 'active'], delivered: ['Delivered', 'ok'], cancelled: ['Cancelled', 'off'],
        failed: ['Failed', 'bad'], payment_pending: ['Bank processing', 'pending'], charge_held: ['Charge held', 'warn'],
    };
    const TRAINING_RESULT = { pass: ['Passed', 'ok'], fail: ['Failed', 'bad'], in_progress: ['In progress', 'active'] };
    const ASSET_EVENTS = { register: 'Registered', issue: 'Issued', return: 'Returned', repair: 'Repaired', lost: 'Lost',
        found: 'Found', retire: 'Retired', maintenance: 'To maintenance' };

    const CSS = `
.dept-app .dept-layout { display: flex; flex: 1; min-height: 0; }
.dept-app .dept-nav { width: 180px; flex: none; }
.dept-app button.pf-nav-item { appearance: none; border: 0; background: transparent; width: 100%; text-align: left; font: inherit; color: var(--pf-fg-2); }
.dept-app .dept-view { flex: 1; overflow: auto; min-width: 0; }
.dept-app.dept-narrow .dept-layout { flex-direction: column; }
.dept-app.dept-narrow .dept-nav { width: auto; display: flex; gap: 4px; overflow-x: auto; border-right: 0; border-bottom: 1px solid var(--pf-line); }
.dept-app.dept-narrow .dept-nav .pf-nav-item { width: auto; white-space: nowrap; margin-top: 0; }
.dept-app :focus-visible { outline: 2px solid var(--pf-accent, #60a5fa); outline-offset: 2px; }
.dept-app .dept-scroll { overflow-x: auto; }
.dept-app .dept-form { display: grid; gap: 10px; grid-template-columns: repeat(auto-fill, minmax(170px, 1fr)); align-items: end; }
.dept-app .dept-msg { min-height: 16px; font-size: 12px; margin-top: 6px; color: var(--pf-fg-2); }
.dept-app .dept-msg[data-tone="bad"] { color: var(--pf-status-bad, #f87171); }
.dept-app .dept-msg[data-tone="ok"] { color: var(--pf-status-ok, #4ade80); }
.dept-app .dept-tone[data-tone="ok"] { color: var(--pf-status-ok, #4ade80); background: var(--pf-status-ok-bg, rgba(74, 222, 128, 0.12)); }
.dept-app .dept-tone[data-tone="active"] { color: var(--pf-status-active, #60a5fa); background: var(--pf-status-active-bg, rgba(96, 165, 250, 0.15)); }
.dept-app .dept-tone[data-tone="pending"] { color: var(--pf-status-pending, #fbbf24); background: var(--pf-status-pending-bg, rgba(251, 191, 36, 0.15)); }
.dept-app .dept-tone[data-tone="warn"] { color: var(--pf-status-warn, #fb923c); background: var(--pf-status-warn-bg, rgba(251, 146, 60, 0.15)); }
.dept-app .dept-tone[data-tone="bad"] { color: var(--pf-status-bad, #f87171); background: var(--pf-status-bad-bg, rgba(248, 113, 113, 0.12)); }
.dept-app .dept-tone[data-tone="off"] { color: var(--pf-status-off, rgba(255, 255, 255, 0.5)); background: var(--pf-status-off-bg, rgba(255, 255, 255, 0.04)); }
.dept-app .dept-tone[data-tone="info"] { color: var(--pf-status-info, #60a5fa); background: var(--pf-status-info-bg, rgba(96, 165, 250, 0.07)); }
.dept-app .dept-badges { display: flex; flex-wrap: wrap; gap: 6px; }
.dept-app .dept-qty { width: 90px; }
`;

    function nonce() {
        let r = '';
        try {
            const a = new Uint32Array(3);
            window.crypto.getRandomValues(a);
            r = Array.from(a, (n) => n.toString(36)).join('');
        } catch (_) {
            r = Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
        }
        return ('dep' + Date.now().toString(36) + r).replace(/[^a-z0-9]/g, '').slice(0, 48);
    }

    const pad2 = (n) => String(n).padStart(2, '0');
    function fmtTime(sec) {
        const n = Number(sec);
        if (!n) return '—';
        const d = new Date(n * 1000);
        return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
    }
    function fmtDate(sec) { return fmtTime(sec).slice(0, 10); }
    function fmtDur(sec) {
        const s = Math.max(0, Math.floor(Number(sec) || 0));
        const hh = Math.floor(s / 3600);
        const mm = Math.floor((s % 3600) / 60);
        return hh ? `${hh}h ${mm}m` : `${mm}m`;
    }
    // a <input type=date> value -> local midnight of that day (seconds); `plusDays` moves it
    function dateToSec(v, plusDays) {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(v || ''));
        if (!m) return null;
        return Math.floor(new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]) + (plusDays || 0)).getTime() / 1000);
    }
    function secToDateInput(sec) { return fmtDate(sec); }
    const text = (v, max) => String(v == null ? '' : v).slice(0, max || 500);
    const str = (v) => (typeof v === 'string' ? v.trim() : '');
    // a Lua list arrives as an array; an empty or missing one as anything else
    const arr = (v) => (Array.isArray(v) ? v : []);

    PFApps.register('department', {
        mount(container, ctx) {
            const { h, money } = ctx;
            const S = {
                ov: null, section: 'overview', back: null, token: 0,
                roster: null, names: {}, keys: {}, catalog: null,
            };

            // ── shell ──────────────────────────────────────────────────────
            const style = h('style');
            style.textContent = CSS;
            const sub = h('div.pf-app-sub', 'Loading…');
            const nav = h('nav.pf-app-nav.dept-nav', { 'aria-label': 'Department sections' });
            const view = h('div.pf-app-body.dept-view', { 'aria-live': 'polite' });
            const refreshBtn = h('button.pf-btn.sm', { type: 'button', onclick: () => boot() }, 'Refresh');
            const root = h('div.pf-app.gov-app.dept-app',
                style,
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '🏛️'), h('div', 'Department', sub)), refreshBtn),
                h('div.dept-layout', nav, view));
            container.appendChild(root);

            // the tablet window is 760 wide, computer windows resize: the layout follows the window,
            // not the screen (no container queries in Chromium 103)
            let observer = null;
            function fit() { root.classList.toggle('dept-narrow', (root.clientWidth || 1000) < 700); }
            if (typeof window.ResizeObserver === 'function') { observer = new window.ResizeObserver(fit); observer.observe(root); }
            fit();

            root.addEventListener('keydown', (e) => {
                if (e.key === 'Escape' && S.back) { e.stopPropagation(); const b = S.back; S.back = null; b(); }
            });

            // ── server calls ───────────────────────────────────────────────
            async function call(method, payload) {
                try {
                    const res = await ctx.rpc(method, payload || {});
                    return res && typeof res === 'object' ? res : { ok: false, error: 'request_failed' };
                } catch (_) {
                    return { ok: false, error: 'request_failed' };
                }
            }
            function errText(res) {
                if (res && typeof res.message === 'string' && res.message.trim()) return text(res.message, 300);
                const code = res && res.error;
                return ERRORS[code] || (code ? text(code, 60).replace(/_/g, ' ') : 'That did not work.');
            }
            function keyFor(scope, payload) {
                const sig = JSON.stringify(payload);
                const cur = S.keys[scope];
                if (cur && cur.sig === sig) return cur.key;
                const key = nonce();
                S.keys[scope] = { sig, key };
                return key;
            }
            function settleKey(scope, res) {
                if (res && (res.ok || !UNCLEAR[res.error])) delete S.keys[scope];
            }
            function setMsg(el, msg, tone) {
                if (!el) return;
                el.textContent = msg || '';
                if (tone) el.dataset.tone = tone; else delete el.dataset.tone;
            }
            // one write: keyed when `scope` is given; the button is disabled while it runs
            async function run(btn, scope, method, payload, msgEl) {
                if (btn && btn.disabled) return null;
                if (scope) payload.key = keyFor(scope, Object.assign({ m: method }, payload));
                if (btn) btn.disabled = true;
                setMsg(msgEl, 'Working…');
                const res = await call(method, payload);
                if (btn) btn.disabled = false;
                if (scope) settleKey(scope, res);
                if (res.ok) setMsg(msgEl, '');
                else { const t = errText(res); setMsg(msgEl, t, 'bad'); ctx.notify(t, 'error'); }
                return res;
            }

            // ── small builders ─────────────────────────────────────────────
            const badge = (label, tone) => h('span.pf-badge.dept-tone', { dataset: { tone: tone || 'off' } }, text(label, 80));
            const stat = (label, value) => h('div.pf-card.pf-stat', h('div.pf-stat-label', label), h('div.pf-stat-value', value == null ? '—' : String(value)));
            const section = (title) => h('div.gov-section', title);
            const msgLine = () => h('div.dept-msg', { role: 'status' });
            const btn = (label, onclick, cls) => h('button.pf-btn.sm' + (cls || ''), { type: 'button', onclick }, label);
            function field(label, control) { return h('div.pf-field', h('label', label), control); }
            function table(cols, rows, emptyText) {
                if (!rows.length) return h('div.pf-empty', emptyText);
                return h('div.dept-scroll', h('table.pf-table', h('thead', h('tr', cols.map((c) => h('th', c)))), h('tbody', rows)));
            }
            function loading(el) { el.innerHTML = ''; el.appendChild(h('div.pfapp-loading', 'Loading…')); }
            function failed(el, res, retry) {
                el.innerHTML = '';
                el.appendChild(h('div.pf-card', h('div.pfapp-error', { role: 'alert' }, errText(res)),
                    retry ? h('div.pf-row', btn('Try again', retry)) : null));
            }
            const who = (cid) => (cid ? (S.names[cid] ? `${S.names[cid]} (${cid})` : String(cid)) : '—');
            function kindLabel(kind) {
                const k = arr(S.ov && S.ov.assetKinds).find((x) => x.id === kind);
                return k ? k.label : kind || '—';
            }
            function select(options, value) {
                return h('select.pf-select', options.map(([v, l]) => h('option', { value: v, selected: v === value }, l)));
            }
            function cidInput(placeholder) {
                const input = h('input.pf-input', { type: 'text', maxlength: '64', placeholder: placeholder || 'Citizen ID', autocomplete: 'off' });
                if (S.roster && S.roster.length) {
                    // a scoped datalist: its id is unique to this window, nothing global can clash
                    const id = 'dept-dl-' + nonce();
                    input.setAttribute('list', id);
                    const dl = h('datalist', { id }, S.roster.map((r) => h('option', { value: r.cid }, text(r.name || r.cid, 80))));
                    return h('div', input, dl);
                }
                return h('div', input);
            }
            const cidOf = (wrap) => str(wrap.querySelector('input').value);
            const isManager = () => !!(S.ov && S.ov.can && S.ov.can.manage);
            const meCid = () => (S.ov && S.ov.me && S.ov.me.cid) || null;

            async function ensureRoster() {
                if (!isManager() || S.roster) return;
                const res = await call('roster');
                if (res.ok && Array.isArray(res.list)) {
                    S.roster = res.list;
                    res.list.forEach((r) => { if (r.cid && r.name) S.names[r.cid] = r.name; });
                }
            }

            // ── navigation (from the server's answer) ──────────────────────
            function sections() {
                const can = (S.ov && S.ov.can) || {};
                const list = [['overview', 'Overview']];
                if (can.manage) list.push(['roster', 'Roster']);
                list.push(['shifts', 'Shifts'], ['training', 'Training'], ['assets', 'Equipment']);
                if (can.manage) list.push(['purchasing', 'Purchasing']);
                if (can.budget) list.push(['budget', 'Budget']);
                if (can.payroll) list.push(['payroll', 'Payroll']);
                return list;
            }
            function renderNav() {
                nav.innerHTML = '';
                const list = sections();
                if (!list.some(([id]) => id === S.section)) S.section = 'overview';
                list.forEach(([id, label], i) => {
                    const b = h('button.pf-nav-item' + (id === S.section ? '.active' : ''), {
                        type: 'button', dataset: { section: id }, 'aria-current': id === S.section ? 'page' : null,
                        onclick: () => go(id),
                        onkeydown: (e) => {
                            const step = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
                            if (!step) return;
                            e.preventDefault();
                            const items = nav.querySelectorAll('button');
                            const next = items[(i + step + items.length) % items.length];
                            if (next) next.focus();
                        },
                    }, label);
                    nav.appendChild(b);
                });
            }
            function go(id, arg) {
                S.section = id;
                S.back = null;
                renderNav();
                const token = ++S.token;
                const fresh = () => token === S.token;
                const fn = SECTIONS[id] || SECTIONS.overview;
                Promise.resolve(fn(fresh, arg)).catch((e) => {
                    console.error('[department] section failed', id, e);
                    if (fresh()) failed(view, { error: 'server_error', message: 'This page failed to load.' }, () => go(id));
                });
            }
            // a detail page inside a section: Back (or Escape) returns to the list
            function detail(backTo) {
                const token = ++S.token;
                S.back = backTo;
                view.innerHTML = '';
                const back = btn('← Back', () => { S.back = null; backTo(); }, '.ghost');
                return { token, fresh: () => token === S.token, back };
            }

            // ── overview ───────────────────────────────────────────────────
            function qualStatus(q) {
                if (q.has) return badge(q.source === 'implied' ? 'Held (rank)' : 'Held', 'ok');
                if (q.reason === 'revoked') return badge('Revoked', 'bad');
                if (q.reason === 'expired') return badge('Expired', 'warn');
                if (q.reason === 'other_department' || q.reason === 'not_employed') return badge('Inactive', 'off');
                return badge('Not held', 'off');
            }

            function showOverview() {
                const ov = S.ov;
                const me = ov.me || {};
                view.innerHTML = '';
                const shift = ov.shift;
                view.appendChild(h('div.gov-stats',
                    stat('Department', text(ov.dept && ov.dept.label, 60)),
                    stat('On duty now', ov.dept ? ov.dept.onDuty : null),
                    stat('Your rank', `Grade ${Number(me.grade) || 0}${me.manager ? ' · manager' : ''}`),
                    stat('Your shift', shift ? fmtDur(shift.seconds) : (me.onDuty ? 'On duty' : 'Off duty'))));
                const counts = ov.dept && ov.dept.assets;
                if (counts && typeof counts === 'object') {
                    view.appendChild(section('Equipment register'));
                    view.appendChild(h('div.dept-badges', ASSET_STATES.map(([s, l]) => badge(`${l}: ${Number(counts[s]) || 0}`, ASSET_TONE[s]))));
                }
                view.appendChild(section('Your qualifications'));
                view.appendChild(table(['Qualification', 'Status', 'Expires', 'Granted by'], arr(ov.quals).map((q) => h('tr',
                    h('td', text(q.label || q.qual, 80)), h('td', qualStatus(q)), h('td', q.expiresAt ? fmtDate(q.expiresAt) : '—'),
                    h('td', q.source === 'implied' ? 'Rank' : text(q.grantedBy || '—', 64)))), 'You hold no qualifications yet.'));
                view.appendChild(section('Equipment you hold'));
                view.appendChild(table(['Serial', 'Kind', 'Label', 'Issued', ''], arr(ov.myAssets).map((a) => h('tr',
                    h('td', text(a.serial, 32)), h('td', kindLabel(a.kind)), h('td', text(a.label || '—', 80)), h('td', fmtTime(a.issuedAt)),
                    h('td', btn('Open', () => go('assets', { serial: a.serial }))))), 'No equipment is issued to you.'));
            }

            // ── roster and one employee ───────────────────────────────────
            async function showRoster(fresh) {
                loading(view);
                const res = await call('roster');
                if (!fresh()) return;
                if (!res.ok) { failed(view, res, () => go('roster')); return; }
                S.roster = Array.isArray(res.list) ? res.list : [];
                S.roster.forEach((r) => { if (r.cid && r.name) S.names[r.cid] = r.name; });
                view.innerHTML = '';
                const filter = h('input.pf-input', { type: 'search', placeholder: 'Filter by name, citizen ID or job', 'aria-label': 'Filter the roster' });
                const holder = h('div');
                const draw = () => {
                    const q = filter.value.trim().toLowerCase();
                    const rows = S.roster.filter((r) => !q || [r.name, r.cid, r.job, r.gradeName].some((v) => String(v || '').toLowerCase().includes(q)));
                    holder.innerHTML = '';
                    holder.appendChild(table(['Name', 'Citizen ID', 'Job', 'Rank', 'Status', 'Shift since', 'Equipment', ''], rows.map((r) => h('tr',
                        h('td', text(r.name || '—', 80), r.me ? h('span.pf-muted', ' (you)') : null),
                        h('td', text(r.cid, 64)), h('td', text(r.job, 40)),
                        h('td', text(r.gradeName || `Grade ${Number(r.grade) || 0}`, 40), r.boss ? h('span.pf-muted', ' · boss') : null),
                        h('td', h('div.dept-badges', r.onDuty ? badge('On duty', 'active') : r.online ? badge('Online', 'info') : badge('Offline', 'off'))),
                        h('td', r.shiftStartedAt ? fmtTime(r.shiftStartedAt) : '—'),
                        h('td', String(Number(r.assets) || 0)),
                        h('td', btn('Open', () => showMember(r.cid, r.name))))), q ? 'Nobody matches that filter.' : 'Nobody works for this department yet.'));
                };
                filter.addEventListener('input', draw);
                view.appendChild(h('div.pf-toolbar', h('div', { style: { flex: '1' } }, filter), btn('Reload', () => go('roster'))));
                view.appendChild(holder);
                draw();
            }

            async function showMember(cid, name) {
                const d = detail(() => go(S.section));
                loading(view);
                const res = await call('member', { cid });
                if (!d.fresh()) return;
                view.innerHTML = '';
                view.appendChild(h('div.pf-toolbar', d.back));
                if (!res.ok) { view.appendChild(h('div.pfapp-error', { role: 'alert' }, errText(res))); return; }
                const m = res.member || {};
                const self = m.cid === meCid();
                view.appendChild(h('div.pf-card',
                    h('div.pf-strong', text(name || S.names[m.cid] || m.cid, 80)),
                    h('dl.gov-kv',
                        h('dt', 'Citizen ID'), h('dd', text(m.cid, 64)),
                        h('dt', 'Job'), h('dd', text(m.job || '—', 40), ` · grade ${Number(m.grade) || 0}`),
                        h('dt', 'Status'), h('dd', m.onDuty ? badge('On duty', 'active') : m.online ? badge('Online', 'info') : badge('Offline', 'off')))));

                // qualifications: managers grant and revoke their department's (never their own)
                view.appendChild(section('Qualifications'));
                const qmsg = msgLine();
                const reload = () => showMember(cid, name);
                const canChange = isManager() && !self;
                const deptOf = S.ov.me && S.ov.me.dept;
                view.appendChild(table(['Qualification', 'Status', 'Expires', 'Granted by', ''], arr(res.quals).map((q) => h('tr',
                    h('td', text(q.label || q.qual, 80)), h('td', qualStatus(q)), h('td', q.expiresAt ? fmtDate(q.expiresAt) : '—'),
                    h('td', q.source === 'implied' ? 'Rank' : text(q.grantedBy || '—', 64)),
                    h('td', canChange && q.dept === deptOf && q.has ? btn('Revoke', async (e) => {
                        const r = await run(e.currentTarget, 'revoke:' + cid + ':' + q.qual, 'revokeQual', { cid, qual: q.qual }, qmsg);
                        if (r && r.ok) { ctx.notify(`${q.label || q.qual} revoked`, 'success'); reload(); }
                    }, '.danger') : null))), 'No qualifications.'));
                if (canChange) {
                    const held = {};
                    arr(res.quals).forEach((q) => { if (q.has) held[q.qual] = true; });
                    const options = arr(S.ov.qualifications).filter((q) => !held[q.id]).map((q) => [q.id, text(q.label, 80)]);
                    if (options.length) {
                        const qual = select(options);
                        const until = h('input.pf-input', { type: 'date' });
                        const reason = h('input.pf-input', { type: 'text', maxlength: '200', placeholder: 'Reason (optional)' });
                        const grant = btn('Grant', async (e) => {
                            const p = { cid, qual: qual.value };
                            const exp = dateToSec(until.value, 1);
                            if (exp) p.expiresAt = exp;
                            if (str(reason.value)) p.reason = str(reason.value);
                            const r = await run(e.currentTarget, 'grant:' + cid, 'grantQual', p, qmsg);
                            if (r && r.ok) { ctx.notify(r.unchanged ? 'Already granted' : 'Qualification granted', 'success'); reload(); }
                        }, '.primary');
                        view.appendChild(h('div.dept-form', field('Grant', qual), field('Valid until (optional)', until), field('Reason', reason), h('div', grant)));
                    }
                }
                view.appendChild(qmsg);

                view.appendChild(section('Training'));
                view.appendChild(trainingTable(arr(res.training)));

                view.appendChild(section('Equipment held'));
                view.appendChild(assetTable(arr(res.assets), (a) => showAsset(a.serial, reload)));
                if (isManager()) {
                    const imsg = msgLine();
                    const serial = h('input.pf-input', { type: 'text', maxlength: '32', placeholder: 'Serial of equipment in stock' });
                    const issue = btn('Issue to this person', async (e) => {
                        const r = await run(e.currentTarget, 'issue:' + cid, 'issueAsset', { serial: str(serial.value), cid }, imsg);
                        if (r && r.ok) { ctx.notify(`${text(r.asset && r.asset.serial, 32)} issued`, 'success'); reload(); }
                    }, '.primary');
                    view.appendChild(h('div.dept-form', field('Issue equipment', serial), h('div', issue)));
                    view.appendChild(imsg);
                }

                view.appendChild(section('Recent shifts'));
                view.appendChild(shiftTable(arr(res.shifts)));
            }

            // ── shifts ─────────────────────────────────────────────────────
            function shiftTable(list) {
                return table(['Employee', 'Job', 'Grade', 'Started', 'Ended', 'Length', 'Reason'], list.map((s) => h('tr',
                    h('td', who(s.cid)), h('td', text(s.job, 40)), h('td', String(Number(s.grade) || 0)), h('td', fmtTime(s.startedAt)),
                    h('td', s.endedAt ? fmtTime(s.endedAt) : badge('Open', 'active')), h('td', fmtDur(s.seconds)),
                    h('td', text(s.endReason || '—', 40)))), 'No shifts recorded.');
            }

            async function showShifts(fresh) {
                await ensureRoster();
                if (!fresh()) return;
                view.innerHTML = '';
                const filter = { open: false, cid: null };
                const list = h('div');
                const more = h('div.pf-row');
                if (isManager()) {
                    const cid = cidInput('Citizen ID (all when empty)');
                    const open = h('input', { type: 'checkbox', 'aria-label': 'Open shifts only' });
                    view.appendChild(h('div.dept-form',
                        field('Employee', cid), field('Open shifts', h('div.pf-row', open, h('span.pf-small', 'Open only'))),
                        h('div', btn('Apply', () => { filter.cid = cidOf(cid) || null; filter.open = open.checked; load(null); }, '.primary'))));
                } else {
                    view.appendChild(h('div.gov-hint', 'Your own shifts. Managers see the whole department.'));
                }
                view.appendChild(list);
                view.appendChild(more);
                let rows = [];
                async function load(cursor) {
                    if (!cursor) { rows = []; loading(list); }
                    const p = {};
                    if (filter.cid) p.cid = filter.cid;
                    if (filter.open) p.open = true;
                    if (cursor) p.beforeId = cursor;
                    const res = await call('shifts', p);
                    if (!fresh()) return;
                    more.innerHTML = '';
                    if (!res.ok) { failed(list, res, () => load(null)); return; }
                    rows = rows.concat(Array.isArray(res.list) ? res.list : []);
                    list.innerHTML = '';
                    list.appendChild(shiftTable(rows));
                    if (res.nextCursor) more.appendChild(btn('Load more', () => load(res.nextCursor)));
                }
                await load(null);
            }

            // ── training ───────────────────────────────────────────────────
            function trainingTable(list) {
                return table(['Date', 'Trainee', 'Course', 'Result', 'Score', 'Qualification', 'Instructor', 'Note'], list.map((t) => {
                    const [rl, rt] = TRAINING_RESULT[t.result] || [text(t.result, 20), 'off'];
                    return h('tr',
                        h('td', fmtTime(t.at)), h('td', who(t.cid)), h('td', text(t.courseLabel || t.course, 80)), h('td', badge(rl, rt)),
                        h('td', t.score != null ? String(t.score) : '—'),
                        h('td', t.qual ? (t.granted ? badge(`Granted${t.expiresAt ? ' to ' + fmtDate(t.expiresAt) : ''}`, 'ok') : badge('Not granted', 'off')) : '—'),
                        h('td', who(t.instructor)), h('td.gov-note', text(t.note || '', 255)));
                }), 'No training records.');
            }

            function instructable() {
                const courses = S.ov.courses || [];
                if (isManager()) return courses;
                const held = {};
                arr(S.ov.quals).forEach((q) => { if (q.has) held[q.qual] = true; });
                return courses.filter((c) => c.instructorQual && held[c.instructorQual]);
            }

            async function showTraining(fresh) {
                await ensureRoster();
                if (!fresh()) return;
                view.innerHTML = '';
                const courses = instructable();
                if (courses.length) {
                    view.appendChild(section('Record training'));
                    const course = select(courses.map((c) => [c.id, text(c.label, 80) + (c.grantsLabel ? ` (grants ${text(c.grantsLabel, 60)})` : '')]));
                    const cid = cidInput('Trainee citizen ID');
                    const result = select([['pass', 'Passed'], ['fail', 'Failed'], ['in_progress', 'In progress']], 'pass');
                    const score = h('input.pf-input', { type: 'number', min: '0', max: '100', step: '1', placeholder: '0–100 (optional)' });
                    const note = h('input.pf-input', { type: 'text', maxlength: '255', placeholder: 'Note (optional)' });
                    const tmsg = msgLine();
                    const save = btn('Record', async (e) => {
                        const p = { cid: cidOf(cid), course: course.value, result: result.value };
                        if (str(score.value) !== '') p.score = Number(score.value);
                        if (str(note.value)) p.note = str(note.value);
                        const r = await run(e.currentTarget, 'training', 'recordTraining', p, tmsg);
                        if (!r || !r.ok) return;
                        let msg = r.duplicate ? 'Already recorded' : 'Training recorded';
                        if (r.granted) msg += '; qualification granted';
                        else if (r.grantError) msg += `; the qualification was not granted (${text(r.grantError, 60).replace(/_/g, ' ')})`;
                        ctx.notify(msg, 'success');
                        setMsg(tmsg, msg, 'ok');
                        score.value = ''; note.value = '';
                        load(null);
                    }, '.primary');
                    view.appendChild(h('div.dept-form', field('Course', course), field('Trainee', cid), field('Result', result),
                        field('Score', score), field('Note', note), h('div', save)));
                    view.appendChild(tmsg);
                }
                view.appendChild(section('Training records'));
                let filterCid = null;
                if (isManager()) {
                    const cid = cidInput('Citizen ID (whole department when empty)');
                    view.appendChild(h('div.dept-form', field('Employee', cid),
                        h('div', btn('Apply', () => { filterCid = cidOf(cid) || null; load(null); }))));
                }
                const list = h('div');
                const more = h('div.pf-row');
                view.appendChild(list);
                view.appendChild(more);
                let rows = [];
                async function load(cursor) {
                    if (!cursor) { rows = []; loading(list); }
                    const p = {};
                    if (filterCid) p.cid = filterCid;
                    if (cursor) p.beforeId = cursor;
                    const res = await call('training', p);
                    if (!fresh()) return;
                    more.innerHTML = '';
                    if (!res.ok) { failed(list, res, () => load(null)); return; }
                    rows = rows.concat(Array.isArray(res.list) ? res.list : []);
                    list.innerHTML = '';
                    list.appendChild(trainingTable(rows));
                    if (res.nextCursor) more.appendChild(btn('Load more', () => load(res.nextCursor)));
                }
                await load(null);
            }

            // ── equipment ──────────────────────────────────────────────────
            function assetTable(list, open) {
                return table(['Serial', 'Kind', 'Label', 'State', 'Holder', 'Location', 'Updated', ''], list.map((a) => h('tr',
                    h('td', text(a.serial, 32)), h('td', kindLabel(a.kind)), h('td', text(a.label || '—', 80)),
                    h('td', badge((ASSET_STATES.find(([s]) => s === a.state) || [0, text(a.state, 20)])[1], ASSET_TONE[a.state]),
                        a.ref === ARMORY_REF ? h('span.pf-muted.pf-small', ' armory') : null),
                    h('td', who(a.holder)), h('td', text(a.location || '—', 48)), h('td', fmtTime(a.updatedAt)),
                    h('td', btn('Open', () => open(a))))), 'No equipment matches.');
            }

            async function showAssets(fresh, arg) {
                await ensureRoster();
                if (!fresh()) return;
                if (arg && arg.serial) { showAsset(arg.serial, () => go('assets')); return; }
                view.innerHTML = '';
                const manager = isManager();
                const kinds = arr(S.ov.assetKinds);
                const filter = {};
                const state = select([['', 'Any state']].concat(ASSET_STATES));
                const kind = select([['', 'Any kind']].concat(kinds.map((k) => [k.id, text(k.label, 60)])));
                const holder = manager ? cidInput('Holder citizen ID') : null;
                const find = h('input.pf-input', { type: 'text', maxlength: '32', placeholder: 'Serial' });
                view.appendChild(h('div.dept-form',
                    field('State', state), field('Kind', kind), holder ? field('Holder', holder) : null,
                    h('div', btn('Apply', () => {
                        filter.state = state.value || null; filter.kind = kind.value || null; filter.holder = holder ? cidOf(holder) || null : null;
                        load(null);
                    }, '.primary')),
                    field('Open by serial', find), h('div', btn('Find', () => { if (str(find.value)) showAsset(str(find.value), () => go('assets')); }))));
                if (!manager) view.appendChild(h('div.gov-hint', 'Equipment issued to you. Managers see the whole register.'));

                // check out: a manager issues from the register; anyone on duty may take a kind that allows it
                const selfKinds = kinds.filter((k) => k.selfIssue);
                if (!manager && selfKinds.length) {
                    view.appendChild(section('Check out equipment'));
                    const serial = h('input.pf-input', { type: 'text', maxlength: '32', placeholder: 'Serial on the equipment' });
                    const cmsg = msgLine();
                    const take = btn('Check out to me', async (e) => {
                        const r = await run(e.currentTarget, 'selfissue', 'issueAsset', { serial: str(serial.value), cid: meCid() }, cmsg);
                        if (r && r.ok) { ctx.notify(`${text(r.asset && r.asset.serial, 32)} checked out`, 'success'); serial.value = ''; load(null); }
                    }, '.primary');
                    view.appendChild(h('div.dept-form', field('Serial', serial), h('div', take)));
                    view.appendChild(h('div.gov-hint', `On duty only. Kinds you may take yourself: ${selfKinds.map((k) => k.label).join(', ')}.`));
                    view.appendChild(cmsg);
                }
                if (manager) view.appendChild(registerForm(() => load(null)));

                view.appendChild(section('Register'));
                const list = h('div');
                const more = h('div.pf-row');
                view.appendChild(list);
                view.appendChild(more);
                let rows = [];
                async function load(cursor) {
                    if (!cursor) { rows = []; loading(list); }
                    const p = {};
                    if (filter.state) p.state = filter.state;
                    if (filter.kind) p.kind = filter.kind;
                    if (filter.holder) p.holder = filter.holder;
                    if (cursor) p.beforeId = cursor;
                    const res = await call('assets', p);
                    if (!fresh()) return;
                    more.innerHTML = '';
                    if (!res.ok) { failed(list, res, () => load(null)); return; }
                    rows = rows.concat(Array.isArray(res.list) ? res.list : []);
                    list.innerHTML = '';
                    list.appendChild(assetTable(rows, (a) => showAsset(a.serial, () => go('assets'))));
                    if (res.nextCursor) more.appendChild(btn('Load more', () => load(res.nextCursor)));
                }
                await load(null);
            }

            function registerForm(after) {
                const wrap = h('div');
                const toggle = btn('Register equipment', () => { form.hidden = !form.hidden; });
                const kind = select(arr(S.ov.assetKinds).map((k) => [k.id, text(k.label, 60)]));
                const serial = h('input.pf-input', { type: 'text', maxlength: '32', placeholder: 'Generated when empty' });
                const item = h('input.pf-input', { type: 'text', maxlength: '48', placeholder: 'Inventory item (optional)' });
                const label = h('input.pf-input', { type: 'text', maxlength: '80', placeholder: 'Label (optional)' });
                const location = h('input.pf-input', { type: 'text', maxlength: '48', placeholder: 'Location (optional)' });
                const cost = h('input.pf-input', { type: 'number', min: '0', step: '1', placeholder: 'Cost (optional)' });
                const rmsg = msgLine();
                const save = btn('Register', async (e) => {
                    const p = { kind: kind.value };
                    if (str(serial.value)) p.serial = str(serial.value);
                    if (str(item.value)) p.item = str(item.value);
                    if (str(label.value)) p.label = str(label.value);
                    if (str(location.value)) p.location = str(location.value);
                    if (str(cost.value) !== '') p.cost = Number(cost.value);
                    const r = await run(e.currentTarget, 'register', 'registerAsset', p, rmsg);
                    if (!r || !r.ok) return;
                    const s = text(r.asset && r.asset.serial, 32);
                    ctx.notify(r.duplicate ? `Already registered: ${s}` : `Registered ${s}`, 'success');
                    setMsg(rmsg, `Registered ${s}`, 'ok');
                    serial.value = ''; item.value = ''; label.value = ''; location.value = ''; cost.value = '';
                    after();
                }, '.primary');
                const form = h('div.pf-card', h('div.dept-form', field('Kind', kind), field('Serial', serial), field('Item', item),
                    field('Label', label), field('Location', location), field('Cost', cost), h('div', save)), rmsg);
                form.hidden = true;
                wrap.appendChild(h('div.pf-toolbar', toggle));
                wrap.appendChild(form);
                return wrap;
            }

            // The actions the server allows on an asset for this viewer (department.lua and assets.lua
            // decide; this only avoids offering what would be refused). Armory equipment (ref
            // 'armory') is booked in at the armory: here a manager may only report it lost, the
            // holder nothing, and lost armory equipment still with its holder is not "found" here.
            function assetActions(a) {
                const manager = isManager();
                const mine = a.holder && a.holder === meCid();
                const armory = a.ref === ARMORY_REF;
                const out = [];
                if (a.state === 'in_stock') {
                    if (manager) out.push(['issue', 'Issue']);
                    if (manager) out.push(['move:maintenance', 'Send to maintenance'], ['move:lost', 'Report lost'], ['move:retire', 'Retire']);
                } else if (a.state === 'issued') {
                    if (armory) {
                        if (manager) out.push(['return:lost', 'Report lost']);
                    } else if (manager || mine) {
                        out.push(['return:in_stock', 'Return to stock'], ['return:maintenance', 'Return for maintenance'], ['return:lost', 'Report lost']);
                    }
                } else if (a.state === 'maintenance') {
                    if (manager) out.push(['move:repair', 'Repaired'], ['move:lost', 'Report lost'], ['move:retire', 'Retire']);
                } else if (a.state === 'lost') {
                    if (manager && !(armory && a.holder)) out.push(['move:found', 'Found']);
                    if (manager) out.push(['move:retire', armory && a.holder ? 'Write off' : 'Retire']);
                }
                return out;
            }

            async function showAsset(serial, backTo) {
                const d = detail(backTo);
                loading(view);
                const res = await call('assetHistory', { serial });
                if (!d.fresh()) return;
                view.innerHTML = '';
                view.appendChild(h('div.pf-toolbar', d.back));
                if (!res.ok) { view.appendChild(h('div.pfapp-error', { role: 'alert' }, errText(res))); return; }
                const a = res.asset || {};
                const armory = a.ref === ARMORY_REF;
                view.appendChild(h('div.pf-card',
                    h('div.pf-row.between', h('div.pf-strong', text(a.serial, 32)),
                        badge((ASSET_STATES.find(([s]) => s === a.state) || [0, text(a.state, 20)])[1], ASSET_TONE[a.state])),
                    h('dl.gov-kv',
                        h('dt', 'Kind'), h('dd', kindLabel(a.kind)),
                        h('dt', 'Label'), h('dd', text(a.label || '—', 80)),
                        h('dt', 'Item'), h('dd', text(a.item || '—', 48)),
                        h('dt', 'Holder'), h('dd', who(a.holder)),
                        h('dt', 'Location'), h('dd', text(a.location || '—', 48)),
                        h('dt', 'Cost'), h('dd', money(a.cost)),
                        h('dt', 'Acquired'), h('dd', fmtTime(a.acquiredAt)),
                        h('dt', 'Issued'), h('dd', a.issuedAt ? `${fmtTime(a.issuedAt)} by ${who(a.issuedBy)}` : '—'),
                        h('dt', 'Reference'), h('dd', armory ? badge('Armory', 'info') : text(a.ref || '—', 64)))));
                if (armory && a.state === 'issued') {
                    view.appendChild(h('div.gov-hint', 'Armory equipment is returned at the armory, which takes the item back. A manager can report it lost here.'));
                }
                if (armory && a.state === 'lost' && a.holder) {
                    view.appendChild(h('div.gov-hint', 'Lost armory equipment is booked in at the armory when it is handed over. Writing it off clears it.'));
                }

                const actions = assetActions(a);
                if (actions.length) {
                    view.appendChild(section('Actions'));
                    const amsg = msgLine();
                    const note = h('input.pf-input', { type: 'text', maxlength: '200', placeholder: 'Note (optional)' });
                    const target = actions.some(([id]) => id === 'issue') ? cidInput('Issue to (citizen ID)') : null;
                    const reload = () => showAsset(a.serial, backTo);
                    const buttons = actions.map(([id, label]) => btn(label, async (e) => {
                        const p = { serial: a.serial };
                        if (str(note.value)) p.note = str(note.value);
                        let method;
                        if (id === 'issue') { method = 'issueAsset'; p.cid = cidOf(target) || meCid(); }
                        else if (id.startsWith('return:')) { method = 'returnAsset'; p.to = id.slice(7); }
                        else { method = 'assetAction'; p.action = id.slice(5); }
                        const r = await run(e.currentTarget, 'asset:' + a.serial, method, p, amsg);
                        if (r && r.ok) { ctx.notify(`${label}: ${text(a.serial, 32)}`, 'success'); reload(); }
                    }, id === 'move:retire' || id.endsWith(':lost') ? '.danger' : id === 'issue' ? '.primary' : ''));
                    view.appendChild(h('div.dept-form', target ? field('Issue to', target) : null, field('Note', note)));
                    view.appendChild(h('div.gov-actions', { style: { marginTop: '8px' } }, buttons));
                    view.appendChild(amsg);
                }

                view.appendChild(section('History'));
                view.appendChild(table(['When', 'Event', 'Change', 'By', 'Holder', 'Note'], arr(res.list).map((e) => h('tr',
                    h('td', fmtTime(e.at)), h('td', ASSET_EVENTS[e.event] || text(e.event, 24)),
                    h('td', `${text(e.from || '—', 16)} → ${text(e.to || '—', 16)}`),
                    h('td', e.actor ? who(e.actor) : text(e.resource || 'system', 48)), h('td', who(e.holder)),
                    h('td.gov-note', text(e.note || '', 200)))), 'No history.'));
            }

            // ── purchasing ─────────────────────────────────────────────────
            async function showPurchasing(fresh) {
                loading(view);
                const cat = await call('procurementCatalog');
                if (!fresh()) return;
                view.innerHTML = '';
                const labels = {};
                if (!cat.ok) {
                    view.appendChild(h('div.pf-card', h('div.pfapp-error', { role: 'alert' }, errText(cat))));
                } else {
                    const facilities = Array.isArray(cat.facilities) ? cat.facilities : [];
                    facilities.forEach((f) => { labels[f.buyerId] = f.label; });
                    view.appendChild(section('New order'));
                    if (!cat.mayOrder) view.appendChild(h('div.gov-hint', 'Only an on-duty manager can place or cancel orders.'));
                    if (!facilities.length) view.appendChild(h('div.pf-empty', 'This department has no supply facility.'));
                    else view.appendChild(orderForm(facilities, !!cat.mayOrder, () => loadOrders(null)));
                }
                view.appendChild(section('Orders'));
                const list = h('div');
                const more = h('div.pf-row');
                view.appendChild(list);
                view.appendChild(more);
                let rows = [];
                const mayOrder = !!(cat.ok && cat.mayOrder);
                async function loadOrders(cursor) {
                    if (!cursor) { rows = []; loading(list); }
                    const res = await call('procurements', cursor ? { beforeId: cursor } : {});
                    if (!fresh()) return;
                    more.innerHTML = '';
                    if (!res.ok) { failed(list, res, () => loadOrders(null)); return; }
                    rows = rows.concat(Array.isArray(res.list) ? res.list : []);
                    list.innerHTML = '';
                    list.appendChild(table(['#', 'Facility', 'Items', 'Total', 'State', 'Ordered by', 'When', ''], rows.map((o) => {
                        const lines = o.items && Array.isArray(o.items.lines) ? o.items.lines : Array.isArray(o.items) ? o.items : [];
                        const [sl, st] = PROC_STATE[o.state] || [text(o.state, 20), 'off'];
                        const omsg = h('div.dept-msg');
                        return h('tr',
                            h('td', String(Number(o.id) || ''), o.order ? h('div.pf-small.pf-muted', `order ${Number(o.order)}`) : null),
                            h('td', text(labels[o.buyer] || o.buyer, 60)),
                            h('td', lines.length ? lines.map((l) => h('div.pf-small', `${Number(l.quantity) || 0} × ${text(l.label || l.name, 60)}`)) : '—'),
                            h('td', money(o.total)), h('td', badge(sl, st), o.note ? h('div.pf-small.pf-muted', text(o.note, 255)) : null),
                            h('td', who(o.by)), h('td', fmtTime(o.at)),
                            h('td', mayOrder && o.state === 'paid' ? [btn('Cancel', async (e) => {
                                const r = await run(e.currentTarget, null, 'cancelProcurement', { id: o.id }, omsg);
                                if (r && r.ok) { ctx.notify(`Order ${Number(o.id)} cancelled; the department is refunded`, 'success'); loadOrders(null); }
                            }, '.danger'), omsg] : null));
                    }), 'No orders yet.'));
                    if (res.nextCursor) more.appendChild(btn('Load more', () => loadOrders(res.nextCursor)));
                }
                await loadOrders(null);
            }

            function orderForm(facilities, mayOrder, after) {
                const wrap = h('div.pf-card');
                const fac = select(facilities.map((f) => [f.buyerId, text(f.label || f.buyerId, 60)]));
                const lines = h('div');
                const subtotal = h('div.pf-strong');
                const omsg = msgLine();
                let qty = [];
                function drawLines() {
                    const f = facilities.find((x) => x.buyerId === fac.value) || facilities[0];
                    qty = [];
                    lines.innerHTML = '';
                    lines.appendChild(table(['Item', 'Per case', 'Price per case', 'Cases'], arr(f.items).map((it) => {
                        const input = h('input.pf-input.dept-qty', { type: 'number', min: '0', max: '200', step: '1', value: '0',
                            'aria-label': `Cases of ${text(it.name, 48)}` });
                        input.addEventListener('input', sum);
                        qty.push({ name: it.name, price: Number(it.price) || 0, input });
                        return h('tr', h('td', text(it.name, 48)), h('td', String(Number(it.caseSize) || 1)), h('td', money(it.price)), h('td', input));
                    }), 'This facility has nothing to order.'));
                    sum();
                }
                function cart() {
                    return qty.map((q) => ({ name: q.name, quantity: Math.floor(Number(q.input.value) || 0) })).filter((l) => l.quantity > 0);
                }
                function sum() {
                    const total = qty.reduce((acc, q) => acc + q.price * Math.max(0, Math.floor(Number(q.input.value) || 0)), 0);
                    subtotal.textContent = `Goods at catalog prices: ${money(total)} (freight is added and the total is priced by the supply service)`;
                }
                fac.addEventListener('change', drawLines);
                const place = btn('Place order', async (e) => {
                    const c = cart();
                    if (!c.length) { setMsg(omsg, 'Enter at least one case.', 'bad'); return; }
                    const r = await run(e.currentTarget, 'order', 'placeProcurement', { buyerId: fac.value, cart: c }, omsg);
                    if (!r || !r.ok) return;
                    const p = r.procurement || {};
                    const [sl] = PROC_STATE[p.state] || [text(p.state, 20)];
                    const msg = `Order ${Number(p.id) || ''} ${r.duplicate ? 'already placed' : 'placed'}: ${money(p.total)} (${sl})`;
                    ctx.notify(msg, 'success');
                    setMsg(omsg, msg, 'ok');
                    qty.forEach((q) => { q.input.value = '0'; });
                    sum();
                    after();
                }, '.primary');
                place.disabled = !mayOrder;
                wrap.appendChild(h('div.dept-form', field('Facility', fac)));
                wrap.appendChild(lines);
                wrap.appendChild(h('div.pf-row.between', { style: { marginTop: '8px' } }, subtotal, place));
                wrap.appendChild(omsg);
                drawLines();
                return wrap;
            }

            // ── budget ─────────────────────────────────────────────────────
            async function showBudget(fresh) {
                loading(view);
                const res = await call('budget');
                if (!fresh()) return;
                if (!res.ok) { failed(view, res, () => go('budget')); return; }
                view.innerHTML = '';
                const s = res.snapshot;
                view.appendChild(h('div.gov-hint', 'Read only. Budgets are set on the City Hall computer.'));
                if (s) {
                    const tone = /Under|Risk|Over/i.test(s.status || '') ? 'bad' : /Tight/i.test(s.status || '') ? 'warn' : 'ok';
                    view.appendChild(h('div.pf-row', { style: { margin: '8px 0' } }, badge(s.status || 'No status', s.status ? tone : 'off'),
                        h('span.pf-muted.pf-small', [s.month, s.society ? `account ${s.society}` : null].filter(Boolean).map((x) => text(x, 60)).join(' · '))));
                    view.appendChild(h('div.gov-stats',
                        stat('Monthly budget', money(s.budget)), stat('Account balance', money(s.balance)),
                        stat('Spent this month', money(s.spent)), stat('Salaries per month', money(s.salaries)),
                        stat('Recommended', money(s.recommended)), stat('Minimum required', money(s.minimum))));
                } else {
                    view.appendChild(h('div.pf-empty', 'No budget is set for this department.'));
                }
                view.appendChild(section('Recent transactions'));
                view.appendChild(table(['When', 'Type', 'Category', 'Amount', 'Balance after', 'By', 'Reason', 'State'], arr(res.recent).map((t) => h('tr',
                    h('td', fmtTime(t.at)), h('td', text(t.type, 40).replace(/_/g, ' ')), h('td', text(t.category || '—', 40)), h('td', money(t.amount)),
                    h('td', t.after != null ? money(t.after) : '—'), h('td', text(t.by || '—', 60)), h('td.gov-note', text(t.reason || '', 255)),
                    h('td', t.state === 'pending' ? badge('Pending', 'pending') : badge(text(t.state || 'applied', 20), t.state && t.state !== 'applied' ? 'off' : 'ok')))),
                'No transactions yet.'));
            }

            // ── payroll ────────────────────────────────────────────────────
            function renderReport(r) {
                const wrap = h('div');
                const t = r.totals || {};
                wrap.appendChild(h('div.pf-row', { style: { margin: '8px 0', flexWrap: 'wrap' } },
                    h('div.pf-strong', `${text(r.label || r.dept, 60)}: ${fmtTime(r.from)} to ${fmtTime(r.to)}`),
                    r.partial ? badge('Period still running: figures can change', 'pending') : badge('Closed period', 'ok'),
                    r.truncated ? badge('Too many rows: some employees are left out', 'warn') : null));
                wrap.appendChild(h('div.gov-stats',
                    stat('Employees', t.employees), stat('Wages paid', money(t.wagesPaid)),
                    stat('Wages not settled yet', money(t.wagesPending)), stat('Paychecks not paid', Number(t.wagesFailed) || 0),
                    stat('Paychecks', Number(t.paychecks) || 0), stat('Hours on duty', (Number(t.hours) || 0).toFixed(1)),
                    stat('Paid by the department', money(t.fromSociety)), stat('Paid by the state', money(t.fromState)),
                    stat('Treasury funding', money(t.fundingIn)), stat('Department spending', money(t.spendOut)),
                    stat('Adjustments', money(t.adjustments)), stat('Budget moves pending', money(t.pendingMoves))));
                wrap.appendChild(section('Employees'));
                wrap.appendChild(table(['Employee', 'Jobs', 'Rank', 'Paid', 'Not settled', 'Not paid', 'Paychecks', 'Hours', 'Shifts'], arr(r.employees).map((p) => h('tr',
                    h('td', text(p.name || p.cid, 80), p.employed ? null : h('div.pf-small.pf-muted', 'no longer employed')),
                    h('td', (Array.isArray(p.jobs) ? p.jobs : []).map((j) => text(j, 40)).join(', ') || '—'),
                    h('td', text(p.gradeName || (p.grade != null ? `Grade ${Number(p.grade)}` : '—'), 40)),
                    h('td', money(p.wagesPaid)), h('td', Number(p.wagesPending) ? badge(money(p.wagesPending), 'pending') : money(0)),
                    h('td', Number(p.wagesFailed) ? badge(String(Number(p.wagesFailed)), 'bad') : '0'),
                    h('td', String(Number(p.paychecks) || 0)), h('td', (Number(p.hours) || 0).toFixed(1)), h('td', String(Number(p.shifts) || 0)))),
                'Nobody was paid or on duty in this period.'));
                wrap.appendChild(section('Budget lines'));
                wrap.appendChild(table(['Type', 'Category', 'Count', 'Total'], arr(r.budget).map((b) => h('tr',
                    h('td', text(b.type, 40).replace(/_/g, ' ')), h('td', text(b.category || '—', 40)), h('td', String(Number(b.count) || 0)), h('td', money(b.total)))),
                'No budget moves in this period.'));
                return wrap;
            }

            async function showPayroll(fresh) {
                view.innerHTML = '';
                const now = new Date();
                const monthStart = (y, m) => Math.floor(new Date(y, m, 1).getTime() / 1000);
                const from = h('input.pf-input', { type: 'date' });
                const to = h('input.pf-input', { type: 'date' });
                const setPeriod = (f, t) => { from.value = secToDateInput(f); to.value = secToDateInput(t - 86400); };
                setPeriod(monthStart(now.getFullYear(), now.getMonth()), monthStart(now.getFullYear(), now.getMonth() + 1));
                const pmsg = msgLine();
                const out = h('div');
                let current = null;
                const saveBtn = btn('Save report', async (e) => {
                    if (!current) return;
                    const r = await run(e.currentTarget, null, 'savePayroll', { from: current.from, to: current.to }, pmsg);
                    if (r && r.ok) {
                        const msg = r.duplicate ? 'This period was already saved' : 'Report saved';
                        ctx.notify(msg, 'success'); setMsg(pmsg, msg, 'ok'); loadSaved();
                    }
                });
                saveBtn.hidden = true;
                async function build(e) {
                    const f = dateToSec(from.value, 0);
                    const t = dateToSec(to.value, 1);
                    if (!f || !t) { setMsg(pmsg, 'Pick both dates.', 'bad'); return; }
                    const r = await run(e && e.currentTarget, null, 'payroll', { from: f, to: t }, pmsg);
                    if (!fresh() || !r) return;
                    out.innerHTML = '';
                    current = null;
                    saveBtn.hidden = true;
                    if (!r.ok || !r.report) return;
                    current = r.report;
                    // only a period that has ended can be saved (the server checks it again)
                    saveBtn.hidden = !!current.partial;
                    out.appendChild(renderReport(current));
                }
                view.appendChild(h('div.pf-toolbar',
                    btn('This month', () => setPeriod(monthStart(now.getFullYear(), now.getMonth()), monthStart(now.getFullYear(), now.getMonth() + 1))),
                    btn('Last month', () => setPeriod(monthStart(now.getFullYear(), now.getMonth() - 1), monthStart(now.getFullYear(), now.getMonth())))));
                view.appendChild(h('div.dept-form', field('From (start of day)', from), field('To (end of day)', to),
                    h('div', btn('Build report', build, '.primary')), h('div', saveBtn)));
                view.appendChild(pmsg);
                view.appendChild(out);

                view.appendChild(section('Saved reports'));
                const saved = h('div');
                view.appendChild(saved);
                async function loadSaved() {
                    loading(saved);
                    const res = await call('payrollReports');
                    if (!fresh()) return;
                    if (!res.ok) { failed(saved, res, loadSaved); return; }
                    saved.innerHTML = '';
                    saved.appendChild(table(['Period', 'Employees', 'Wages paid', 'Not settled', 'Funding', 'Spending', 'Saved', ''], arr(res.list).map((s) => h('tr',
                        h('td', `${fmtDate(s.from)} – ${fmtDate((Number(s.to) || 0) - 1)}`), h('td', String(Number(s.employees) || 0)),
                        h('td', money(s.wagesTotal)), h('td', money(s.wagesPending)), h('td', money(s.fundingTotal)), h('td', money(s.spendTotal)),
                        h('td', `${fmtTime(s.at)} · ${who(s.by)}`),
                        h('td', btn('View', async (e) => {
                            const r = await run(e.currentTarget, null, 'payrollReports', { id: s.id }, pmsg);
                            if (!fresh() || !r || !r.ok) return;
                            out.innerHTML = '';
                            current = null;
                            saveBtn.hidden = true;
                            out.appendChild(h('div.gov-hint', `Saved report #${Number(s.id)}: as it was when it was saved.`));
                            out.appendChild(renderReport((r.saved && r.saved.report) || {}));
                        })))), 'No saved reports yet.'));
                }
                await loadSaved();
            }

            const SECTIONS = {
                overview: () => showOverview(),
                roster: showRoster,
                shifts: showShifts,
                training: showTraining,
                assets: showAssets,
                purchasing: showPurchasing,
                budget: showBudget,
                payroll: showPayroll,
            };

            // ── start ──────────────────────────────────────────────────────
            async function boot() {
                const token = ++S.token;
                S.roster = null;
                nav.innerHTML = '';
                loading(view);
                const res = await call('overview');
                if (token !== S.token) return;
                if (!res.ok) {
                    S.ov = null;
                    sub.textContent = 'Unavailable';
                    failed(view, res, boot);
                    return;
                }
                S.ov = res;
                const me = res.me || {};
                sub.textContent = `${text(res.dept && res.dept.label, 60)} · ${text(me.job, 40)} grade ${Number(me.grade) || 0}${me.manager ? ' · manager' : ''}`;
                go(S.section);
            }

            S.unmount = () => { S.token++; if (observer) observer.disconnect(); };
            container.__deptState = S;
            boot();
        },

        unmount(ctx) {
            const root = ctx && ctx.el;
            const S = root && root.__deptState;
            if (S && S.unmount) S.unmount();
        },
    });
})();
