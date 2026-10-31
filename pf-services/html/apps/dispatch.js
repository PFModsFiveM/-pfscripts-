// Dispatch: requests for the player's job (from other jobs, citizens and city events).
(function () {
    const STATUS = {
        open: ['Open', 'accent'], accepted: ['In progress', 'warn'], completed: ['Done', 'ok'],
        cancelled: ['Cancelled', ''], expired: ['Expired', 'bad'],
    };
    const ERRORS = {
        off_duty: 'Go on duty first', wrong_job: 'This request is not for your job', taken: 'Someone else took it',
        not_open: 'This request is no longer open', too_many_active: 'Finish your current requests first',
        not_yours: 'This is not your request', not_done: 'The job is not finished yet',
        needs_requester_confirmation: 'The customer has to confirm this one', own_request: 'You made this request',
        too_far: 'You are too far away', no_location: 'This request has no location',
    };

    PFApps.register('dispatch', {
        mount(container, ctx) {
            const { h, esc, money, timeAgo } = ctx;
            let data = null;
            let tab = 'open';
            let selected = null;
            let busy = false;
            let reloadTimer = null;

            const tabs = h('div.pf-tabs');
            const list = h('div.pf-list');
            const detail = h('div.pf-card.pf-stack.pfs-detail');
            const sub = h('div.pf-app-sub', '');
            const root = h('div.pf-app.pfs-dispatch',
                h('div.pf-app-header',
                    h('div.pf-app-title', h('span.pf-icon', '📟'), h('div', 'Dispatch', sub)),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                tabs,
                h('div.pf-app-body.pfs-split', h('div.pfs-list-wrap', list), detail));
            container.appendChild(root);

            function errorText(res) { return ERRORS[res && res.error] || 'That did not work'; }

            function badge(status) {
                const [label, cls] = STATUS[status] || [status, ''];
                return h('span.pf-badge' + (cls ? '.' + cls : ''), label);
            }

            function rows() {
                if (!data) return [];
                if (tab === 'mine') return data.mine || [];
                const all = data.requests || [];
                if (tab === 'open') return all.filter((r) => r.status === 'open' || r.status === 'accepted');
                return all.filter((r) => r.status !== 'open' && r.status !== 'accepted');
            }

            function renderTabs() {
                tabs.innerHTML = '';
                const counts = {
                    open: (data && data.requests || []).filter((r) => r.status === 'open').length,
                    mine: (data && data.mine || []).length,
                };
                [['open', `Queue${counts.open ? ' (' + counts.open + ')' : ''}`], ['mine', `Mine${counts.mine ? ' (' + counts.mine + ')' : ''}`], ['history', 'Today']]
                    .forEach(([id, label]) => tabs.appendChild(h('div.pf-tab' + (tab === id ? '.active' : ''), { onclick: () => { tab = id; render(); } }, label)));
            }

            function renderDetail() {
                detail.innerHTML = '';
                const r = selected && (rows().find((x) => x.id === selected) || (data && [...(data.requests || []), ...(data.mine || [])].find((x) => x.id === selected)));
                if (!r) {
                    detail.appendChild(h('div.pf-muted', 'Select a request to see its details.'));
                    if (data && data.kinds && data.kinds.length) {
                        detail.appendChild(h('div.pf-divider'));
                        detail.appendChild(h('div.pf-small.pf-muted', 'Your job handles:'));
                        data.kinds.forEach((k) => detail.appendChild(h('div.pf-small', `${k.icon} ${k.label}${k.reward ? ' — ' + money(k.reward) : ''}`)));
                    }
                    return;
                }
                detail.appendChild(h('div.pf-row.between', h('div.pf-strong', `${r.icon} ${r.label}`), badge(r.status)));
                detail.appendChild(h('div', r.title));
                if (r.details) detail.appendChild(h('div.pf-small', r.details));
                const facts = h('div.pf-small.pf-muted.pf-stack');
                if (r.fromName) facts.appendChild(h('div', `From: ${r.fromName}`));
                if (r.plate) facts.appendChild(h('div', `Plate: ${r.plate}`));
                if (r.reward) facts.appendChild(h('div', `Pay: ${money(r.reward)}${r.paid ? '' : ' (unfunded)'}`));
                if (r.assigneeName) facts.appendChild(h('div', `Taken by: ${r.assigneeName}`));
                if (r.created) facts.appendChild(h('div', `Created ${timeAgo(r.created)}`));
                if (r.closeReason && r.status !== 'open' && r.status !== 'accepted') facts.appendChild(h('div', `Closed: ${r.closeReason}`));
                detail.appendChild(facts);
                const actions = h('div.pf-row', { style: { flexWrap: 'wrap' } });
                if (r.coords) actions.appendChild(h('button.pf-btn.sm', { onclick: () => act('waypoint', r) }, 'Waypoint'));
                if (r.status === 'open') actions.appendChild(h('button.pf-btn.sm.primary', { disabled: !data.onduty, onclick: () => act('accept', r) }, 'Accept'));
                if (r.status === 'accepted' && r.mine) {
                    actions.appendChild(h('button.pf-btn.sm.primary', { onclick: () => act('complete', r) }, r.verify ? 'Mark done' : 'Complete'));
                    actions.appendChild(h('button.pf-btn.sm.ghost', { onclick: () => act('release', r) }, 'Give back'));
                }
                if ((r.status === 'open' || r.status === 'accepted') && r.fromType === 'job') {
                    actions.appendChild(h('button.pf-btn.sm.danger', { onclick: () => act('cancel', r) }, 'Cancel'));
                }
                detail.appendChild(actions);
                if (!data.onduty && r.status === 'open') detail.appendChild(h('div.pf-small.pf-muted', 'You are off duty.'));
            }

            function renderList() {
                list.innerHTML = '';
                const items = rows();
                if (!items.length) {
                    list.appendChild(h('div.pf-empty', tab === 'mine' ? 'You have no active requests.' : 'Nothing here right now.'));
                    return;
                }
                items.forEach((r) => {
                    list.appendChild(h('div.pf-list-item.pfs-item' + (selected === r.id ? '.selected' : ''), { onclick: () => { selected = r.id; render(); } },
                        h('div.pf-row', h('span.pfs-icon', r.icon),
                            h('div', h('div.pf-strong', r.title), h('div.pf-small.pf-muted', `${r.label} · ${timeAgo(r.created)}${r.fromName ? ' · ' + r.fromName : ''}`))),
                        h('div.pf-row', r.reward ? h('span.pf-badge.ok', money(r.reward)) : null, badge(r.status))));
                });
            }

            function render() {
                sub.textContent = data ? `${data.jobLabel || data.job || ''} · ${data.onduty ? 'on duty' : 'off duty'}` : '';
                renderTabs();
                renderList();
                renderDetail();
            }

            async function load() {
                const res = await ctx.rpc('list');
                if (!res || !res.ok) {
                    list.innerHTML = '';
                    list.appendChild(h('div.pf-empty', 'Dispatch is unavailable.'));
                    return;
                }
                data = res;
                render();
            }

            function scheduleReload() {
                clearTimeout(reloadTimer);
                reloadTimer = setTimeout(load, 300);
            }

            async function act(method, r) {
                if (busy) return;
                busy = true;
                const res = await ctx.rpc(method, { id: r.id });
                busy = false;
                if (!res || !res.ok) { ctx.notify(errorText(res), 'error'); }
                else if (method === 'accept') { ctx.notify('Request accepted', 'success'); tab = 'mine'; if (r.coords) ctx.rpc('waypoint', { id: r.id }); }
                else if (method === 'complete') ctx.notify('Request completed', 'success');
                else if (method === 'waypoint') ctx.notify('Waypoint set', 'success');
                scheduleReload();
            }

            ctx.on('request:new', scheduleReload);
            ctx.on('request:changed', scheduleReload);
            this._timer = setInterval(load, 15000);
            load();
        },
        unmount() {
            clearInterval(this._timer);
        },
    });
})();
