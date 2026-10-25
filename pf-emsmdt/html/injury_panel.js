// EMS MDT - Injury Panel JavaScript
// Renders injury assessment panel inside index.html and bridges to NUI callbacks.

(function () {
    const state = {
        citizenId: null,
        patientName: null,
        injuries: [],
        health: 100,
        armor: 0,
        selectedZone: null,
    };

    const ZONES = ['head', 'torso', 'left_arm', 'right_arm', 'left_leg', 'right_leg'];

    function el(id) {
        return document.getElementById(id);
    }

    // HTML-escape (& < > " '); prefers the global escapeHtml from app.js when present.
    function esc(v) {
        if (typeof escapeHtml === 'function') return escapeHtml(v);
        return String(v ?? '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    function clampPct(v) {
        const n = Number(v);
        if (!Number.isFinite(n)) return 0;
        return Math.max(0, Math.min(100, n));
    }

    function normalizeZone(raw) {
        const s = String(raw || '').toLowerCase().trim();
        if (!s) return null;
        const cleaned = s
            .replace(/\s+/g, '_')
            .replace(/[^a-z0-9_]/g, '');

        if (ZONES.includes(cleaned)) return cleaned;

        // Common fallbacks
        if (cleaned === 'chest' || cleaned === 'abdomen' || cleaned === 'stomach') return 'torso';
        if (cleaned === 'larm' || cleaned === 'leftarm') return 'left_arm';
        if (cleaned === 'rarm' || cleaned === 'rightarm') return 'right_arm';
        if (cleaned === 'lleg' || cleaned === 'leftleg') return 'left_leg';
        if (cleaned === 'rleg' || cleaned === 'rightleg') return 'right_leg';

        return null;
    }

    function severityRank(sev) {
        const s = String(sev || '').toLowerCase();
        if (s === 'critical') return 4;
        if (s === 'severe') return 3;
        if (s === 'moderate') return 2;
        return 1;
    }

    function groupInjuriesByZone(injuries) {
        const grouped = { head: [], torso: [], left_arm: [], right_arm: [], left_leg: [], right_leg: [] };
        for (const inj of injuries || []) {
            const zone = normalizeZone(inj.bodyZone || inj.bodyPart || inj.location);
            if (!zone) continue;
            grouped[zone].push(inj);
        }
        return grouped;
    }

    function renderVitals() {
        const health = clampPct(state.health);
        const armor = clampPct(state.armor);

        const healthBar = el('healthBar');
        const healthValue = el('healthValue');
        if (healthBar) healthBar.style.width = `${health}%`;
        if (healthValue) healthValue.textContent = `${health}%`;

        const armorBar = el('armorBar');
        const armorValue = el('armorValue');
        if (armorBar) armorBar.style.width = `${armor}%`;
        if (armorValue) armorValue.textContent = `${armor}%`;
    }

    function renderPatientHeader() {
        const nameEl = el('injuryPatientName');
        const idEl = el('injuryPatientId');
        if (nameEl) nameEl.textContent = state.patientName || 'Unknown Patient';
        if (idEl) idEl.textContent = state.citizenId ? `#${state.citizenId}` : '#0000';
    }

    function renderInjuryList() {
        const container = el('injuryListContainer');
        if (!container) return;

        const injuries = Array.isArray(state.injuries) ? state.injuries : [];
        const selected = state.selectedZone;
        const filtered = selected ? injuries.filter((i) => normalizeZone(i.bodyZone || i.bodyPart || i.location) === selected) : injuries;

        if (filtered.length === 0) {
            container.innerHTML = '<div class="empty-state">No injuries found</div>';
            return;
        }

        container.innerHTML = filtered
            .map((inj) => {
                const sev = String(inj.severity || 'minor').toLowerCase();
                const type = String(inj.injuryType || inj.injury_type || 'Injury');
                const zone = normalizeZone(inj.bodyZone || inj.bodyPart || inj.location);
                const desc = String(inj.description || '').trim();
                return `
                    <div class="injury-card">
                        <div class="injury-card__row">
                            <div class="injury-card__title">${esc(type)}</div>
                            <div class="injury-card__meta">${zone ? zone.replace(/_/g, ' ') : 'unknown'} · ${esc(sev)}</div>
                        </div>
                        ${desc ? `<div class="injury-card__desc">${esc(desc)}</div>` : ''}
                    </div>
                `;
            })
            .join('');
    }

    function highlightBodyMap() {
        const grouped = groupInjuriesByZone(state.injuries);
        for (const zone of ZONES) {
            const zoneEl = el(`zone-${zone}`);
            if (!zoneEl) continue;

            const injuries = grouped[zone] || [];
            const has = injuries.length > 0;
            const maxSev = injuries.reduce((m, i) => Math.max(m, severityRank(i.severity)), 0);

            zoneEl.classList.toggle('selected', state.selectedZone === zone);
            zoneEl.classList.toggle('has-injury', has);

            // Best-effort visual hint without new CSS: adjust opacity by severity.
            if (!has) {
                zoneEl.style.opacity = '0.35';
            } else if (maxSev >= 4) {
                zoneEl.style.opacity = '1';
            } else if (maxSev === 3) {
                zoneEl.style.opacity = '0.85';
            } else if (maxSev === 2) {
                zoneEl.style.opacity = '0.7';
            } else {
                zoneEl.style.opacity = '0.6';
            }
        }
    }

    function setVisible(visible) {
        const panel = el('injuryAssessmentPanel');
        if (!panel) return;
        panel.classList.toggle('hidden', !visible);
    }

    function selectZone(zone) {
        state.selectedZone = zone;
        highlightBodyMap();
        renderInjuryList();
    }

    async function postNui(name, payload) {
        const res = await fetch(`https://${GetParentResourceName()}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload || {}),
        });
        try {
            return await res.json();
        } catch (_) {
            return null;
        }
    }

    function bindUi() {
        // Zone buttons
        document.querySelectorAll('.zone-btn[data-zone]').forEach((btn) => {
            btn.addEventListener('click', () => {
                const zone = normalizeZone(btn.getAttribute('data-zone'));
                if (!zone) return;
                selectZone(zone);
            });
        });

        // SVG zones
        document.querySelectorAll('.body-zone[data-zone]').forEach((zoneEl) => {
            zoneEl.addEventListener('click', () => {
                const zone = normalizeZone(zoneEl.getAttribute('data-zone'));
                if (!zone) return;
                selectZone(zone);
            });
        });

        // Treatments
        document.querySelectorAll('.treatment-btn[data-treatment]').forEach((btn) => {
            btn.addEventListener('click', async () => {
                if (!state.citizenId) return;
                const treatmentType = btn.getAttribute('data-treatment');
                const notes = (el('medicalNotesInput')?.value || '').trim();
                await postNui('treatPatient', {
                    citizenId: state.citizenId,
                    treatmentType,
                    bodyZone: state.selectedZone,
                    notes,
                });
            });
        });

        // Save notes
        const saveBtn = el('saveMedicalNotes');
        if (saveBtn) {
            saveBtn.addEventListener('click', async () => {
                if (!state.citizenId) return;
                const notes = (el('medicalNotesInput')?.value || '').trim();
                await postNui('saveMedicalNotes', { citizenId: state.citizenId, notes });
            });
        }

        // Close
        const closeBtn = el('closeInjuryPanel');
        if (closeBtn) {
            closeBtn.addEventListener('click', async () => {
                setVisible(false);
                state.selectedZone = null;
                await postNui('closeInjuryPanel', {});
            });
        }
    }

    function displayInjuryAssessment(data) {
        if (!data || typeof data !== 'object') return;

        state.citizenId = data.citizenId || data.citizenid || null;
        state.patientName = data.patientName || data.name || null;
        state.injuries = Array.isArray(data.injuries) ? data.injuries : [];
        state.health = data.health != null ? data.health : 100;
        state.armor = data.armor != null ? data.armor : 0;
        state.selectedZone = null;

        renderPatientHeader();
        renderVitals();
        highlightBodyMap();
        renderInjuryList();
        setVisible(true);
    }

    document.addEventListener('DOMContentLoaded', () => {
        bindUi();
        window.InjuryPanel = window.InjuryPanel || {};
        window.InjuryPanel.displayInjuryAssessment = displayInjuryAssessment;
    });
})();
