// Business Setup (government tablet): approve equipment slots and delivery zones for a business,
// standing where they go; set its registry location and district; district default delivery zones.
// The server reads your position — the tablet never sends coordinates.
(function () {
    const ERRORS = {
        no_permission: 'You need the businesses permission', too_far: 'Go to the business first', too_close: 'Too close to another slot',
        invalid_slot_type: 'Pick a slot type', too_many_slots: 'This business has the maximum number of slots', slot_in_use: 'Equipment stands in that slot',
        unknown_district: 'Pick a district', not_found: 'Nothing to clear',
    };
    const errText = (e) => ERRORS[e] || (e ? String(e).replace(/_/g, ' ') : 'That did not work');
    const fmt = (p) => (p ? `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}` : '—');

    PFApps.register('govsetup', {
        mount(container, ctx) {
            const { h } = ctx;
            const state = { tab: 'business', businesses: [], districts: [], districtZones: {}, slotTypes: [], selected: null, detail: null, filter: '' };
            const tabs = h('div.pf-tabs');
            const body = h('div.pf-app-body');
            container.appendChild(h('div.pf-app.gov-app',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '📐'), h('div', 'Business Setup', h('div.pf-app-sub', 'Slots and delivery zones, approved where you stand'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                tabs, body));

            async function call(method, payload, okText) {
                const res = await ctx.rpc(method, payload);
                if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return null; }
                if (okText) ctx.notify(okText, 'success');
                return res;
            }

            async function load() {
                const res = await call('businesses', {});
                if (!res) return;
                Object.assign(state, { businesses: res.businesses || [], districts: res.districts || [], districtZones: res.districtZones || {}, slotTypes: res.slotTypes || [] });
                if (state.selected) await open(state.selected); else render();
            }

            async function open(id) {
                state.selected = id;
                const res = await call('business', { businessId: id });
                state.detail = res;
                render();
            }

            function businessDetail() {
                const d = state.detail;
                if (!d) return h('div.pf-empty', 'Pick a business.');
                const b = d.business;
                const refresh = () => open(b.id);
                const slotType = h('select.pf-select', state.slotTypes.map((t) => h('option', { value: t }, t.replace(/_/g, ' '))));
                const slotLabel = h('input.pf-input', { maxlength: '64', placeholder: 'Label (optional)' });
                const zoneLabel = h('input.pf-input', { maxlength: '64', placeholder: 'Zone label (optional)' });
                const district = h('select.pf-select', [h('option', { value: '' }, '— none —')].concat(state.districts.map((x) => h('option', { value: x.id }, x.label))));
                district.value = b.district || '';
                return h('div.pf-stack',
                    h('div.pf-card.pf-stack',
                        h('h3', b.name || b.id),
                        h('dl.gov-kv',
                            h('dt', 'Registry location'), h('dd', b.location ? fmt({ x: b.location.x, y: b.location.y, z: b.location.z || 0 }) : 'Not recorded'),
                            h('dt', 'You are at'), h('dd', fmt(d.here)),
                            h('dt', 'Delivery zone'), h('dd', d.zone ? `${d.zone.label || 'Zone'} at ${fmt(d.zone)}` : (d.effectiveZone ? `District zone (${d.effectiveZone.district}) at ${fmt(d.effectiveZone)}` : 'None'))),
                        h('div.gov-actions',
                            h('button.pf-btn.sm', { onclick: async () => { if (await call('setLocation', { businessId: b.id }, 'Location set where you stand')) { load(); } } }, 'Set location here')),
                        h('div.pf-row', district, h('button.pf-btn.sm', { onclick: async () => { if (await call('setDistrict', { businessId: b.id, district: district.value }, 'District saved')) refresh(); } }, 'Save district'))),
                    h('div.gov-section', 'Approved equipment slots'),
                    d.slots && d.slots.length ? h('table.pf-table',
                        h('thead', h('tr', ['#', 'Type', 'Label', 'Position', 'Equipment', ''].map((t) => h('th', t)))),
                        h('tbody', d.slots.map((s) => h('tr',
                            h('td', String(s.id)), h('td', (s.type || '').replace(/_/g, ' ')), h('td', s.label || ''), h('td', fmt(s)),
                            h('td', s.equipment || h('span.pf-muted', 'empty')),
                            h('td', s.equipment ? null : h('button.pf-btn.sm.danger', { onclick: async () => { if (await call('removeSlot', { businessId: b.id, slotId: s.id }, 'Slot withdrawn')) refresh(); } }, 'Remove')))))) : h('div.pf-empty', 'No approved slots yet.'),
                    h('div.pf-card.gov-form',
                        h('div.pf-small.pf-muted', 'Stand exactly where the equipment will go.'),
                        h('div.pf-row', slotType, slotLabel),
                        h('div.pf-row', h('button.pf-btn.primary', { onclick: async () => { if (await call('approveSlot', { businessId: b.id, slotType: slotType.value, label: slotLabel.value }, 'Slot approved here')) refresh(); } }, 'Approve slot here'))),
                    h('div.gov-section', 'Default delivery zone'),
                    h('div.pf-card.gov-form',
                        h('div.pf-small.pf-muted', 'Supply pallets go here when the business has no delivery point of its own. Stand where trucks should unload, facing the way the pallet should face.'),
                        zoneLabel,
                        h('div.gov-actions',
                            h('button.pf-btn.primary', { onclick: async () => { if (await call('setZone', { businessId: b.id, label: zoneLabel.value }, 'Delivery zone set here')) refresh(); } }, 'Set zone here'),
                            d.zone ? h('button.pf-btn.danger', { onclick: async () => { if (await call('clearZone', { businessId: b.id }, 'Delivery zone cleared')) refresh(); } }, 'Clear zone') : null)));
            }

            function businessTab() {
                const search = h('input.pf-input', { placeholder: 'Search', value: state.filter, oninput: (e) => { state.filter = e.target.value; renderList(); } });
                const list = h('div.pf-stack');
                function renderList() {
                    list.innerHTML = '';
                    const q = state.filter.toLowerCase();
                    state.businesses.filter((b) => !q || String(b.name || '').toLowerCase().includes(q) || String(b.id).toLowerCase().includes(q)).forEach((b) => {
                        list.appendChild(h('div.pf-card.gov-pick' + (b.id === state.selected ? '.active' : ''), { onclick: () => open(b.id) },
                            h('strong', b.name || b.id), h('div.pf-small.pf-muted', [b.type, b.status, b.district].filter(Boolean).join(' · '))));
                    });
                }
                renderList();
                return h('div.gov-split', h('div.gov-pane.pf-stack', search, list), h('div.gov-pane', businessDetail()));
            }

            function districtTab() {
                return h('div.pf-stack', state.districts.map((x) => {
                    const z = state.districtZones[x.id];
                    const label = h('input.pf-input', { maxlength: '64', placeholder: 'Zone label (optional)' });
                    return h('div.pf-card.pf-stack',
                        h('div.pf-row.between', h('strong', x.label), h('span.pf-small.pf-muted', z ? `${z.label || 'Zone'} at ${fmt(z)}` : 'No district zone')),
                        h('div.pf-row', label,
                            h('button.pf-btn.sm.primary', { onclick: async () => { if (await call('setDistrictZone', { district: x.id, label: label.value }, 'District zone set here')) load(); } }, 'Set here'),
                            z ? h('button.pf-btn.sm.danger', { onclick: async () => { if (await call('clearDistrictZone', { district: x.id }, 'District zone cleared')) load(); } }, 'Clear') : null));
                }), h('div.gov-hint', 'A district zone is used by businesses in that district that have no zone of their own.'));
            }

            function render() {
                tabs.innerHTML = '';
                [['business', 'Businesses'], ['district', 'District zones']].forEach(([id, l]) => tabs.appendChild(h('div.pf-tab' + (state.tab === id ? '.active' : ''), { onclick: () => { state.tab = id; render(); } }, l)));
                body.innerHTML = '';
                body.appendChild(state.tab === 'business' ? businessTab() : districtTab());
            }

            load();
        },
    });
})();
