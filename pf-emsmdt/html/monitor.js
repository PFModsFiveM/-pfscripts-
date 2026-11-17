// EMS MDT - vitals monitor (batch 21).
//
// Shows measured values only, each with when and how it was measured:
//   * an exam's vitals (pf-ambulancejob:server:exam answers { vitals, at } for pulse, blood pressure,
//     pulse oximetry, temperature, glucose, ECG and pain);
//   * the chart's vital-sign findings of the last 24 hours (getChart vitals rows);
//   * the live monitor (pf-ambulancejob:client:Monitor, forwarded as 'careMonitor').
// Nothing is estimated or carried forward as if it were current: a value is as old as its time says.
// The colour bands are a reading aid for the medic, not a diagnosis.

(function () {
    const CHANNELS = [
        { id: 'hr', label: 'Heart rate', unit: 'bpm', modality: 'pulse' },
        { id: 'bp', label: 'Blood pressure', unit: 'mmHg', modality: 'bp_cuff' },
        { id: 'rr', label: 'Resp. rate', unit: '/min', modality: 'pulse' },
        { id: 'spo2', label: 'SpO2', unit: '%', modality: 'spo2_probe' },
        { id: 'temp', label: 'Temperature', unit: '°C', modality: 'temperature' },
        { id: 'glucose', label: 'Glucose', unit: 'mg/dL', modality: 'glucose' },
        { id: 'pain', label: 'Pain', unit: '/10', modality: 'pain_scale' },
        { id: 'rhythm', label: 'Rhythm', unit: '', modality: 'ecg' },
    ];
    const SOURCE_LABEL = { exam: 'exam', chart: 'chart', live: 'monitor' };

    function num(v) {
        const n = Number(v);
        return Number.isFinite(n) ? n : null;
    }

    // ok | warn | bad | '' (no band for this value)
    function classify(id, value) {
        if (id === 'rhythm') {
            const r = String(value || '').toLowerCase();
            if (!r) return '';
            if (r === 'sinus') return 'ok';
            return /vf|vt|asystole|pea|arrest/.test(r) ? 'bad' : 'warn';
        }
        if (id === 'bp') {
            const sbp = num(String(value || '').split('/')[0]);
            if (sbp === null) return value ? 'bad' : '';
            if (sbp <= 0 || sbp < 80) return 'bad';
            if (sbp < 90 || sbp > 180) return 'warn';
            return 'ok';
        }
        const n = num(value);
        if (n === null) return '';
        switch (id) {
            case 'hr': return (n < 40 || n > 140) ? 'bad' : ((n < 50 || n > 110) ? 'warn' : 'ok');
            case 'rr': return (n < 8 || n > 30) ? 'bad' : ((n < 12 || n > 20) ? 'warn' : 'ok');
            case 'spo2': return n < 90 ? 'bad' : (n < 95 ? 'warn' : 'ok');
            case 'temp': return (n < 35 || n > 39.5) ? 'bad' : ((n < 36 || n > 38) ? 'warn' : 'ok');
            case 'glucose': return (n < 60 || n > 300) ? 'bad' : ((n < 70 || n > 180) ? 'warn' : 'ok');
            case 'pain': return n >= 7 ? 'bad' : (n >= 4 ? 'warn' : 'ok');
            default: return '';
        }
    }

    // display text for the server's raw value of a channel
    function display(id, value) {
        if (value === null || value === undefined || value === '') return '';
        if (id === 'rhythm') return emsHumanize(value);
        if (id === 'spo2' && (value === 'no_reading' || num(value) === 0)) return 'No reading';
        if (id === 'bp' && (value === 'unrecordable' || /^0\//.test(String(value)))) return 'Unrecordable';
        if (id === 'hr' && value === 'absent') return 'Absent';
        if (id === 'temp' && num(value) !== null) return String(Math.round(num(value) * 10) / 10);
        return String(value);
    }

    // chart vitals rows: sign -> channel (pf-ambulancejob diagnosis.lua Generate)
    const SIGN_CHANNEL = { pulse: 'hr', respiratory_rate: 'rr', blood_pressure: 'bp', spo2: 'spo2', temperature: 'temp',
        glucose: 'glucose', rhythm: 'rhythm', pain_score: 'pain' };

    class Monitor {
        constructor() { this.reset(null); }

        reset(key) {
            this.key = key;
            this.values = {};
        }

        set(id, value, at, source) {
            if (value === null || value === undefined || value === '') return false;
            const cur = this.values[id];
            const t = num(at) || 0;
            // an older reading never replaces a newer one (live readings are always the newest)
            if (cur && source !== 'live' && cur.at > t) return false;
            this.values[id] = { value, at: t, source };
            return true;
        }

        // exam answer: { vitals = { hr, rr, sbp, dbp, spo2, temp, glucose, pain, rhythm }, at }
        ingestExam(res) {
            const v = res && res.vitals;
            if (!v || typeof v !== 'object') return 0;
            const at = res.at;
            let n = 0;
            if (v.hr !== undefined) n += this.set('hr', v.hr, at, 'exam');
            if (v.rr !== undefined) n += this.set('rr', v.rr, at, 'exam');
            if (v.sbp !== undefined) n += this.set('bp', `${v.sbp}/${v.dbp ?? 0}`, at, 'exam');
            if (v.spo2 !== undefined) n += this.set('spo2', v.spo2, at, 'exam');
            if (v.temp !== undefined) n += this.set('temp', v.temp, at, 'exam');
            if (v.glucose !== undefined) n += this.set('glucose', v.glucose, at, 'exam');
            if (v.pain !== undefined) n += this.set('pain', v.pain, at, 'exam');
            if (v.rhythm !== undefined) n += this.set('rhythm', v.rhythm, at, 'exam');
            return n;
        }

        // getChart vitals: [{ modality, sign, value, at }] (newest first)
        ingestChart(rows) {
            let n = 0;
            for (const r of Array.isArray(rows) ? rows : []) {
                const id = r && SIGN_CHANNEL[r.sign];
                if (!id) continue;
                const value = (id === 'hr' && r.value === 'absent') ? 0 : r.value;
                n += this.set(id, value, r.at, 'chart');
            }
            return n;
        }

        // live monitor: vitals = { hr, sbp, dbp, rr, spo2, temp }, rhythm
        ingestLive(vitals, rhythm, at) {
            if (!vitals || typeof vitals !== 'object') return 0;
            const t = num(at) || Math.floor(Date.now() / 1000);
            let n = this.ingestExam({ vitals, at: t });
            for (const id of Object.keys(this.values)) if (this.values[id].at === t) this.values[id].source = 'live';
            if (rhythm) n += this.set('rhythm', rhythm, t, 'live');
            return n;
        }

        // opts: { measure: { modality: available }, busy, onMeasure(modality) }
        render(opts) {
            opts = opts || {};
            const tiles = CHANNELS.map((c) => {
                const v = this.values[c.id];
                const shown = v ? display(c.id, v.value) : '';
                const band = v ? classify(c.id, v.value) : '';
                const canMeasure = opts.measure && opts.measure[c.modality] === true && c.id !== 'rr';
                return emsEl('div', { class: `ems-vital${band ? ' ems-vital-' + band : ''}`, dataset: { channel: c.id } },
                    emsEl('div', { class: 'ems-vital-label', text: c.label }),
                    emsEl('div', { class: 'ems-vital-value' },
                        emsEl('span', { class: 'ems-vital-num', text: shown || '—' }),
                        shown && c.unit && !/[a-z]/i.test(shown) ? emsEl('span', { class: 'ems-vital-unit', text: c.unit }) : null),
                    emsEl('div', { class: 'ems-vital-meta', text: v ? `${SOURCE_LABEL[v.source] || v.source} · ${emsTime(v.at).slice(11) || '—'}` : 'Not measured' }),
                    canMeasure ? emsEl('button', { class: 'btn ems-vital-measure', type: 'button', disabled: opts.busy ? true : null,
                        text: 'Measure', 'aria-label': `Measure ${c.label}`, onclick: () => opts.onMeasure && opts.onMeasure(c.modality) }) : null);
            });
            return emsEl('div', { class: 'ems-monitor', role: 'group', 'aria-label': 'Vitals monitor' },
                emsEl('div', { class: 'ems-monitor-head' },
                    emsEl('h3', { text: 'Vitals monitor' }),
                    emsEl('span', { class: 'ems-muted', text: 'Measured values only' })),
                emsEl('div', { class: 'ems-vitals' }, tiles));
        }
    }

    window.EmsMonitor = { Monitor, classify, display, CHANNELS };
})();
