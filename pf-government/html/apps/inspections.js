// Inspections (government tablet): businesses due, overdue or awaiting a follow-up; file a result
// while standing at the business; history. The server checks the distance to the registry location.
(function () {
    const ERRORS = {
        no_permission: 'You may not file inspections', too_far: 'Go to the business to inspect it',
        no_business_location: 'This business has no recorded location — set it in Business Setup first',
        findings_required: 'Describe what failed', invalid_result: 'Pick a result',
    };
    const errText = (e) => ERRORS[e] || (e ? String(e).replace(/_/g, ' ') : 'That did not work');
    const STATES = {
        follow_up: ['Follow-up due', '.bad'], requested: ['Requested', '.accent'], overdue: ['Overdue', '.bad'],
        never: ['Never inspected', '.warn'], due: ['Due', '.warn'], ok: ['Up to date', '.ok'],
    };
    const RESULTS = [['compliant', 'Pass'], ['warning', 'Pass with remarks'], ['non_compliant', 'Fail'], ['flagged', 'Fail — flagged']];

    PFApps.register('govinspections', {
        mount(container, ctx, params) {
            const { h } = ctx;
            const state = { list: [], canFile: false, selected: (params && params.businessId) || null, history: [], filter: 'attention' };
            const listPane = h('div.gov-pane.pf-stack');
            const detail = h('div.gov-pane');
            container.appendChild(h('div.pf-app.gov-app',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '🧾'), h('div', 'Inspections', h('div.pf-app-sub', 'Due, overdue and follow-ups'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                h('div.pf-app-body', h('div.gov-split', listPane, detail))));

            async function load() {
                const res = await ctx.rpc('list');
                if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                state.list = res.businesses || [];
                state.canFile = !!res.canFile;
                renderList();
                if (state.selected) select(state.selected);
            }

            function renderList() {
                listPane.innerHTML = '';
                listPane.appendChild(h('div.pf-row',
                    h('button.pf-btn.sm' + (state.filter === 'attention' ? '.primary' : ''), { onclick: () => { state.filter = 'attention'; renderList(); } }, 'Needs a visit'),
                    h('button.pf-btn.sm' + (state.filter === 'all' ? '.primary' : ''), { onclick: () => { state.filter = 'all'; renderList(); } }, 'All')));
                const shown = state.list.filter((b) => state.filter === 'all' || b.state !== 'ok');
                if (!shown.length) { listPane.appendChild(h('div.pf-empty', 'Nothing needs a visit.')); return; }
                shown.forEach((b) => {
                    const [label, cls] = STATES[b.state] || [b.state, ''];
                    listPane.appendChild(h('div.pf-card.gov-pick' + (b.id === state.selected ? '.active' : ''), { onclick: () => select(b.id) },
                        h('div.pf-row.between', h('strong', b.name || b.id), h('span.pf-badge' + cls, label)),
                        h('div.pf-small.pf-muted', [b.type, b.ageDays != null ? `last ${b.ageDays} d ago` : null, b.lastResult].filter(Boolean).join(' · '))));
                });
            }

            async function select(id) {
                state.selected = id;
                renderList();
                const res = await ctx.rpc('history', { businessId: id });
                state.history = (res && res.ok && res.inspections) || [];
                renderDetail();
            }

            function renderDetail() {
                detail.innerHTML = '';
                const b = state.list.find((x) => x.id === state.selected);
                if (!b) { detail.appendChild(h('div.pf-empty', 'Pick a business.')); return; }
                const result = h('select.pf-select', RESULTS.map(([v, l]) => h('option', { value: v }, l)));
                const findings = h('textarea.pf-textarea', { rows: '4', maxlength: '1000', placeholder: 'Findings (required for a fail)' });
                const followUp = h('input.pf-input', { type: 'number', min: '1', max: '30', value: '3' });
                const fileBtn = h('button.pf-btn.primary', {
                    onclick: async () => {
                        const res = await ctx.rpc('file', { businessId: b.id, result: result.value, findings: findings.value, followUpDays: Number(followUp.value) });
                        if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                        ctx.notify(res.requestCompleted ? 'Inspection filed; the business request is closed' : 'Inspection filed', 'success');
                        load();
                    },
                }, 'File inspection');
                detail.appendChild(h('div.pf-card.pf-stack',
                    h('div.pf-row.between', h('h3', b.name || b.id), h('div.gov-actions',
                        b.location ? h('button.pf-btn.sm', { onclick: async () => {
                            const res = await ctx.rpc('waypoint', { businessId: b.id });
                            if (res && res.ok && res.coords) { ctx.setWaypoint(res.coords.x, res.coords.y); ctx.notify('Waypoint set', 'success'); }
                            else ctx.notify(errText(res && res.error), 'error');
                        } }, 'Waypoint') : null)),
                    h('dl.gov-kv',
                        h('dt', 'Compliance'), h('dd', b.compliance || '—'),
                        h('dt', 'Status'), h('dd', b.status || '—'),
                        h('dt', 'Address'), h('dd', b.address || (b.location ? `${Math.round(b.location.x)}, ${Math.round(b.location.y)}` : 'No location recorded')),
                        h('dt', 'Follow-up'), h('dd', b.followUpAt ? new Date(b.followUpAt * 1000).toLocaleString() : '—'))));
                if (state.canFile) {
                    detail.appendChild(h('div.gov-section', 'File a result (on site)'));
                    detail.appendChild(h('div.pf-card.gov-form',
                        h('div.pf-field', h('label', 'Result'), result),
                        h('div.pf-field', h('label', 'Findings'), findings),
                        h('div.pf-field', h('label', 'Follow-up after (days, for a fail)'), followUp),
                        h('div.pf-row', fileBtn)));
                }
                detail.appendChild(h('div.gov-section', 'History'));
                if (!state.history.length) { detail.appendChild(h('div.pf-empty', 'No inspections yet.')); return; }
                detail.appendChild(h('div.pf-list', state.history.map((i) => h('div.pf-list-item',
                    h('div', h('strong', i.result), h('div.pf-small.gov-note', i.findings || '')),
                    h('div.pf-small.pf-muted', `${i.inspector || ''} ${i.at || ''}`)))));
            }

            load();
        },
    });
})();
