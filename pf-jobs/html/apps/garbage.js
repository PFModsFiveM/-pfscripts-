/*
 * Garbage app (pf-devices platform module): runs, crew and progression. One module for the tablet
 * and the computer, styled like the original (html/apps/gruppe6.css + garbage.css). Requests go
 * through ctx.rpc (server/devices.lua → server/apps/garbage.lua); XP, bag, zone and crew pushes come
 * through client/devices_bridge.lua. DOM work stays inside the container; server strings are escaped.
 */
(function () {
    'use strict';
    if (!window.PFApps) return;

    const ERRORS = {
        not_installed: 'Install Garbage from the App Store first',
        rate_limited: 'Slow down a little',
        timeout: 'The server did not answer',
        server_error: 'Something went wrong',
        request_failed: 'Could not reach the server',
        run_active: 'You already have a garbage run going',
        not_leader: 'Only the crew leader can do that',
    };
    const TABS = [['work', '🛠️', 'Work'], ['crew', '👥', 'Crew'], ['progress', '⚡', 'Progression']];

    function create(container, ctx) {
        const { esc, money } = ctx;
        const st = { tab: ctx.storage.get('tab', 'work'), s: null, config: null, status: null, busy: {}, error: null };
        let alive = true;
        let resizeObs = null;
        let refreshTimer = null;

        const root = document.createElement('div');
        root.className = 'pfj-g6 pfj-garb';
        container.appendChild(root);

        const num = (v, d = 0) => (Number.isFinite(Number(v)) ? Number(v) : d);
        const me = () => num(st.s && st.s.playerId, -1);
        const crew = () => (st.s && st.s.currentGroup) || null;
        const isLeader = () => !!crew() && num(crew().leader) === me();
        const levelCfg = (lvl) => ((st.config && st.config.levels) || []).find((l) => num(l.level) === lvl) || null;

        function report(res) {
            if (res && res.ok === false && res.error !== 'refused') ctx.notify(res.message || ERRORS[res.error] || 'That did not work', 'error');
            return res;
        }

        function applyState(s) {
            if (!s || typeof s !== 'object') return;
            st.s = Object.assign({}, st.s || {}, s);
            if (s.config) st.config = s.config;
            if (!st.s.active) st.status = null;
        }

        async function act(key, method, payload) {
            if (st.busy[key]) return null;
            st.busy[key] = true;
            render();
            let res;
            try { res = await ctx.rpc(method, payload); } finally { st.busy[key] = false; }
            if (!alive) return res;
            if (res && res.state) applyState(res.state);
            report(res);
            render();
            return res;
        }

        async function loadInit() {
            const res = await ctx.rpc('getInit');
            if (!alive) return;
            if (!res || res.ok === false) st.error = ERRORS[res && res.error] || 'The garbage depot is not answering';
            else { st.error = null; applyState(res); }
            render();
        }

        function refreshSoon() {
            if (refreshTimer) return;
            refreshTimer = setTimeout(() => { refreshTimer = null; loadInit(); }, 300);
        }

        function btn(action, label, cls, opts) {
            const key = action + (opts && opts.key != null ? ':' + opts.key : '');
            const busy = st.busy[key];
            const data = Object.entries((opts && opts.data) || {}).map(([k, v]) => ` data-${k}="${esc(v)}"`).join('');
            const disabled = busy || (opts && opts.disabled) ? ' disabled' : '';
            return `<button type="button" class="pfj-g6-btn ${cls || ''}" data-action="${action}"${data}${disabled}>${busy ? 'Working…' : esc(label)}</button>`;
        }

        function infoRow(icon, label, value) {
            return `<div class="pfj-g6-info"><span class="pfj-g6-info-label"><span>${icon}</span>${esc(label)}</span><span class="pfj-g6-info-value">${value}</span></div>`;
        }

        function xpInfo() {
            const lvl = num(st.s && st.s.level, 1);
            const xp = num(st.s && st.s.xp);
            const cur = levelCfg(lvl);
            const next = levelCfg(lvl + 1);
            const base = num(cur && cur.xp);
            if (!next) return { lvl, text: `${xp} XP • top level`, pct: 100 };
            const span = Math.max(1, num(next.xp) - base);
            return { lvl, text: `${Math.max(0, xp - base)} / ${span} XP`, pct: Math.min(100, Math.max(0, ((xp - base) / span) * 100)) };
        }

        function leftHtml() {
            const s = st.s || {};
            const lvl = num(s.level, 1);
            const cap = num(s.cap);
            const zone = s.zone;
            const memberOnly = crew() && !isLeader();
            const startLabel = s.active ? 'Run in progress' : memberOnly ? 'Your crew leader starts the run' : 'Start job';
            return `
                <div class="pfj-g6-contract">
                    <div class="pfj-g6-tier">Level ${lvl}</div>
                    <div class="pfj-g6-vehicle">Trashmaster</div>
                    <div class="pfj-garb-truck">🚛</div>
                    <div class="pfj-g6-infos">
                        ${infoRow('🛣️', 'Status', s.active ? 'On a run' : 'At the depot')}
                        ${s.active && s.plate ? infoRow('🚚', 'Truck', esc(s.plate)) : ''}
                        ${infoRow('🛍️', 'Carrying', s.carrying ? 'A bag' : 'Nothing')}
                        ${infoRow('📦', 'In the truck', `${num(s.deposited)}${cap && cap < 9999 ? ' / ' + cap : ''}`)}
                        ${s.active ? infoRow('💵', 'Paid bags', `${Math.min(num(s.collected), num(s.objectiveTarget, 10))} / ${num(s.objectiveTarget, 10)}`) : ''}
                        ${zone ? infoRow('📍', esc(zone.name || 'Zone'), `${num(zone.cleared)} / ${num(zone.target)} dumpsters`) : ''}
                    </div>
                    ${st.status ? `<div class="pfj-g6-stage">${esc(st.status)}</div>` : ''}
                    ${btn('startJob', startLabel, 'big', { disabled: !!s.active || memberOnly })}
                </div>`;
        }

        function workHtml() {
            const s = st.s || {};
            const cfg = st.config || {};
            const cur = levelCfg(num(s.level, 1)) || {};
            const target = num(s.objectiveTarget || cfg.objectiveTarget, 10);
            return `
                <div class="pfj-g6-card">
                    <div class="pfj-g6-card-title">How a run works</div>
                    <ol class="pfj-g6-steps">
                        <li>Start the job: your truck waits at the depot and the first zone shows on the map.</li>
                        <li>Take one bag at a time from dumpsters (or loose bags) inside the zone.</li>
                        <li>Throw it into the back of your truck. Clear ${num(cfg.dumpstersPerZone, 8)} dumpsters to move to the next zone.</li>
                        <li>Drive the truck back to the depot to end the run and get paid.</li>
                    </ol>
                </div>
                <div class="pfj-g6-card">
                    <div class="pfj-g6-card-title">Your pay</div>
                    <div class="pfj-garb-pay">
                        <div><strong>${money(cur.payPerBag)}</strong><span>per bag</span></div>
                        <div><strong>${target}</strong><span>paid bags per run</span></div>
                        <div><strong>${num(cfg.xpPerBag)}</strong><span>XP per bag</span></div>
                        ${cfg.crewBonus ? `<div><strong>${num(cfg.crewBonus)}×</strong><span>pool per member, in a crew</span></div>` : ''}
                    </div>
                    <div class="pfj-g6-muted">The truck holds ${cur.cap && num(cur.cap) < 9999 ? num(cur.cap) + ' bags' : 'as many bags as you can collect'} at your level. Pay is set by the level of whoever returns the truck.</div>
                </div>`;
        }

        function crewHtml() {
            const g = crew();
            const invites = (st.s && st.s.pendingInvites) || [];
            const max = num(st.config && st.config.maxMembers, 4);
            const mult = st.config && st.config.crewBonus;
            const floor = num(st.config && st.config.splitFloor, 10);
            const inviteBlock = invites.length ? `
                <div class="pfj-g6-invites">
                    <div class="pfj-g6-card-title">📬 Crew invites</div>
                    ${invites.map((inv) => `
                        <div class="pfj-g6-invite">
                            <div><strong>${esc(inv.leaderName || 'Leader')}</strong> <span class="pfj-g6-muted">ID ${num(inv.leaderId)}</span></div>
                            <div class="pfj-g6-row">
                                ${btn('acceptInvite', 'Accept', 'ok', { key: inv.leaderId, data: { leader: inv.leaderId } })}
                                ${btn('declineInvite', 'Decline', 'danger', { key: inv.leaderId, data: { leader: inv.leaderId } })}
                            </div>
                        </div>`).join('')}
                </div>` : '';
            if (!g) {
                return `${inviteBlock}
                    <div class="pfj-g6-card center">
                        <div class="pfj-g6-big-icon">👥</div>
                        <div class="pfj-g6-card-title">No crew</div>
                        <div class="pfj-g6-muted">Create a crew and share the code, or join one by code.${mult ? ` A crew run pays a pool of ${num(mult)}× the run's pay for every member; the leader decides the shares.` : ''}</div>
                        <div class="pfj-g6-row center">${btn('createGroup', 'Create crew', 'primary')}</div>
                        <div class="pfj-g6-row center">
                            <input class="pfj-g6-input" data-keep="code" maxlength="8" placeholder="Crew code" autocomplete="off">
                            ${btn('joinByCode', 'Join', 'gold')}
                        </div>
                    </div>`;
            }
            const leader = isLeader();
            const members = Array.isArray(g.members) ? g.members : [];
            return `${inviteBlock}
                <div class="pfj-g6-card">
                    <div class="pfj-g6-row between">
                        <div class="pfj-g6-code">Crew code <strong>${esc(g.groupCode || '------')}</strong></div>
                        ${btn('copyCode', 'Copy', 'ghost sm')}
                    </div>
                    <div class="pfj-g6-row between">
                        <div><div class="pfj-g6-card-title">${leader ? '👑 Your crew' : '👥 Crew'}</div><div class="pfj-g6-muted">${members.length + 1}/${max} members${leader ? ' • you start and end the runs' : ''}</div></div>
                        ${leader ? btn('disbandGroup', 'Close crew', 'danger') : btn('leaveGroup', 'Leave', 'ghost')}
                    </div>
                    <div class="pfj-g6-members">
                        <div class="pfj-g6-member leader">
                            <div class="pfj-g6-avatar gold">👑</div>
                            <div class="pfj-g6-grow"><strong>${leader ? 'You' : esc(g.leaderName || 'Leader')}</strong> <span class="pfj-g6-tag">Leader</span><div class="pfj-g6-muted">ID ${num(g.leader)}</div></div>
                        </div>
                        ${members.map((m) => `
                            <div class="pfj-g6-member${num(m.id) === me() ? ' you' : ''}">
                                <div class="pfj-g6-avatar">👤</div>
                                <div class="pfj-g6-grow"><strong>${esc(m.name || 'Member')}</strong>${num(m.id) === me() ? ' <span class="pfj-g6-tag">You</span>' : ''}<div class="pfj-g6-muted">ID ${num(m.id)}</div></div>
                                ${leader ? btn('kickMember', 'Kick', 'danger sm', { key: m.id, data: { target: m.id } }) : ''}
                            </div>`).join('')}
                    </div>
                    ${mult ? splitsHtml(g, leader, floor) : ''}
                    ${leader && members.length + 1 < max ? `
                        <div class="pfj-g6-subcard">
                            <div class="pfj-g6-card-title">✉️ Invite by server ID</div>
                            <div class="pfj-g6-row">
                                <input class="pfj-g6-input grow" data-keep="invite" type="number" min="1" placeholder="Player server ID">
                                ${btn('invitePlayer', 'Send invite', 'primary')}
                            </div>
                        </div>` : ''}
                </div>`;
        }

        // The leader's shares of the crew pool; members see them read-only.
        function splitsHtml(g, leader, floor) {
            const splits = Array.isArray(g.splits) ? g.splits : [];
            if (splits.length < 2) return '';
            const names = { [num(g.leader)]: leader ? 'You' : (g.leaderName || 'Leader') };
            (g.members || []).forEach((m) => { names[num(m.id)] = num(m.id) === me() ? 'You' : (m.name || 'Member'); });
            const shares = {};
            ((st.s && st.s.payShares) || []).forEach((x) => { shares[num(x.id)] = x; });
            return `
                <div class="pfj-g6-subcard">
                    <div class="pfj-g6-card-title">💵 Shares of the pool</div>
                    <div class="pfj-g6-muted">${leader ? `Whole percent, at least ${floor}% each, adding up to 100.` : 'Set by your crew leader.'}${st.s && st.s.active ? ' Amounts are what the run pays if it ended now.' : ''}</div>
                    ${splits.map((x) => `
                        <div class="pfj-g6-row between">
                            <span>${esc(names[num(x.id)] || ('ID ' + num(x.id)))}</span>
                            <span class="pfj-g6-row">
                                ${leader ? `<input class="pfj-g6-input" data-keep="split-${num(x.id)}" data-split-id="${num(x.id)}" type="number" min="${floor}" max="100" step="1" value="${num(x.pct)}" style="width:80px">%` : `<strong>${num(x.pct)}%</strong>`}
                                ${shares[num(x.id)] && st.s && st.s.active ? `<span class="pfj-g6-muted">${money(shares[num(x.id)].amount)}</span>` : ''}
                            </span>
                        </div>`).join('')}
                    ${leader ? `<div class="pfj-g6-row">${btn('saveSplits', 'Save shares', 'primary sm')}</div>` : ''}
                </div>`;
        }

        function progressHtml() {
            const lvl = num(st.s && st.s.level, 1);
            const levels = (st.config && st.config.levels) || [];
            const areaName = (a) => String(a || '').replace(/^\w/, (c) => c.toUpperCase());
            return `
                <div class="pfj-g6-card">
                    <div class="pfj-g6-card-title">Levels</div>
                    <div class="pfj-g6-muted">Every bag thrown into the truck gives ${num(st.config && st.config.xpPerBag)} XP. Higher levels pay more per bag and open more areas.</div>
                    <div class="pfj-g6-tiers">
                        ${levels.map((l) => `
                            <div class="pfj-g6-tier-row${num(l.level) <= lvl ? ' open' : ''}">
                                <div><strong>Level ${num(l.level)}</strong><div class="pfj-g6-muted">${num(l.xp).toLocaleString()} XP</div></div>
                                <div class="pfj-g6-pay">${money(l.payPerBag)} / bag</div>
                                <div class="pfj-g6-muted">${l.cap && num(l.cap) < 9999 ? num(l.cap) + ' bags' : 'No bag limit'}</div>
                                <div class="pfj-g6-muted">${esc((l.areas || []).map(areaName).join(', ') || '—')}</div>
                            </div>`).join('')}
                    </div>
                </div>`;
        }

        function keepInputs(fn) {
            const saved = {};
            root.querySelectorAll('[data-keep]').forEach((el) => { saved[el.dataset.keep] = el.value; });
            const active = document.activeElement;
            const focused = active && root.contains(active) && active.dataset ? active.dataset.keep : null;
            fn();
            Object.keys(saved).forEach((k) => { const el = root.querySelector(`[data-keep="${k}"]`); if (el) el.value = saved[k]; });
            if (focused) { const el = root.querySelector(`[data-keep="${focused}"]`); if (el) el.focus(); }
        }

        function render() {
            if (!alive) return;
            if (!st.s) {
                root.innerHTML = st.error
                    ? `<div class="pfj-g6-empty">${esc(st.error)}<br><br><button type="button" class="pfj-g6-btn primary" data-action="reload">Try again</button></div>`
                    : '<div class="pfj-g6-empty">Calling the depot…</div>';
                return;
            }
            const x = xpInfo();
            const invites = ((st.s && st.s.pendingInvites) || []).length;
            const right = st.tab === 'crew' ? crewHtml() : st.tab === 'progress' ? progressHtml() : workHtml();
            keepInputs(() => {
                root.innerHTML = `
                    <div class="pfj-g6-top">
                        <div class="pfj-g6-brand"><div class="pfj-g6-logo">🚚</div><div><div class="pfj-g6-title">Garbage</div><div class="pfj-g6-muted">Sanitation crew</div></div></div>
                        <div class="pfj-g6-tabs">${TABS.map(([id, icon, label]) => `<button type="button" class="pfj-g6-tab${st.tab === id ? ' active' : ''}" data-tab="${id}"><span>${icon}</span>${esc(label)}${id === 'crew' && invites ? ` <em>${invites}</em>` : ''}</button>`).join('')}</div>
                        <div class="pfj-g6-prog"><div class="pfj-g6-prog-head">⚡ Level ${x.lvl}</div><div class="pfj-g6-bar"><div style="width:${x.pct.toFixed(1)}%"></div></div><div class="pfj-g6-muted">${esc(x.text)}</div></div>
                    </div>
                    <div class="pfj-g6-main">
                        <div class="pfj-g6-left">${leftHtml()}</div>
                        <div class="pfj-g6-right">${right}</div>
                    </div>`;
            });
        }

        async function onClick(ev) {
            const tabEl = ev.target.closest('[data-tab]');
            if (tabEl && root.contains(tabEl)) {
                st.tab = tabEl.dataset.tab;
                ctx.storage.set('tab', st.tab);
                render();
                return;
            }
            const el = ev.target.closest('[data-action]');
            if (!el || !root.contains(el) || el.disabled) return;
            const value = (k) => { const i = root.querySelector(`[data-keep="${k}"]`); return i ? String(i.value || '').trim() : ''; };
            switch (el.dataset.action) {
                case 'reload': await loadInit(); break;
                case 'startJob': await act('startJob', 'startJob'); break;
                case 'createGroup': await act('createGroup', 'createGroup'); break;
                case 'joinByCode': {
                    const code = value('code').toUpperCase();
                    if (!code) { ctx.notify('Enter a crew code', 'error'); break; }
                    await act('joinByCode', 'joinByCode', { code });
                    break;
                }
                case 'invitePlayer': {
                    const id = parseInt(value('invite'), 10);
                    if (!id) { ctx.notify('Enter a player server ID', 'error'); break; }
                    const res = await act('invitePlayer', 'invitePlayer', { targetId: id });
                    if (res && res.ok) { const i = root.querySelector('[data-keep="invite"]'); if (i) i.value = ''; }
                    break;
                }
                case 'acceptInvite': await act('acceptInvite:' + el.dataset.leader, 'acceptInvite', { leaderId: Number(el.dataset.leader) }); break;
                case 'declineInvite': {
                    const leader = Number(el.dataset.leader);
                    const res = await act('declineInvite:' + leader, 'declineInvite', { leaderId: leader });
                    if (res && res.ok && st.s) { st.s.pendingInvites = (st.s.pendingInvites || []).filter((i) => num(i.leaderId) !== leader); render(); }
                    break;
                }
                case 'kickMember': await act('kickMember:' + el.dataset.target, 'kickMember', { targetId: Number(el.dataset.target) }); break;
                case 'leaveGroup': await act('leaveGroup', 'leaveGroup'); break;
                case 'disbandGroup': await act('disbandGroup', 'disbandGroup'); break;
                case 'saveSplits': {
                    const splits = [...root.querySelectorAll('[data-split-id]')].map((i) => ({ id: Number(i.dataset.splitId), pct: Math.round(Number(i.value)) }));
                    const total = splits.reduce((n, x) => n + (Number.isFinite(x.pct) ? x.pct : 0), 0);
                    if (total !== 100) { ctx.notify(`The shares add up to ${total}%, not 100%`, 'error'); break; }
                    const res = await act('saveSplits', 'setSplits', { splits });
                    if (res && res.ok) ctx.notify('Shares saved', 'success');
                    break;
                }
                case 'copyCode': {
                    const code = crew() && crew().groupCode;
                    if (code && navigator.clipboard && navigator.clipboard.writeText) {
                        navigator.clipboard.writeText(String(code)).then(() => ctx.notify('Code copied', 'success')).catch(() => ctx.notify('Code: ' + code, 'primary'));
                    } else if (code) ctx.notify('Code: ' + code, 'primary');
                    break;
                }
                default: break;
            }
        }
        root.addEventListener('click', onClick);
        root.addEventListener('keydown', (ev) => {
            if (ev.key !== 'Enter' || !ev.target.dataset) return;
            const target = ev.target.dataset.keep === 'code' ? 'joinByCode' : ev.target.dataset.keep === 'invite' ? 'invitePlayer' : null;
            const b = target && root.querySelector(`[data-action="${target}"]`);
            if (b) b.click();
        });

        const patch = (fields) => { if (st.s) { Object.assign(st.s, fields); render(); } };
        ctx.on('xp', (p) => p && patch({ xp: num(p.xp), level: num(p.level, 1) }));
        ctx.on('carrying', (p) => patch({ carrying: !!(p && p.carrying) }));
        ctx.on('deposited', (p) => p && patch({ deposited: num(p.count), cap: num(p.cap, st.s && st.s.cap) }));
        ctx.on('group', (p) => patch({ currentGroup: (p && p.group) || null }));
        ctx.on('invite', (inv) => {
            if (!st.s || !inv) return;
            const list = st.s.pendingInvites || [];
            if (!list.some((i) => num(i.leaderId) === num(inv.leaderId))) list.push(inv);
            patch({ pendingInvites: list });
        });
        ctx.on('status', (p) => { st.status = p && p.text ? String(p.text) : null; refreshSoon(); });
        ctx.on('zone', () => refreshSoon());
        ctx.on('started', () => refreshSoon());
        ctx.on('ended', () => { st.status = null; refreshSoon(); });

        if (typeof ResizeObserver === 'function') {
            resizeObs = new ResizeObserver(() => root.classList.toggle('is-narrow', container.clientWidth < 820));
            resizeObs.observe(container);
        }
        root.classList.toggle('is-narrow', container.clientWidth > 0 && container.clientWidth < 820);

        render();
        return {
            start: loadInit,
            destroy() {
                alive = false;
                if (refreshTimer) clearTimeout(refreshTimer);
                if (resizeObs) resizeObs.disconnect();
                root.removeEventListener('click', onClick);
            },
        };
    }

    let instance = null;
    PFApps.register('garbage', {
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
