// Business Requests (government tablet and computer): slot, inspection, license and delivery zone
// requests from businesses. Approving a slot or a delivery zone happens where you stand, at the spot
// the business recorded; inspections are filed from the Inspections app.
(function () {
    const ERRORS = {
        no_permission: 'Your role cannot decide this request', too_far: 'Stand at the spot the business recorded',
        not_yours: 'Another official is handling this request', off_duty: 'Go on duty first', wrong_job: 'Government staff only',
        too_many_active: 'Finish your other requests first', closed: 'This request is closed', note_required: 'Write a note for the business',
        too_close: 'Another slot is too close to this spot', license_active: 'The business already holds this license',
        services_offline: 'The request service is offline', own_request: 'You cannot handle your own request',
    };
    const errText = (e) => ERRORS[e] || (e ? String(e).replace(/_/g, ' ') : 'That did not work');
    const ICONS = { slot: '📐', inspection: '🧾', license: '🪪', delivery_zone: '🚚' };

    PFApps.register('govrequests', {
        mount(container, ctx) {
            const { h, timeAgo } = ctx;
            let requests = [];
            let busy = false;
            const body = h('div.pf-app-body.pf-stack');
            container.appendChild(h('div.pf-app.gov-app',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '📥'), h('div', 'Business Requests', h('div.pf-app-sub', 'What businesses ask City Hall for'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                body));

            async function act(method, payload, okText) {
                if (busy) return null;
                busy = true;
                const res = await ctx.rpc(method, payload);
                busy = false;
                if (!res || !res.ok) {
                    if (res && res.error === 'file_inspection' && res.businessId) {
                        ctx.openApp('govinspections', { businessId: res.businessId });
                        return res;
                    }
                    ctx.notify(errText(res && res.error) + (res && res.approved ? ' (approved; try again to close it)' : ''), 'error');
                    return res;
                }
                if (okText) ctx.notify(okText, 'success');
                load();
                return res;
            }

            function card(r) {
                const note = h('input.pf-input', { maxlength: '300', placeholder: r.kind === 'inspection' ? 'Note' : 'Note for the business (required to deny)' });
                const open = r.status === 'open' || r.status === 'accepted';
                const badgeCls = r.status === 'completed' ? '.ok' : r.status === 'open' ? '.accent' : r.status === 'accepted' ? '.warn' : '';
                const buttons = [];
                if (open && r.status === 'open') buttons.push(h('button.pf-btn.sm', { onclick: () => act('accept', { id: r.id }, 'Request accepted') }, 'Accept'));
                if (r.coords) buttons.push(h('button.pf-btn.sm', { onclick: async () => {
                    const res = await ctx.rpc('waypoint', { id: r.id });
                    if (res && res.ok && res.coords) { ctx.setWaypoint(res.coords.x, res.coords.y); ctx.notify('Waypoint set', 'success'); }
                    else ctx.notify(errText(res && res.error), 'error');
                } }, 'Waypoint'));
                if (open && r.canDecide) {
                    if (r.kind === 'inspection') {
                        buttons.push(h('button.pf-btn.sm.primary', { onclick: () => ctx.openApp('govinspections', { businessId: r.businessId }) }, 'Inspect'));
                    } else {
                        const label = r.kind === 'license' ? 'Grant license' : 'Approve here';
                        buttons.push(h('button.pf-btn.sm.primary', { onclick: () => act('approve', { id: r.id, note: note.value }, 'Approved') }, label));
                    }
                    buttons.push(h('button.pf-btn.sm.danger', { onclick: () => act('deny', { id: r.id, note: note.value }, 'Denied') }, 'Deny'));
                }
                return h('div.pf-card.pf-stack',
                    h('div.pf-row.between',
                        h('div', h('strong', `${ICONS[r.kind] || '📋'} ${r.title || r.label}`),
                            h('div.pf-small.pf-muted', [r.business, r.requester ? `asked by ${r.requester}` : null, r.created ? timeAgo(r.created) : null].filter(Boolean).join(' · '))),
                        h('span.pf-badge' + badgeCls, r.status + (r.assignee ? ` · ${r.assignee}` : ''))),
                    r.details ? h('div.gov-note.pf-small', r.details) : null,
                    r.decisionNote ? h('div.pf-small', `Decision: ${r.decision || ''} — ${r.decisionNote}`) : null,
                    open && r.canDecide ? note : null,
                    buttons.length ? h('div.gov-actions', buttons) : null);
            }

            function render() {
                body.innerHTML = '';
                if (!requests.length) { body.appendChild(h('div.pf-empty', 'No business requests right now.')); return; }
                const open = requests.filter((r) => r.status === 'open' || r.status === 'accepted');
                const closed = requests.filter((r) => !(r.status === 'open' || r.status === 'accepted'));
                if (open.length) { body.appendChild(h('div.gov-section', 'Open')); open.forEach((r) => body.appendChild(card(r))); }
                if (closed.length) { body.appendChild(h('div.gov-section', 'Closed today')); closed.forEach((r) => body.appendChild(card(r))); }
            }

            async function load() {
                const res = await ctx.rpc('list');
                if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                requests = res.requests || [];
                render();
            }

            ctx.on('changed', () => load());
            load();
        },
    });
})();
