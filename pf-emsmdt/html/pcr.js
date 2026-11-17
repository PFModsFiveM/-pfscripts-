// EMS MDT - Care Reports (PCR editor) and the Units board (batch 21).
//
// PCRs are charted by the server (server/pcr.lua) from pf-ambulancejob's events; the page reads them
// and edits only what the server lets this viewer edit, from the `can` flags of pf_emsmdt:pcr:get:
//   can.narrative   -> the narrative is editable; it saves itself to the server (pcr:saveNarrative)
//                      a moment after typing stops and when the field loses focus (no local storage);
//   can.close       -> close with a disposition (pcr:close; the server keeps 'transported' for a
//                      handed-over report and refuses it otherwise);
//   can.acknowledge -> receiving hospital staff accept the handover (pcr:acknowledgeHandover).
// The lists are paged and sorted by the server (pcr:list { sort, cursor } -> { list, next }): "Load more"
// asks for the page after the last one shown. A narrative typed less than AUTOSAVE_MS before the
// window closes or loses focus is sent at once (NUI close message, Escape, window blur, page hide).
// The Units board is server/units.lua: join/leave/status/rig are requests; the board comes back from
// the server (answer or the pf_emsmdt:client:UnitBoard push).

(function () {
    const STATE_LABEL = { open: 'Open', handed_over: 'Handed over', closed: 'Closed' };
    const AUTOSAVE_MS = 1500;

    function stateBadge(state) {
        return emsEl('span', { class: `ems-badge ems-state-${STATE_LABEL[state] ? state : 'unknown'}`, text: STATE_LABEL[state] || emsHumanize(state) });
    }

    // ── Care Reports ──────────────────────────────────────────────────────────────────────────

    class EmsPcrPage extends BasePage {
        constructor() {
            super('pcr', 'Care Reports');
            this.tab = 'mine';           // mine | patient | handover
            this.lists = { mine: null, patient: null, handover: null };   // null = not loaded
            this.listError = { mine: null, patient: null, handover: null };
            this.patientQuery = '';
            this.next = { mine: null, patient: null };      // server cursor of the next page
            this.sort = 'newest';                          // newest | oldest (server order)
            this.moreLoading = false;
            // a pending narrative is sent when the window goes away (see flushOnLeave)
            window.addEventListener('message', (e) => {
                const a = e && e.data && e.data.action;
                if (a === 'close' || a === 'closeTablet' || a === 'hide') this.flushOnLeave(false);
            });
            window.addEventListener('keydown', (e) => { if (e.key === 'Escape') this.flushOnLeave(false); }, true);
            window.addEventListener('blur', () => this.flushOnLeave(false));
            window.addEventListener('pagehide', () => this.flushOnLeave(true));
            this.detail = null;          // pcr:get answer { pcr, dispositions, narrativeMax }
            this.detailError = null;
            this.detailId = null;
            this.loading = false;
            this.saveState = '';         // '', 'dirty', 'saving', 'saved', 'error'
            this.saveMessage = '';
            this.draft = null;           // narrative text not yet saved
            this.saveTimer = null;
            this.actionError = null;
            this.closeChoice = '';
        }

        mount(root) {
            super.mount(root);
            this.render();
            if (this.detailId === null && this.lists[this.tab] === null && this.tab !== 'patient') this.loadList(this.tab);
        }

        unmount() {
            this.flushNarrative();
            super.unmount();
        }

        // pcr:list (mine) answered on open (app.js emsRefreshAccess), newest first
        onMine(list, next) {
            if (this.sort !== 'newest') return;
            this.lists.mine = Array.isArray(list) ? list : [];
            this.next.mine = next || null;
            this.listError.mine = null;
            if (this.root && this.tab === 'mine' && this.detailId === null) this.render();
        }

        async loadList(tab) {
            this.listError[tab] = null;
            this.lists[tab] = null;
            this.render();
            let res;
            if (tab === 'handover') res = await emsServer('pcr:pendingHandovers');
            else res = await emsServer('pcr:list', this.listQuery(tab));
            if (res && res.ok) {
                this.lists[tab] = Array.isArray(res.list) ? res.list : [];
                if (tab !== 'handover') this.next[tab] = res.next || null;
            } else { this.lists[tab] = []; this.listError[tab] = emsErrorText(res); }
            this.render();
        }

        listQuery(tab, cursor) {
            const q = tab === 'patient' ? { scope: 'patient', citizenId: this.patientQuery } : { scope: 'mine' };
            q.sort = this.sort;
            if (cursor) q.cursor = cursor;
            return q;
        }

        // the page after the last one shown (server cursor); rows already shown stay
        async loadMore(tab) {
            const cursor = this.next[tab];
            if (!cursor || this.moreLoading) return;
            this.moreLoading = true;
            this.render();
            const res = await emsServer('pcr:list', this.listQuery(tab, cursor));
            this.moreLoading = false;
            if (res && res.ok) {
                const seen = new Set((this.lists[tab] || []).map((p) => Number(p.id)));
                const add = (Array.isArray(res.list) ? res.list : []).filter((p) => !seen.has(Number(p.id)));
                this.lists[tab] = (this.lists[tab] || []).concat(add);
                this.next[tab] = res.next || null;
            } else this.listError[tab] = emsErrorText(res);
            this.render();
        }

        setSort(sort) {
            if (sort !== 'newest' && sort !== 'oldest') return;
            this.sort = sort;
            this.lists.mine = null;
            this.next = { mine: null, patient: null };
            if (this.tab === 'patient') { this.lists.patient = null; if (this.patientQuery) this.loadList('patient'); else this.render(); }
            else if (this.tab === 'mine') this.loadList('mine');
            else this.render();
        }

        async openReport(id) {
            const n = Number(id);
            if (!Number.isInteger(n) || n <= 0) return;
            await this.flushNarrative();
            this.detailId = n;
            this.detail = null;
            this.detailError = null;
            this.actionError = null;
            this.draft = null;
            this.saveState = '';
            this.saveMessage = '';
            this.closeChoice = '';
            this.loading = true;
            this.render();
            const res = await emsServer('pcr:get', { id: n });
            this.loading = false;
            if (this.detailId !== n) return;
            if (res && res.ok && res.pcr) this.detail = res;
            else this.detailError = emsErrorText(res);
            this.render();
        }

        back() {
            this.flushNarrative();
            this.detailId = null;
            this.detail = null;
            this.render();
            if (this.lists[this.tab] === null && this.tab !== 'patient') this.loadList(this.tab);
        }

        // ── narrative autosave (server only) ──────────────────────────────────────────────────

        onNarrativeInput(text) {
            this.draft = text;
            this.saveState = 'dirty';
            this.saveMessage = 'Not saved yet';
            this.paintSaveState();
            clearTimeout(this.saveTimer);
            this.saveTimer = setTimeout(() => this.flushNarrative(), AUTOSAVE_MS);
        }

        async flushNarrative() {
            clearTimeout(this.saveTimer);
            this.saveTimer = null;
            if (this.draft === null || !this.detail || !this.detail.pcr) return;
            const id = this.detail.pcr.id;
            const text = this.draft;
            this.draft = null;
            this.saveState = 'saving';
            this.saveMessage = 'Saving...';
            this.paintSaveState();
            const res = await emsServer('pcr:saveNarrative', { id, text });
            if (res && res.ok) {
                if (this.detail && this.detail.pcr && this.detail.pcr.id === id) this.detail.pcr.narrative = text;
                this.saveState = 'saved';
                this.saveMessage = res.clipped ? `Saved, cut to ${Number(res.length) || 0} characters` : 'Saved';
            } else {
                // keep the text so the next keystroke or blur tries again
                if (this.draft === null) this.draft = text;
                this.saveState = 'error';
                this.saveMessage = `Not saved: ${emsErrorText(res)}`;
            }
            this.paintSaveState();
        }

        // The window is closing or losing focus: a narrative still waiting for the autosave timer is
        // sent now. On page hide (the device window's frame goes away) the request is sent with
        // keepalive so it survives the page; the server answers nobody then, which is fine.
        flushOnLeave(pageGone) {
            if (this.draft === null || !this.detail || !this.detail.pcr) return;
            if (!pageGone) { this.flushNarrative(); return; }
            clearTimeout(this.saveTimer);
            this.saveTimer = null;
            const id = this.detail.pcr.id;
            const text = this.draft;
            this.draft = null;
            try {
                const res = typeof getResourceName === 'function' ? getResourceName() : 'pf-emsmdt';
                fetch(`https://${res}/emsServer`, {
                    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                    body: JSON.stringify({ op: 'pcr:saveNarrative', data: { id, text } }), keepalive: true,
                }).catch(() => {});
            } catch (_) { this.draft = text; }
        }

        paintSaveState() {
            const el = this.root && this.root.querySelector('.ems-save-state');
            if (!el) return;
            el.textContent = this.saveMessage;
            el.dataset.state = this.saveState;
        }

        // ── actions ────────────────────────────────────────────────────────────────────────────

        async closeReport() {
            const pcr = this.detail && this.detail.pcr;
            if (!pcr || !this.closeChoice) return;
            await this.flushNarrative();
            this.actionError = null;
            const res = await emsServer('pcr:close', { id: pcr.id, disposition: this.closeChoice });
            if (!res || !res.ok) { this.actionError = emsErrorText(res); this.render(); return; }
            this.lists.mine = null;
            this.openReport(pcr.id);
        }

        async acknowledge() {
            const pcr = this.detail && this.detail.pcr;
            if (!pcr) return;
            this.actionError = null;
            const res = await emsServer('pcr:acknowledgeHandover', { id: pcr.id });
            if (!res || !res.ok) { this.actionError = emsErrorText(res); this.render(); return; }
            this.lists.handover = null;
            this.openReport(pcr.id);
        }

        // ── render ─────────────────────────────────────────────────────────────────────────────

        render() {
            if (!this.root) return;
            const focus = emsFocusKey(this.root);
            this.root.replaceChildren(emsEl('div', { class: 'ems-page ems-pcr' }, this.detailId !== null ? this.renderDetail() : this.renderList()));
            emsRestoreFocus(this.root, focus);
        }

        renderList() {
            const tabs = emsEl('div', { class: 'tabs', role: 'tablist' }, [['mine', 'My reports'], ['patient', 'By patient'], ['handover', 'Awaiting handover']].map(([id, label]) =>
                emsEl('button', { class: `tab${this.tab === id ? ' active' : ''}`, type: 'button', role: 'tab', 'aria-selected': this.tab === id ? 'true' : 'false',
                    dataset: { pcrTab: id }, text: label, onclick: () => {
                        this.tab = id;
                        if (this.lists[id] === null && id !== 'patient') this.loadList(id); else this.render();
                    } })));
            let search = null;
            if (this.tab === 'patient') {
                search = emsEl('form', { class: 'ems-row', onsubmit: (e) => {
                    e.preventDefault();
                    const v = String(e.target.querySelector('input').value || '').trim();
                    if (!v) return;
                    this.patientQuery = v;
                    this.loadList('patient');
                } },
                    emsEl('input', { class: 'ems-input', id: 'emsPcrPatient', placeholder: 'Citizen ID', maxlength: '64', value: this.patientQuery, 'aria-label': 'Citizen ID' }),
                    emsEl('button', { class: 'btn primary', type: 'submit', text: 'Search' }));
            }
            const list = this.lists[this.tab];
            let body;
            if (this.tab === 'patient' && list === null && !this.patientQuery) body = emsState('empty', 'Enter a citizen ID to see their reports you may see.');
            else if (list === null) body = emsState('loading', 'Loading reports...');
            else if (this.listError[this.tab]) body = emsState('error', this.listError[this.tab]);
            else if (!list.length) body = emsState('empty', this.tab === 'handover' ? 'No patient is waiting for a handover.' : 'No reports.');
            else body = this.table(list);
            const paged = this.tab === 'mine' || this.tab === 'patient';
            const sortSel = paged ? emsEl('select', { class: 'ems-input ems-pcr-sort', 'aria-label': 'Order', onchange: (e) => this.setSort(e.target.value) },
                [['newest', 'Newest first'], ['oldest', 'Oldest first']].map(([v, t]) => {
                    const o = emsEl('option', { value: v, text: t });
                    if (v === this.sort) o.selected = true;
                    return o;
                })) : null;
            const more = paged && list && list.length && this.next[this.tab]
                ? emsEl('button', { class: 'btn ems-pcr-more', type: 'button', text: this.moreLoading ? 'Loading...' : 'Load more',
                    disabled: this.moreLoading ? 'disabled' : null, onclick: () => this.loadMore(this.tab) })
                : null;
            return emsEl('div', { class: 'ems-card' },
                emsEl('div', { class: 'ems-card-head' }, emsEl('h3', { text: 'Patient care reports' }), sortSel,
                    this.tab !== 'patient' ? emsEl('button', { class: 'btn', type: 'button', text: 'Refresh', onclick: () => this.loadList(this.tab) }) : null),
                tabs, search, body, more);
        }

        table(list) {
            const head = emsEl('tr', null, ['Report', 'Patient', 'State', 'Unit', 'Lead', 'Opened', 'Lines'].map((h) => emsEl('th', { text: h })));
            const rows = list.map((p) => {
                const id = Number(p.id);
                return emsEl('tr', null,
                    emsEl('td', null, emsEl('button', { class: 'ems-link', type: 'button', dataset: { pcrId: String(id) }, text: `#${id}`,
                        onclick: () => this.openReport(id) })),
                    emsEl('td', { text: p.patientName || p.citizenid || '—' }),
                    emsEl('td', null, stateBadge(p.state)),
                    emsEl('td', { text: p.unit || '—' }),
                    emsEl('td', { text: (p.lead && p.lead.name) || '—' }),
                    emsEl('td', { text: emsTime(p.createdAt) }),
                    emsEl('td', { text: String(Number(p.entryCount) || 0) }));
            });
            return emsEl('div', { class: 'ems-table-wrap' }, emsEl('table', { class: 'ems-table' }, emsEl('thead', null, head), emsEl('tbody', null, rows)));
        }

        renderDetail() {
            const back = emsEl('button', { class: 'btn', type: 'button', text: 'Back to list', onclick: () => this.back() });
            if (this.loading) return emsEl('div', { class: 'ems-card' }, back, emsState('loading', 'Loading the report...'));
            if (this.detailError || !this.detail) return emsEl('div', { class: 'ems-card' }, back, emsState('error', this.detailError || 'Not found.'));
            const d = this.detail;
            const p = d.pcr;
            const can = p.can || {};
            const kv = (k, v) => emsEl('div', { class: 'ems-kv' }, emsEl('span', { class: 'ems-k', text: k }), emsEl('span', { class: 'ems-v', text: v || '—' }));
            const facts = emsEl('div', { class: 'ems-kv-grid' },
                kv('Patient', [p.patientName, p.citizenid].filter(Boolean).join(' · ')),
                kv('Lead', p.lead && p.lead.name),
                kv('Unit', p.unit),
                kv('Call', p.callRef),
                kv('Dispatched', emsTime(p.dispatchAt)),
                kv('On scene', emsTime(p.arriveAt)),
                kv('Left scene', emsTime(p.departAt)),
                kv('Handover', p.handoverAt ? `${emsTime(p.handoverAt)}${p.handoverBy && p.handoverBy.name ? ' to ' + p.handoverBy.name : ''}` : null),
                kv('Hospital', p.hospitalId ? emsHumanize(p.hospitalId) : null),
                kv('Outcome', p.dispositionLabel),
                kv('Closed', emsTime(p.closedAt)));

            const max = Number(d.narrativeMax) || 4000;
            const text = this.draft !== null ? this.draft : (p.narrative || '');
            const narrative = can.narrative
                ? emsEl('div', { class: 'ems-field' },
                    emsEl('label', { for: 'emsPcrNarrative', text: 'Narrative' }),
                    (() => {
                        const ta = emsEl('textarea', { class: 'ems-input ems-narrative', id: 'emsPcrNarrative', maxlength: String(max), rows: '8',
                            oninput: (e) => this.onNarrativeInput(e.target.value), onblur: () => this.flushNarrative() });
                        ta.value = text;
                        return ta;
                    })(),
                    emsEl('div', { class: 'ems-row ems-muted' },
                        emsEl('span', { class: 'ems-save-state', role: 'status', dataset: { state: this.saveState }, text: this.saveMessage || 'Saves to the server as you type' }),
                        emsEl('span', { text: `max ${max} characters` })))
                : emsEl('section', { class: 'ems-section' }, emsEl('h4', { class: 'ems-section-title', text: 'Narrative' }),
                    p.narrative ? emsEl('p', { class: 'ems-prewrap', text: p.narrative }) : emsState('empty', 'No narrative.'));

            const entries = Array.isArray(p.entries) ? p.entries : [];
            const timeline = emsEl('section', { class: 'ems-section' }, emsEl('h4', { class: 'ems-section-title', text: 'Charted by the server' }),
                entries.length ? emsEl('ol', { class: 'ems-timeline' }, entries.map((e) => emsEl('li', null,
                    emsEl('span', { class: 'ems-muted', text: emsTime(e.at) }),
                    emsEl('span', { class: `ems-badge ems-kind-${['treatment', 'vitals', 'note'].includes(e.kind) ? e.kind : 'other'}`, text: emsHumanize(e.kind) }),
                    emsEl('span', { text: e.summary || '' }),
                    e.byName ? emsEl('span', { class: 'ems-muted', text: e.byName }) : null))) : emsState('empty', 'Nothing charted yet.'));

            const actions = [];
            if (can.acknowledge) {
                actions.push(emsEl('button', { class: 'btn primary', type: 'button', id: 'emsPcrAck', text: 'Accept handover', onclick: () => this.acknowledge() }));
            }
            if (can.close) {
                const dispositions = d.dispositions && typeof d.dispositions === 'object' ? d.dispositions : {};
                // the server's rule: a handed-over report closes as transported, an open one cannot
                const keys = Object.keys(dispositions).filter((k) => (k === 'transported') === (p.state === 'handed_over'));
                if (!keys.includes(this.closeChoice)) this.closeChoice = keys[0] || '';
                actions.push(emsEl('form', { class: 'ems-row', onsubmit: (e) => { e.preventDefault(); this.closeReport(); } },
                    emsEl('select', { class: 'ems-input', id: 'emsPcrDisposition', 'aria-label': 'How the call ended', onchange: (e) => { this.closeChoice = e.target.value; } },
                        keys.map((k) => emsEl('option', { value: k, selected: k === this.closeChoice ? true : null, text: String(dispositions[k]) }))),
                    emsEl('button', { class: 'btn danger', type: 'submit', id: 'emsPcrClose', disabled: keys.length ? null : true, text: 'Close report' })));
            }
            return emsEl('div', { class: 'ems-card' },
                emsEl('div', { class: 'ems-card-head' }, back,
                    emsEl('h3', { text: `Care report #${Number(p.id)}` }), stateBadge(p.state)),
                facts, narrative,
                actions.length ? emsEl('div', { class: 'ems-actions' }, actions) : null,
                this.actionError ? emsState('error', this.actionError) : null,
                timeline);
        }
    }

    // ── Units board ───────────────────────────────────────────────────────────────────────────

    class EmsUnitsPage extends BasePage {
        constructor() {
            super('units', 'Units');
            this.board = null;           // { units, unassigned, statuses }
            this.error = null;
            this.actionError = null;
            this.pending = false;
        }

        mount(root) {
            super.mount(root);
            this.render();
            this.load();
        }

        myCid() { return (typeof userInfo === 'object' && userInfo && userInfo.citizenid) || null; }

        async load() {
            const res = await emsServer('units:list');
            if (res && res.ok) this.onBoard(res);
            else { this.error = emsErrorText(res); this.render(); }
        }

        onBoard(board) {
            if (!board || typeof board !== 'object') return;
            this.board = { units: Array.isArray(board.units) ? board.units : [], unassigned: Array.isArray(board.unassigned) ? board.unassigned : [],
                statuses: board.statuses && typeof board.statuses === 'object' ? board.statuses : {} };
            this.error = null;
            this.render();
        }

        myUnit() {
            const cid = this.myCid();
            if (!cid || !this.board) return null;
            return this.board.units.find((u) => (u.crew || []).some((m) => m.citizenid === cid)) || null;
        }

        async act(op, data) {
            if (this.pending) return;
            this.pending = true;
            this.actionError = null;
            this.render();
            const res = await emsServer(op, data);
            this.pending = false;
            if (!res || !res.ok) { this.actionError = emsErrorText(res); this.render(); return; }
            this.load();
        }

        render() {
            if (!this.root) return;
            const focus = emsFocusKey(this.root);
            this.root.replaceChildren(emsEl('div', { class: 'ems-page ems-units' }, this.renderMine(), this.renderBoard()));
            emsRestoreFocus(this.root, focus);
        }

        renderMine() {
            const mine = this.myUnit();
            const statuses = (this.board && this.board.statuses) || {};
            const body = [];
            if (mine) {
                body.push(emsEl('p', null, 'You are in ', emsEl('strong', { text: mine.unit }), '.'));
                body.push(emsEl('div', { class: 'ems-row' },
                    emsEl('label', { class: 'ems-field' }, emsEl('span', { text: 'Status' }),
                        emsEl('select', { class: 'ems-input', id: 'emsUnitStatus', disabled: this.pending ? true : null,
                            onchange: (e) => this.act('units:setStatus', { status: e.target.value }) },
                            Object.keys(statuses).map((k) => emsEl('option', { value: k, selected: k === mine.status ? true : null, text: String(statuses[k]) })))),
                    emsEl('button', { class: 'btn', type: 'button', id: 'emsUnitRig', disabled: this.pending ? true : null,
                        text: 'Set rig (the vehicle I sit in)', onclick: () => this.act('units:setRig', {}) }),
                    mine.rigPlate ? emsEl('button', { class: 'btn', type: 'button', id: 'emsUnitRigClear', disabled: this.pending ? true : null,
                        text: 'Clear rig', onclick: () => this.act('units:setRig', { clear: true }) }) : null,
                    emsEl('button', { class: 'btn danger', type: 'button', id: 'emsUnitLeave', disabled: this.pending ? true : null,
                        text: 'Leave unit', onclick: () => this.act('units:leave') })));
            } else {
                body.push(emsEl('form', { class: 'ems-row', onsubmit: (e) => {
                    e.preventDefault();
                    const v = String(e.target.querySelector('input').value || '').trim();
                    if (v) this.act('units:join', { unit: v });
                } },
                    emsEl('input', { class: 'ems-input', id: 'emsUnitName', maxlength: '16', placeholder: 'Unit name, e.g. MEDIC 12', 'aria-label': 'Unit name' }),
                    emsEl('button', { class: 'btn primary', type: 'submit', id: 'emsUnitJoin', disabled: this.pending ? true : null, text: 'Join or create' })));
            }
            return emsEl('div', { class: 'ems-card' }, emsEl('div', { class: 'ems-card-head' }, emsEl('h3', { text: 'My unit' })),
                body, this.actionError ? emsState('error', this.actionError) : null);
        }

        renderBoard() {
            const head = emsEl('div', { class: 'ems-card-head' }, emsEl('h3', { text: 'Unit board' }),
                emsEl('button', { class: 'btn', type: 'button', text: 'Refresh', onclick: () => this.load() }));
            if (this.error) return emsEl('div', { class: 'ems-card' }, head, emsState('error', this.error));
            if (!this.board) return emsEl('div', { class: 'ems-card' }, head, emsState('loading', 'Loading the board...'));
            const mine = this.myUnit();
            const units = this.board.units;
            const table = units.length ? emsEl('div', { class: 'ems-table-wrap' }, emsEl('table', { class: 'ems-table' },
                emsEl('thead', null, emsEl('tr', null, ['Unit', 'Status', 'Crew', 'Rig', 'Call', 'Since', ''].map((h) => emsEl('th', { text: h })))),
                emsEl('tbody', null, units.map((u) => emsEl('tr', { class: mine && mine.unit === u.unit ? 'ems-row-mine' : null },
                    emsEl('td', { class: 'ems-strong', text: u.unit }),
                    emsEl('td', null, emsEl('span', { class: `ems-badge ems-unit-${/^[a-z_]+$/.test(u.status || '') ? u.status : 'other'}`, text: u.statusLabel || emsHumanize(u.status) })),
                    emsEl('td', { text: (u.crew || []).map((m) => m.name).join(', ') || '—' }),
                    emsEl('td', { text: u.rigPlate || '—' }),
                    emsEl('td', { text: u.callRef || '—' }),
                    emsEl('td', { text: emsTime(u.statusAt) }),
                    emsEl('td', null, mine && mine.unit === u.unit ? null : emsEl('button', { class: 'btn', type: 'button', dataset: { unitJoin: u.unit },
                        disabled: this.pending ? true : null, text: 'Join', onclick: () => this.act('units:join', { unit: u.unit }) })))))))
                : emsState('empty', 'No unit is on the board.');
            const free = this.board.unassigned;
            return emsEl('div', { class: 'ems-card' }, head, table,
                emsEl('section', { class: 'ems-section' }, emsEl('h4', { class: 'ems-section-title', text: 'On duty, in no unit' }),
                    free.length ? emsEl('ul', { class: 'ems-lines' }, free.map((m) => emsEl('li', { text: m.name || '—' }))) : emsState('empty', 'Everyone on duty is in a unit.')));
        }
    }

    window.EmsPcrPage = EmsPcrPage;
    window.EmsUnitsPage = EmsUnitsPage;
})();
