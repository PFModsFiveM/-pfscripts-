/*
 * Bus app (pf-devices platform module): routes, the route in progress, stats and levels. One module
 * for the tablet and the computer. Requests go through ctx.rpc (server/devices.lua →
 * server/apps/bus.lua); route and stats pushes come through client/devices_bridge.lua. Stops and
 * the route end are checked in by the bus itself (client/bus.lua), then again by the server.
 */
(function () {
    'use strict';
    if (!window.PFApps) return;

    const ERRORS = {
        not_installed: 'Install Bus from the App Store first',
        rate_limited: 'Slow down a little',
        timeout: 'The server did not answer',
        server_error: 'Something went wrong',
        request_failed: 'Could not reach the server',
        route_active: 'Finish or cancel your current route first',
        no_route: 'You are not on a route',
        bus_out: 'You already have a bus out',
        no_bus: 'You have no bus out',
        not_at_depot: 'Go to the bus depot first',
    };
    const TABS = [['dashboard', '📊', 'Dashboard'], ['routes', '🚏', 'Routes'], ['stats', '📈', 'Statistics'], ['levels', '⭐', 'Levels']];

    function create(container, ctx) {
        const { esc, money } = ctx;
        const st = { tab: ctx.storage.get('tab', 'dashboard'), v: null, config: null, busy: {}, error: null };
        let alive = true;
        let refreshTimer = null;

        const root = document.createElement('div');
        root.className = 'pfj-bus';
        container.appendChild(root);

        const num = (v, d = 0) => (Number.isFinite(Number(v)) ? Number(v) : d);
        const stats = () => (st.v && st.v.stats) || {};
        const active = () => (st.v && st.v.activeRoute) || null;

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
            if (!res || res.ok === false) st.error = ERRORS[res && res.error] || 'Dispatch is not answering';
            else { st.error = null; apply(res); }
            render();
        }

        function refreshSoon() {
            if (refreshTimer) return;
            refreshTimer = setTimeout(() => { refreshTimer = null; loadInit(); }, 250);
        }

        function btn(action, label, cls, opts) {
            const key = action + (opts && opts.key != null ? ':' + opts.key : '');
            const busy = st.busy[key];
            const data = Object.entries((opts && opts.data) || {}).map(([k, v]) => ` data-${k}="${esc(v)}"`).join('');
            const disabled = busy || (opts && opts.disabled) ? ' disabled' : '';
            return `<button type="button" class="pfj-bus-btn ${cls || ''}" data-action="${action}"${data}${disabled}>${busy ? 'Working…' : esc(label)}</button>`;
        }

        // the server's estimate: passengers usually waiting along the route, before the time of day,
        // level, on-time, condition and rating multipliers
        const passengers = (route) => num(route.expectedPassengers);
        const basePay = (route) => num(route.estimatedPay);

        function card(label, value, sub) {
            return `<div class="pfj-bus-card"><div class="pfj-bus-label">${esc(label)}</div><div class="pfj-bus-value">${value}</div>${sub ? `<div class="pfj-bus-sub">${esc(sub)}</div>` : ''}</div>`;
        }

        function depotHtml() {
            const v = st.v || {};
            const bus = v.bus;
            const depot = v.depot;
            if (bus) {
                return `
                    <div class="pfj-bus-panel">
                        <div class="pfj-bus-row between"><div class="pfj-bus-title">🚍 ${esc(bus.label || bus.model || 'Bus')}</div><span class="pfj-bus-pill on">${esc(bus.plate || '')}</span></div>
                        <div class="pfj-bus-muted">${bus.present === false ? 'Your bus is gone. Return it at the depot to free the bay.' : `Seats ${num(bus.capacity)} passengers. Return it at the depot when you are done.`}</div>
                        <div class="pfj-bus-row">${btn('returnBus', 'Return bus', '', { disabled: !v.atDepot })}${depot ? btn('waypoint', 'Depot on GPS', 'sm', { data: { x: depot.x, y: depot.y } }) : ''}</div>
                    </div>`;
            }
            const vehicles = Array.isArray(v.vehicles) ? v.vehicles : [];
            return `
                <div class="pfj-bus-panel">
                    <div class="pfj-bus-title">🏢 ${esc((depot && depot.label) || 'Bus depot')}</div>
                    <div class="pfj-bus-muted">${v.atDepot ? 'Pick a bus. Passengers only board a bus you are driving.' : 'Buses are handed out at the depot.'}</div>
                    <div class="pfj-bus-row">${vehicles.map((b) => btn('takeBus', b.unlocked ? `${b.label} (${num(b.capacity)} seats)` : `${b.label} · level ${num(b.minLevel)}`, b.unlocked ? 'primary sm' : 'sm', { key: b.model, data: { model: b.model }, disabled: !b.unlocked || !v.atDepot })).join('')}
                    ${!v.atDepot && depot ? btn('waypoint', 'Depot on GPS', 'sm', { data: { x: depot.x, y: depot.y } }) : ''}</div>
                </div>`;
        }

        function dashboardHtml() {
            const s = stats();
            const a = active();
            let route = '<div class="pfj-bus-panel"><div class="pfj-bus-title">No route in progress</div><div class="pfj-bus-muted">Take a bus at the depot and pick a route in the Routes tab.</div><div class="pfj-bus-row">' + btn('goRoutes', 'Choose a route', 'primary') + '</div></div>';
            if (a) {
                const done = num(a.currentStop) > num(a.totalStops);
                route = `
                    <div class="pfj-bus-panel active">
                        <div class="pfj-bus-row between"><div class="pfj-bus-title">🚌 ${esc(a.name || 'Route')}</div><span class="pfj-bus-pill">${done ? 'All stops done' : `Stop ${num(a.currentStop)} of ${num(a.totalStops)}`}</span></div>
                        <div class="pfj-bus-progress"><div style="width:${Math.min(100, ((num(a.currentStop) - 1) / Math.max(1, num(a.totalStops))) * 100).toFixed(1)}%"></div></div>
                        <div class="pfj-bus-meta">
                            ${done ? '<span>Finish the route from the bus</span>' : `<span>Next: <strong>${esc(a.nextStop || 'Stop')}</strong></span>`}
                            <span>On board ${num(a.onBoard)}</span>
                            <span>Picked up ${num(a.passengersPickedUp)}</span>
                            <span>Delivered ${num(a.passengersDelivered)}</span>
                            ${num(a.missed) ? `<span>Left behind ${num(a.missed)}</span>` : ''}
                            <span>Fare so far ${money(a.estimatedPay)}</span>
                        </div>
                        <div class="pfj-bus-row">
                            ${done ? btn('completeRoute', 'Complete route', 'primary') : btn('checkInStop', 'Check in at stop', 'primary')}
                            ${!done && a.nextStopAt ? btn('waypoint', 'Stop on GPS', '', { data: { x: a.nextStopAt.x, y: a.nextStopAt.y } }) : ''}
                            ${btn('cancelRoute', 'Cancel route', 'danger')}
                        </div>
                        <div class="pfj-bus-muted">Check stops in from your bus within a few metres of the stop. Passengers ride to their own stop; everyone gets off at the end.</div>
                    </div>`;
            }
            return `
                <div class="pfj-bus-cards">
                    ${card('Level', num(s.level, 1), levelName(num(s.level, 1)))}
                    ${card('Earnings', money(s.totalEarnings), 'All time')}
                    ${card('Routes', num(s.routesCompleted), 'Completed')}
                    ${card('Rating', num(s.averageRating, 5).toFixed(1), '⭐')}
                </div>
                ${route}
                ${depotHtml()}`;
        }

        function routesHtml() {
            const routes = (st.v && Array.isArray(st.v.routes)) ? st.v.routes : [];
            if (!routes.length) return '<div class="pfj-bus-empty">No routes for your level.</div>';
            const busyRoute = !!active();
            return `<div class="pfj-bus-routes">${routes.map((r) => `
                <div class="pfj-bus-route ${esc(r.difficulty || 'easy')}">
                    <div class="pfj-bus-route-info">
                        <div class="pfj-bus-title">${esc(r.name || ('Route ' + num(r.id)))}</div>
                        <div class="pfj-bus-muted">${esc(String(r.difficulty || 'easy').replace(/^\w/, (c) => c.toUpperCase()))} • ${Math.round(num(r.estimatedTime) / 60000)} min • ${num(r.stopCount || (Array.isArray(r.stops) ? r.stops.length : 0))} stops</div>
                        ${r.description ? `<div class="pfj-bus-muted">${esc(r.description)}</div>` : ''}
                        <div class="pfj-bus-muted">~${passengers(r)} passengers • ${num(r.baseDistance).toFixed(1)} miles</div>
                    </div>
                    <div class="pfj-bus-route-side">
                        <div class="pfj-bus-pay">${money(basePay(r))}</div>
                        <div class="pfj-bus-sub">usual fare</div>
                        ${btn('startRoute', busyRoute ? 'On a route' : 'Start', 'primary sm', { key: r.id, data: { route: r.id }, disabled: busyRoute })}
                    </div>
                </div>`).join('')}</div>
                ${lockedHtml()}`;
        }

        function lockedHtml() {
            const locked = (st.v && Array.isArray(st.v.lockedRoutes)) ? st.v.lockedRoutes : [];
            if (!locked.length) return '';
            return `<div class="pfj-bus-panel"><div class="pfj-bus-title">🔒 More routes</div>${locked.map((r) => `<div class="pfj-bus-row between"><span>${esc(r.name || 'Route')}</span><span class="pfj-bus-pill">Level ${num(r.minLevel)}</span></div>`).join('')}</div>`;
        }

        function statsHtml() {
            const s = stats();
            return `<div class="pfj-bus-cards">
                ${card('Passengers', num(s.totalPassengers).toLocaleString())}
                ${card('Routes completed', num(s.routesCompleted))}
                ${card('Earnings', money(s.totalEarnings))}
                ${card('On time', num(s.onTimeCount))}
                ${card('Minutes driven', num(s.totalTime))}
                ${card('Average rating', num(s.averageRating, 5).toFixed(1) + ' ⭐')}
                ${card('Best rating', num(s.bestRating).toFixed(1) + ' ⭐')}
            </div>`;
        }

        function levelName(level) {
            const l = ((st.config && st.config.levels) || []).find((x) => num(x.level) === level);
            return (l && (l.name || l.label)) || '';
        }

        function levelsHtml() {
            const levels = (st.config && st.config.levels) || [];
            if (!levels.length) return '<div class="pfj-bus-empty">No levels configured.</div>';
            const s = stats();
            const mult = (st.config && st.config.levelMultiplier) || {};
            return `<div class="pfj-bus-levels">${levels.map((l) => {
                const current = num(l.level) === num(s.level, 1);
                // a Lua list arrives as a JSON array (level 1 at index 0), a keyed table as an object
                const m = Array.isArray(mult) ? mult[num(l.level) - 1] : (mult[l.level] || mult[String(l.level)]);
                return `<div class="pfj-bus-level${current ? ' current' : ''}">
                    <div><div class="pfj-bus-title">Level ${num(l.level)}${l.name || l.label ? ' – ' + esc(l.name || l.label) : ''}</div>
                    <div class="pfj-bus-muted">Routes ${num(l.minRoutes)}–${num(l.maxRoutes) >= 99999 ? '∞' : num(l.maxRoutes)}${m ? ` • pay ×${num(m)}` : ''}</div></div>
                    <span class="pfj-bus-pill${current ? ' on' : ''}">${current ? 'Current' : num(l.level) < num(s.level, 1) ? 'Done' : 'Locked'}</span>
                </div>`;
            }).join('')}</div>`;
        }

        function render() {
            if (!alive) return;
            if (!st.v) {
                root.innerHTML = st.error
                    ? `<div class="pfj-bus-empty">${esc(st.error)}<br><br><button type="button" class="pfj-bus-btn primary" data-action="reload">Try again</button></div>`
                    : '<div class="pfj-bus-empty">Calling dispatch…</div>';
                return;
            }
            const body = st.tab === 'routes' ? routesHtml() : st.tab === 'stats' ? statsHtml() : st.tab === 'levels' ? levelsHtml() : dashboardHtml();
            root.innerHTML = `
                <div class="pfj-bus-header"><span class="pfj-bus-logo">🚌</span><div><div class="pfj-bus-h1">Bus Driver</div><div class="pfj-bus-muted light">City transit dispatch</div></div></div>
                <nav class="pfj-bus-tabs">${TABS.map(([id, icon, label]) => `<button type="button" class="pfj-bus-tab${st.tab === id ? ' active' : ''}" data-tab="${id}">${icon} ${esc(label)}</button>`).join('')}</nav>
                <div class="pfj-bus-body">${body}</div>`;
        }

        async function onClick(ev) {
            const tabEl = ev.target.closest('[data-tab]');
            if (tabEl && root.contains(tabEl)) {
                st.tab = tabEl.dataset.tab;
                ctx.storage.set('tab', st.tab);
                render();
                if (st.tab === 'routes') refreshSoon();
                return;
            }
            const el = ev.target.closest('[data-action]');
            if (!el || !root.contains(el) || el.disabled) return;
            switch (el.dataset.action) {
                case 'reload': await loadInit(); break;
                case 'goRoutes': st.tab = 'routes'; render(); break;
                case 'startRoute': {
                    const res = await act('startRoute:' + el.dataset.route, 'startRoute', { routeId: Number(el.dataset.route) });
                    if (res && res.ok) { st.tab = 'dashboard'; render(); }
                    break;
                }
                case 'checkInStop': await act('checkInStop', 'checkInStop'); break;
                case 'completeRoute': await act('completeRoute', 'completeRoute'); break;
                case 'cancelRoute': await act('cancelRoute', 'cancelRoute'); break;
                case 'takeBus': await act('takeBus:' + el.dataset.model, 'takeBus', { model: String(el.dataset.model || '') }); break;
                case 'returnBus': await act('returnBus', 'returnBus'); break;
                case 'waypoint': ctx.setWaypoint(Number(el.dataset.x), Number(el.dataset.y)); ctx.notify('GPS set', 'success'); break;
                default: break;
            }
        }
        root.addEventListener('click', onClick);

        ctx.on('stats', () => refreshSoon());
        ctx.on('routes', (routes) => { if (st.v && Array.isArray(routes)) { st.v.routes = routes; render(); } });
        ctx.on('route', () => refreshSoon());
        ctx.on('stop', () => refreshSoon());
        ctx.on('routeEnded', () => refreshSoon());
        ctx.on('bus', () => refreshSoon());

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
    PFApps.register('bus', {
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
