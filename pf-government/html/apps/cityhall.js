// City Hall Requests (business owners and bosses, tablet and computer): ask City Hall for an
// equipment slot, an inspection, a license or a delivery zone, and follow the answers. Slot and
// delivery zone requests record where you stand — stand at the spot first.
(function () {
    const ERRORS = {
        not_owner: 'You do not manage this business', already_requested: 'You already have an open request for this',
        cooldown: 'Wait a moment before the next request', too_far: 'Go to your business first',
        invalid_slot_type: 'Pick a slot type', invalid_license_type: 'Pick a license', license_active: 'You already hold this license',
        services_offline: 'City Hall is not taking requests right now',
    };
    const errText = (e) => ERRORS[e] || (e ? String(e).replace(/_/g, ' ') : 'That did not work');
    const STATUS = { open: ['Waiting', '.accent'], accepted: ['Being handled', '.warn'], completed: ['Approved', '.ok'], cancelled: ['Closed', ''], expired: ['Expired', ''] };

    PFApps.register('cityhallrequests', {
        mount(container, ctx) {
            const { h, timeAgo } = ctx;
            const state = { data: null, business: ctx.storage.get('business', null), kind: 'slot' };
            const body = h('div.pf-app-body.pf-stack');
            container.appendChild(h('div.pf-app.gov-app',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '🏛️'), h('div', 'City Hall Requests', h('div.pf-app-sub', 'Ask the city for what your business needs'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                body));

            async function submit(method, payload) {
                const res = await ctx.rpc(method, payload);
                if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                ctx.notify(`Request #${res.id} sent to City Hall`, 'success');
                load();
            }

            function requestForm(d, biz) {
                const note = h('textarea.pf-textarea', { rows: '2', maxlength: '300', placeholder: 'Note for City Hall (optional)' });
                const slotType = h('select.pf-select', (d.slotTypes || []).map((t) => h('option', { value: t }, t.replace(/_/g, ' '))));
                const license = h('select.pf-select', (d.licenseTypes || []).map((l) => h('option', { value: l.type }, `${l.label}${l.fee ? ' — $' + l.fee : ''}`)));
                const kinds = [['slot', 'Equipment slot'], ['delivery_zone', 'Delivery zone'], ['license', 'License'], ['inspection', 'Inspection']];
                const hints = {
                    slot: 'Stand exactly where the new equipment should go. City Hall approves the spot on site.',
                    delivery_zone: 'Stand where supply trucks should unload. City Hall approves the bay on site.',
                    license: 'The license fee is billed to the business when it is granted.',
                    inspection: 'An inspector visits the business (to reopen it or to certify it).',
                };
                const methods = { slot: 'requestSlot', delivery_zone: 'requestDeliveryZone', license: 'requestLicense', inspection: 'requestInspection' };
                return h('div.pf-card.gov-form',
                    h('div.pf-row', kinds.map(([k, l]) => h('button.pf-btn.sm' + (state.kind === k ? '.primary' : ''), { onclick: () => { state.kind = k; render(); } }, l))),
                    h('div.gov-hint', hints[state.kind]),
                    state.kind === 'slot' ? h('div.pf-field', h('label', 'Slot type'), slotType) : null,
                    state.kind === 'license' ? h('div.pf-field', h('label', 'License'), license) : null,
                    note,
                    h('div.pf-row', h('button.pf-btn.primary', {
                        onclick: () => submit(methods[state.kind], { businessId: biz.id, note: note.value, slotType: slotType.value, licenseType: license.value }),
                    }, 'Send request')));
            }

            function requestList(list) {
                if (!list.length) return h('div.pf-empty', 'No requests yet.');
                return h('div.pf-list', list.map((r) => {
                    const [label, cls] = STATUS[r.status] || [r.status, ''];
                    const shown = r.decision === 'denied' ? ['Denied', '.bad'] : [label, cls];
                    return h('div.pf-list-item',
                        h('div', h('strong', `${r.label || r.kind}${r.subject ? ' — ' + r.subject.replace(/_/g, ' ') : ''}`),
                            h('div.pf-small.pf-muted', [r.requestedBy, r.created ? timeAgo(r.created) : null].filter(Boolean).join(' · ')),
                            r.decisionNote ? h('div.pf-small.gov-note', `City Hall: ${r.decisionNote}`) : null),
                        h('div.gov-actions', h('span.pf-badge' + shown[1], shown[0]),
                            r.status === 'open' || r.status === 'accepted' ? h('button.pf-btn.sm.ghost', { onclick: async () => {
                                const res = await ctx.rpc('cancel', { id: r.id });
                                if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                                ctx.notify('Request withdrawn', 'success');
                                load();
                            } }, 'Withdraw') : null));
                }));
            }

            function render() {
                body.innerHTML = '';
                const d = state.data;
                if (!d) return;
                const list = d.businesses || [];
                if (!list.length) { body.appendChild(h('div.pf-empty', 'You do not manage a registered business.')); return; }
                if (!list.find((b) => b.id === state.business)) state.business = list[0].id;
                const picker = h('select.pf-select', { onchange: (e) => { state.business = e.target.value; ctx.storage.set('business', state.business); render(); } },
                    list.map((b) => h('option', { value: b.id }, b.name || b.id)));
                picker.value = state.business;
                const biz = list.find((b) => b.id === state.business);
                body.appendChild(h('div.pf-card.pf-row.between', picker,
                    h('div.pf-small.pf-muted', [biz.type, biz.status, biz.licenseStatus ? `license: ${biz.licenseStatus}` : null].filter(Boolean).join(' · '))));
                body.appendChild(requestForm(d, biz));
                body.appendChild(h('div.gov-section', 'Your requests'));
                body.appendChild(requestList((d.requests || []).filter((r) => r.businessId === biz.id)));
            }

            async function load() {
                const res = await ctx.rpc('overview');
                if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                state.data = res;
                render();
            }

            ctx.on('changed', () => load());
            load();
        },
    });
})();
