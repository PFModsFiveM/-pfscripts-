/*
 * Taxi app (pf-devices platform module): the same module runs in the tablet and the computer.
 * Everything goes through ctx.rpc (server/devices.lua → server/apps/taxi.lua) and server pushes
 * forwarded by client/devices_bridge.lua (calls, rides, stats, rentals) and client/taxi.lua (meter).
 * All DOM work stays inside the container the shell gives us; every server string is escaped.
 */
(function () {
    'use strict';
    if (!window.PFApps) return;

    const NUI_BASE = 'https://cfx-nui-pf-jobs/html/';
    const POLL_MS = 5000;
    const ERRORS = {
        not_authorized: 'You need to work for the taxi company to use this app',
        rate_limited: 'Slow down a little',
        timeout: 'The server did not answer',
        server_error: 'Something went wrong',
        request_failed: 'Could not reach the server',
        rental_active: 'Return your current rental first',
        no_rental: 'You have no rental to return',
        no_active_ride: 'That ride is no longer active',
    };
    const TABS = [
        ['dashboard', 'Dashboard'],
        ['calls', 'Calls'],
        ['levels', 'Levels'],
        ['rentals', 'Rentals'],
        ['photos', 'Photos'],
    ];

    function create(container, ctx) {
        const { esc, money } = ctx;
        const st = {
            tab: ctx.storage.get('tab', 'dashboard'),
            dashboard: null,
            calls: [],
            photos: null,
            meter: null,
            lastRide: null,
            levelIndex: null,
            busy: {},
            error: null,
        };
        let pollTimer = null;
        let resizeObs = null;
        let alive = true;

        const root = document.createElement('div');
        root.className = 'pfj-taxi';
        container.appendChild(root);

        // ── helpers ───────────────────────────────────────────
        const num = (v, d = 0) => (Number.isFinite(Number(v)) ? Number(v) : d);
        const level = () => num(st.dashboard && st.dashboard.level, 1);
        const levels = () => (st.dashboard && Array.isArray(st.dashboard.levels) ? st.dashboard.levels : []);
        const visibleCalls = () => (st.calls || []).filter((c) => num(c.requiredLevel, 1) <= level());
        const ride = () => (st.dashboard && st.dashboard.activeRide) || null;

        function report(res) {
            if (res && res.ok === false && res.error !== 'refused') {
                ctx.notify(res.message || ERRORS[res.error] || 'That did not work', 'error');
            }
            return res;
        }

        async function act(key, method, payload) {
            if (st.busy[key]) return null;
            st.busy[key] = true;
            render();
            let res;
            try { res = await ctx.rpc(method, payload); } finally { st.busy[key] = false; }
            if (!alive) return res;
            if (res && res.dashboard) setDashboard(res.dashboard);
            report(res);
            render();
            return res;
        }

        function setDashboard(d) {
            if (!d || typeof d !== 'object') return;
            st.dashboard = d;
            if (st.levelIndex == null) {
                const idx = levels().findIndex((l) => num(l.level, 1) === level());
                st.levelIndex = idx >= 0 ? idx : 0;
            }
            schedulePoll();
        }

        function schedulePoll() {
            const on = !!(st.dashboard && st.dashboard.accepting);
            if (on && !pollTimer) pollTimer = setInterval(loadCalls, POLL_MS);
            if (!on && pollTimer) { clearInterval(pollTimer); pollTimer = null; st.calls = []; }
        }

        async function loadInit() {
            const res = await ctx.rpc('getInit');
            if (!alive) return;
            if (!res || res.ok === false) {
                st.error = ERRORS[res && res.error] || 'The taxi service is not answering';
            } else {
                st.error = null;
                setDashboard(res.dashboard);
            }
            render();
        }

        async function loadCalls() {
            const res = await ctx.rpc('getCalls');
            if (!alive || !res || res.ok === false) return;
            st.calls = Array.isArray(res.calls) ? res.calls : [];
            render();
        }

        async function loadPhotos() {
            const res = await ctx.rpc('getPhotos');
            if (!alive) return;
            st.photos = res && res.ok !== false && Array.isArray(res.photos) ? res.photos : [];
            render();
        }

        function imageUrl(path) {
            if (typeof path !== 'string' || !path) return '';
            if (/^https?:\/\//i.test(path) || /^nui:\/\//i.test(path)) return path;
            return NUI_BASE + path.replace(/^\/+/, '');
        }

        function badges(call) {
            const out = [];
            if (call.vip) out.push('<span class="pfj-taxi-badge vip">VIP</span>');
            if (call.playerClient) out.push('<span class="pfj-taxi-badge player">Player</span>');
            if (call.premium && !call.vip) out.push('<span class="pfj-taxi-badge premium">Premium</span>');
            if (!call.vip && !call.premium) out.push('<span class="pfj-taxi-badge standard">Standard</span>');
            return out.join('');
        }

        function btn(action, label, cls, attrs) {
            const busy = st.busy[action + (attrs && attrs.key ? ':' + attrs.key : '')];
            const data = Object.entries((attrs && attrs.data) || {})
                .map(([k, v]) => ` data-${k}="${esc(v)}"`).join('');
            const disabled = busy || (attrs && attrs.disabled) ? ' disabled' : '';
            return `<button type="button" class="pfj-taxi-btn ${cls || ''}" data-action="${action}"${data}${disabled}>${busy ? 'Working…' : esc(label)}</button>`;
        }

        // ── views ─────────────────────────────────────────────
        function headerHtml() {
            const d = st.dashboard || {};
            const accepting = d.accepting === true;
            return `
                <header class="pfj-taxi-header">
                    <div class="pfj-taxi-brand">
                        <div class="pfj-taxi-logo">🚕</div>
                        <div>
                            <div class="pfj-taxi-title">Taxi Dispatch Center</div>
                            <div class="pfj-taxi-sub">${esc(d.levelTitle || 'Driver')} • Level ${level()}</div>
                        </div>
                    </div>
                    <div class="pfj-taxi-actions">
                        ${btn('toggle', accepting ? 'Stop Accepting' : 'Start Accepting', accepting ? 'on' : 'off')}
                        ${btn('refresh', 'Refresh', 'ghost')}
                    </div>
                </header>
                <nav class="pfj-taxi-tabs">
                    ${TABS.map(([id, label]) => `<button type="button" class="pfj-taxi-tab${st.tab === id ? ' active' : ''}" data-tab="${id}">${esc(label)}${id === 'calls' ? ` (${visibleCalls().length})` : ''}</button>`).join('')}
                </nav>`;
        }

        function rideHtml() {
            const r = ride();
            if (!r) return '';
            const onBoard = r.stage === 'destination';
            const dest = (r.destination && r.destination.label) || 'Destination';
            return `
                <section class="pfj-taxi-ride ${r.vip ? 'vip' : ''}">
                    <div class="pfj-taxi-ride-top">
                        <div>
                            <div class="pfj-taxi-label">Active ride</div>
                            <div class="pfj-taxi-ride-client">${esc(r.clientName || 'Client')} ${r.vip ? '👑' : ''}</div>
                        </div>
                        <div class="pfj-taxi-badges">${badges(r)}</div>
                    </div>
                    <div class="pfj-taxi-ride-meta">
                        <span>${onBoard ? '🧍 Passenger on board' : '📍 Head to the pickup'}</span>
                        <span>➡️ ${esc(dest)}</span>
                        <span>${num(r.distanceMiles).toFixed(1)} mi</span>
                    </div>
                    <div class="pfj-taxi-row">
                        ${btn('gps', onBoard ? 'GPS to destination' : 'GPS to pickup', 'ghost')}
                        ${onBoard ? btn('complete', 'Complete ride', 'primary') : ''}
                        ${btn('cancelRide', 'Cancel ride', 'danger')}
                    </div>
                </section>`;
        }

        function meterHtml() {
            const m = st.meter;
            if (!(m && m.visible && m.inTaxi)) {
                return '<div class="pfj-taxi-empty">Meter is off.<br><small>It runs while you drive a taxi on a ride (or with /taximeter).</small></div>';
            }
            const collisions = num(m.collisions);
            const penalty = Math.round(num(m.penaltyPct) * 100) || Math.min(100, collisions * 5);
            return `
                <div class="pfj-taxi-meter ${esc(m.passengerType || 'standard')}">
                    <div class="pfj-taxi-meter-row"><span>Passenger</span><strong>${esc(m.passengerName || 'Customer')}</strong></div>
                    <div class="pfj-taxi-meter-row"><span>Fare</span><strong class="pfj-taxi-fare">${money(m.currentFare)}</strong></div>
                    <div class="pfj-taxi-chips">
                        <span class="pfj-taxi-chip">Distance ${num(m.distance).toFixed(2)} mi</span>
                        <span class="pfj-taxi-chip">Rate ${money(m.rate)}/mi</span>
                        <span class="pfj-taxi-chip warn">Collisions ${collisions}</span>
                        <span class="pfj-taxi-chip warn">Penalty -${penalty}%</span>
                    </div>
                </div>`;
        }

        function dashboardHtml() {
            const d = st.dashboard || {};
            const next = d.nextLevel;
            const cur = levels().find((l) => num(l.level, 1) === level());
            const base = num(cur && cur.xp);
            const pct = next ? Math.max(0, Math.min(100, ((num(d.xp) - base) / Math.max(1, num(next.xpRequired) - base)) * 100)) : 100;
            const last = st.lastRide;
            return `
                ${rideHtml()}
                <div class="pfj-taxi-stats">
                    <div class="pfj-taxi-stat"><div class="pfj-taxi-label">Rating</div><div class="pfj-taxi-stat-value">${num(d.rating, 5).toFixed(1)} ⭐</div></div>
                    <div class="pfj-taxi-stat money"><div class="pfj-taxi-label">This shift</div><div class="pfj-taxi-stat-value">${money(d.earningsRun)}</div></div>
                    <div class="pfj-taxi-stat"><div class="pfj-taxi-label">Rides this shift</div><div class="pfj-taxi-stat-value">${num(d.ridesCompletedRun)}</div></div>
                    <div class="pfj-taxi-stat"><div class="pfj-taxi-label">XP</div><div class="pfj-taxi-stat-value">${Math.floor(num(d.xp))}</div></div>
                </div>
                <section class="pfj-taxi-panel">
                    <div class="pfj-taxi-section">Progress</div>
                    <div class="pfj-taxi-bar"><div style="width:${pct.toFixed(1)}%"></div></div>
                    <div class="pfj-taxi-muted">${next ? `Level ${num(next.level)} at ${num(next.xpRequired)} XP — unlocks ${esc(next.unlocks || 'more')}` : 'Maximum level reached'}</div>
                </section>
                ${last ? `
                <section class="pfj-taxi-panel">
                    <div class="pfj-taxi-section">Last ride</div>
                    <div class="pfj-taxi-chips">
                        <span class="pfj-taxi-chip">${esc(last.clientName || 'Client')}</span>
                        <span class="pfj-taxi-chip good">+${money(last.fare)}</span>
                        <span class="pfj-taxi-chip">+${num(last.xp)} XP</span>
                        <span class="pfj-taxi-chip">${num(last.rating, 5).toFixed(1)} ⭐</span>
                        ${num(last.collisions) > 0 ? `<span class="pfj-taxi-chip warn">${num(last.collisions)} collision(s)</span>` : ''}
                    </div>
                </section>` : ''}
                <div class="pfj-taxi-split">
                    <section class="pfj-taxi-panel">
                        <div class="pfj-taxi-section">Career</div>
                        <div class="pfj-taxi-mini">
                            <div><strong>${num(d.totalRides)}</strong><span>Rides</span></div>
                            <div><strong>${money(d.totalEarnings)}</strong><span>Earned</span></div>
                            <div><strong>${num(d.totalMiles).toFixed(1)}</strong><span>Miles</span></div>
                        </div>
                        ${d.rental ? `<div class="pfj-taxi-muted">Rented cab: <strong>${esc(d.rental.plate || '')}</strong></div>` : ''}
                    </section>
                    <section class="pfj-taxi-panel">
                        <div class="pfj-taxi-section">Taxi meter</div>
                        ${meterHtml()}
                    </section>
                </div>`;
        }

        function callCard(call, compact) {
            const blocked = !!ride();
            const dest = (call.destination && call.destination.label) || 'Unknown';
            return `
                <div class="pfj-taxi-call ${call.vip ? 'vip' : ''} ${compact ? 'compact' : ''}">
                    <div class="pfj-taxi-call-top">
                        <div class="pfj-taxi-call-client">${esc(call.clientName || 'Client')} ${call.vip ? '👑' : ''}</div>
                        ${compact ? '' : `<div class="pfj-taxi-badges">${badges(call)}</div>`}
                    </div>
                    <div class="pfj-taxi-call-meta">
                        <span>➡️ ${esc(dest)}</span>
                        ${compact ? '' : `<span>${num(call.distanceMiles).toFixed(1)} mi</span><span>Level ${num(call.requiredLevel, 1)}</span>`}
                        <span class="pfj-taxi-pay">${call.playerClient ? 'Fare hidden' : money(call.payPreview)}</span>
                    </div>
                    ${btn('accept', blocked ? 'Finish your ride first' : 'Accept call', 'primary', { key: call.id, data: { id: call.id }, disabled: blocked })}
                </div>`;
        }

        function callsHtml() {
            if (!(st.dashboard && st.dashboard.accepting)) return '<div class="pfj-taxi-empty">Start accepting rides to receive calls.</div>';
            const calls = visibleCalls();
            if (!calls.length) return '<div class="pfj-taxi-empty">No calls for your level right now. New calls come in while you are accepting.</div>';
            return `<div class="pfj-taxi-calls">${calls.map((c) => callCard(c, false)).join('')}</div>`;
        }

        function levelsHtml() {
            const list = levels();
            if (!list.length) return '<div class="pfj-taxi-empty">No levels configured.</div>';
            const i = Math.max(0, Math.min(num(st.levelIndex), list.length - 1));
            st.levelIndex = i;
            const sel = list[i];
            const selLevel = num(sel.level, i + 1);
            const next = list.find((l) => num(l.level, 1) > selLevel);
            const xp = num(st.dashboard && st.dashboard.xp);
            let pct = 0;
            if (selLevel < level()) pct = 100;
            else if (selLevel === level()) pct = next ? Math.max(0, Math.min(100, ((xp - num(sel.xp)) / Math.max(1, num(next.xp) - num(sel.xp))) * 100)) : 100;
            const unlocked = selLevel <= level();
            return `
                <div class="pfj-taxi-levels">
                    <button type="button" class="pfj-taxi-arrow" data-action="levelPrev"${i === 0 ? ' disabled' : ''}>‹</button>
                    <div class="pfj-taxi-level ${unlocked ? 'unlocked' : 'locked'} ${selLevel === level() ? 'current' : ''}">
                        <div class="pfj-taxi-level-head">
                            <div class="pfj-taxi-level-title">Level ${selLevel} • ${esc(sel.title || 'Driver')}</div>
                            <div class="pfj-taxi-badge ${unlocked ? 'standard' : 'premium'}">${unlocked ? 'Unlocked' : 'Locked'}</div>
                        </div>
                        <div class="pfj-taxi-muted">Required XP: ${num(sel.xp)}</div>
                        <div class="pfj-taxi-level-unlocks">${esc(sel.unlocks || 'No unlocks listed')}</div>
                        <div class="pfj-taxi-bar"><div style="width:${pct.toFixed(1)}%"></div></div>
                        <div class="pfj-taxi-muted">${next ? `Your XP ${xp} • Level ${num(next.level)} at ${num(next.xp)} XP` : 'Top level'}</div>
                    </div>
                    <button type="button" class="pfj-taxi-arrow" data-action="levelNext"${i >= list.length - 1 ? ' disabled' : ''}>›</button>
                </div>
                <div class="pfj-taxi-muted center">Level ${i + 1} of ${list.length}</div>`;
        }

        function rentalsHtml() {
            const d = st.dashboard || {};
            const list = Array.isArray(d.rentalVehicles) ? d.rentalVehicles : [];
            const current = d.rental;
            const cards = list.map((v) => {
                const unlock = num(v.unlockLevel, 1);
                const locked = level() < unlock;
                const img = imageUrl(v.image);
                const total = num(v.rental) + num(v.deposit);
                return `
                    <div class="pfj-taxi-rental ${locked ? 'locked' : ''}">
                        <div class="pfj-taxi-rental-img">${img ? `<img src="${esc(img)}" alt="">` : ''}<span>🚖</span></div>
                        <div class="pfj-taxi-rental-name">${esc(v.name || v.spawnCode || 'Vehicle')}</div>
                        <div class="pfj-taxi-muted">Level ${unlock} • ${num(v.maxCapacity, 2)} seats</div>
                        <div class="pfj-taxi-muted">Rent ${money(v.rental)} + deposit ${money(v.deposit)}</div>
                        ${btn('rent', locked ? `Unlocks at level ${unlock}` : (current ? 'Return yours first' : `Rent for ${money(total)}`), 'primary', { key: v.spawnCode, data: { code: v.spawnCode || '' }, disabled: locked || !!current })}
                    </div>`;
            }).join('');
            return `
                <section class="pfj-taxi-panel">
                    <div class="pfj-taxi-row between">
                        <div>
                            <div class="pfj-taxi-section">Your rental</div>
                            <div class="pfj-taxi-muted">${current ? `Plate ${esc(current.plate || '')} • deposit ${money(current.deposit)} back if it comes back undamaged` : 'No cab rented. The deposit is refunded when you return an undamaged cab.'}</div>
                        </div>
                        ${current ? btn('return', 'Return rental', 'danger') : ''}
                    </div>
                </section>
                ${list.length ? `<div class="pfj-taxi-rentals">${cards}</div>` : '<div class="pfj-taxi-empty">No rental cabs configured.</div>'}`;
        }

        function photosHtml() {
            if (st.dashboard && st.dashboard.photosEnabled === false) return '<div class="pfj-taxi-empty">Photo records need the taxi database (Config.Taxi.UseDatabase).</div>';
            if (st.photos == null) return '<div class="pfj-taxi-empty">Loading photos…</div>';
            const head = `<div class="pfj-taxi-row between"><div class="pfj-taxi-muted">Use /vehiclephoto next to a vehicle to log a photo.</div>${btn('photos', 'Refresh', 'ghost')}</div>`;
            if (!st.photos.length) return head + '<div class="pfj-taxi-empty">📸 No photos logged yet.</div>';
            return head + `<div class="pfj-taxi-photos">${st.photos.map((p) => `
                <div class="pfj-taxi-photo">
                    <div class="pfj-taxi-photo-icon">📸</div>
                    <div class="pfj-taxi-photo-name">${esc(p.filename || 'photo')}</div>
                    <div class="pfj-taxi-muted">${esc(p.model || 'Unknown')} • ${esc(p.plate || 'N/A')}</div>
                    <div class="pfj-taxi-muted">${esc(p.timestamp || '')}</div>
                </div>`).join('')}</div>`;
        }

        function sideHtml() {
            const calls = visibleCalls();
            return `
                <div class="pfj-taxi-side-head"><span>Active calls</span><span class="pfj-taxi-count">${calls.length}</span></div>
                <div class="pfj-taxi-side-list">
                    ${calls.length ? calls.slice(0, 4).map((c) => callCard(c, true)).join('') : `<div class="pfj-taxi-empty small">${st.dashboard && st.dashboard.accepting ? 'Waiting for calls…' : 'Not accepting rides.'}</div>`}
                    ${calls.length > 4 ? `<div class="pfj-taxi-more">+${calls.length - 4} more in Calls</div>` : ''}
                </div>`;
        }

        function bodyHtml() {
            switch (st.tab) {
                case 'calls': return callsHtml();
                case 'levels': return levelsHtml();
                case 'rentals': return rentalsHtml();
                case 'photos': return photosHtml();
                default: return dashboardHtml();
            }
        }

        function render() {
            if (!alive) return;
            if (st.error && !st.dashboard) {
                root.innerHTML = `<div class="pfj-taxi-empty">${esc(st.error)}<br><br><button type="button" class="pfj-taxi-btn primary" data-action="refresh">Try again</button></div>`;
                return;
            }
            if (!st.dashboard) {
                root.innerHTML = '<div class="pfj-taxi-empty">Loading Taxi Dispatch…</div>';
                return;
            }
            const oldBody = root.querySelector('.pfj-taxi-body');
            const scroll = oldBody ? oldBody.scrollTop : 0;
            root.innerHTML = `${headerHtml()}
                <div class="pfj-taxi-content">
                    <main class="pfj-taxi-body">${bodyHtml()}</main>
                    <aside class="pfj-taxi-side">${sideHtml()}</aside>
                </div>`;
            const body = root.querySelector('.pfj-taxi-body');
            if (body) body.scrollTop = scroll;
            root.querySelectorAll('.pfj-taxi-rental-img img').forEach((img) => {
                img.addEventListener('error', () => img.remove(), { once: true });
                img.addEventListener('load', () => img.parentNode && img.parentNode.classList.add('has-img'), { once: true });
            });
        }

        // ── interactions ──────────────────────────────────────
        async function onClick(ev) {
            const tabEl = ev.target.closest('[data-tab]');
            if (tabEl && root.contains(tabEl)) {
                st.tab = tabEl.dataset.tab;
                ctx.storage.set('tab', st.tab);
                render();
                if (st.tab === 'photos') loadPhotos();
                if (st.tab === 'calls' && st.dashboard && st.dashboard.accepting) loadCalls();
                return;
            }
            const el = ev.target.closest('[data-action]');
            if (!el || !root.contains(el) || el.disabled) return;
            const r = ride();
            switch (el.dataset.action) {
                case 'refresh': await loadInit(); if (st.dashboard && st.dashboard.accepting) loadCalls(); break;
                case 'toggle': {
                    const res = await act('toggle', 'toggleAccepting', { accepting: !(st.dashboard && st.dashboard.accepting) });
                    if (res && res.ok && st.dashboard.accepting) loadCalls();
                    break;
                }
                case 'accept': {
                    const id = el.dataset.id;
                    const res = await act('accept:' + id, 'acceptCall', { id });
                    if (res && res.ok) { st.calls = st.calls.filter((c) => c.id !== id); st.tab = 'dashboard'; render(); }
                    break;
                }
                case 'complete': if (r) await act('complete', 'completeRide', { rideId: r.id }); break;
                case 'cancelRide': if (r) await act('cancelRide', 'cancelRide', { rideId: r.id }); break;
                case 'gps': {
                    const p = r && (r.stage === 'destination' ? r.destination : r.pickup);
                    if (p) { ctx.setWaypoint(num(p.x), num(p.y)); ctx.notify('GPS set', 'success'); }
                    break;
                }
                case 'rent': await act('rent:' + el.dataset.code, 'rentVehicle', { spawnCode: el.dataset.code }); break;
                case 'return': await act('return', 'returnVehicle', {}); break;
                case 'photos': st.photos = null; render(); await loadPhotos(); break;
                case 'levelPrev': st.levelIndex = Math.max(0, num(st.levelIndex) - 1); render(); break;
                case 'levelNext': st.levelIndex = num(st.levelIndex) + 1; render(); break;
                default: break;
            }
        }
        root.addEventListener('click', onClick);

        // ── server pushes ─────────────────────────────────────
        ctx.on('updateStats', (d) => { setDashboard(d); render(); });
        ctx.on('callsData', (calls) => { st.calls = Array.isArray(calls) ? calls : []; render(); });
        ctx.on('startCall', () => loadInit());
        ctx.on('rideStarted', () => loadInit());
        ctx.on('rideCompleted', (data) => { st.lastRide = data || null; st.meter = null; loadInit(); });
        ctx.on('rideCancelled', () => { st.meter = null; loadInit(); });
        ctx.on('rental', () => loadInit());
        ctx.on('meter', (m) => {
            st.meter = m && typeof m === 'object' ? m : null;
            if (st.tab === 'dashboard') render();
        });

        if (typeof ResizeObserver === 'function') {
            resizeObs = new ResizeObserver(() => root.classList.toggle('is-narrow', container.clientWidth < 720));
            resizeObs.observe(container);
        }
        root.classList.toggle('is-narrow', container.clientWidth > 0 && container.clientWidth < 720);

        render();
        return {
            start: loadInit,
            destroy() {
                alive = false;
                if (pollTimer) clearInterval(pollTimer);
                if (resizeObs) resizeObs.disconnect();
                root.removeEventListener('click', onClick);
            },
        };
    }

    let instance = null;
    PFApps.register('taxi', {
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
