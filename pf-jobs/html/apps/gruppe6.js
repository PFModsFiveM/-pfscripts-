/*
 * Gruppe 6 app (pf-devices platform module): cash transport contracts, parties and progression.
 * One module for the tablet and the computer. Requests go through ctx.rpc (server/devices.lua →
 * server/apps/gruppe6.lua); contract, XP and party pushes come through client/devices_bridge.lua.
 * DOM work stays inside the given container; every server string is escaped.
 */
(function () {
    'use strict';
    if (!window.PFApps) return;

    const ERRORS = {
        not_installed: 'Install Gruppe 6 from the App Store first',
        rate_limited: 'Slow down a little',
        timeout: 'The server did not answer',
        server_error: 'Something went wrong',
        request_failed: 'Could not reach the server',
        contract_active: 'Finish or end your contract first',
        not_leader: 'Only the party leader can do that',
    };
    const TABS = [['contracts', '📋', 'Contracts'], ['work', '🛠️', 'Work'], ['party', '👥', 'Party'], ['progress', '⚡', 'Progression'], ['upgrades', '⬆️', 'Upgrades']];
    const BLOCKERS = { owned: 'Owned', level: 'Level too low' };

    function create(container, ctx) {
        const { esc, money } = ctx;
        const st = { tab: ctx.storage.get('tab', 'contracts'), view: null, config: null, stage: null, busy: {}, error: null };
        let alive = true;
        let resizeObs = null;
        let refreshTimer = null;

        const root = document.createElement('div');
        root.className = 'pfj-g6';
        container.appendChild(root);

        const num = (v, d = 0) => (Number.isFinite(Number(v)) ? Number(v) : d);
        const me = () => num(st.view && st.view.playerId, -1);
        const group = () => (st.view && st.view.group) || null;
        const isLeader = () => !!group() && num(group().leader) === me();
        const contract = () => (st.view && st.view.contract) || null;

        function report(res) {
            if (res && res.ok === false && res.error !== 'refused') ctx.notify(res.message || ERRORS[res.error] || 'That did not work', 'error');
            return res;
        }

        function applyView(v) {
            if (!v || typeof v !== 'object') return;
            const keep = st.view || {};
            st.view = Object.assign({}, keep, v);
            if (v.xp == null) { st.view.xp = keep.xp; st.view.level = keep.level; }
            if (v.upgrades == null) st.view.upgrades = keep.upgrades;
            if (v.config) st.config = v.config;
            if (!st.view.contract) st.stage = null;
        }

        async function act(key, method, payload) {
            if (st.busy[key]) return null;
            st.busy[key] = true;
            render();
            let res;
            try { res = await ctx.rpc(method, payload); } finally { st.busy[key] = false; }
            if (!alive) return res;
            if (res && res.view) applyView(res.view);
            report(res);
            render();
            return res;
        }

        async function loadInit() {
            const res = await ctx.rpc('getInit');
            if (!alive) return;
            if (!res || res.ok === false) st.error = ERRORS[res && res.error] || 'Gruppe 6 is not answering';
            else { st.error = null; applyView(res); }
            render();
        }

        // pushes about the contract come in bursts; one refresh covers them
        function refreshSoon() {
            if (refreshTimer) return;
            refreshTimer = setTimeout(async () => {
                refreshTimer = null;
                const res = await ctx.rpc('refresh');
                if (!alive || !res || res.ok === false) return;
                applyView(res);
                render();
            }, 250);
        }

        function btn(action, label, cls, opts) {
            const key = action + (opts && opts.key != null ? ':' + opts.key : '');
            const busy = st.busy[key];
            const data = Object.entries((opts && opts.data) || {}).map(([k, v]) => ` data-${k}="${esc(v)}"`).join('');
            const disabled = busy || (opts && opts.disabled) ? ' disabled' : '';
            return `<button type="button" class="pfj-g6-btn ${cls || ''}" data-action="${action}"${data}${disabled}>${busy ? 'Working…' : esc(label)}</button>`;
        }

        function xpInfo() {
            const levels = (st.config && st.config.levels) || [];
            const lvl = num(st.view && st.view.level, 1);
            const xp = num(st.view && st.view.xp);
            const cur = levels.find((l) => num(l.level) === lvl);
            const next = levels.find((l) => num(l.level) === lvl + 1);
            const base = num(cur && cur.xp);
            if (!next) return { lvl, text: `${xp} XP • top level`, pct: 100 };
            const span = Math.max(1, num(next.xp) - base);
            return { lvl, text: `${Math.max(0, xp - base)} / ${span} XP`, pct: Math.min(100, Math.max(0, ((xp - base) / span) * 100)) };
        }

        function infoRow(icon, label, value) {
            return `<div class="pfj-g6-info"><span class="pfj-g6-info-label"><span>${icon}</span>${esc(label)}</span><span class="pfj-g6-info-value">${value}</span></div>`;
        }

        function rankBadge() {
            return '<div class="pfj-g6-rank"><span class="pfj-g6-wing left">🪽</span><div class="pfj-g6-rank-circle">⭐</div><span class="pfj-g6-wing">🪽</span></div>';
        }

        function leftHtml() {
            const c = contract();
            if (!c) {
                const searching = st.view && st.view.searching;
                const offers = (st.view && st.view.offers) || [];
                return `
                    <div class="pfj-g6-waiting">
                        <div class="pfj-g6-waiting-icon">⏳</div>
                        <div>
                            <div class="pfj-g6-waiting-title">No active contract</div>
                            <div class="pfj-g6-muted">${searching ? 'Searching for contracts…' : offers.length ? 'Accept an offer from the list' : 'Start searching in the Work tab'}</div>
                        </div>
                    </div>`;
            }
            let stage = 'Collect the money bags at each pickup';
            if (c.earlyEnd) stage = 'Ending early: deliver what you collected to the vault';
            else if (st.stage && st.stage.stage === 'deposit') stage = 'Deliver the bags to the central vault';
            if (st.stage && st.stage.total) stage += ` (${num(st.stage.deposited)}/${num(st.stage.total)} deposited)`;
            const holds = (st.view && st.view.holds) || [];
            const holdNote = holds.length ? `<div class="pfj-g6-note">🚨 ${holds.map((h) => `Police hold near ${esc(h.label || 'an attack')} (${num(h.minutes)} min)`).join(' · ')}: pickups there are closed.</div>` : '';
            return `
                <div class="pfj-g6-contract">
                    ${holdNote}
                    <div class="pfj-g6-tier">Tier ${num(c.tier, 1)}</div>
                    <div class="pfj-g6-vehicle">${esc(c.vehicle || 'Stockade')}</div>
                    ${rankBadge()}
                    <div class="pfj-g6-infos">
                        ${infoRow('📦', 'Type', esc(c.contractType || 'Bank Delivery'))}
                        ${infoRow('💼', 'Bags', `${num(c.bagsTaken)} / ${num(c.totalBags || c.bags)}`)}
                        ${infoRow('📍', 'Pickups', `${num(c.completedPickups)} / ${num(c.totalPickups)}`)}
                        ${infoRow('🏦', 'Deposited', String(num(c.depositedBags)))}
                        ${infoRow('💰', 'Payout', money(c.payout))}
                        ${c.plate ? infoRow('🚚', 'Truck', esc(c.plate)) : ''}
                    </div>
                    <div class="pfj-g6-stage">${esc(stage)}</div>
                    ${c.earlyEnd ? '' : btn('endContract', 'End contract early', 'big')}
                </div>`;
        }

        function contractsHtml() {
            if (contract()) return '<div class="pfj-g6-empty"><div class="pfj-g6-empty-icon">🛡️</div>Contract in progress<br><small>Finish or end it to see new offers.</small></div>';
            const offers = ((st.view && st.view.offers) || []).slice(0, 3);
            if (!offers.length) return `<div class="pfj-g6-empty"><div class="pfj-g6-empty-icon">📋</div>No contracts offered<br><small>${st.view && st.view.searching ? 'Offers arrive while you search.' : 'Start searching in the Work tab.'}</small></div>`;
            const leaderOnly = group() && !isLeader();
            return `
                <div class="pfj-g6-head">Available contracts <small>${offers.length} offer${offers.length === 1 ? '' : 's'}</small></div>
                ${leaderOnly ? '<div class="pfj-g6-note">You are in a party: the contract your leader accepts is shared with you.</div>' : ''}
                <div class="pfj-g6-offers">
                    ${offers.map((c, i) => `
                        <div class="pfj-g6-offer">
                            <div class="pfj-g6-tier static">Tier ${num(c.tier, 1)}</div>
                            <div class="pfj-g6-vehicle small">${esc(c.vehicle || 'Stockade')}</div>
                            ${rankBadge()}
                            <div class="pfj-g6-infos">
                                ${infoRow('📦', 'Type', esc(c.contractType || 'Bank Delivery'))}
                                ${infoRow('💰', 'Payout', money(c.payout))}
                                ${infoRow('👥', 'Max party', String(num(c.maxGroup, 4)))}
                            </div>
                            ${btn('accept', 'Accept contract', 'big', { key: i, data: { index: i } })}
                        </div>`).join('')}
                </div>`;
        }

        function workHtml() {
            const searching = st.view && st.view.searching;
            const c = contract();
            return `
                <div class="pfj-g6-card">
                    <div class="pfj-g6-row between">
                        <div class="pfj-g6-card-title">Work status</div>
                        ${c ? '' : (searching ? btn('stopSearch', 'Stop searching', 'danger') : btn('startSearch', 'Start searching', 'primary'))}
                    </div>
                    <div class="pfj-g6-status">${c ? '🚚 On a contract' : searching ? '🔍 Searching for contracts… offers show in the Contracts tab.' : '💼 Start searching to receive contract offers.'}</div>
                    <ol class="pfj-g6-steps">
                        <li>Accept an offer and collect the armored truck at Gruppe 6.</li>
                        <li>Drive to each pickup and take the money bags.</li>
                        <li>Open the vault with the security panel and hand the bags in.</li>
                        <li>You are paid for the share of bags handed in; ending early pays for what you collected.</li>
                    </ol>
                </div>`;
        }

        function inviteCards(invites) {
            if (!invites.length) return '';
            return `
                <div class="pfj-g6-invites">
                    <div class="pfj-g6-card-title">📬 Party invites</div>
                    ${group() ? '<div class="pfj-g6-muted">Accepting moves you to that party.</div>' : ''}
                    ${invites.map((inv) => `
                        <div class="pfj-g6-invite">
                            <div><strong>${esc(inv.leaderName || 'Leader')}</strong> <span class="pfj-g6-muted">ID ${num(inv.leaderId)}</span></div>
                            <div class="pfj-g6-row">
                                ${btn('acceptInvite', 'Accept', 'ok', { key: inv.leaderId, data: { leader: inv.leaderId } })}
                                ${btn('declineInvite', 'Decline', 'danger', { key: inv.leaderId, data: { leader: inv.leaderId } })}
                            </div>
                        </div>`).join('')}
                </div>`;
        }

        function partyHtml() {
            const g = group();
            const invites = (st.view && st.view.invites) || [];
            const max = num(st.config && st.config.maxMembers, 4);
            const mult = num(st.config && st.config.crewBonus, 1.5);
            const floor = num(st.config && st.config.splitFloor, 10);
            if (!g) {
                return `
                    ${inviteCards(invites)}
                    <div class="pfj-g6-card center">
                        <div class="pfj-g6-big-icon">👥</div>
                        <div class="pfj-g6-card-title">No party</div>
                        <div class="pfj-g6-muted">Create a party, share its code or invite players by server ID. A party contract pays a pool of ${mult}× the payout for every member, for the bags the party hands in; the leader decides the shares.</div>
                        <div class="pfj-g6-row center">${btn('createGroup', 'Create party', 'primary')}</div>
                        <div class="pfj-g6-row center">
                            <input class="pfj-g6-input" data-keep="code" maxlength="8" placeholder="Party code" autocomplete="off">
                            ${btn('joinByCode', 'Join', 'gold')}
                        </div>
                    </div>`;
            }
            const leader = isLeader();
            const members = Array.isArray(g.members) ? g.members : [];
            return `
                ${inviteCards(invites)}
                <div class="pfj-g6-card">
                    <div class="pfj-g6-row between">
                        <div class="pfj-g6-code">Party code <strong>${esc(g.groupCode || '------')}</strong></div>
                        ${btn('copyCode', 'Copy', 'ghost sm')}
                    </div>
                    <div class="pfj-g6-row between">
                        <div><div class="pfj-g6-card-title">${leader ? '👑 Your party' : '👥 Party'}</div><div class="pfj-g6-muted">${members.length + 1}/${max} members • pool of ${mult}× the payout per member</div></div>
                        ${leader ? btn('disbandGroup', 'Disband', 'danger') : btn('leaveGroup', 'Leave', 'ghost')}
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
                    ${splitsHtml(g, leader, floor)}
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

        // The leader's shares of the party pool; members see them read-only.
        function splitsHtml(g, leader, floor) {
            const splits = Array.isArray(g.splits) ? g.splits : [];
            if (splits.length < 2) return '';
            const names = { [num(g.leader)]: leader ? 'You' : (g.leaderName || 'Leader') };
            (g.members || []).forEach((m) => { names[num(m.id)] = num(m.id) === me() ? 'You' : (m.name || 'Member'); });
            const shares = {};
            ((st.view && st.view.payShares) || []).forEach((x) => { shares[num(x.id)] = x; });
            return `
                <div class="pfj-g6-subcard">
                    <div class="pfj-g6-card-title">💵 Shares of the pool</div>
                    <div class="pfj-g6-muted">${leader ? `Whole percent, at least ${floor}% each, adding up to 100.` : 'Set by your leader.'}${Object.keys(shares).length ? ' Amounts are for every bag of this contract handed in.' : ''}</div>
                    ${splits.map((x) => `
                        <div class="pfj-g6-row between">
                            <span>${esc(names[num(x.id)] || ('ID ' + num(x.id)))}</span>
                            <span class="pfj-g6-row">
                                ${leader ? `<input class="pfj-g6-input" data-keep="split-${num(x.id)}" data-split-id="${num(x.id)}" type="number" min="${floor}" max="100" step="1" value="${num(x.pct)}" style="width:80px">%` : `<strong>${num(x.pct)}%</strong>`}
                                ${shares[num(x.id)] ? `<span class="pfj-g6-muted">${money(shares[num(x.id)].amount)}</span>` : ''}
                            </span>
                        </div>`).join('')}
                    ${leader ? `<div class="pfj-g6-row">${btn('saveSplits', 'Save shares', 'primary sm')}</div>` : ''}
                </div>`;
        }

        function upgradesHtml() {
            const list = (st.view && st.view.upgrades) || [];
            if (!list.length) return '<div class="pfj-g6-empty"><div class="pfj-g6-empty-icon">⬆️</div>No upgrades on offer</div>';
            return `
                <div class="pfj-g6-card">
                    <div class="pfj-g6-card-title">Upgrades</div>
                    <div class="pfj-g6-muted">Bought once from your bank account and kept for good. They apply to the contracts you accept.</div>
                </div>
                ${list.map((u) => {
                    const why = u.owned ? 'Owned' : u.canBuy ? '' : (BLOCKERS[u.blocker] || (String(u.blocker || '').indexOf('requires:') === 0 ? 'Needs the previous licence' : 'Locked'));
                    return `<div class="pfj-g6-card">
                        <div class="pfj-g6-row between">
                            <div class="pfj-g6-row"><span class="pfj-g6-big-icon" style="font-size:28px">${esc(u.icon || '⬆️')}</span><div><strong>${esc(u.label || u.id)}</strong><div class="pfj-g6-muted">${esc(u.description || '')}</div><div class="pfj-g6-muted">From level ${num(u.requiredLevel, 1)}</div></div></div>
                            <div class="pfj-g6-row">${u.owned ? '<span class="pfj-g6-tag">Owned</span>' : btn('buyUpgrade', u.canBuy ? `Buy ${money(u.cost)}` : `${why} · ${money(u.cost)}`, u.canBuy ? 'gold' : '', { key: u.id, data: { id: u.id }, disabled: !u.canBuy })}</div>
                        </div>
                    </div>`;
                }).join('')}`;
        }

        function progressHtml() {
            const cfg = st.config || {};
            const lvl = num(st.view && st.view.level, 1);
            const levels = cfg.levels || [];
            const tiers = cfg.tiers || [];
            return `
                <div class="pfj-g6-card">
                    <div class="pfj-g6-card-title">Levels</div>
                    <div class="pfj-g6-muted">XP comes from completed contracts: the bigger the payout and the more bags handed in, the more XP.</div>
                    <div class="pfj-g6-levels">
                        ${levels.map((l) => `<div class="pfj-g6-level${num(l.level) === lvl ? ' current' : num(l.level) < lvl ? ' done' : ''}"><strong>Level ${num(l.level)}</strong><span>${num(l.xp).toLocaleString()} XP</span></div>`).join('')}
                    </div>
                </div>
                <div class="pfj-g6-card">
                    <div class="pfj-g6-card-title">Contract tiers</div>
                    <div class="pfj-g6-tiers">
                        ${tiers.map((t) => {
                            const owned = !t.upgrade || ((st.view && st.view.upgrades) || []).some((u) => u.id === t.upgrade && u.owned);
                            const open = lvl >= num(t.minLevel, 1) && owned;
                            const bags = Array.isArray(t.bags) ? `${num(t.bags[0])}–${num(t.bags[1])}` : '';
                            const pay = Array.isArray(t.payout) ? `${money(t.payout[0])}–${money(t.payout[1])}` : '';
                            return `<div class="pfj-g6-tier-row${open ? ' open' : ''}">
                                <div><strong>${esc(t.label || ('Tier ' + num(t.tier)))}</strong><div class="pfj-g6-muted">From level ${num(t.minLevel, 1)}${t.upgrade ? ` with the ${esc(t.upgradeLabel || t.upgrade)}` : ''}</div></div>
                                <div class="pfj-g6-muted">${esc(bags)} bags</div>
                                <div class="pfj-g6-pay">${esc(pay)}</div>
                                <div class="pfj-g6-tag">${open ? 'Unlocked' : 'Locked'}</div>
                            </div>`;
                        }).join('')}
                    </div>
                </div>`;
        }

        function rightHtml() {
            switch (st.tab) {
                case 'work': return workHtml();
                case 'party': return partyHtml();
                case 'progress': return progressHtml();
                case 'upgrades': return upgradesHtml();
                default: return contractsHtml();
            }
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
            if (!st.view) {
                root.innerHTML = st.error
                    ? `<div class="pfj-g6-empty">${esc(st.error)}<br><br><button type="button" class="pfj-g6-btn primary" data-action="reload">Try again</button></div>`
                    : '<div class="pfj-g6-empty">Connecting to Gruppe 6…</div>';
                return;
            }
            const x = xpInfo();
            const invites = ((st.view && st.view.invites) || []).length;
            keepInputs(() => {
                root.innerHTML = `
                    <div class="pfj-g6-top">
                        <div class="pfj-g6-brand"><div class="pfj-g6-logo">🛡️</div><div><div class="pfj-g6-title">Gruppe 6</div><div class="pfj-g6-muted">Secure cash transport</div></div></div>
                        <div class="pfj-g6-tabs">${TABS.map(([id, icon, label]) => `<button type="button" class="pfj-g6-tab${st.tab === id ? ' active' : ''}" data-tab="${id}"><span>${icon}</span>${esc(label)}${id === 'party' && invites ? ` <em>${invites}</em>` : ''}</button>`).join('')}</div>
                        <div class="pfj-g6-prog"><div class="pfj-g6-prog-head">⚡ Level ${x.lvl}</div><div class="pfj-g6-bar"><div style="width:${x.pct.toFixed(1)}%"></div></div><div class="pfj-g6-muted">${esc(x.text)}</div></div>
                    </div>
                    <div class="pfj-g6-main">
                        <div class="pfj-g6-left">${leftHtml()}</div>
                        <div class="pfj-g6-right">${rightHtml()}</div>
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
            const clear = (k) => { const i = root.querySelector(`[data-keep="${k}"]`); if (i) i.value = ''; };
            switch (el.dataset.action) {
                case 'reload': await loadInit(); break;
                case 'startSearch': await act('startSearch', 'startSearch'); break;
                case 'stopSearch': await act('stopSearch', 'stopSearch'); break;
                case 'accept': {
                    const res = await act('accept:' + el.dataset.index, 'acceptContract', { index: Number(el.dataset.index) });
                    if (res && res.ok) ctx.notify('Contract accepted', 'success');
                    break;
                }
                case 'endContract': await act('endContract', 'endContract'); break;
                case 'createGroup': await act('createGroup', 'createGroup'); break;
                case 'joinByCode': {
                    const code = value('code').toUpperCase();
                    if (!code) { ctx.notify('Enter a party code', 'error'); break; }
                    const res = await act('joinByCode', 'joinByCode', { code });
                    if (res && res.ok) clear('code');
                    break;
                }
                case 'invitePlayer': {
                    const id = parseInt(value('invite'), 10);
                    if (!id) { ctx.notify('Enter a player server ID', 'error'); break; }
                    const res = await act('invitePlayer', 'invitePlayer', { targetId: id });
                    if (res && res.ok) clear('invite');
                    break;
                }
                case 'acceptInvite': await act('acceptInvite:' + el.dataset.leader, 'acceptInvite', { leaderId: Number(el.dataset.leader) }); break;
                case 'declineInvite': {
                    const leader = Number(el.dataset.leader);
                    const res = await act('declineInvite:' + leader, 'declineInvite', { leaderId: leader });
                    if (res && res.ok && st.view) { st.view.invites = (st.view.invites || []).filter((i) => num(i.leaderId) !== leader); render(); }
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
                case 'buyUpgrade': {
                    const res = await act('buyUpgrade:' + el.dataset.id, 'buyUpgrade', { id: String(el.dataset.id || '') });
                    if (res && res.ok) ctx.notify('Upgrade bought', 'success');
                    break;
                }
                case 'copyCode': {
                    const code = group() && group().groupCode;
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

        ctx.on('contracts', (offers) => { if (st.view) { st.view.offers = Array.isArray(offers) ? offers : []; render(); } });
        ctx.on('activeContract', () => refreshSoon());
        ctx.on('progress', (p) => { st.stage = p || null; refreshSoon(); });
        ctx.on('xp', (p) => { if (st.view && p) { st.view.xp = num(p.xp); st.view.level = num(p.level, 1); render(); } });
        ctx.on('group', (p) => { if (st.view) { st.view.group = (p && p.group) || null; render(); } });
        ctx.on('upgrades', () => loadInit());
        ctx.on('alert', (p) => { if (p && p.message) ctx.notify(String(p.message), 'error'); refreshSoon(); });
        ctx.on('invite', (inv) => {
            if (!st.view || !inv) return;
            const list = st.view.invites || [];
            if (!list.some((i) => num(i.leaderId) === num(inv.leaderId))) list.push(inv);
            st.view.invites = list;
            render();
        });

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
    PFApps.register('gruppe6', {
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
