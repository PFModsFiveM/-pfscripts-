// Calendar: personal events, city events (government staff post them) and events at the businesses
// the citizen works for. Reminders arrive as a notification shortly before the start.
(function () {
    const ERRORS = {
        no_title: 'Give the event a title', bad_time: 'Pick a start date and time (within a year)', bad_end: 'The end must be after the start (at most a week)',
        bad_reminder: 'Pick a reminder', not_authorized: 'You cannot post or change that event', rate_limited: 'Slow down a little',
        too_many_events: 'You have too many upcoming events', not_found: 'That event is gone',
    };
    const REMINDERS = [[0, 'No reminder'], [5, '5 minutes before'], [10, '10 minutes before'], [15, '15 minutes before'], [30, '30 minutes before'], [60, '1 hour before'], [1440, '1 day before']];
    const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const SCOPE_LABEL = { personal: 'Personal', city: 'City', business: 'Work' };

    const pad = (n) => String(n).padStart(2, '0');
    const dayKey = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    const timeOf = (ts) => new Date(ts * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

    PFApps.register('calendar', {
        mount(container, ctx) {
            const { h } = ctx;
            const today = new Date();
            const state = { month: new Date(today.getFullYear(), today.getMonth(), 1), selected: dayKey(today), events: [], canPostCity: false, businesses: [], busy: false };
            const titleEl = h('div.pf-strong');
            const grid = h('div.pfc-cal');
            const side = h('div.pfc-cal-side.pf-stack');
            const root = h('div.pf-app.pfc.pfc-calendar',
                h('div.pf-app-header',
                    h('div.pf-app-title', h('span.pf-icon', '📅'), 'Calendar'),
                    h('div.pf-row',
                        h('button.pf-btn.sm', { onclick: () => shift(-1) }, '‹'), titleEl, h('button.pf-btn.sm', { onclick: () => shift(1) }, '›'),
                        h('button.pf-btn.sm.ghost', { onclick: () => { state.month = new Date(today.getFullYear(), today.getMonth(), 1); state.selected = dayKey(today); load(); } }, 'Today'),
                        h('button.pf-btn.sm.primary', { onclick: () => form(null) }, '+ Event'))),
                h('div.pf-app-body', h('div.pfc-cal-wrap', h('div.pfc-cal-main', grid), side)));
            container.appendChild(root);
            const fit = () => root.classList.toggle('pfc-narrow', container.clientWidth < 820);
            if (typeof ResizeObserver !== 'undefined') { root.__ro = new ResizeObserver(fit); root.__ro.observe(container); }
            fit();

            function shift(n) { state.month = new Date(state.month.getFullYear(), state.month.getMonth() + n, 1); load(); }

            function byDay() {
                const map = {};
                state.events.forEach((e) => { const k = dayKey(new Date(e.starts * 1000)); (map[k] = map[k] || []).push(e); });
                return map;
            }

            function render() {
                titleEl.textContent = state.month.toLocaleDateString([], { month: 'long', year: 'numeric' });
                grid.innerHTML = '';
                DAYS.forEach((d) => grid.appendChild(h('div.pfc-cal-head', d)));
                const first = new Date(state.month);
                const offset = (first.getDay() + 6) % 7; // weeks start on Monday
                const start = new Date(first.getFullYear(), first.getMonth(), 1 - offset);
                const map = byDay();
                for (let i = 0; i < 42; i++) {
                    const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
                    const k = dayKey(d);
                    const evs = map[k] || [];
                    const cls = (d.getMonth() !== state.month.getMonth() ? '.other' : '') + (k === dayKey(today) ? '.today' : '') + (k === state.selected ? '.selected' : '');
                    grid.appendChild(h('div.pfc-day' + cls, { onclick: () => { state.selected = k; render(); } },
                        h('div.pfc-day-num', String(d.getDate())),
                        evs.slice(0, 3).map((e) => h('div.pfc-ev.' + e.scope, timeOf(e.starts) + ' ' + e.title)),
                        evs.length > 3 ? h('div.pf-small.pf-muted', `+${evs.length - 3} more`) : null));
                }
                renderSide(map[state.selected] || []);
            }

            function renderSide(evs) {
                side.innerHTML = '';
                const [y, m, d] = state.selected.split('-').map(Number);
                side.appendChild(h('div.pf-row.between', h('h3', { style: { margin: 0 } }, new Date(y, m - 1, d).toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' })),
                    h('button.pf-btn.sm', { onclick: () => form(null, state.selected) }, '+ Add')));
                if (!evs.length) { side.appendChild(h('div.pfc-empty', 'Nothing planned.')); return; }
                evs.forEach((e) => {
                    const actions = h('div.pf-row', { style: { flexWrap: 'wrap' } });
                    if (e.scope !== 'personal' && e.starts * 1000 > Date.now()) {
                        actions.appendChild(h('button.pf-btn.sm', { onclick: () => subscribe(e) }, e.subscribed ? '🔔 Reminding you' : '🔕 Remind me'));
                    }
                    if (e.canEdit) {
                        actions.appendChild(h('button.pf-btn.sm', { onclick: () => form(e) }, 'Edit'));
                        actions.appendChild(h('button.pf-btn.sm.danger', { onclick: () => cancel(e) }, 'Cancel event'));
                    }
                    side.appendChild(h('div.pf-card.pf-stack', { style: { gap: '6px' } },
                        h('div.pf-row.between', h('span.pf-strong', e.title), h('span.pf-badge' + (e.scope === 'city' ? '.warn' : e.scope === 'business' ? '.ok' : '.accent'), SCOPE_LABEL[e.scope] || e.scope)),
                        h('div.pf-small.pf-muted', [timeOf(e.starts) + (e.ends ? '–' + timeOf(e.ends) : ''), e.location, e.ownerName, e.by ? 'by ' + e.by : null].filter(Boolean).join(' · ')),
                        e.description ? h('div.pfc-body.pf-small', e.description) : null,
                        e.scope === 'personal' && e.remind ? h('div.pf-small.pf-muted', `🔔 ${e.remind} min before`) : null,
                        actions));
                });
            }

            async function load() {
                const from = new Date(state.month.getFullYear(), state.month.getMonth(), -7);
                const to = new Date(state.month.getFullYear(), state.month.getMonth() + 1, 8);
                const res = await ctx.rpc('list', { from: Math.floor(from.getTime() / 1000), to: Math.floor(to.getTime() / 1000) });
                if (!res || !res.ok) { ctx.notify('The calendar is not available right now', 'error'); return; }
                state.events = res.events || [];
                state.canPostCity = !!res.canPostCity;
                state.businesses = res.businesses || [];
                render();
            }

            async function act(method, payload, okMsg) {
                if (state.busy) return null;
                state.busy = true;
                const res = await ctx.rpc(method, payload);
                state.busy = false;
                if (!res || !res.ok) { ctx.notify(ERRORS[res && res.error] || 'That did not work', 'error'); return null; }
                if (okMsg) ctx.notify(okMsg, 'success');
                return res;
            }

            async function subscribe(e) { if (await act('subscribe', { id: e.id, on: !e.subscribed })) load(); }
            async function cancel(e) { if (await act('cancel', { id: e.id }, 'Event cancelled')) load(); }

            function form(ev, onDay) {
                const startDate = ev ? new Date(ev.starts * 1000) : null;
                const base = onDay || dayKey(new Date());
                const scope = h('select.pf-select');
                scope.appendChild(h('option', { value: 'personal' }, 'Personal'));
                if (state.canPostCity) scope.appendChild(h('option', { value: 'city' }, 'City event (public)'));
                state.businesses.forEach((b) => scope.appendChild(h('option', { value: 'business:' + b.id }, 'Work: ' + b.name)));
                if (ev) { scope.value = ev.scope === 'business' ? 'business:' + ev.owner : ev.scope; scope.disabled = true; }
                const title = h('input.pf-input', { maxlength: 100, value: ev ? ev.title : '', placeholder: 'Title' });
                const date = h('input.pf-input', { type: 'date', value: startDate ? dayKey(startDate) : base });
                const time = h('input.pf-input', { type: 'time', value: startDate ? `${pad(startDate.getHours())}:${pad(startDate.getMinutes())}` : '18:00' });
                const endEl = ev && ev.ends ? new Date(ev.ends * 1000) : null;
                const endTime = h('input.pf-input', { type: 'time', value: endEl ? `${pad(endEl.getHours())}:${pad(endEl.getMinutes())}` : '' });
                const location = h('input.pf-input', { maxlength: 100, value: ev && ev.location ? ev.location : '', placeholder: 'Where (optional)' });
                const remind = h('select.pf-select', REMINDERS.map(([v, l]) => h('option', { value: v }, l)));
                remind.value = String(ev ? ev.remind : 15);
                const desc = h('textarea.pf-textarea', { maxlength: 1000, placeholder: 'Details (optional)' });
                desc.value = ev && ev.description ? ev.description : '';
                const overlay = h('div.pfc-overlay');
                const close = () => overlay.remove();
                const save = async () => {
                    const starts = Math.floor(new Date(`${date.value}T${time.value || '00:00'}`).getTime() / 1000);
                    let ends;
                    if (endTime.value) {
                        ends = Math.floor(new Date(`${date.value}T${endTime.value}`).getTime() / 1000);
                        if (ends < starts) ends += 86400; // ends after midnight
                    }
                    const [sc, biz] = scope.value.split(':');
                    const payload = { id: ev ? ev.id : undefined, scope: sc, businessId: biz ? scope.value.slice('business:'.length) : undefined, title: title.value,
                        starts: Number.isFinite(starts) ? starts : null, ends, location: location.value, description: desc.value, remind: Number(remind.value) };
                    if (await act(ev ? 'update' : 'create', payload, ev ? 'Event updated' : 'Event added')) { close(); state.selected = date.value; load(); }
                };
                overlay.appendChild(h('div.pfc-dialog', h('h3', ev ? 'Edit event' : 'New event'),
                    h('div.pf-field', h('label', 'Calendar'), scope),
                    h('div.pf-field', h('label', 'Title'), title),
                    h('div.pf-row', h('div.pf-field', { style: { flex: 1 } }, h('label', 'Date'), date), h('div.pf-field', { style: { flex: 1 } }, h('label', 'Starts'), time), h('div.pf-field', { style: { flex: 1 } }, h('label', 'Ends'), endTime)),
                    h('div.pf-field', h('label', 'Location'), location),
                    h('div.pf-field', h('label', 'Reminder'), remind),
                    h('div.pf-field', h('label', 'Details'), desc),
                    h('div.pfc-actions', h('button.pf-btn.ghost', { onclick: close }, 'Close'), h('button.pf-btn.primary', { onclick: save }, 'Save'))));
                root.appendChild(overlay);
                title.focus();
            }

            ctx.on('changed', load);
            ctx.on('reminder', (r) => ctx.notify(`📅 ${r && r.title ? r.title : 'An event'} starts soon`, 'primary'));
            load();
        },
        unmount(ctx) {
            const root = ctx.el && ctx.el.querySelector('.pfc-calendar');
            if (root && root.__ro) root.__ro.disconnect();
        },
    });
})();
