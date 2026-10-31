/*
 * Tow app (pf-devices platform module): the driver's flatbed, the current tow contract or accepted
 * request, the dispatch tow requests (pf-services), stats and levels. One module for the tablet and
 * the computer. Requests go through ctx.rpc (server/devices.lua → server/apps/tow.lua); state pushes
 * come through client/devices_bridge.lua and pf-devices PushToJob. DOM work stays inside the given
 * container and every server string is escaped.
 */
(function () {
    'use strict';
    if (!window.PFApps) return;

    const ERRORS = {
        not_authorized: 'Only tow drivers can use this app',
        rate_limited: 'Slow down a little',
        timeout: 'The server did not answer',
        server_error: 'Something went wrong',
        request_failed: 'Could not reach the server',
        not_open: 'Someone else took that request',
        taken: 'Someone else took that request',
        too_many_active: 'Finish your other requests first',
        off_duty: 'Clock in first',
        wrong_job: 'That request is not for tow drivers',
        not_yours: 'That request is not yours',
        vehicle_not_found: 'The car is not in the city any more',
        not_at_destination: 'The car is not at the destination yet',
        too_far: 'Stand next to the car you delivered',
        no_plate: 'That request has no plate',
    };
    const TABS = [['overview', '🛻', 'Overview'], ['requests', '📟', 'Requests'], ['contracts', '📋', 'Contracts'], ['progress', '⭐', 'Progress']];
    const STAGES = { pickup: 'Drive to the breakdown and hook the car', deliver: 'Take the car to the drop-off and set it down', delivered: 'Delivered', payment_due: 'Delivered — the pay is waiting for you' };

    function create(container, ctx) {
        const { esc, money } = ctx;
        const st = { tab: ctx.storage.get('tab', 'overview'), v: null, config: null, busy: {}, error: null };
        let alive = true;
        let refreshTimer = null;

        const root = document.createElement('div');
        root.className = 'pf-app pfj-tow';
        container.appendChild(root);

        const num = (v, d = 0) => (Number.isFinite(Number(v)) ? Number(v) : d);

        function report(res) {
            if (res && res.ok === false && res.error !== 'refused') ctx.notify(res.message || ERRORS[res.error] || 'That did not work', 'error');
            return res;
        }

        function apply(v) {
            if (!v || typeof v !== 'object') return;
            st.v = Object.assign({}, st.v || {}, v);
            if (v.config) st.config = v.config;
        }

        async function act(key, method, payload) {
            if (st.busy[key]) return null;
            st.busy[key] = true;
            render();
            let res;
            try { res = await ctx.rpc(method, payload); } finally { st.busy[key] = false; }
            if (!alive) return res;
            if (res && res.view) apply(res.view);
            report(res);
            render();
            return res;
        }

        async function loadInit() {
            const res = await ctx.rpc('getInit');
            if (!alive) return;
            if (!res || res.ok === false) st.error = (res && (res.message || ERRORS[res.error])) || 'The tow yard is not answering';
            else { st.error = null; apply(res); }
            render();
        }

        function refreshSoon() {
            if (refreshTimer) return;
            refreshTimer = setTimeout(async () => {
                refreshTimer = null;
                const res = await ctx.rpc('refresh');
                if (!alive || !res || res.ok === false) return;
                apply(res);
                render();
            }, 250);
        }

        function btn(action, label, cls, opts) {
            const key = action + (opts && opts.key != null ? ':' + opts.key : '');
            const busy = st.busy[key];
            const data = Object.entries((opts && opts.data) || {}).map(([k, v]) => ` data-${k}="${esc(v)}"`).join('');
            const disabled = busy || (opts && opts.disabled) ? ' disabled' : '';
            return `<button type="button" class="pf-btn ${cls || ''}" data-action="${action}"${data}${disabled}>${busy ? 'Working…' : esc(label)}</button>`;
        }

        const gps = (x, y, label) => (Number.isFinite(Number(x)) && Number.isFinite(Number(y)) ? btn('waypoint', label || 'GPS', 'sm ghost', { key: `${x},${y}`, data: { x, y } }) : '');

        function stat(label, value) {
            return `<div class="pf-card pf-stat"><span class="pf-stat-value">${value}</span><span class="pf-stat-label">${esc(label)}</span></div>`;
        }

        function flatbedCard() {
            const v = st.v || {};
            const r = v.rental;
            const depot = v.depot;
            if (r) {
                let status = '<span class="pf-badge ok">Out on the road</span>';
                let hint = 'Return it to the bay at the yard to get the deposit back.';
                if (r.orphaned) { status = '<span class="pf-badge warn">Truck put away</span>'; hint = 'The truck was put away while you were gone. Come to the bay to get your deposit back.'; }
                else if (r.present === false) { status = '<span class="pf-badge bad">Truck missing</span>'; hint = 'Your flatbed is gone. Report it lost to close the rental (the deposit covers it).'; }
                return `
                    <div class="pf-card pf-stack">
                        <div class="pf-row between"><div class="pf-strong">🛻 ${esc(r.label || r.model || 'Flatbed')} <span class="pf-muted">${esc(r.plate || '')}</span></div>${status}</div>
                        <div class="pf-muted pf-small">Deposit ${money(r.deposit)} · ${esc(hint)}</div>
                        <div class="pf-row">
                            ${btn('returnFlatbed', r.orphaned ? 'Get my deposit back' : 'Return flatbed', 'primary sm', { disabled: !v.atBay })}
                            ${!r.orphaned && r.present === false ? btn('reportLost', 'Report lost', 'danger sm') : ''}
                            ${depot ? gps(depot.x, depot.y, 'Yard on GPS') : ''}
                        </div>
                        ${v.atBay ? '' : '<div class="pf-muted pf-small">You are not at the flatbed bay.</div>'}
                    </div>`;
            }
            const vehicles = Array.isArray(v.vehicles) ? v.vehicles : [];
            return `
                <div class="pf-card pf-stack">
                    <div class="pf-strong">🏗️ ${esc((depot && depot.label) || 'Tow yard')}</div>
                    <div class="pf-muted pf-small">${v.atBay ? 'Rent a flatbed. The deposit comes back when you return it here.' : 'Flatbeds are rented at the bay in the tow yard.'}</div>
                    <div class="pf-row" style="flex-wrap:wrap">
                        ${vehicles.map((x) => btn('rentFlatbed', x.unlocked ? `${x.label} · ${money(x.deposit)} deposit` : `${x.label} · level ${num(x.minLevel)}`, x.unlocked ? 'primary sm' : 'sm', { key: x.model, data: { model: x.model }, disabled: !x.unlocked || !v.atBay })).join('')}
                        ${depot && !v.atBay ? gps(depot.x, depot.y, 'Yard on GPS') : ''}
                    </div>
                </div>`;
        }

        function hookCard() {
            const h = st.v && st.v.hook;
            return `
                <div class="pf-card pf-stack">
                    <div class="pf-row between"><div class="pf-strong">🪝 On the bed</div>${h ? `<span class="pf-badge accent">${esc(h.plate || 'Car')}</span>` : '<span class="pf-badge">Empty</span>'}</div>
                    <div class="pf-muted pf-small">${h ? 'Set it down where it belongs: the drop-off, the impound lot or the shop.' : 'Stand at your flatbed facing a car and use /tow (or the radial menu) to hook it.'}</div>
                </div>`;
        }

        function contractCard(withActions) {
            const v = st.v || {};
            const c = v.contract;
            if (!c) return '';
            const drop = v.dropOff;
            return `
                <div class="pf-card pf-stack pfj-tow-job">
                    <div class="pf-row between"><div class="pf-strong">📋 Breakdown: ${esc(c.model || 'car')} <span class="pf-muted">${esc(c.plate || '')}</span></div><span class="pf-badge ${c.stage === 'payment_due' ? 'warn' : 'accent'}">${money(c.pay)}</span></div>
                    <div class="pf-muted pf-small">${esc(STAGES[c.stage] || c.stage || '')} · ${num(c.km).toFixed(1)} km to the depot · +${num(c.xp)} XP</div>
                    <div class="pf-row" style="flex-wrap:wrap">
                        ${c.stage === 'pickup' ? gps(c.x, c.y, 'Breakdown on GPS') : ''}
                        ${c.stage === 'deliver' && drop ? gps(drop.x, drop.y, `${drop.label || 'Drop-off'} on GPS`) : ''}
                        ${c.stage === 'payment_due' ? btn('claimPay', 'Collect pay', 'primary sm') : ''}
                        ${withActions && (c.stage === 'pickup' || c.stage === 'deliver') ? btn('cancelContract', 'Cancel contract', 'danger sm') : ''}
                    </div>
                </div>`;
        }

        function requestCard(r) {
            const statusBadge = r.mine ? '<span class="pf-badge ok">Yours</span>' : '<span class="pf-badge">Open</span>';
            const dests = Array.isArray(r.destinations) ? r.destinations : [];
            return `
                <div class="pf-list-item pf-stack pfj-tow-req">
                    <div class="pf-row between"><div class="pf-strong">${esc(r.icon || '📋')} ${esc(r.title || r.label || 'Tow request')}</div><div class="pf-row">${statusBadge}${num(r.reward) > 0 ? `<span class="pf-badge accent">${money(r.reward)}</span>` : ''}</div></div>
                    <div class="pf-muted pf-small">${esc(r.label || '')}${r.plate ? ` · plate ${esc(r.plate)}` : ''}${r.fromName ? ` · from ${esc(r.fromName)}` : ''}${r.created ? ` · ${esc(ctx.timeAgo(r.created))}` : ''}</div>
                    ${r.details ? `<div class="pf-small">${esc(r.details)}</div>` : ''}
                    ${dests.length ? `<div class="pf-muted pf-small">Take it to: ${dests.map((d) => esc(d.label || 'destination')).join(', ')}</div>` : ''}
                    <div class="pf-row" style="flex-wrap:wrap">
                        ${r.coords ? gps(r.coords.x, r.coords.y, 'Car on GPS') : ''}
                        ${r.mine && dests[0] ? gps(dests[0].x, dests[0].y, `${dests[0].label || 'Destination'} on GPS`) : ''}
                        ${r.mine ? btn('completeRequest', 'Complete', 'primary sm', { key: r.id, data: { id: r.id } }) + btn('releaseRequest', 'Hand back', 'ghost sm', { key: r.id, data: { id: r.id } }) : btn('acceptRequest', 'Accept', 'primary sm', { key: r.id, data: { id: r.id }, disabled: st.v && !st.v.onDuty })}
                    </div>
                </div>`;
        }

        function overviewHtml() {
            const v = st.v || {};
            const s = v.stats || {};
            const mine = (Array.isArray(v.requests) ? v.requests : []).filter((r) => r.mine);
            const job = v.contract ? contractCard(true) : mine.length ? `<div class="pf-stack">${mine.map(requestCard).join('')}</div>`
                : `<div class="pf-card pf-empty">No job in progress. Take a request or ask for a contract.<div class="pf-row" style="justify-content:center;margin-top:8px">${btn('goTab', 'Requests', 'sm', { data: { tab: 'requests' } })}${btn('goTab', 'Contracts', 'sm', { data: { tab: 'contracts' } })}</div></div>`;
            return `
                ${v.onDuty ? '' : '<div class="pf-card pfj-tow-warn">You are off duty. Clock in to take requests and contracts.</div>'}
                <div class="pf-grid pfj-tow-two">${flatbedCard()}${hookCard()}</div>
                <div class="pf-strong pfj-tow-h">Current job</div>
                ${job}
                <div class="pf-grid pfj-tow-stats">
                    ${stat('Contracts', num(s.contracts))}
                    ${stat('Requests', num(s.requests))}
                    ${stat('Cars hooked', num(s.towed))}
                    ${stat('Earned', money(s.earned))}
                </div>`;
        }

        function requestsHtml() {
            const v = st.v || {};
            if (v.servicesOnline === false) return '<div class="pf-card pf-empty">Dispatch is offline.</div>';
            const list = Array.isArray(v.requests) ? v.requests : [];
            if (!list.length) return '<div class="pf-card pf-empty">No tow requests right now. NPC contracts are open in the Contracts tab.</div>';
            return `<div class="pf-muted pf-small">Police impounds and recoveries to mechanic shops. Hook the car, take it to the destination and set it down; the request completes when the car is there.</div>
                <div class="pf-list">${list.map(requestCard).join('')}</div>`;
        }

        function contractsHtml() {
            const v = st.v || {};
            const cfg = st.config || {};
            const lvl = v.level || {};
            const blocker = v.contractBlocker;
            const reasons = {
                requests_waiting: 'Tow requests are waiting in dispatch: those come first.',
                no_truck: 'You need a flatbed for contracts.',
                contract_active: 'Finish or cancel your current contract first.',
                payment_due: 'Collect the pay for your last contract first.',
                cooldown: 'Dispatch is looking for the next breakdown.',
                hourly_limit: 'That is enough contracts for this hour.',
            };
            return `
                ${contractCard(true)}
                <div class="pf-card pf-stack">
                    <div class="pf-strong">Breakdown contracts</div>
                    <div class="pf-muted pf-small">When nobody needs a tow, dispatch sends you to a broken-down car within ${num(lvl.maxKm) >= 99 ? 'the whole city' : num(lvl.maxKm).toFixed(1) + ' km of the depot'}. Bring it to the depot drop-off: ${money(cfg.payBase)} plus ${money(cfg.payPerKm)} per km${num(lvl.payMultiplier, 1) !== 1 ? `, ×${num(lvl.payMultiplier, 1)} at your level` : ''}.</div>
                    <div class="pf-row">${btn('startContract', 'Get a contract', 'primary', { disabled: !!blocker || !v.onDuty })}</div>
                    ${blocker ? `<div class="pf-muted pf-small">${esc(reasons[blocker] || '')}</div>` : ''}
                </div>`;
        }

        function progressHtml() {
            const v = st.v || {};
            const lvl = v.level || {};
            const levels = Array.isArray(v.levels) ? v.levels : [];
            const xp = num(v.stats && v.stats.xp);
            const base = num(lvl.xp);
            const next = lvl.nextXp != null ? num(lvl.nextXp) : null;
            const pct = next ? Math.min(100, Math.max(0, ((xp - base) / Math.max(1, next - base)) * 100)) : 100;
            return `
                <div class="pf-card pf-stack">
                    <div class="pf-row between"><div class="pf-strong">Level ${num(lvl.level, 1)} · ${esc(lvl.title || '')}</div><span class="pf-muted">${xp.toLocaleString()} XP${next ? ` / ${next.toLocaleString()}` : ' · top level'}</span></div>
                    <div class="pfj-tow-bar"><div style="width:${pct.toFixed(1)}%"></div></div>
                    <div class="pf-muted pf-small">Contracts give XP by distance; every completed dispatch request gives ${num(st.config && st.config.requestXp, 80)} XP.</div>
                </div>
                <table class="pf-table">
                    <thead><tr><th>Level</th><th>Title</th><th>XP</th><th>Contract reach</th><th>Pay</th></tr></thead>
                    <tbody>${levels.map((l) => `<tr class="${num(l.level) === num(lvl.level, 1) ? 'pfj-tow-current' : ''}"><td>${num(l.level)}</td><td>${esc(l.title || '')}</td><td>${num(l.xp).toLocaleString()}</td><td>${num(l.maxKm) >= 99 ? 'Whole city' : num(l.maxKm).toFixed(1) + ' km'}</td><td>×${num(l.payMultiplier, 1)}</td></tr>`).join('')}</tbody>
                </table>`;
        }

        function render() {
            if (!alive) return;
            if (!st.v) {
                root.innerHTML = st.error
                    ? `<div class="pf-app-body"><div class="pf-card pf-empty">${esc(st.error)}<br><br><button type="button" class="pf-btn primary" data-action="reload">Try again</button></div></div>`
                    : '<div class="pf-app-body"><div class="pf-card pf-empty">Calling the tow yard…</div></div>';
                return;
            }
            const v = st.v;
            const open = (Array.isArray(v.requests) ? v.requests : []).filter((r) => !r.mine).length;
            const body = st.tab === 'requests' ? requestsHtml() : st.tab === 'contracts' ? contractsHtml() : st.tab === 'progress' ? progressHtml() : overviewHtml();
            root.innerHTML = `
                <div class="pf-app-header"><div class="pf-app-title"><span class="pf-icon">🛻</span>Tow<span class="pf-app-sub">Level ${num(v.level && v.level.level, 1)} · ${esc((v.level && v.level.title) || '')}</span></div>
                    <span class="pf-badge ${v.onDuty ? 'ok' : 'warn'}">${v.onDuty ? 'On duty' : 'Off duty'}</span></div>
                <div class="pf-tabs">${TABS.map(([id, icon, label]) => `<div class="pf-tab${st.tab === id ? ' active' : ''}" data-tab="${id}">${icon} ${esc(label)}${id === 'requests' && open ? ` <span class="pf-badge accent">${open}</span>` : ''}</div>`).join('')}</div>
                <div class="pf-app-body pf-stack">${body}</div>`;
        }

        async function onClick(ev) {
            const tabEl = ev.target.closest('[data-tab]');
            if (tabEl && root.contains(tabEl) && !tabEl.dataset.action) {
                st.tab = tabEl.dataset.tab;
                ctx.storage.set('tab', st.tab);
                render();
                if (st.tab === 'requests') refreshSoon();
                return;
            }
            const el = ev.target.closest('[data-action]');
            if (!el || !root.contains(el) || el.disabled) return;
            const id = Number(el.dataset.id);
            switch (el.dataset.action) {
                case 'reload': await loadInit(); break;
                case 'goTab': st.tab = el.dataset.tab; ctx.storage.set('tab', st.tab); render(); break;
                case 'rentFlatbed': await act('rentFlatbed:' + el.dataset.model, 'rentFlatbed', { model: String(el.dataset.model || '') }); break;
                case 'returnFlatbed': await act('returnFlatbed', 'returnFlatbed'); break;
                case 'reportLost': await act('reportLost', 'reportLost'); break;
                case 'startContract': await act('startContract', 'startContract'); break;
                case 'cancelContract': await act('cancelContract', 'cancelContract'); break;
                case 'claimPay': await act('claimPay', 'claimPay'); break;
                case 'acceptRequest': {
                    const res = await act('acceptRequest:' + id, 'acceptRequest', { id });
                    if (res && res.ok) ctx.notify('Request accepted', 'success');
                    break;
                }
                case 'completeRequest': {
                    const res = await act('completeRequest:' + id, 'completeRequest', { id });
                    if (res && res.ok) ctx.notify('Request completed', 'success');
                    break;
                }
                case 'releaseRequest': {
                    const res = await act('releaseRequest:' + id, 'releaseRequest', { id });
                    if (res && res.ok) ctx.notify('Request handed back to dispatch', 'success');
                    break;
                }
                case 'waypoint': ctx.setWaypoint(Number(el.dataset.x), Number(el.dataset.y)); ctx.notify('GPS set', 'success'); break;
                default: break;
            }
        }
        root.addEventListener('click', onClick);

        ctx.on('state', () => refreshSoon());
        ctx.on('requests', () => refreshSoon());

        render();
        return {
            start: loadInit,
            destroy() {
                alive = false;
                if (refreshTimer) clearTimeout(refreshTimer);
                root.removeEventListener('click', onClick);
            },
        };
    }

    let instance = null;
    PFApps.register('tow', {
        async mount(container, ctx) {
            if (instance) instance.destroy();
            instance = create(container, ctx);
            await instance.start();
        },
        unmount() {
            if (instance) instance.destroy();
            instance = null;
        },
    });
})();
