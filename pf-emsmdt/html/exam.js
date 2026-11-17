// EMS MDT - Patient Care page (batch 21): exams by modality, treatments, the chart and the vitals
// monitor for one patient next to the medic.
//
// The page only asks. pf-ambulancejob decides everything and the page shows its answers:
//   emsCareSelect -> who the patient is (pf-emsmdt server), examOptions (which exams this medic may do
//                    here and why not), treatOptions (actions of the medic's tier);
//   emsCareExam   -> the server's findings (a miss is no finding: "Nothing found" never means normal);
//   emsCareTreat  -> the server's result or refusal (items, tier, place, distance, state);
//   emsCareChart  -> findings, diagnoses, treatments and vital signs of the last 24 hours.
// Labels come from pf-ambulancejob's catalogues (sent by the client with the selection).

(function () {
    const CERTAINTY = { observed: 'Observed', suspected: 'Suspected', confirmed: 'Confirmed' };
    const RESULT_LABEL = { applied: 'Applied', no_effect: 'No effect', stabilized: 'Stabilised', treated: 'Treated', started: 'Started', rosc: 'Pulse back' };

    class EmsCarePage extends BasePage {
        constructor() {
            super('care', 'Patient Care');
            this.nearby = null;          // null = not loaded
            this.nearbyError = null;
            this.sel = null;             // { patient, exam, treat, catalog }
            this.selError = null;
            this.tab = 'exam';
            this.busy = null;            // 'exam:<modality>' | 'treat' | 'select' | 'chart'
            this.lastExam = null;        // the last exam answer (or refusal)
            this.lastTreat = null;       // the last treatment answer (or refusal)
            this.chart = null;
            this.chartError = null;
            this.monitor = new window.EmsMonitor.Monitor();
            this.found = [];             // findings of this patient's exams (for wound treatments)
            this.treatForm = { action: '', where: '' };
        }

        mount(root) {
            super.mount(root);
            this.render();
            if (this.nearby === null) this.loadNearby();
        }

        // ── data ───────────────────────────────────────────────────────────────────────────────

        async loadNearby() {
            this.nearbyError = null;
            this.nearby = null;
            this.render();
            const res = await emsRequest('emsCareNearby', {});
            if (res && res.ok) this.nearby = Array.isArray(res.list) ? res.list : [];
            else { this.nearby = []; this.nearbyError = emsErrorText(res); }
            this.render();
        }

        async selectTarget(target) {
            const t = Number(target);
            if (!Number.isInteger(t) || t <= 0) return;
            this.busy = 'select';
            this.selError = null;
            this.render();
            const res = await emsRequest('emsCareSelect', { target: t });
            this.busy = null;
            if (!res || res.ok !== true || !res.patient) {
                this.selError = emsErrorText(res);
                this.render();
                return;
            }
            const sameKey = this.sel && this.sel.patient && this.sel.patient.citizenid === res.patient.citizenid;
            this.sel = res;
            if (!sameKey) {
                this.monitor.reset(res.patient.citizenid);
                this.lastExam = null;
                this.lastTreat = null;
                this.found = [];
                this.chart = null;
                this.chartError = null;
                this.treatForm = { action: '', where: '' };
            }
            this.render();
        }

        async closePatient() {
            this.sel = null;
            this.selError = null;
            await emsRequest('emsCareClose', {});
            this.render();
        }

        modality(id) {
            const list = this.sel && this.sel.exam && Array.isArray(this.sel.exam.modalities) ? this.sel.exam.modalities : [];
            return list.find((m) => m.id === id) || null;
        }

        async runExam(id) {
            if (!this.sel || this.busy) return;
            const m = this.modality(id);
            const seconds = Number(m && m.seconds) || 1;
            this.busy = 'exam:' + id;
            this.render();
            // the server waits the exam's time before it answers
            const res = await emsRequest('emsCareExam', { target: this.sel.patient.target, modality: id }, (seconds + 15) * 1000);
            this.busy = null;
            this.lastExam = { modality: id, label: (m && m.label) || emsHumanize(id), res };
            if (res && res.ok) {
                this.monitor.ingestExam(res);
                if (Array.isArray(res.findings)) this.found = res.findings.concat(this.found).slice(0, 80);
            }
            this.render();
        }

        async runTreat() {
            if (!this.sel || this.busy) return;
            const action = this.treatForm.action;
            const def = this.actionDef(action);
            if (!def) return;
            const payload = { target: this.sel.patient.target, action };
            const where = this.treatForm.where;
            if (where.startsWith('injury:')) payload.injuryId = Number(where.slice(7));
            else if (where.startsWith('region:')) payload.region = where.slice(7);
            this.busy = 'treat';
            this.render();
            const res = await emsRequest('emsCareTreat', payload, ((Number(def.seconds) || 4) + 15) * 1000);
            this.busy = null;
            this.lastTreat = { action, label: def.label, res };
            if (res && res.ok) this.chart = null; // the chart changed: load it again when it is opened
            this.render();
        }

        async loadChart() {
            if (!this.sel || this.busy) return;
            this.busy = 'chart';
            this.chartError = null;
            this.render();
            const res = await emsRequest('emsCareChart', { target: this.sel.patient.target });
            this.busy = null;
            if (res && res.ok) {
                this.chart = res;
                this.monitor.ingestChart(res.vitals);
            } else {
                this.chart = null;
                this.chartError = emsErrorText(res);
            }
            this.render();
        }

        onMonitor(data) {
            if (!this.sel || !data || Number(data.target) !== Number(this.sel.patient.target)) return;
            if (this.monitor.ingestLive(data.vitals, data.rhythm)) this.render();
        }

        // ── helpers ────────────────────────────────────────────────────────────────────────────

        catalog() { return (this.sel && this.sel.catalog) || { regions: [], structures: {}, actions: {} }; }

        actionDef(name) {
            const a = this.catalog().actions || {};
            return Object.prototype.hasOwnProperty.call(a, name) ? a[name] : null;
        }

        regionLabel(id) {
            const r = (this.catalog().regions || []).find((x) => x.id === id);
            return r ? r.label : emsHumanize(id);
        }

        structureLabel(id) {
            const s = this.catalog().structures || {};
            return Object.prototype.hasOwnProperty.call(s, id) ? s[id] : emsHumanize(id);
        }

        // actions the server says this medic's tier allows, with a catalogue entry, by label
        actions() {
            const names = this.sel && this.sel.treat && this.sel.treat.ok && Array.isArray(this.sel.treat.actions) ? this.sel.treat.actions : [];
            return names.map((n) => ({ name: n, def: this.actionDef(n) })).filter((x) => x.def)
                .sort((a, b) => String(a.def.label).localeCompare(String(b.def.label)));
        }

        // findings that name an injury (from this patient's exams and the chart), for wound treatments
        knownWounds() {
            const out = new Map();
            const add = (f) => {
                const id = Number(f && f.injuryId);
                if (!Number.isInteger(id) || id <= 0 || out.has(id)) return;
                out.set(id, `${f.label || emsHumanize(f.sign)}${f.region ? ', ' + this.regionLabel(f.region) : ''}`);
            };
            this.found.forEach(add);
            if (this.chart) (this.chart.findings || []).forEach(add);
            return out;
        }

        findingRow(f) {
            const head = (f.label || emsHumanize(f.sign)) + (f.value !== undefined && f.value !== null && f.value !== '' ? `: ${emsHumanize(f.value)}` : '');
            const where = f.structure ? this.structureLabel(f.structure) : (f.region ? this.regionLabel(f.region) : '');
            return emsEl('li', { class: 'ems-finding' },
                emsEl('span', { class: 'ems-finding-head', text: head }),
                where ? emsEl('span', { class: 'ems-muted', text: where }) : null,
                emsEl('span', { class: `ems-badge ems-cert-${CERTAINTY[f.certainty] ? f.certainty : 'other'}`, text: CERTAINTY[f.certainty] || emsHumanize(f.certainty) }));
        }

        // ── render ─────────────────────────────────────────────────────────────────────────────

        render() {
            if (!this.root) return;
            const side = this.renderNearby();
            const main = this.sel ? this.renderPatient() : emsEl('div', { class: 'ems-card' },
                this.busy === 'select' ? emsState('loading', 'Checking the patient...') : null,
                this.selError ? emsState('error', this.selError) : null,
                !this.busy && !this.selError ? emsState('empty', 'Choose a patient next to you to examine and treat them.') : null);
            const monitor = this.sel ? this.monitor.render({
                measure: this.measurable(), busy: !!this.busy, onMeasure: (m) => this.runExam(m),
            }) : null;
            const focus = emsFocusKey(this.root);
            this.root.replaceChildren(emsEl('div', { class: 'ems-page ems-care' },
                emsEl('aside', { class: 'ems-care-side' }, side),
                emsEl('section', { class: 'ems-care-main' }, main),
                monitor ? emsEl('aside', { class: 'ems-care-monitor' }, monitor) : null));
            emsRestoreFocus(this.root, focus);
        }

        measurable() {
            const out = {};
            for (const m of (this.sel && this.sel.exam && this.sel.exam.modalities) || []) out[m.id] = m.available === true;
            return out;
        }

        renderNearby() {
            const head = emsEl('div', { class: 'ems-card-head' },
                emsEl('h3', { text: 'Patients next to you' }),
                emsEl('button', { class: 'btn', type: 'button', text: 'Refresh', disabled: this.nearby === null ? true : null,
                    onclick: () => this.loadNearby() }));
            let body;
            if (this.nearby === null) body = emsState('loading', 'Looking around...');
            else if (this.nearbyError) body = emsState('error', this.nearbyError);
            else if (!this.nearby.length) body = emsState('empty', 'Nobody is close enough. Stand next to the patient.');
            else {
                body = emsEl('ul', { class: 'ems-list' }, this.nearby.map((p) => {
                    const active = this.sel && this.sel.patient && Number(this.sel.patient.target) === Number(p.target);
                    return emsEl('li', null, emsEl('button', { class: `ems-list-btn${active ? ' active' : ''}`, type: 'button',
                        'aria-pressed': active ? 'true' : 'false', disabled: this.busy ? true : null,
                        onclick: () => this.selectTarget(p.target) },
                        emsEl('span', { class: 'ems-strong', text: p.name || 'Unknown' }),
                        emsEl('span', { class: 'ems-muted', text: `${p.citizenid || ''} · ${Number(p.distance) || 0} m` })));
                }));
            }
            return emsEl('div', { class: 'ems-card' }, head, body);
        }

        renderPatient() {
            const p = this.sel.patient;
            const tier = this.sel.exam && this.sel.exam.ok ? this.sel.exam.tierLabel : null;
            const header = emsEl('div', { class: 'ems-card-head' },
                emsEl('div', null,
                    emsEl('h3', { text: p.name || 'Patient' }),
                    emsEl('span', { class: 'ems-muted', text: `${p.citizenid || ''}${tier ? ' · your level: ' + tier : ''}` })),
                emsEl('div', { class: 'ems-row' },
                    emsEl('button', { class: 'btn', type: 'button', text: 'Re-check', disabled: this.busy ? true : null,
                        onclick: () => this.selectTarget(p.target) }),
                    emsEl('button', { class: 'btn', type: 'button', text: 'Done', onclick: () => this.closePatient() })));
            const tabs = emsEl('div', { class: 'tabs', role: 'tablist' }, [['exam', 'Exam'], ['treat', 'Treat'], ['chart', 'Chart']].map(([id, label]) =>
                emsEl('button', { class: `tab${this.tab === id ? ' active' : ''}`, type: 'button', role: 'tab', 'aria-selected': this.tab === id ? 'true' : 'false',
                    dataset: { careTab: id }, text: label, onclick: () => {
                        this.tab = id;
                        if (id === 'chart' && !this.chart && !this.busy) this.loadChart(); else this.render();
                    } })));
            let panel;
            if (this.tab === 'treat') panel = this.renderTreat();
            else if (this.tab === 'chart') panel = this.renderChart();
            else panel = this.renderExam();
            return emsEl('div', { class: 'ems-card' }, header, tabs, panel);
        }

        renderExam() {
            const exam = this.sel.exam;
            if (!exam || exam.ok !== true) return emsState('error', emsErrorText(exam));
            const myTier = Number(exam.tier) || 0;
            const rows = (exam.modalities || []).filter((m) => m.available || (Number(m.tier) || 0) <= myTier).map((m) => {
                const running = this.busy === 'exam:' + m.id;
                return emsEl('li', { class: 'ems-exam-row' },
                    emsEl('div', null,
                        emsEl('span', { class: 'ems-strong', text: m.label || emsHumanize(m.id) }),
                        emsEl('span', { class: 'ems-muted', text: m.available ? `${Number(m.seconds) || 0} s` : String(m.reason || 'Not possible here') })),
                    emsEl('button', { class: 'btn primary', type: 'button', dataset: { modality: m.id },
                        disabled: (!m.available || this.busy) ? true : null,
                        text: running ? `Examining... ${Number(m.seconds) || 0} s` : 'Examine', onclick: () => this.runExam(m.id) }));
            });
            const list = rows.length ? emsEl('ul', { class: 'ems-list' }, rows) : emsState('empty', 'No exam is possible for you on this patient.');
            return emsEl('div', { class: 'ems-panel' }, list, this.renderExamResult());
        }

        renderExamResult() {
            const last = this.lastExam;
            if (!last) return null;
            const res = last.res;
            const title = emsEl('h4', { class: 'ems-section-title', text: `Result: ${last.label}` });
            if (!res || res.ok !== true) return emsEl('section', { class: 'ems-section ems-result' }, title, emsState('error', emsErrorText(res)));
            const findings = Array.isArray(res.findings) ? res.findings : [];
            return emsEl('section', { class: 'ems-section ems-result', 'aria-live': 'polite' }, title,
                emsEl('div', { class: 'ems-muted', text: `${res.reused ? 'Result from the last minute' : 'Examined'} · ${emsTime(res.at)}` }),
                findings.length
                    ? emsEl('ul', { class: 'ems-lines' }, findings.map((f) => this.findingRow(f)))
                    : emsState('empty', 'Nothing found. An exam can miss things; it never shows what is not there.'));
        }

        renderTreat() {
            const treat = this.sel.treat;
            if (!treat || treat.ok !== true) return emsState('error', emsErrorText(treat));
            const actions = this.actions();
            if (!actions.length) return emsState('empty', 'No treatment is open to your level.');
            if (!this.actionDef(this.treatForm.action)) this.treatForm = { action: actions[0].name, where: '' };
            const def = this.actionDef(this.treatForm.action);
            const actionSel = emsEl('select', { class: 'ems-input', id: 'emsTreatAction', 'aria-label': 'Treatment',
                onchange: (e) => { this.treatForm = { action: e.target.value, where: '' }; this.render(); } },
                actions.map((a) => emsEl('option', { value: a.name, selected: a.name === this.treatForm.action ? true : null, text: a.def.label })));
            let whereField = null;
            let ready = true;
            if (def.target === 'region' || def.target === 'wound') {
                const regions = (this.catalog().regions || []).filter((r) => !Array.isArray(def.regions) || def.regions.includes(r.id));
                const opts = [];
                if (def.target === 'wound') {
                    opts.push(emsEl('option', { value: '', text: 'Worst wound (the server picks)' }));
                    for (const [id, label] of this.knownWounds()) opts.push(emsEl('option', { value: `injury:${id}`, text: `Found: ${label}` }));
                } else {
                    opts.push(emsEl('option', { value: '', text: 'Choose where' }));
                    ready = this.treatForm.where !== '';
                }
                for (const r of regions) opts.push(emsEl('option', { value: `region:${r.id}`, text: r.label }));
                for (const o of opts) if (o.value === this.treatForm.where) o.selected = true;
                whereField = emsEl('label', { class: 'ems-field' }, emsEl('span', { text: 'Where' }),
                    emsEl('select', { class: 'ems-input', id: 'emsTreatWhere', onchange: (e) => { this.treatForm.where = e.target.value; this.render(); } }, opts));
            }
            const form = emsEl('form', { class: 'ems-form', onsubmit: (e) => { e.preventDefault(); if (ready) this.runTreat(); } },
                emsEl('label', { class: 'ems-field' }, emsEl('span', { text: 'Treatment' }), actionSel),
                whereField,
                emsEl('div', { class: 'ems-muted', text: `Takes about ${Number(def.seconds) || 0} s; uses the items it needs from your inventory or the rig.` }),
                emsEl('button', { class: 'btn primary', type: 'submit', id: 'emsTreatApply', disabled: (!ready || this.busy) ? true : null,
                    text: this.busy === 'treat' ? 'Treating...' : 'Apply' }));
            return emsEl('div', { class: 'ems-panel' }, form, this.renderTreatResult());
        }

        renderTreatResult() {
            const last = this.lastTreat;
            if (!last) return null;
            const res = last.res;
            const title = emsEl('h4', { class: 'ems-section-title', text: `Result: ${last.label}` });
            if (!res || res.ok !== true) return emsEl('section', { class: 'ems-section ems-result' }, title, emsState('error', emsErrorText(res)));
            const changed = (res.result && res.result.changed) || {};
            const outcome = changed.result || (changed.rosc ? 'rosc' : null);
            return emsEl('section', { class: 'ems-section ems-result', 'aria-live': 'polite' }, title,
                outcome ? emsEl('span', { class: `ems-badge ems-outcome-${outcome === 'no_effect' ? 'none' : 'done'}`, text: RESULT_LABEL[outcome] || emsHumanize(outcome) }) : null,
                changed.stabilized ? emsEl('span', { class: 'ems-badge ems-outcome-done', text: 'Bleeding controlled' }) : null,
                changed.treated ? emsEl('span', { class: 'ems-badge ems-outcome-done', text: 'Wound treated' }) : null,
                res.result && res.result.message ? emsEl('p', { text: res.result.message }) : null,
                res.duplicate ? emsEl('p', { class: 'ems-muted', text: 'Already done: this is the first answer.' }) : null);
        }

        renderChart() {
            if (this.busy === 'chart') return emsState('loading', 'Loading the chart...');
            if (this.chartError) return emsEl('div', null, emsState('error', this.chartError),
                emsEl('button', { class: 'btn', type: 'button', text: 'Try again', onclick: () => this.loadChart() }));
            const c = this.chart;
            if (!c) return emsEl('button', { class: 'btn', type: 'button', text: 'Load chart', onclick: () => this.loadChart() });
            const diagnoses = Array.isArray(c.diagnoses) ? c.diagnoses : [];
            const findings = Array.isArray(c.findings) ? c.findings : [];
            const treatments = Array.isArray(c.treatments) ? c.treatments : [];
            const tx = (t) => {
                const def = this.actionDef(t.action);
                return emsEl('li', { class: 'ems-finding' },
                    emsEl('span', { class: 'ems-finding-head', text: def ? def.label : emsHumanize(t.action) }),
                    emsEl('span', { class: 'ems-muted', text: [RESULT_LABEL[t.result] || emsHumanize(t.result), emsHumanize(t.location), emsTime(t.at)].filter(Boolean).join(' · ') }));
            };
            const dx = (d) => emsEl('li', { class: 'ems-finding' },
                emsEl('span', { class: 'ems-finding-head', text: emsHumanize(d.injuryType) }),
                d.structure ? emsEl('span', { class: 'ems-muted', text: this.structureLabel(d.structure) }) : null,
                emsEl('span', { class: `ems-badge ems-cert-${d.status === 'confirmed' ? 'confirmed' : 'suspected'}`, text: emsHumanize(d.status) }));
            const section = (title, list, row, empty) => emsEl('section', { class: 'ems-section' },
                emsEl('h4', { class: 'ems-section-title', text: title }),
                list.length ? emsEl('ul', { class: 'ems-lines' }, list.map(row)) : emsState('empty', empty));
            return emsEl('div', { class: 'ems-panel' },
                emsEl('div', { class: 'ems-row' },
                    emsEl('span', { class: 'ems-muted', text: 'Last 24 hours' }),
                    emsEl('button', { class: 'btn', type: 'button', text: 'Reload', onclick: () => this.loadChart() })),
                section('Diagnoses', diagnoses, dx, 'No diagnoses recorded.'),
                section('Findings', findings.slice(0, 40), (f) => this.findingRow(f), 'No findings recorded.'),
                section('Treatments', treatments.slice(0, 30), tx, 'No treatments recorded.'));
        }
    }

    window.EmsCarePage = EmsCarePage;
})();
