// EMS MDT - the patient profile's Medical tab (batch 21).
//
// The record comes from the server's patient profile (pf_emsmdt:getPatientProfile): profile.medical
// is pf-ambulancejob's GetMedicalRecord, which decides who may see it and audits every read, already
// cut to short text lines (documented injuries, diagnoses, prescriptions, treatments, admissions);
// profile.pcrs are this MDT's patient care reports the viewer may see. Everything is put on the
// page as text. (This file used to drive the old injury overlay, which listed every recorded injury
// and reported every treatment as applied; exams and treatments now live on the Patient Care page.)

(function () {
    const RECORD_REFUSED = {
        no_permission: 'You may not see this record: only the patient, a medic who treated them in the last 24 hours, staff of an admitted patient or a physician can.',
        not_on_duty: 'Go on duty to see medical records.',
        unavailable: 'Medical records are unavailable right now.',
        db_unavailable: 'Medical records are unavailable right now.',
        offline: 'You are not loaded yet.',
    };

    const STATE_LABEL = { open: 'Open', handed_over: 'Handed over', closed: 'Closed' };

    function lines(title, list, empty) {
        const items = (Array.isArray(list) ? list : []).map((x) => String(x ?? '').trim()).filter(Boolean);
        return emsEl('section', { class: 'ems-section' },
            emsEl('h4', { class: 'ems-section-title', text: title }),
            items.length
                ? emsEl('ul', { class: 'ems-lines' }, items.map((t) => emsEl('li', { text: t })))
                : emsState('empty', empty));
    }

    function pcrTable(pcrs, openPcr) {
        if (!pcrs.length) return emsState('empty', 'No care reports you may see.');
        const head = emsEl('tr', null, ['Report', 'State', 'Unit', 'Lead', 'Opened', 'Outcome', ''].map((h) => emsEl('th', { text: h })));
        const rows = pcrs.map((p) => {
            const id = Number(p.id);
            const open = emsEl('button', { class: 'btn', type: 'button', text: 'Open',
                'aria-label': `Open care report ${Number.isFinite(id) ? id : ''}`,
                onclick: () => { if (Number.isFinite(id) && typeof openPcr === 'function') openPcr(id); } });
            return emsEl('tr', null,
                emsEl('td', { text: Number.isFinite(id) ? `#${id}` : '—' }),
                emsEl('td', null, emsEl('span', { class: `ems-badge ems-state-${STATE_LABEL[p.state] ? p.state : 'unknown'}`, text: STATE_LABEL[p.state] || emsHumanize(p.state) })),
                emsEl('td', { text: p.unit || '—' }),
                emsEl('td', { text: (p.lead && p.lead.name) || '—' }),
                emsEl('td', { text: emsTime(p.createdAt) }),
                emsEl('td', { text: p.dispositionLabel || '—' }),
                emsEl('td', null, open));
        });
        return emsEl('div', { class: 'ems-table-wrap' }, emsEl('table', { class: 'ems-table' }, emsEl('thead', null, head), emsEl('tbody', null, rows)));
    }

    function build(profile, opts) {
        profile = profile && typeof profile === 'object' ? profile : {};
        opts = opts || {};
        const medical = profile.medical && typeof profile.medical === 'object' ? profile.medical : {};
        const pcrs = Array.isArray(profile.pcrs) ? profile.pcrs : [];
        const root = emsEl('div', { class: 'ems-medical' });
        root.appendChild(emsEl('div', { class: 'ems-kv' },
            emsEl('span', { class: 'ems-k', text: 'Blood type' }),
            emsEl('span', { class: 'ems-v', text: String(profile.bloodtype || '').trim() || 'Not recorded' })));
        if (medical.available !== true) {
            root.appendChild(emsState('error', RECORD_REFUSED[medical.error] || 'The medical record is not available.'));
        } else {
            root.appendChild(lines('Documented injuries', medical.injuries, 'No documented injuries.'));
            root.appendChild(lines('Diagnoses', medical.conditions, 'No diagnoses.'));
            root.appendChild(lines('Prescriptions', medical.medications, 'No prescriptions.'));
            root.appendChild(lines('Treatments', medical.treatments, 'No treatments recorded.'));
            root.appendChild(lines('Hospital admissions', medical.admissions, 'No admissions.'));
        }
        root.appendChild(emsEl('section', { class: 'ems-section' },
            emsEl('h4', { class: 'ems-section-title', text: 'Patient care reports' }),
            pcrTable(pcrs, opts.openPcr)));
        return root;
    }

    window.EmsMedicalTab = { build };
})();
